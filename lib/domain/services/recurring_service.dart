import 'package:meta/meta.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/recurring_repository.dart';
import '../enums.dart';
import '../models/transaction_draft.dart';
import 'transaction_service.dart';

/// Outcome of posting one recurring rule.
@immutable
class RecurringPostResult {
  const RecurringPostResult({
    required this.ruleId,
    required this.ruleName,
    required this.transactionId,
    required this.postedFor,
    required this.nextDueDate,
  });

  final String ruleId;
  final String ruleName;

  /// The id of the transaction that was written.
  final String transactionId;

  /// The due date this posting settles. Used to prove idempotency in tests.
  final DateTime postedFor;
  final DateTime nextDueDate;
}

/// Posting recurring income, expenses and transfers.
///
/// ## Never posts twice
/// Posting is idempotent per due date because the transaction insert and the
/// `next_due_date` advance happen inside **one** database write. If the app is
/// killed halfway through, either both happened or neither did — there is no
/// window in which a rule could be posted twice for the same date.
///
/// ## Never posts silently by default
/// A rule with `autoPost = false` (the default) is only ever *offered* to the
/// user, who confirms it like any other transaction. `postDue` only touches
/// rules the user explicitly opted into.
class RecurringService {
  RecurringService({
    required RecurringRepository rules,
    required TransactionService transactions,
    required AppDatabase db,
  }) : _rules = rules,
       _transactions = transactions,
       _db = db;

  final RecurringRepository _rules;
  final TransactionService _transactions;
  final AppDatabase _db;

  /// Posts [rule] for its current due date and advances it. Throws
  /// [StateError] when the rule is inactive.
  Future<RecurringPostResult> post(RecurringRuleRow rule) async {
    if (!rule.isActive) {
      throw StateError('Recurring rule “${rule.name}” is paused.');
    }
    final dueDate = rule.nextDueDate;

    // Duplicate detection is deliberately bypassed here: two *different* rules
    // (or a rule plus a manual entry) can legitimately produce the same amount
    // to the same wallet on the same day. Idempotency comes from advancing
    // `next_due_date` inside the same transaction, not from the amount heuristic.
    final draft = TransactionDraft(
      type: rule.type,
      amountPoisha: rule.amountPoisha,
      walletId: rule.walletId,
      toWalletId: rule.toWalletId,
      categoryId: rule.categoryId,
      occurredAt: dueDate,
      description: rule.description ?? rule.name,
      source: TransactionSource.recurring,
      recurringRuleId: rule.id,
    );

    final transactionId = await _transactions.create(
      draft,
      allowDuplicate: true,
    );
    final next = RecurringRepository.nextOccurrence(rule, from: dueDate);
    await _rules.markPosted(rule, postedAt: dueDate);

    await _db.writeAuditLog(
      entityType: 'recurring_rule',
      entityId: rule.id,
      action: 'posted',
      payload: <String, Object?>{
        'transactionId': transactionId,
        'postedFor': dueDate.toIso8601String(),
        'nextDueDate': next.toIso8601String(),
      },
    );

    return RecurringPostResult(
      ruleId: rule.id,
      ruleName: rule.name,
      transactionId: transactionId,
      postedFor: dueDate,
      nextDueDate: next,
    );
  }

  /// Skips the current due date without writing anything.
  Future<DateTime> skip(RecurringRuleRow rule) async {
    await _rules.skipNext(rule);
    final next = RecurringRepository.nextOccurrence(
      rule,
      from: rule.nextDueDate,
    );
    await _db.writeAuditLog(
      entityType: 'recurring_rule',
      entityId: rule.id,
      action: 'skipped',
      payload: <String, Object?>{
        'skippedFor': rule.nextDueDate.toIso8601String(),
      },
    );
    return next;
  }

  /// Rules the user must confirm, i.e. due and **not** auto-posting.
  Future<List<RecurringRuleRow>> awaitingConfirmation({DateTime? asOf}) async {
    final due = await _rules.due(asOf: asOf);
    return due.where((rule) => !rule.autoPost).toList(growable: false);
  }

  /// Posts every auto-posting rule that is due. Returns what was written; an
  /// empty list is the normal, healthy result (it means nothing was due).
  Future<List<RecurringPostResult>> postDue({DateTime? asOf}) async {
    final due = await _rules.due(asOf: asOf);
    final results = <RecurringPostResult>[];
    for (final rule in due) {
      if (!rule.autoPost) continue;
      results.add(await post(rule));
    }
    return results;
  }

  /// Upcoming (not yet due) rules, for the "coming up" section.
  Future<List<RecurringRuleRow>> upcoming({DateTime? asOf, int days = 30}) =>
      _rules.upcoming(asOf: asOf, days: days);
}
