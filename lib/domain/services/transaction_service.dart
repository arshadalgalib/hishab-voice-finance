import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/id_generator.dart';
import '../../data/local/app_database.dart' as local;
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../data/repositories/wallet_repository.dart';
import '../enums.dart';
import '../models/transaction_draft.dart';

/// The only place in the application that writes to the transaction ledger.
///
/// Manual forms and the voice confirmation screen both funnel through here, so
/// the financial rules cannot diverge between the two entry paths.
///
/// ## Invariants enforced
/// * amount is strictly positive and within a sanity bound;
/// * the wallet exists, is not archived, and for transfers source != destination;
/// * a transfer carries a destination and no category; income/expense carry no
///   destination;
/// * an income/expense category matches the transaction type;
/// * a transfer fee becomes a real linked `expense` row on the source wallet, so
///   it appears in expense reports exactly once;
/// * deleting or editing a transfer removes/rebuilds its linked fee atomically.
class TransactionService {
  TransactionService({
    required local.AppDatabase db,
    required TransactionRepository transactions,
    required WalletRepository wallets,
    required CategoryRepository categories,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = db,
       _transactions = transactions,
       _wallets = wallets,
       _categories = categories,
       _ids = ids,
       _clock = clock;

  final local.AppDatabase _db;
  final TransactionRepository _transactions;
  final WalletRepository _wallets;
  final CategoryRepository _categories;
  final IdGenerator _ids;
  final Clock _clock;

  /// 10 billion BDT — a hard ceiling that catches fat-finger input without
  /// blocking any realistic transaction.
  static const int maxAmountPoisha = 1000000000000;

  static const Duration defaultDuplicateWindow = Duration(minutes: 10);

  DateTime get now => _clock.now();

  // ─────────────────────────────────────────────────────────── creation ────

  Future<String> createIncome({
    required int amountPoisha,
    required String walletId,
    DateTime? occurredAt,
    String? categoryId,
    String? description,
    String? payer,
    String? note,
    List<String> tags = const <String>[],
    TransactionSource source = TransactionSource.manual,
    bool allowDuplicate = false,
  }) => create(
    TransactionDraft.income(
      amountPoisha: amountPoisha,
      walletId: walletId,
      occurredAt: occurredAt ?? now,
      categoryId: categoryId,
      description: description,
      payer: payer,
      note: note,
      tags: tags,
      source: source,
    ),
    allowDuplicate: allowDuplicate,
  );

  Future<String> createExpense({
    required int amountPoisha,
    required String walletId,
    DateTime? occurredAt,
    String? categoryId,
    String? description,
    String? merchant,
    String? note,
    List<String> tags = const <String>[],
    TransactionSource source = TransactionSource.manual,
    bool allowDuplicate = false,
  }) => create(
    TransactionDraft.expense(
      amountPoisha: amountPoisha,
      walletId: walletId,
      occurredAt: occurredAt ?? now,
      categoryId: categoryId,
      description: description,
      merchant: merchant,
      note: note,
      tags: tags,
      source: source,
    ),
    allowDuplicate: allowDuplicate,
  );

  /// Creates one logical transfer. The source wallet is debited and the
  /// destination credited; income and expense totals are untouched. A non-zero
  /// `feePoisha` additionally records a linked expense on the source wallet.
  Future<String> createTransfer({
    required int amountPoisha,
    required String fromWalletId,
    required String toWalletId,
    DateTime? occurredAt,
    String? note,
    String? description,
    int feePoisha = 0,
    TransactionSource source = TransactionSource.manual,
    bool allowDuplicate = false,
  }) => create(
    TransactionDraft.transfer(
      amountPoisha: amountPoisha,
      fromWalletId: fromWalletId,
      toWalletId: toWalletId,
      occurredAt: occurredAt ?? now,
      note: note,
      description: description,
      feePoisha: feePoisha,
      source: source,
    ),
    allowDuplicate: allowDuplicate,
  );

  /// Creates and persists [draft]. Returns the new transaction id.
  Future<String> create(
    TransactionDraft draft, {
    bool allowDuplicate = false,
    Duration duplicateWindow = defaultDuplicateWindow,
  }) async {
    await validate(draft);

    if (!allowDuplicate) {
      final duplicate = await _transactions.findProbableDuplicate(
        type: draft.type,
        amountPoisha: draft.amountPoisha,
        walletId: draft.walletId,
        occurredAt: draft.occurredAt,
        window: duplicateWindow,
      );
      if (duplicate != null) {
        throw DuplicateTransactionException(
          duplicate.id,
          'A ${draft.type.name} of the same amount was just recorded from '
          '${duplicate.walletName}. Save anyway?',
        );
      }
    }

    final id = _ids.next();
    final groupId = draft.type.isTransfer ? _ids.nextPrefixed('tr') : '';
    final createdAt = now;

    await _db.transaction(() async {
      await _transactions.insert(
        _companionFromDraft(
          draft,
          id: id,
          transferGroupId: groupId,
          createdAt: createdAt,
        ),
      );
      if (draft.type.isTransfer && draft.feePoisha > 0) {
        await _insertTransferFee(draft, groupId: groupId, createdAt: createdAt);
      }
      await _db.writeAuditLog(
        entityType: 'transaction',
        entityId: id,
        action: 'created',
        payload: <String, Object?>{
          'type': draft.type.name,
          'amountPoisha': draft.amountPoisha,
          'walletId': draft.walletId,
          if (draft.toWalletId != null) 'toWalletId': draft.toWalletId,
          'source': draft.source.name,
        },
      );
    });

    return id;
  }

  // ───────────────────────────────────────────────────────────── updates ────

  /// Replaces the content of an existing transaction.
  ///
  /// Because a transfer is a single row, editing it can never leave a
  /// half-updated pair. Its linked fee rows are rebuilt in the same database
  /// transaction.
  Future<void> update(String id, TransactionDraft draft) async {
    await validate(draft);
    final existing = await _transactions.findRow(id);
    if (existing == null) {
      throw const NotFoundException('That transaction no longer exists.');
    }

    final updatedAt = now;
    final groupId = draft.type.isTransfer
        ? (existing.transferGroupId ?? _ids.nextPrefixed('tr'))
        : '';

    await _db.transaction(() async {
      // Remove any previously linked fee rows, never the row being edited.
      final previousGroup = existing.transferGroupId;
      if (previousGroup != null) {
        await _deleteGroupRows(groupId: previousGroup, exceptId: id);
      }
      await _transactions.patch(
        id,
        _companionFromDraft(
          draft,
          id: id,
          transferGroupId: groupId,
          createdAt: updatedAt,
        ).copyWith(
          createdAt: const Value.absent(),
          updatedAt: Value(updatedAt),
        ),
      );
      if (draft.type.isTransfer && draft.feePoisha > 0) {
        await _insertTransferFee(draft, groupId: groupId, createdAt: updatedAt);
      }
      await _db.writeAuditLog(
        entityType: 'transaction',
        entityId: id,
        action: 'updated',
        payload: <String, Object?>{
          'type': draft.type.name,
          'amountPoisha': draft.amountPoisha,
          'previousAmountPoisha': existing.amountPoisha,
          'previousType': existing.type.name,
        },
      );
    });
  }

  /// Deletes a transaction. Deleting a transfer also deletes its linked fee.
  /// Returns the raw rows that were removed so the caller can offer an undo.
  Future<List<local.TransactionRow>> delete(String id) async {
    final existing = await _transactions.findRow(id);
    if (existing == null) {
      throw const NotFoundException('That transaction no longer exists.');
    }
    final removed = <local.TransactionRow>[existing];
    await _db.transaction(() async {
      final group = existing.transferGroupId;
      if (group != null) {
        for (final row in await _transactions.rowsByGroup(group)) {
          if (row.id != id) removed.add(row);
        }
        await _transactions.deleteGroup(group);
      } else {
        await _transactions.deleteRow(id);
      }
      await _db.writeAuditLog(
        entityType: 'transaction',
        entityId: id,
        action: 'deleted',
        payload: <String, Object?>{
          'type': existing.type.name,
          'amountPoisha': existing.amountPoisha,
          'walletId': existing.walletId,
          if (existing.toWalletId != null) 'toWalletId': existing.toWalletId,
        },
      );
    });
    return removed;
  }

  /// Re-inserts rows previously returned by [delete], used by undo.
  Future<void> restoreRows(List<local.TransactionRow> rows) async {
    await _db.transaction(() async {
      for (final row in rows) {
        await _transactions.insert(companionFromRow(row));
      }
    });
  }

  // ────────────────────────────────────────────────────────── validation ────

  /// Throws a [ValidationException] describing the first problem found.
  /// Exposed publicly so forms can validate before enabling a save button.
  Future<void> validate(TransactionDraft draft) async {
    if (draft.amountPoisha <= 0) {
      throw const ValidationException(
        'Enter an amount greater than zero.',
        field: 'amount',
      );
    }
    if (draft.amountPoisha > maxAmountPoisha) {
      throw const ValidationException(
        'That amount looks too large. Please check it.',
        field: 'amount',
      );
    }
    if (draft.feePoisha < 0) {
      throw const ValidationException(
        'A transfer fee cannot be negative.',
        field: 'fee',
      );
    }
    if (!draft.type.isTransfer && draft.feePoisha > 0) {
      throw const ValidationException(
        'Only transfers can have a fee.',
        field: 'fee',
      );
    }
    if (draft.occurredAt.year < 2000) {
      throw const ValidationException(
        'Please pick a date from this century.',
        field: 'date',
      );
    }
    if (draft.occurredAt.isAfter(now.add(const Duration(days: 366)))) {
      throw const ValidationException(
        'That date is more than a year away.',
        field: 'date',
      );
    }

    // Wallet checks — this is what stops an expense hitting the wrong wallet.
    await _wallets.requireUsableWallet(draft.walletId);

    if (draft.type.isTransfer) {
      final toWalletId = draft.toWalletId;
      if (toWalletId == null || toWalletId.isEmpty) {
        throw const ValidationException(
          'Choose the wallet the money is going to.',
          field: 'toWalletId',
        );
      }
      if (toWalletId == draft.walletId) {
        throw const ValidationException(
          'Source and destination wallets must be different.',
          field: 'toWalletId',
        );
      }
      await _wallets.requireUsableWallet(toWalletId);
      if (draft.categoryId != null) {
        // A transfer is not a categorised expense; refusing here keeps category
        // reports honest.
        throw const ValidationException(
          'Transfers are not categorised. Remove the category or record it as '
          'an expense instead.',
          field: 'categoryId',
        );
      }
      return;
    }

    if (draft.toWalletId != null) {
      throw const ValidationException(
        'Only transfers have a destination wallet.',
        field: 'toWalletId',
      );
    }

    final categoryId = draft.categoryId;
    if (categoryId != null) {
      final category = await _categories.find(categoryId);
      if (category == null) {
        throw const ValidationException(
          'That category no longer exists. Pick another one.',
          field: 'categoryId',
        );
      }
      final expected = draft.type.isIncome
          ? CategoryKind.income
          : CategoryKind.expense;
      if (category.kind != expected) {
        throw ValidationException(
          '“${category.name}” is a ${category.kind.name} category. '
          'Choose a ${draft.type.name} category.',
          field: 'categoryId',
        );
      }
    }
  }

  // ──────────────────────────────────────────────────────────── helpers ─────

  /// Builds the row companion for [draft]. [id] and the group id are supplied
  /// by the service so it can control idempotency and auditability.
  local.TransactionsCompanion _companionFromDraft(
    TransactionDraft draft, {
    required String id,
    required String transferGroupId,
    required DateTime createdAt,
  }) {
    return local.TransactionsCompanion.insert(
      id: id,
      type: draft.type,
      amountPoisha: draft.amountPoisha,
      walletId: draft.walletId,
      toWalletId: Value(draft.toWalletId),
      categoryId: Value(draft.categoryId),
      occurredAt: draft.occurredAt,
      dayKey: dayKeyOf(draft.occurredAt),
      description: Value(_nullIfBlank(draft.description)),
      merchant: Value(_nullIfBlank(draft.merchant)),
      counterparty: Value(_nullIfBlank(draft.counterparty)),
      note: Value(_nullIfBlank(draft.note)),
      tagsJson: Value(draft.tags.isEmpty ? '[]' : jsonEncode(draft.tags)),
      transferGroupId: Value(transferGroupId.isEmpty ? null : transferGroupId),
      feePoisha: Value(
        draft.type == TransactionType.transfer ? draft.feePoisha : 0,
      ),
      source: draft.source,
      recurringRuleId: Value(draft.recurringRuleId),
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  static String? _nullIfBlank(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Future<void> _insertTransferFee(
    TransactionDraft draft, {
    required String groupId,
    required DateTime createdAt,
  }) async {
    final feeCategoryId = await _findFeeCategoryId();
    final feeDraft = TransactionDraft.expense(
      amountPoisha: draft.feePoisha,
      walletId: draft.walletId,
      occurredAt: draft.occurredAt,
      categoryId: feeCategoryId,
      description: 'Transfer fee',
      source: draft.source,
    );
    await _transactions.insert(
      _companionFromDraft(
        feeDraft,
        id: _ids.next(),
        transferGroupId: groupId,
        createdAt: createdAt,
      ),
    );
  }

  Future<String?> _findFeeCategoryId() async {
    final match = await _categories.findByName('Fees & Charges');
    return match?.id;
  }

  Future<void> _deleteGroupRows({
    required String groupId,
    required String exceptId,
  }) async {
    await (_db.delete(_db.transactions)..where(
          (t) =>
              t.transferGroupId.equals(groupId) & t.id.equals(exceptId).not(),
        ))
        .go();
  }

  // ──────────────────────────────────────────────────── (de)serialisation ───

  /// Rebuilds an insert companion from a stored row. Used by undo / restore.
  static local.TransactionsCompanion companionFromRow(
    local.TransactionRow row,
  ) {
    return local.TransactionsCompanion.insert(
      id: row.id,
      type: row.type,
      amountPoisha: row.amountPoisha,
      walletId: row.walletId,
      toWalletId: Value(row.toWalletId),
      categoryId: Value(row.categoryId),
      occurredAt: row.occurredAt,
      dayKey: dayKeyOf(row.occurredAt),
      description: Value(row.description),
      merchant: Value(row.merchant),
      counterparty: Value(row.counterparty),
      note: Value(row.note),
      tagsJson: Value(row.tagsJson),
      transferGroupId: Value(row.transferGroupId),
      feePoisha: Value(row.feePoisha),
      source: row.source,
      recurringRuleId: Value(row.recurringRuleId),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  /// JSON-safe snapshot used by the backup exporter and round-trip tests.
  static Map<String, Object?> rowToJson(local.TransactionRow row) =>
      <String, Object?>{
        'id': row.id,
        'type': row.type.name,
        'amountPoisha': row.amountPoisha,
        'walletId': row.walletId,
        'toWalletId': row.toWalletId,
        'categoryId': row.categoryId,
        'occurredAt': row.occurredAt.toIso8601String(),
        'dayKey': row.dayKey,
        'description': row.description,
        'merchant': row.merchant,
        'counterparty': row.counterparty,
        'note': row.note,
        'tags': row.tagsJson,
        'transferGroupId': row.transferGroupId,
        'feePoisha': row.feePoisha,
        'source': row.source.name,
        'recurringRuleId': row.recurringRuleId,
        'createdAt': row.createdAt.toIso8601String(),
        'updatedAt': row.updatedAt.toIso8601String(),
      };

  static local.TransactionsCompanion companionFromJson(
    Map<String, Object?> json,
  ) {
    final tags = json['tags'];
    return local.TransactionsCompanion.insert(
      id: json['id']! as String,
      type: TransactionType.fromId(json['type']! as String),
      amountPoisha: (json['amountPoisha']! as num).toInt(),
      walletId: json['walletId']! as String,
      toWalletId: Value(json['toWalletId'] as String?),
      categoryId: Value(json['categoryId'] as String?),
      occurredAt: DateTime.parse(json['occurredAt']! as String),
      dayKey: json['dayKey']! as String,
      description: Value(json['description'] as String?),
      merchant: Value(json['merchant'] as String?),
      counterparty: Value(json['counterparty'] as String?),
      note: Value(json['note'] as String?),
      tagsJson: Value(
        tags is String ? tags : jsonEncode(tags ?? const <String>[]),
      ),
      transferGroupId: Value(json['transferGroupId'] as String?),
      feePoisha: Value(((json['feePoisha'] as num?) ?? 0).toInt()),
      source: TransactionSource.fromId(json['source']! as String),
      recurringRuleId: Value(json['recurringRuleId'] as String?),
      createdAt: DateTime.parse(json['createdAt']! as String),
      updatedAt: DateTime.parse(json['updatedAt']! as String),
    );
  }
}
