import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/repositories/wallet_repository.dart';
import '../domain/category_matcher.dart';
import '../domain/voice_parse_result.dart';
import '../domain/wallet_alias_matcher.dart';

/// Builds the [ParserContext] the voice parser needs.
///
/// Reading wallets and categories fresh before every interpretation is what
/// makes the voice flow honest: if the user archived a wallet five seconds ago,
/// the parser can no longer match it, and if they just added a category the
/// parser can use it immediately.
class VoiceContextFactory {
  VoiceContextFactory({
    required WalletRepository wallets,
    required CategoryRepository categories,
    required SettingsRepository settings,
    DateTime Function()? now,
  }) : _wallets = wallets,
       _categories = categories,
       _settings = settings,
       _now = now ?? DateTime.now;

  final WalletRepository _wallets;
  final CategoryRepository _categories;
  final SettingsRepository _settings;
  final DateTime Function() _now;

  Future<ParserContext> build() async {
    final settings = await _settings.load();
    final wallets = await walletCandidates();
    final categories = await categoryCandidates();
    return ParserContext(
      wallets: wallets,
      categories: categories,
      now: _now(),
      defaultIncomeWalletId: settings.defaultIncomeWalletId,
      defaultExpenseWalletId: settings.defaultExpenseWalletId,
    );
  }

  Future<List<WalletCandidate>> walletCandidates() async {
    final rows = await _wallets.rows(includeArchived: true);
    return rows
        .map(
          (row) => WalletCandidate(
            id: row.id,
            name: row.name,
            type: row.type,
            isArchived: row.isArchived,
            isDefaultIncome: row.isDefaultIncome,
            isDefaultExpense: row.isDefaultExpense,
          ),
        )
        .toList(growable: false);
  }

  Future<List<CategoryCandidate>> categoryCandidates() async {
    final rows = await _categories.list(includeArchived: true);
    return rows
        .map(
          (row) => CategoryCandidate(
            id: row.id,
            name: row.name,
            kind: row.kind,
            keywords: CategoryRepository.keywordsOf(row),
          ),
        )
        .toList(growable: false);
  }
}
