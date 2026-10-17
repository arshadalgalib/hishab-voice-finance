import '../../core/constants/app_constants.dart';
import '../../domain/enums.dart';
import '../repositories/category_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/wallet_repository.dart';
import '../local/seed_data.dart';

/// First-run setup and idempotent top-ups of the built-in templates.
///
/// Seeding is deliberately non-destructive: it is keyed on `(kind, name)` and
/// on a seed-version marker, so it can run on every launch without duplicating
/// categories or overwriting a user's renames, and a partially completed first
/// run is repaired the next time the app starts.
class SeedService {
  SeedService({
    required CategoryRepository categories,
    required WalletRepository wallets,
    required SettingsRepository settings,
  }) : _categories = categories,
       _wallets = wallets,
       _settings = settings;

  final CategoryRepository _categories;
  final WalletRepository _wallets;
  final SettingsRepository _settings;

  /// Creates default categories plus a first wallet. Returns true when
  /// anything was created, so onboarding can tell whether this is a first run.
  Future<bool> ensureSeeded() async {
    final settings = await _settings.load();
    var created = false;

    final inserted = await _categories.ensureDefaultCategories();
    created = created || inserted > 0;

    final existing = await _wallets.rows(includeArchived: true);
    if (existing.isEmpty) {
      await _wallets.createWallet(
        name: 'Cash',
        type: WalletType.cash,
        isDefaultIncome: true,
        isDefaultExpense: true,
        note:
            'Created automatically so you can start right away. '
            'Rename it or add more wallets any time.',
      );
      created = true;
    }

    if (settings.seedVersion < SettingKeys.currentSeedVersion) {
      await _settings.update(
        (current) =>
            current.copyWith(seedVersion: SettingKeys.currentSeedVersion),
      );
    }
    return created;
  }

  /// Templates offered during onboarding, so the user can add their real
  /// wallets in one tap without any of them being created silently.
  List<DefaultWalletTemplate> get walletTemplates => kDefaultWalletTemplates;

  /// Creates the wallets the user picked during onboarding. Never re-creates a
  /// wallet whose name already exists.
  Future<int> createChosenWallets(
    Iterable<DefaultWalletTemplate> templates,
  ) async {
    var count = 0;
    final existing = await _wallets.rows(includeArchived: true);
    final names = existing.map((w) => w.name.toLowerCase()).toSet();
    for (final template in templates) {
      if (names.contains(template.name.toLowerCase())) continue;
      await _wallets.createWallet(
        name: template.name,
        type: template.type,
        institution: template.institution,
      );
      count++;
    }
    return count;
  }
}
