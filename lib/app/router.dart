import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/enums.dart';
import '../features/budgets/presentation/budgets_screen.dart';
import '../features/categories/presentation/categories_screen.dart';
import '../features/categories/presentation/category_form_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/goals/presentation/goal_detail_screen.dart';
import '../features/goals/presentation/goals_screen.dart';
import '../features/loans/presentation/loan_detail_screen.dart';
import '../features/loans/presentation/loans_screen.dart';
import '../features/more/presentation/more_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/recurring/presentation/recurring_form_screen.dart';
import '../features/recurring/presentation/recurring_screen.dart';
import '../features/reminders/presentation/reminder_form_screen.dart';
import '../features/reminders/presentation/reminders_screen.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/settings/presentation/audit_log_screen.dart';
import '../features/settings/presentation/data_screen.dart';
import '../features/settings/presentation/security_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/settings/presentation/voice_settings_screen.dart';
import '../features/transactions/presentation/history_screen.dart';
import '../features/transactions/presentation/transaction_detail_screen.dart';
import '../features/transactions/presentation/transaction_form_screen.dart';
import '../features/voice/presentation/voice_capture_screen.dart';
import '../features/wallets/presentation/wallet_detail_screen.dart';
import '../features/wallets/presentation/wallet_form_screen.dart';
import '../features/wallets/presentation/wallets_screen.dart';
import 'providers.dart';

/// Notifies `GoRouter` when a setting changes so the onboarding redirect is
/// re-evaluated. Without it, finishing onboarding would leave the user stuck on
/// the welcome screen until the next navigation.
///
/// The underlying subscription is owned by the Riverpod container (it is
/// created inside a `Provider`), so there is nothing to close by hand.
class RouterRefresh extends ChangeNotifier {
  RouterRefresh(Ref ref) {
    ref.listen(appSettingsProvider, (previous, next) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final settings = ref.read(appSettingsProvider).value;
      // Settings are still loading: `HishabApp` is showing the splash, so
      // deciding anything here would be guessing.
      if (settings == null) return null;

      final atOnboarding = state.matchedLocation == '/onboarding';
      if (!settings.onboardingCompleted) {
        return atOnboarding ? null : '/onboarding';
      }
      if (atOnboarding) return '/';
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) =>
            OnboardingScreen(onFinished: () => context.go('/')),
      ),
      // The four persistent destinations. Everything else is pushed on top,
      // which keeps the tab bar visible only where it is useful.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/',
                name: 'dashboard',
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/history',
                name: 'history',
                builder: (context, state) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/voice',
                name: 'voice',
                builder: (context, state) => const VoiceCaptureScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/more',
                name: 'more',
                builder: (context, state) => const MoreScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/budgets',
        name: 'budgets',
        builder: (context, state) => const BudgetsScreen(),
      ),
      GoRoute(
        path: '/reports',
        name: 'reports',
        builder: (context, state) => const ReportsScreen(),
      ),
      GoRoute(
        path: '/wallets',
        name: 'wallets',
        builder: (context, state) => const WalletsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'new',
            name: 'wallet-form',
            builder: (context, state) =>
                WalletFormScreen(walletId: state.extra as String?),
          ),
          GoRoute(
            path: ':id',
            name: 'wallet-detail',
            builder: (context, state) =>
                WalletDetailScreen(walletId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/categories',
        name: 'categories',
        builder: (context, state) => const CategoriesScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'new',
            name: 'category-form',
            builder: (context, state) =>
                CategoryFormScreen(categoryId: state.extra as String?),
          ),
        ],
      ),
      GoRoute(
        path: '/transactions',
        routes: <RouteBase>[
          GoRoute(
            path: 'new',
            name: 'transaction-form',
            builder: (context, state) => TransactionFormScreen(
              initialType: _typeFromQuery(state.uri.queryParameters['type']),
              transactionId: state.extra as String?,
            ),
          ),
          GoRoute(
            path: ':id',
            name: 'transaction-detail',
            builder: (context, state) => TransactionDetailScreen(
              transactionId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/goals',
        name: 'goals',
        builder: (context, state) => const GoalsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: ':id',
            name: 'goal-detail',
            builder: (context, state) =>
                GoalDetailScreen(goalId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/recurring',
        name: 'recurring',
        builder: (context, state) => const RecurringScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'new',
            name: 'recurring-form',
            builder: (context, state) =>
                RecurringFormScreen(ruleId: state.extra as String?),
          ),
        ],
      ),
      GoRoute(
        path: '/reminders',
        name: 'reminders',
        builder: (context, state) => const RemindersScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'new',
            name: 'reminder-form',
            builder: (context, state) =>
                ReminderFormScreen(reminderId: state.extra as String?),
          ),
        ],
      ),
      GoRoute(
        path: '/loans',
        name: 'loans',
        builder: (context, state) => const LoansScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: ':id',
            name: 'loan-detail',
            builder: (context, state) =>
                LoanDetailScreen(loanId: state.pathParameters['id']!),
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) => const SettingsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'voice',
            name: 'settings-voice',
            builder: (context, state) => const VoiceSettingsScreen(),
          ),
          GoRoute(
            path: 'security',
            name: 'settings-security',
            builder: (context, state) => const SecurityScreen(),
          ),
          GoRoute(
            path: 'data',
            name: 'settings-data',
            builder: (context, state) => const DataScreen(),
          ),
          GoRoute(
            path: 'audit',
            name: 'settings-audit',
            builder: (context, state) => const AuditLogScreen(),
          ),
        ],
      ),
    ],
  );
});

TransactionType? _typeFromQuery(String? value) {
  if (value == null) return null;
  return TransactionType.values.where((type) => type.name == value).firstOrNull;
}

/// The persistent frame: a `NavigationBar` around whichever branch is active.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          // Tapping the destination you are already on returns it to its root,
          // which is what users expect from a tab bar.
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_none_outlined),
            selectedIcon: Icon(Icons.mic),
            label: 'Voice',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            selectedIcon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
