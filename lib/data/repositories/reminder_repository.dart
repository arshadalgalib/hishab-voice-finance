import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/id_generator.dart';
import '../local/app_database.dart';

/// A reminder write-back channel for the device notification that belongs to a
/// reminder.
///
/// Optional and nullable on the repository so it can be constructed in tests,
/// and on platforms without a notification plugin, with no sink at all. The
/// repository never depends on the notification plugin directly.
abstract class ReminderAlertSink {
  Future<void> scheduleReminder(ReminderRow reminder);

  Future<void> cancelReminder(String reminderId);
}

/// Bill / payment reminders.
class ReminderRepository {
  ReminderRepository({
    required AppDatabase db,
    required IdGenerator ids,
    required Clock clock,
    ReminderAlertSink? alerts,
  }) : _db = db,
       _ids = ids,
       _clock = clock,
       _alerts = alerts;

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;
  final ReminderAlertSink? _alerts;

  Stream<List<ReminderRow>> watch({bool includePaid = true}) =>
      _db.watchReminders(includePaid: includePaid);

  Future<List<ReminderRow>> list({bool includePaid = true}) =>
      _db.getReminders(includePaid: includePaid);

  Future<String> create({
    required String title,
    required DateTime dueDate,
    int? amountPoisha,
    String? walletId,
    String? categoryId,
    String? note,
    int reminderDaysBefore = 0,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException(
        'Reminder title is required.',
        field: 'title',
      );
    }
    if (amountPoisha != null && amountPoisha < 0) {
      throw const ValidationException(
        'Amount cannot be negative.',
        field: 'amount',
      );
    }
    if (reminderDaysBefore < 0) {
      throw const ValidationException(
        'Remind-before days cannot be negative.',
        field: 'daysBefore',
      );
    }
    final id = _ids.next();
    final now = _clock.now();
    await _db.upsertReminder(
      RemindersCompanion.insert(
        id: id,
        title: trimmed,
        amountPoisha: Value(amountPoisha),
        dueDate: dueDate,
        walletId: Value(walletId),
        categoryId: Value(categoryId),
        note: Value(note?.trim()),
        reminderDaysBefore: Value(reminderDaysBefore),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _syncAlert(id);
    return id;
  }

  Future<void> update(
    String id, {
    String? title,
    int? amountPoisha,
    bool clearAmount = false,
    DateTime? dueDate,
    String? walletId,
    String? categoryId,
    String? note,
    int? reminderDaysBefore,
    bool? isPaid,
  }) async {
    final existing = await (_db.select(
      _db.reminders,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing == null) {
      throw const NotFoundException('That reminder no longer exists.');
    }
    await _db.upsertReminder(
      RemindersCompanion(
        id: Value(id),
        title: title == null ? const Value.absent() : Value(title.trim()),
        amountPoisha: clearAmount
            ? const Value(null)
            : (amountPoisha == null
                  ? const Value.absent()
                  : Value(amountPoisha)),
        dueDate: dueDate == null ? const Value.absent() : Value(dueDate),
        walletId: walletId == null ? const Value.absent() : Value(walletId),
        categoryId: categoryId == null
            ? const Value.absent()
            : Value(categoryId),
        note: note == null ? const Value.absent() : Value(note.trim()),
        reminderDaysBefore: reminderDaysBefore == null
            ? const Value.absent()
            : Value(reminderDaysBefore),
        isPaid: isPaid == null ? const Value.absent() : Value(isPaid),
        updatedAt: Value(_clock.now()),
      ),
    );
    await _syncAlert(id);
  }

  Future<void> markPaid(String id, {bool paid = true}) =>
      update(id, isPaid: paid);

  Future<void> delete(String id) async {
    await _db.deleteReminder(id);
    await _alerts?.cancelReminder(id);
  }

  /// Pushes the current state of a reminder to the notification sink.
  ///
  /// Failures are swallowed: a reminder that could not be scheduled is still
  /// saved, and the next app start re-schedules everything anyway.
  Future<void> _syncAlert(String id) async {
    final sink = _alerts;
    if (sink == null) return;
    final row = await (_db.select(
      _db.reminders,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    try {
      await sink.scheduleReminder(row);
    } catch (_) {
      // Ignored on purpose.
    }
  }

  /// Unpaid reminders due within [days] (or already overdue).
  Future<List<ReminderRow>> due({DateTime? asOf, int days = 30}) async {
    final now = asOf ?? _clock.now();
    final horizon = endOfDay(now.add(Duration(days: days)));
    final reminders = await list(includePaid: false);
    return reminders
        .where((reminder) => !reminder.dueDate.isAfter(horizon))
        .toList(growable: false);
  }

  static bool isOverdue(ReminderRow reminder, {DateTime? now}) =>
      !reminder.isPaid &&
      reminder.dueDate.isBefore(startOfDay(now ?? DateTime.now()));
}
