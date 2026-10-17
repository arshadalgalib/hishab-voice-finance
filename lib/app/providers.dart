import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/build_config.dart';
import '../core/security/pin_service.dart';
import '../core/security/secure_store.dart';
import '../core/utils/id_generator.dart';
import '../data/local/app_database.dart';
import '../data/local/connection.dart';
import '../data/repositories/budget_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/goal_repository.dart';
import '../data/repositories/loan_repository.dart';
import '../data/repositories/recurring_repository.dart';
import '../data/repositories/reminder_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../data/repositories/wallet_repository.dart';
import '../data/services/alert_service.dart';
import '../data/services/backup_service.dart';
import '../data/services/csv_export_service.dart';
import '../data/services/notification_service.dart';
import '../data/services/seed_service.dart';
import '../domain/enums.dart';
import '../domain/models/aggregates.dart';
import '../domain/models/app_settings.dart';
import '../domain/models/budget_progress.dart';
import '../domain/models/date_range.dart';
import '../domain/models/transaction_filter.dart';
import '../domain/services/budget_service.dart';
import '../domain/services/goal_service.dart';
import '../domain/services/loan_service.dart';
import '../domain/services/recurring_service.dart';
import '../domain/services/report_service.dart';
import '../domain/services/transaction_service.dart';
import '../domain/services/undo_service.dart';
import '../features/voice/application/native_speech_recognizer.dart';
import '../features/voice/application/speech_recognizer.dart';
import '../features/voice/application/voice_context_factory.dart';
import '../features/voice/application/voice_controller.dart';
import '../features/voice/application/voice_interpreter.dart';

/// ────────────────────────────────────────────────────────────────
/// Dependency-injection graph.
///
/// Every provider is *overridable*, so `ProviderScope(overrides: [...])` can
/// swap the database for an in-memory one, the recogniser for a fake, or the
/// clock for a fixed one in tests. Nothing in the app constructs a dependency
/// for itself.
/// ────────────────────────────────────────────────────────────────

// ── infrastructure ─────────────────────────────────────────────────────────

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase(openAppDatabaseConnection());
  ref.onDispose(database.close);
  return database;
});

final clockProvider = Provider<Clock>((ref) => const SystemClock());

final idGeneratorProvider = Provider<IdGenerator>(
  (ref) => const UuidGenerator(),
);

final secureStoreProvider = Provider<SecureStore>(
  (ref) => FlutterSecureStore(),
);

final pinServiceProvider = Provider<PinService>(
  (ref) => PinService(ref.watch(secureStoreProvider)),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

// ── repositories ───────────────────────────────────────────────────────────

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider)),
);

final walletRepositoryProvider = Provider<WalletRepository>(
  (ref) => WalletRepository(
    db: ref.watch(appDatabaseProvider),
    settings: ref.watch(settingsRepositoryProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(
    db: ref.watch(appDatabaseProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepository(ref.watch(appDatabaseProvider)),
);

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepository(
    db: ref.watch(appDatabaseProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

final goalRepositoryProvider = Provider<GoalRepository>(
  (ref) => GoalRepository(
    db: ref.watch(appDatabaseProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

final recurringRepositoryProvider = Provider<RecurringRepository>(
  (ref) => RecurringRepository(
    db: ref.watch(appDatabaseProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

final reminderRepositoryProvider = Provider<ReminderRepository>(
  (ref) => ReminderRepository(
    db: ref.watch(appDatabaseProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
    alerts: ref.watch(alertServiceProvider),
  ),
);

final loanRepositoryProvider = Provider<LoanRepository>(
  (ref) => LoanRepository(
    db: ref.watch(appDatabaseProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

// ── domain services ────────────────────────────────────────────────────────

final transactionServiceProvider = Provider<TransactionService>(
  (ref) => TransactionService(
    db: ref.watch(appDatabaseProvider),
    transactions: ref.watch(transactionRepositoryProvider),
    wallets: ref.watch(walletRepositoryProvider),
    categories: ref.watch(categoryRepositoryProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

final reportServiceProvider = Provider<ReportService>(
  (ref) =>
      ReportService(transactions: ref.watch(transactionRepositoryProvider)),
);

final budgetServiceProvider = Provider<BudgetService>(
  (ref) => BudgetService(budgets: ref.watch(budgetRepositoryProvider)),
);

final goalServiceProvider = Provider<GoalService>(
  (ref) => GoalService(
    goals: ref.watch(goalRepositoryProvider),
    transactions: ref.watch(transactionServiceProvider),
  ),
);

final recurringServiceProvider = Provider<RecurringService>(
  (ref) => RecurringService(
    rules: ref.watch(recurringRepositoryProvider),
    transactions: ref.watch(transactionServiceProvider),
    db: ref.watch(appDatabaseProvider),
  ),
);

final loanServiceProvider = Provider<LoanService>(
  (ref) => LoanService(
    loans: ref.watch(loanRepositoryProvider),
    transactions: ref.watch(transactionServiceProvider),
  ),
);

final undoServiceProvider = Provider<UndoService>(
  (ref) => UndoService(now: () => ref.read(clockProvider).now()),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    db: ref.watch(appDatabaseProvider),
    now: () => ref.read(clockProvider).now(),
  ),
);

/// Budget and reminder notifications. Deliberately independent of the writing
/// services so a missing notification plugin can never affect a save.
final alertServiceProvider = Provider<AlertService>(
  (ref) => AlertService(
    budgets: ref.watch(budgetServiceProvider),
    settings: ref.watch(settingsRepositoryProvider),
    notifications: ref.watch(notificationServiceProvider),
  ),
);

final csvExportServiceProvider = Provider<CsvExportService>(
  (ref) =>
      CsvExportService(transactions: ref.watch(transactionRepositoryProvider)),
);

final seedServiceProvider = Provider<SeedService>(
  (ref) => SeedService(
    categories: ref.watch(categoryRepositoryProvider),
    wallets: ref.watch(walletRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
  ),
);

// ── voice ──────────────────────────────────────────────────────────────────

/// The recogniser is a seam: tests override this with a fake so the whole voice
/// flow runs without a microphone.
final speechRecognizerProvider = Provider<SpeechRecognizer>(
  (ref) => NativeSpeechRecognizer(),
);

/// Whether online interpretation will actually be used.
///
/// The user's endpoint wins; if they have not set one, a compile-time default
/// (`--dart-define=PFM_CLOUD_SPEECH_ENDPOINT=...`) is honoured. Online mode is
/// still gated behind the explicit `cloud` provider switch.
bool onlineInterpretationActive(AppSettings settings) =>
    settings.voiceProviderId == 'cloud' &&
    BuildConfig.resolveCloudSpeechEndpoint(settings.cloudSpeechEndpoint) !=
        null;

final onlineInterpreterFactoryProvider =
    Provider<Future<OnlineVoiceInterpreter?> Function()>((ref) {
      return () async {
        final settings = await ref.read(settingsRepositoryProvider).load();
        if (!onlineInterpretationActive(settings)) return null;
        final endpoint = BuildConfig.resolveCloudSpeechEndpoint(
          settings.cloudSpeechEndpoint,
        )!;
        final store = ref.read(secureStoreProvider);
        return OnlineVoiceInterpreter(
          endpoint: endpoint,
          languageCode: settings.cloudSpeechLanguageCode,
          tokenReader: () => store.read(SecureKeys.cloudSpeechToken),
        );
      };
    });

/// Alias used by the voice controller.
final onlineInterpreterProvider = onlineInterpreterFactoryProvider;

final voiceContextFactoryProvider = Provider<VoiceContextFactory>(
  (ref) => VoiceContextFactory(
    wallets: ref.watch(walletRepositoryProvider),
    categories: ref.watch(categoryRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    now: () => ref.read(clockProvider).now(),
  ),
);

final voiceControllerProvider =
    NotifierProvider<VoiceController, VoiceSessionState>(VoiceController.new);

// ── settings ───────────────────────────────────────────────────────────────

final appSettingsProvider = StreamProvider<AppSettings>(
  (ref) => ref.watch(settingsRepositoryProvider).watch(),
);

final themeModeProvider = Provider<ThemeMode>((ref) {
  // Android's own theme is the default; the user can pin light or dark.
  return ref.watch(appSettingsProvider).value?.themeMode ?? ThemeMode.system;
});

final onboardingCompletedProvider = Provider<bool>(
  (ref) => ref.watch(appSettingsProvider).value?.onboardingCompleted ?? false,
);

/// Seeds default categories and a first wallet exactly once. Safe to call on
/// every launch because seeding is keyed and idempotent.
final bootstrapProvider = FutureProvider<bool>((ref) async {
  final seeded = await ref.watch(seedServiceProvider).ensureSeeded();
  return seeded;
});

// ── read models ────────────────────────────────────────────────────────────

final walletBalancesProvider = StreamProvider<List<WalletBalance>>(
  (ref) => ref.watch(walletRepositoryProvider).watchBalances(),
);

final activeWalletBalancesProvider = StreamProvider<List<WalletBalance>>(
  (ref) =>
      ref.watch(walletRepositoryProvider).watchBalances(includeArchived: false),
);

final allCategoriesProvider = StreamProvider<List<CategoryRow>>(
  (ref) => ref.watch(categoryRepositoryProvider).watch(includeArchived: true),
);

final expenseCategoriesProvider = StreamProvider<List<CategoryRow>>(
  (ref) =>
      ref.watch(categoryRepositoryProvider).watch(kind: CategoryKind.expense),
);

final incomeCategoriesProvider = StreamProvider<List<CategoryRow>>(
  (ref) =>
      ref.watch(categoryRepositoryProvider).watch(kind: CategoryKind.income),
);

final budgetProgressProvider = StreamProvider<List<BudgetProgress>>(
  (ref) => ref.watch(budgetRepositoryProvider).watchProgressList(),
);

final goalProgressProvider = StreamProvider<List<GoalProgress>>(
  (ref) => ref.watch(goalRepositoryProvider).watchProgressList(),
);

final loanProgressProvider = FutureProvider<List<LoanProgress>>(
  (ref) => ref.watch(loanRepositoryProvider).progressList(),
);

final remindersProvider = StreamProvider<List<ReminderRow>>(
  (ref) => ref.watch(reminderRepositoryProvider).watch(),
);

final recurringRulesProvider = StreamProvider<List<RecurringRuleRow>>(
  (ref) => ref.watch(recurringRepositoryProvider).watch(),
);

final pendingRecurringProvider = FutureProvider<List<RecurringRuleRow>>(
  (ref) => ref.watch(recurringServiceProvider).awaitingConfirmation(),
);

final auditLogProvider = StreamProvider<List<AuditLogRow>>(
  (ref) => ref.watch(appDatabaseProvider).watchAuditLogs(),
);

final undoEntryProvider = Provider<ValueListenable<UndoEntry?>>(
  (ref) => ref.watch(undoServiceProvider).pendingNotifier,
);

final frequentTagsProvider = StreamProvider<List<String>>(
  (ref) => ref.watch(transactionRepositoryProvider).watchTags(),
);

/// The current month, used as the dashboard's default window.
final currentMonthRangeProvider = Provider<DateRange>(
  (ref) => DateRange.month(ref.watch(clockProvider).now()),
);

final dashboardReportProvider = FutureProvider<PeriodReport>((ref) async {
  final range = ref.watch(currentMonthRangeProvider);
  return ref.watch(reportServiceProvider).reportFor(range);
});

final monthlyTrendProvider = FutureProvider<List<TrendPoint>>(
  (ref) => ref.watch(reportServiceProvider).monthlyTrend(months: 6),
);

final totalBalanceProvider = StreamProvider<int>(
  (ref) => ref.watch(walletRepositoryProvider).watchTotalBalance(),
);

// ── transaction list ───────────────────────────────────────────────────────

/// Holds the history screen's filter. Kept in a notifier so the stream provider
/// below rebuilds only when the filter actually changes.
class TransactionFilterController extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() => const TransactionFilter();

  void update(TransactionFilter filter) => state = filter;

  void setRange(DateRange? range) =>
      state = state.copyWith(range: range, clearRange: range == null);

  void setTypes(Set<TransactionType> types) =>
      state = state.copyWith(types: types);

  void setWallets(Set<String> walletIds) =>
      state = state.copyWith(walletIds: walletIds);

  void setCategories(Set<String> categoryIds) =>
      state = state.copyWith(categoryIds: categoryIds);

  void setSearch(String? text) => state = state.copyWith(
    searchText: text,
    clearSearch: text == null || text.trim().isEmpty,
  );

  void setSort(TransactionSort sort) => state = state.copyWith(sort: sort);

  void clear() => state = const TransactionFilter();
}

final transactionFilterProvider =
    NotifierProvider<TransactionFilterController, TransactionFilter>(
      TransactionFilterController.new,
    );

final filteredTransactionsProvider = StreamProvider<List<TransactionListItem>>((
  ref,
) {
  final filter = ref.watch(transactionFilterProvider);
  return ref.watch(transactionRepositoryProvider).watch(filter);
});

final recentTransactionsProvider = StreamProvider<List<TransactionListItem>>((
  ref,
) {
  return ref.watch(transactionRepositoryProvider).watchRecent(limit: 8);
});

final transactionDetailProvider =
    StreamProvider.family<TransactionListItem?, String>((ref, id) {
      return ref.watch(transactionRepositoryProvider).watchOne(id);
    });

final transactionCountProvider = FutureProvider<int>((ref) {
  final filter = ref.watch(transactionFilterProvider);
  return ref.watch(transactionRepositoryProvider).count(filter: filter);
});
