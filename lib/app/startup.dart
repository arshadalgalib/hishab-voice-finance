import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exception.dart';
import 'providers.dart';
import 'theme.dart';

/// One-time startup work.
///
/// Seeding is idempotent and keyed, so a crash halfway through the very first
/// run is repaired on the next launch rather than leaving a half-populated
/// database. Notification setup is best-effort: a device that refuses to
/// initialise the plugin must still be able to record money.
final startupProvider = FutureProvider<void>((ref) async {
  await ref.watch(bootstrapProvider.future);
  await ref.watch(notificationServiceProvider).initialize();
  // A reminder created before the last restart (or restored from a backup) has
  // no scheduled notification yet, so every launch re-syncs them.
  final reminders = await ref
      .watch(reminderRepositoryProvider)
      .list(includePaid: true);
  await ref.watch(alertServiceProvider).syncReminders(reminders);
});

/// Shown while the database is opened and seeded.
class StartupSplash extends StatelessWidget {
  const StartupSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.seed.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  size: 56,
                  color: AppColors.seed,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Hishab',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Voice-first money tracking for Bangladesh',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the database could not be opened at all.
///
/// The message is whatever the domain layer produced; it never contains SQL or
/// a stack trace.
class StartupFailureScreen extends StatelessWidget {
  const StartupFailureScreen({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.storage_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                'Hishab could not start',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Turns any startup failure into a message that is safe to display.
String describeStartupError(Object error) {
  if (error is AppException) return error.message;
  return 'The local database could not be opened. Your data has not been '
      'changed. Restart the app, and if this keeps happening restore from a '
      'backup.';
}
