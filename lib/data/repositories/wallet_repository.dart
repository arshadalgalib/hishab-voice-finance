import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/enums.dart';
import '../../domain/models/aggregates.dart';
import '../../domain/models/transaction_filter.dart';
import '../../domain/models/wallet_resolution.dart';
import '../local/app_database.dart';
import 'settings_repository.dart';

/// Wallet CRUD plus the rules that keep balances trustworthy.
///
/// Balances are **always derived** from the opening balance and the recorded
/// transactions — `AppDatabase` never stores a mutable "current balance", so
/// there is no second source of truth that could drift out of sync.
class WalletRepository {
  WalletRepository({
    required AppDatabase db,
    required SettingsRepository settings,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = db,
       _settings = settings,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final SettingsRepository _settings;
  final IdGenerator _ids;
  final Clock _clock;

  Stream<List<WalletBalance>> watchBalances({bool includeArchived = true}) =>
      _db.watchWalletBalances(includeArchived: includeArchived);

  Future<List<WalletBalance>> balances({bool includeArchived = true}) =>
      _db.getWalletBalances(includeArchived: includeArchived);

  Future<WalletBalance?> balance(String walletId) =>
      _db.getWalletBalance(walletId);

  Stream<List<WalletRow>> watchRows({bool includeArchived = true}) =>
      _db.watchWalletRows(includeArchived: includeArchived);

  Future<List<WalletRow>> rows({bool includeArchived = true}) =>
      _db.getWalletRows(includeArchived: includeArchived);

  Future<WalletRow?> find(String walletId) => _db.findWalletById(walletId);

  Future<List<WalletBalance>> activeBalances() =>
      _db.getWalletBalances(includeArchived: false);

  /// Total of every *active* wallet. This is the number shown on the dashboard
  /// as "Total balance" and is explicitly not the same as net income.
  Stream<int> watchTotalBalance() => _db
      .watchWalletBalances(includeArchived: false)
      .map(
        (list) =>
            list.fold<int>(0, (sum, wallet) => sum + wallet.balancePoisha),
      );

  /// Throws [NotFoundException] when the wallet is missing, and
  /// [ValidationException] when it has been archived.
  Future<WalletRow> requireUsableWallet(String walletId) async {
    final wallet = await _db.findWalletById(walletId);
    if (wallet == null) {
      throw const NotFoundException('That wallet no longer exists.');
    }
    if (wallet.isArchived) {
      throw ValidationException(
        '“${wallet.name}” is archived. Unarchive it or pick another wallet.',
        field: 'walletId',
      );
    }
    return wallet;
  }

  Future<String> createWallet({
    required String name,
    required WalletType type,
    String? institution,
    int openingBalancePoisha = 0,
    int? colorValue,
    int? iconCodePoint,
    String? note,
    bool isDefaultIncome = false,
    bool isDefaultExpense = false,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException(
        'Wallet name is required.',
        field: 'name',
      );
    }
    if (trimmed.length > 80) {
      throw const ValidationException(
        'Wallet name must be 80 characters or fewer.',
        field: 'name',
      );
    }
    final existing = await _db.findWalletByName(trimmed);
    if (existing != null) {
      throw ValidationException(
        'A wallet named “${existing.name}” already exists.',
        field: 'name',
      );
    }
    if (openingBalancePoisha < 0) {
      throw const ValidationException(
        'Opening balance cannot be negative.',
        field: 'openingBalance',
      );
    }

    final id = _ids.next();
    final now = _clock.now();
    final sortOrder = await _db.nextWalletSortOrder();

    await _db.transaction(() async {
      if (isDefaultIncome) {
        await _db.clearDefaultWalletFlags(kind: CategoryKind.income);
      }
      if (isDefaultExpense) {
        await _db.clearDefaultWalletFlags(kind: CategoryKind.expense);
      }
      await _db.upsertWallet(
        WalletsCompanion.insert(
          id: id,
          name: trimmed,
          type: type,
          institution: Value(institution?.trim()),
          openingBalancePoisha: Value(openingBalancePoisha),
          colorValue: Value(colorValue),
          iconCodePoint: Value(iconCodePoint),
          note: Value(note?.trim()),
          isDefaultIncome: Value(isDefaultIncome),
          isDefaultExpense: Value(isDefaultExpense),
          sortOrder: Value(sortOrder),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _db.writeAuditLog(
        entityType: 'wallet',
        entityId: id,
        action: 'created',
        payload: {
          'name': trimmed,
          'type': type.name,
          'openingBalancePoisha': openingBalancePoisha,
        },
      );
      await _syncDefaultSettings();
    });

    return id;
  }

  Future<void> updateWallet(
    String walletId, {
    String? name,
    WalletType? type,
    String? institution,
    int? colorValue,
    int? iconCodePoint,
    String? note,
  }) async {
    final wallet = await _requireWalletRow(walletId);
    var newName = wallet.name;
    if (name != null) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        throw const ValidationException(
          'Wallet name is required.',
          field: 'name',
        );
      }
      final clash = await _db.findWalletByName(trimmed);
      if (clash != null && clash.id != walletId) {
        throw ValidationException(
          'A wallet named “${clash.name}” already exists.',
          field: 'name',
        );
      }
      newName = trimmed;
    }

    await _db.upsertWallet(
      WalletsCompanion(
        id: Value(walletId),
        name: Value(newName),
        type: type == null ? const Value.absent() : Value(type),
        institution: institution == null
            ? const Value.absent()
            : Value(institution.trim().isEmpty ? null : institution.trim()),
        colorValue: colorValue == null
            ? const Value.absent()
            : Value(colorValue),
        iconCodePoint: iconCodePoint == null
            ? const Value.absent()
            : Value(iconCodePoint),
        note: note == null
            ? const Value.absent()
            : Value(note.trim().isEmpty ? null : note.trim()),
        updatedAt: Value(_clock.now()),
      ),
    );
    await _db.writeAuditLog(
      entityType: 'wallet',
      entityId: walletId,
      action: 'updated',
      payload: {'name': newName},
    );
  }

  /// Archived wallets keep their full history and still contribute to reports;
  /// they simply cannot be used for new transactions.
  Future<void> setArchived(String walletId, bool archived) async {
    final wallet = await _requireWalletRow(walletId);
    await _db.transaction(() async {
      await _db.upsertWallet(
        WalletsCompanion(
          id: Value(walletId),
          isArchived: Value(archived),
          isDefaultIncome: archived ? const Value(false) : const Value.absent(),
          isDefaultExpense: archived
              ? const Value(false)
              : const Value.absent(),
          updatedAt: Value(_clock.now()),
        ),
      );
      await _db.writeAuditLog(
        entityType: 'wallet',
        entityId: walletId,
        action: archived ? 'archived' : 'unarchived',
        payload: {'name': wallet.name},
      );
      await _syncDefaultSettings();
    });
  }

  Future<void> setDefault({
    required CategoryKind kind,
    required String walletId,
  }) async {
    final wallet = await _db.findWalletById(walletId);
    if (wallet == null) {
      throw const NotFoundException('That wallet no longer exists.');
    }
    if (wallet.isArchived) {
      throw const ValidationException(
        'An archived wallet cannot be the default.',
        field: 'walletId',
      );
    }
    await _db.transaction(() async {
      await _db.clearDefaultWalletFlags(kind: kind, exceptWalletId: walletId);
      await _db.upsertWallet(
        WalletsCompanion(
          id: Value(walletId),
          isDefaultIncome: kind == CategoryKind.income
              ? const Value(true)
              : const Value.absent(),
          isDefaultExpense: kind == CategoryKind.expense
              ? const Value(true)
              : const Value.absent(),
          updatedAt: Value(_clock.now()),
        ),
      );
      await _syncDefaultSettings();
    });
  }

  Future<void> clearDefault(CategoryKind kind) async {
    await _db.transaction(() async {
      await _db.clearDefaultWalletFlags(kind: kind);
      await _syncDefaultSettings();
    });
  }

  /// Records an opening-balance correction and leaves an audit trail. The
  /// balance itself is still derived, so this can never contradict history.
  Future<void> adjustOpeningBalance({
    required String walletId,
    required int newOpeningBalancePoisha,
    String? reason,
  }) async {
    final wallet = await _requireWalletRow(walletId);
    final previous = wallet.openingBalancePoisha;
    await _db.transaction(() async {
      await _db.upsertWallet(
        WalletsCompanion(
          id: Value(walletId),
          openingBalancePoisha: Value(newOpeningBalancePoisha),
          updatedAt: Value(_clock.now()),
        ),
      );
      await _db.writeAuditLog(
        entityType: 'wallet',
        entityId: walletId,
        action: 'opening_balance_adjusted',
        payload: {
          'wallet': wallet.name,
          'previousPoisha': previous,
          'newPoisha': newOpeningBalancePoisha,
          'deltaPoisha': newOpeningBalancePoisha - previous,
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
      );
    });
  }

  /// Deletes a wallet. Refuses when anything references it, so the user can
  /// never silently lose transactions.
  Future<void> deleteWallet(String walletId) async {
    final wallet = await _requireWalletRow(walletId);
    final usage = await _db.countTransactions(
      filter: TransactionFilter(walletIds: {walletId}),
    );
    if (usage > 0) {
      throw OperationNotAllowedException(
        '“${wallet.name}” has $usage transaction(s). Archive it instead of deleting.',
      );
    }
    final active = await _db.getWalletRows(includeArchived: false);
    if (active.length <= 1 && !wallet.isArchived) {
      throw const OperationNotAllowedException(
        'You need at least one wallet. Create another one first.',
      );
    }
    await _db.transaction(() async {
      await (_db.delete(_db.wallets)..where((t) => t.id.equals(walletId))).go();
      await _db.writeAuditLog(
        entityType: 'wallet',
        entityId: walletId,
        action: 'deleted',
        payload: {'name': wallet.name},
      );
      await _syncDefaultSettings();
    });
  }

  /// Chooses a wallet for a transaction that did not name one.
  ///
  /// Deliberately conservative: the user's configured default wins; with a
  /// single wallet that wallet is used and the UI explains why; with several
  /// candidates nothing is guessed and the user is asked to choose.
  Future<WalletResolution> resolveDefaultWallet(CategoryKind kind) async {
    final settings = await _settings.load();
    final configuredId = kind == CategoryKind.income
        ? settings.defaultIncomeWalletId
        : settings.defaultExpenseWalletId;

    final active = await _db.getWalletBalances(includeArchived: false);
    if (active.isEmpty) {
      return const WalletResolution.unresolved(
        'No wallet yet — create one to record this transaction.',
      );
    }
    if (configuredId != null) {
      final match = active.where((w) => w.walletId == configuredId).firstOrNull;
      if (match != null) {
        return WalletResolution(
          walletId: match.walletId,
          walletName: match.name,
          isConfiguredDefault: true,
          reason: kind == CategoryKind.income
              ? 'Using your default income wallet'
              : 'Using your default expense wallet',
        );
      }
    }
    if (active.length == 1) {
      return WalletResolution(
        walletId: active.first.walletId,
        walletName: active.first.name,
        isOnlyWallet: true,
        reason: 'Only one wallet available',
      );
    }
    return const WalletResolution.unresolved('Which wallet should this use?');
  }

  Future<WalletBalance> requireBalance(String walletId) async {
    final balance = await _db.getWalletBalance(walletId);
    if (balance == null) {
      throw const NotFoundException('That wallet no longer exists.');
    }
    return balance;
  }

  /// Keeps the `app_settings` defaults in step with the wallet flags after a
  /// wallet is added, archived or removed.
  Future<void> _syncDefaultSettings() async {
    final wallets = await _db.getWalletRows(includeArchived: true);
    final incomeDefault = wallets
        .where((w) => w.isDefaultIncome && !w.isArchived)
        .firstOrNull;
    final expenseDefault = wallets
        .where((w) => w.isDefaultExpense && !w.isArchived)
        .firstOrNull;
    await _settings.update(
      (current) => current.copyWith(
        defaultIncomeWalletId: incomeDefault?.id,
        clearDefaultIncomeWallet: incomeDefault == null,
        defaultExpenseWalletId: expenseDefault?.id,
        clearDefaultExpenseWallet: expenseDefault == null,
      ),
    );
  }

  Future<WalletRow> _requireWalletRow(String walletId) async {
    final wallet = await _db.findWalletById(walletId);
    if (wallet == null) {
      throw const NotFoundException('That wallet no longer exists.');
    }
    return wallet;
  }
}
