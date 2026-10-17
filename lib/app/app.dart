import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_lock_gate.dart';
import 'providers.dart';
import 'router.dart';
import 'startup.dart';
import 'theme.dart';

/// Display name shown by the task switcher and the about screen.
const String kAppName = 'Hishab — Voice Finance';
const String kAppVersion = '1.0.0+1';

/// Root widget.
///
/// Startup happens in three plain stages so nothing is guessed: splash (opening
/// and seeding the database), a failure screen if that is impossible, and only
/// then the real router. The onboarding redirect lives in the router, which
/// means a half-configured install cannot sneak past it.
class HishabApp extends ConsumerWidget {
  const HishabApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(startupProvider);
    final settings = ref.watch(appSettingsProvider);

    if (startup.hasError) {
      return MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: StartupFailureScreen(
          message: describeStartupError(startup.error!),
          onRetry: () => ref.invalidate(startupProvider),
        ),
      );
    }

    if (!startup.hasValue || !settings.hasValue) {
      return MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const StartupSplash(),
      );
    }

    final preferences = settings.requireValue;
    return MaterialApp.router(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: preferences.themeMode,
      locale: Locale(preferences.languageCode),
      supportedLocales: const <Locale>[Locale('en'), Locale('bn')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) =>
          AppLockGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
