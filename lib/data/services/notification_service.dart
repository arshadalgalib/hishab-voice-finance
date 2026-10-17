import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/models/budget_progress.dart';

/// Local notifications for budget thresholds and bill reminders.
///
/// Everything is scheduled on-device. No push service, no FCM, no account. The
/// plugin throws on unsupported platforms (unit tests, desktop), so every call
/// is wrapped and a failure degrades to "no notification" rather than breaking
/// a financial write.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  bool _initialized = false;
  bool _available = true;

  static const String _channelBudgets = 'pfm_budgets';
  static const String _channelReminders = 'pfm_reminders';

  /// True when the platform plugin accepted initialisation.
  bool get isAvailable => _available && _initialized;

  Future<void> initialize() async {
    if (_initialized || !_available) return;
    try {
      tz_data.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        // Fall back to UTC; schedules are still correct relative to the device
        // clock in the common case and never crash the app.
      }

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(settings: settings);
      _initialized = true;
    } catch (error, stack) {
      _available = false;
      debugPrint('Notifications unavailable: $error\n$stack');
    }
  }

  /// Asks Android 13+ for the POST_NOTIFICATIONS permission.
  Future<bool> requestPermissions() async {
    await initialize();
    if (!_available) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (_) {
      return false;
    }
  }

  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String channel = _channelBudgets,
  }) async {
    await initialize();
    if (!_available) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _detailsFor(channel),
      );
    } catch (error) {
      debugPrint('Could not show notification: $error');
    }
  }

  /// Schedules a one-shot notification at [when]. Times in the past are shown
  /// immediately rather than silently dropped.
  Future<void> scheduleAt({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String channel = _channelReminders,
  }) async {
    await initialize();
    if (!_available) return;
    try {
      final scheduled = tz.TZDateTime.from(when, tz.local);
      if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) {
        await showNow(id: id, title: title, body: body, channel: channel);
        return;
      }
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduled,
        notificationDetails: _detailsFor(channel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (error) {
      debugPrint('Could not schedule notification: $error');
    }
  }

  Future<void> cancel(int id) async {
    if (!_available) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {
      // Ignore: a missing notification is never worth an error dialog.
    }
  }

  Future<void> cancelAll() async {
    if (!_available) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {
      // Ignore.
    }
  }

  /// Notification shown when a budget crosses its alert threshold or is
  /// exceeded. One notification per (budget, period, threshold) is enforced by
  /// the caller through the `budget_alerts` table, not by this service.
  Future<void> notifyBudget(BudgetProgress progress) async {
    final overBudget = progress.isOverBudget;
    final title = overBudget
        ? 'Budget exceeded: ${progress.name}'
        : 'Budget alert: ${progress.name}';
    final body = overBudget
        ? 'You have spent the full ৳${_taka(progress.amountPoisha)} budget '
              'for this period.'
        : 'You have used ${progress.percentUsed.toStringAsFixed(0)}% of your '
              '৳${_taka(progress.amountPoisha)} budget.';
    await showNow(
      id: budgetNotificationId(progress.budgetId),
      title: title,
      body: body,
    );
  }

  Future<void> notifyReminder({
    required String reminderId,
    required String title,
    required DateTime dueDate,
    int? amountPoisha,
    int daysBefore = 0,
  }) async {
    final amountText = amountPoisha == null || amountPoisha <= 0
        ? ''
        : ' (৳${_taka(amountPoisha)})';
    final when = dueDate.subtract(Duration(days: daysBefore));
    final whenText = daysBefore == 0
        ? 'today'
        : 'on ${when.day}/${when.month}/${when.year}';
    await scheduleAt(
      id: reminderNotificationId(reminderId),
      title: 'Reminder: $title$amountText',
      body: 'Due $whenText.',
      when: DateTime(when.year, when.month, when.day, 9),
    );
  }

  NotificationDetails _detailsFor(String channel) {
    switch (channel) {
      case _channelReminders:
        return const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelReminders,
            'Bill reminders',
            channelDescription: 'Reminders for upcoming bills and payments',
            importance: Importance.high,
            priority: Priority.high,
          ),
        );
      default:
        return const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelBudgets,
            'Budget alerts',
            channelDescription: 'Warnings when a budget threshold is reached',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        );
    }
  }

  /// Stable, collision-resistant notification ids derived from the entity id, so
  /// re-notifying replaces the previous notification instead of stacking.
  static int budgetNotificationId(String budgetId) =>
      1000000 + (budgetId.hashCode & 0x0FFFFFFF);

  static int reminderNotificationId(String reminderId) =>
      2000000 + (reminderId.hashCode & 0x0FFFFFFF);

  static String _taka(int poisha) {
    final whole = poisha ~/ 100;
    final fraction = poisha % 100;
    return fraction == 0
        ? whole.toString()
        : '$whole.${fraction.toString().padLeft(2, '0')}';
  }
}
