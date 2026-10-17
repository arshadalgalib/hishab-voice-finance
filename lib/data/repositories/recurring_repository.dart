import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/enums.dart';
import '../../domain/models/date_range.dart';
import '../local/app_database.dart';

/// Recurring income/expense/transfer rules.
///
/// Rules never post silently: [autoPost] defaults to `false`, which means the
/// rule produces an *upcoming* entry the user confirms. Even when auto-posting
/// is enabled, posting is idempotent per due date because the rule's
/// `nextDueDate` is advanced inside the same transaction that inserts the
/// transaction.
class RecurringRepository {
  RecurringRepository({
    required AppDatabase db,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = db,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;

  Stream<List<RecurringRuleRow>> watch() => _db.watchRecurringRules();

  Future<List<RecurringRuleRow>> list() => _db.getRecurringRules();

  Future<RecurringRuleRow?> find(String id) => _db.findRecurringRule(id);

  Future<String> create({
    required String name,
    required TransactionType type,
    required int amountPoisha,
    required String walletId,
    required RecurrenceFrequency frequency,
    required DateTime startDate,
    String? toWalletId,
    String? categoryId,
    String? description,
    int intervalCount = 1,
    DateTime? endDate,
    bool autoPost = false,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Rule name is required.', field: 'name');
    }
    if (amountPoisha <= 0) {
      throw const ValidationException(
        'Amount must be greater than zero.',
        field: 'amount',
      );
    }
    if (intervalCount < 1) {
      throw const ValidationException(
        'Repeat interval must be at least 1.',
        field: 'interval',
      );
    }
    if (type == TransactionType.transfer) {
      if (toWalletId == null) {
        throw const ValidationException(
          'A recurring transfer needs a destination wallet.',
          field: 'toWalletId',
        );
      }
      if (toWalletId == walletId) {
        throw const ValidationException(
          'Source and destination wallets must be different.',
          field: 'toWalletId',
        );
      }
    }
    final id = _ids.next();
    final now = _clock.now();
    await _db.upsertRecurringRule(
      RecurringRulesCompanion.insert(
        id: id,
        name: trimmed,
        type: type,
        amountPoisha: amountPoisha,
        walletId: walletId,
        toWalletId: Value(toWalletId),
        categoryId: Value(categoryId),
        description: Value(description?.trim()),
        frequency: frequency,
        intervalCount: Value(intervalCount),
        startDate: startDate,
        nextDueDate: startDate,
        endDate: Value(endDate),
        autoPost: Value(autoPost),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> update(
    String id, {
    String? name,
    int? amountPoisha,
    String? walletId,
    String? toWalletId,
    String? categoryId,
    bool clearCategory = false,
    String? description,
    RecurrenceFrequency? frequency,
    int? intervalCount,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    bool? autoPost,
    bool? isActive,
  }) async {
    final existing = await _db.findRecurringRule(id);
    if (existing == null) {
      throw const NotFoundException('That recurring rule no longer exists.');
    }
    if (amountPoisha != null && amountPoisha <= 0) {
      throw const ValidationException(
        'Amount must be greater than zero.',
        field: 'amount',
      );
    }
    if (intervalCount != null && intervalCount < 1) {
      throw const ValidationException(
        'Repeat interval must be at least 1.',
        field: 'interval',
      );
    }
    final resolvedTo = toWalletId ?? existing.toWalletId;
    final resolvedFrom = walletId ?? existing.walletId;
    if (existing.type == TransactionType.transfer) {
      if (resolvedTo == null || resolvedTo == resolvedFrom) {
        throw const ValidationException(
          'A recurring transfer needs two different wallets.',
          field: 'toWalletId',
        );
      }
    }
    await _db.upsertRecurringRule(
      RecurringRulesCompanion(
        id: Value(id),
        name: name == null ? const Value.absent() : Value(name.trim()),
        amountPoisha: amountPoisha == null
            ? const Value.absent()
            : Value(amountPoisha),
        walletId: walletId == null ? const Value.absent() : Value(walletId),
        toWalletId: toWalletId == null
            ? const Value.absent()
            : Value(toWalletId),
        categoryId: clearCategory
            ? const Value(null)
            : (categoryId == null ? const Value.absent() : Value(categoryId)),
        description: description == null
            ? const Value.absent()
            : Value(description.trim()),
        frequency: frequency == null ? const Value.absent() : Value(frequency),
        intervalCount: intervalCount == null
            ? const Value.absent()
            : Value(intervalCount),
        startDate: startDate == null ? const Value.absent() : Value(startDate),
        endDate: clearEndDate
            ? const Value(null)
            : (endDate == null ? const Value.absent() : Value(endDate)),
        autoPost: autoPost == null ? const Value.absent() : Value(autoPost),
        isActive: isActive == null ? const Value.absent() : Value(isActive),
        updatedAt: Value(_clock.now()),
      ),
    );
  }

  Future<void> delete(String id) => _db.deleteRecurringRule(id);

  /// Advances [nextDueDate] after a rule has been posted or skipped.
  Future<void> markPosted(RecurringRuleRow rule, {required DateTime postedAt}) {
    return _db.upsertRecurringRule(
      RecurringRulesCompanion(
        id: Value(rule.id),
        lastPostedAt: Value(postedAt),
        nextDueDate: Value(nextOccurrence(rule, from: rule.nextDueDate)),
        updatedAt: Value(_clock.now()),
      ),
    );
  }

  Future<void> skipNext(RecurringRuleRow rule) {
    return _db.upsertRecurringRule(
      RecurringRulesCompanion(
        id: Value(rule.id),
        nextDueDate: Value(nextOccurrence(rule, from: rule.nextDueDate)),
        updatedAt: Value(_clock.now()),
      ),
    );
  }

  /// Next due date strictly after [from], honouring the interval. Monthly rules
  /// clamp to the last valid day (31 Jan → 28/29 Feb) instead of overflowing
  /// into the next month.
  static DateTime nextOccurrence(
    RecurringRuleRow rule, {
    required DateTime from,
  }) {
    switch (rule.frequency) {
      case RecurrenceFrequency.daily:
        return from.add(Duration(days: rule.intervalCount));
      case RecurrenceFrequency.weekly:
        return from.add(Duration(days: 7 * rule.intervalCount));
      case RecurrenceFrequency.monthly:
        return _addMonths(from, rule.intervalCount);
      case RecurrenceFrequency.yearly:
        return _addMonths(from, 12 * rule.intervalCount);
    }
  }

  static DateTime _addMonths(DateTime from, int months) {
    final totalMonths = from.month - 1 + months;
    final year = from.year + (totalMonths ~/ 12);
    final month = (totalMonths % 12) + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = from.day > lastDay ? lastDay : from.day;
    return DateTime(year, month, day, from.hour, from.minute);
  }

  /// Rules whose next due date is on or before [asOf], i.e. "needs attention".
  Future<List<RecurringRuleRow>> due({DateTime? asOf}) async {
    final now = asOf ?? _clock.now();
    final rules = await list();
    return rules
        .where(
          (rule) => rule.isActive && !rule.nextDueDate.isAfter(endOfDay(now)),
        )
        .toList(growable: false);
  }

  /// Rules due later, used for the "upcoming" section so upcoming entries are
  /// never confused with posted transactions.
  Future<List<RecurringRuleRow>> upcoming({
    DateTime? asOf,
    int days = 30,
  }) async {
    final now = asOf ?? _clock.now();
    final horizon = endOfDay(now.add(Duration(days: days)));
    final rules = await list();
    return rules
        .where(
          (rule) =>
              rule.isActive &&
              rule.nextDueDate.isAfter(now) &&
              !rule.nextDueDate.isAfter(horizon),
        )
        .toList(growable: false);
  }

  /// Human readable schedule, e.g. "Every 1 month (soonest 12 Mar 2026)".
  static String describeSchedule(RecurringRuleRow rule) {
    final unit = switch (rule.frequency) {
      RecurrenceFrequency.daily => 'day',
      RecurrenceFrequency.weekly => 'week',
      RecurrenceFrequency.monthly => 'month',
      RecurrenceFrequency.yearly => 'year',
    };
    final plural = rule.intervalCount == 1 ? unit : '${unit}s';
    return 'Every ${rule.intervalCount} $plural · next ${formatDate(rule.nextDueDate)}';
  }

  DateRange projectionRange(RecurringRuleRow rule, {int periods = 6}) {
    var cursor = rule.nextDueDate;
    for (var i = 1; i < periods; i++) {
      cursor = nextOccurrence(rule, from: cursor);
    }
    return DateRange(startOfDay(rule.nextDueDate), endOfDay(cursor));
  }
}
