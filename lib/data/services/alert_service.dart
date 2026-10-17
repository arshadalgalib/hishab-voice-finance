import '../../domain/services/budget_service.dart';
import '../local/app_database.dart';
import '../repositories/reminder_repository.dart';
import '../repositories/settings_repository.dart';
import 'notification_service.dart';

/// The one place that decides whether a financial event is allowed to interrupt
/// the user with a notification.
///
/// Writing a transaction and telling the user about a budget must not be
/// coupled: a device whose notification plugin failed to initialise still
/// records everything perfectly, and nothing here ever throws into a save path.
class AlertService implements ReminderAlertSink {
  AlertService({
    required BudgetService budgets,
    required SettingsRepository settings,
    required NotificationService notifications,
  }) : _budgets = budgets,
       _settings = settings,
       _notifications = notifications;

  final BudgetService _budgets;
  final SettingsRepository _settings;
  final NotificationService _notifications;

  /// Announces (and permanently records) every budget threshold that has been
  /// crossed since the last check.
  ///
  /// Safe to call after any write: `BudgetService` keeps at most one alert per
  /// budget, period and threshold, so calling it twice does nothing the second
  /// time.
  Future<void> announceBudgetAlerts() async {
    try {
      final alerts = await _budgets.consumePending();
      if (alerts.isEmpty) return;
      final preferences = await _settings.load();
      if (!preferences.notificationsEnabled ||
          !preferences.budgetAlertsEnabled) {
        return;
      }
      for (final alert in alerts) {
        await _notifications.notifyBudget(alert.progress);
      }
    } catch (_) {
      // A notification must never be able to fail a saved transaction.
    }
  }

  /// Re-schedules every unpaid reminder and clears the ones already paid.
  ///
  /// Called on start-up so a reminder created before a device restart, or one
  /// restored from a backup, still fires.
  Future<void> syncReminders(List<ReminderRow> reminders) async {
    try {
      for (final reminder in reminders) {
        await scheduleReminder(reminder);
      }
    } catch (_) {
      // Same reasoning as above.
    }
  }

  @override
  Future<void> scheduleReminder(ReminderRow reminder) async {
    try {
      if (reminder.isPaid) {
        await cancelReminder(reminder.id);
        return;
      }
      final preferences = await _settings.load();
      if (!preferences.notificationsEnabled ||
          !preferences.reminderAlertsEnabled) {
        await cancelReminder(reminder.id);
        return;
      }
      await _notifications.notifyReminder(
        reminderId: reminder.id,
        title: reminder.title,
        dueDate: reminder.dueDate,
        amountPoisha: reminder.amountPoisha,
        daysBefore: reminder.reminderDaysBefore,
      );
    } catch (_) {
      // Ignored on purpose: a reminder is still useful without a notification.
    }
  }

  @override
  Future<void> cancelReminder(String reminderId) async {
    try {
      await _notifications.cancel(
        NotificationService.reminderNotificationId(reminderId),
      );
    } catch (_) {
      // Ignored on purpose.
    }
  }
}
