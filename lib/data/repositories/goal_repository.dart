import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/models/budget_progress.dart';
import '../local/app_database.dart';

/// Savings-goal CRUD and progress.
///
/// A goal's progress is derived, never typed in by hand:
/// * when the goal is linked to a wallet, progress is that wallet's balance;
/// * otherwise progress is the sum of the goal's explicit contributions.
class GoalRepository {
  GoalRepository({
    required AppDatabase db,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = db,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;

  Stream<List<SavingsGoalRow>> watchRows() => _db.watchSavingsGoals();

  Future<List<SavingsGoalRow>> list() => _db.getSavingsGoals();

  Future<SavingsGoalRow?> find(String id) => _db.findSavingsGoal(id);

  Stream<List<GoalContributionRow>> watchContributions(String goalId) =>
      _db.watchGoalContributions(goalId);

  Future<List<GoalContributionRow>> contributions(String goalId) =>
      _db.getGoalContributions(goalId);

  Future<String> create({
    required String name,
    required int targetPoisha,
    DateTime? targetDate,
    String? walletId,
    String? note,
    int? colorValue,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Goal name is required.', field: 'name');
    }
    if (targetPoisha <= 0) {
      throw const ValidationException(
        'Target amount must be greater than zero.',
        field: 'target',
      );
    }
    final id = _ids.next();
    final now = _clock.now();
    await _db.upsertSavingsGoal(
      SavingsGoalsCompanion.insert(
        id: id,
        name: trimmed,
        targetPoisha: targetPoisha,
        targetDate: Value(targetDate),
        walletId: Value(walletId),
        note: Value(note?.trim()),
        colorValue: Value(colorValue),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> update(
    String id, {
    String? name,
    int? targetPoisha,
    DateTime? targetDate,
    bool clearTargetDate = false,
    String? walletId,
    bool clearWallet = false,
    String? note,
    bool? isCompleted,
    int? colorValue,
  }) async {
    final existing = await _db.findSavingsGoal(id);
    if (existing == null) {
      throw const NotFoundException('That savings goal no longer exists.');
    }
    final target = targetPoisha ?? existing.targetPoisha;
    if (target <= 0) {
      throw const ValidationException(
        'Target amount must be greater than zero.',
        field: 'target',
      );
    }
    await _db.upsertSavingsGoal(
      SavingsGoalsCompanion(
        id: Value(id),
        name: name == null ? const Value.absent() : Value(name.trim()),
        targetPoisha: Value(target),
        targetDate: clearTargetDate
            ? const Value(null)
            : (targetDate == null ? const Value.absent() : Value(targetDate)),
        walletId: clearWallet
            ? const Value(null)
            : (walletId == null ? const Value.absent() : Value(walletId)),
        note: note == null ? const Value.absent() : Value(note.trim()),
        isCompleted: isCompleted == null
            ? const Value.absent()
            : Value(isCompleted),
        colorValue: colorValue == null
            ? const Value.absent()
            : Value(colorValue),
        updatedAt: Value(_clock.now()),
      ),
    );
  }

  Future<void> delete(String id) => _db.deleteSavingsGoal(id);

  Future<String> addContribution({
    required String goalId,
    required int amountPoisha,
    required DateTime occurredAt,
    String? fromWalletId,
    String? transferId,
    String? note,
  }) async {
    if (amountPoisha <= 0) {
      throw const ValidationException(
        'Contribution must be greater than zero.',
        field: 'amount',
      );
    }
    final goal = await _db.findSavingsGoal(goalId);
    if (goal == null) {
      throw const NotFoundException('That savings goal no longer exists.');
    }
    final id = _ids.next();
    await _db.upsertGoalContribution(
      GoalContributionsCompanion.insert(
        id: id,
        goalId: goalId,
        amountPoisha: amountPoisha,
        occurredAt: occurredAt,
        fromWalletId: Value(fromWalletId),
        transferId: Value(transferId),
        note: Value(note?.trim()),
        createdAt: _clock.now(),
      ),
    );
    return id;
  }

  Future<void> deleteContribution(String id) => _db.deleteGoalContribution(id);

  Future<int> savedAmount(SavingsGoalRow goal) async {
    if (goal.walletId != null) {
      final balance = await _db.getWalletBalance(goal.walletId!);
      // A linked wallet's balance is the most accurate representation of what
      // the user has actually put aside.
      return balance?.balancePoisha ?? 0;
    }
    return _db.totalGoalContributions(goal.id);
  }

  Future<GoalProgress> progressFor(SavingsGoalRow goal) async {
    final saved = await savedAmount(goal);
    String? walletName;
    if (goal.walletId != null) {
      walletName = (await _db.findWalletById(goal.walletId!))?.name;
    }
    return GoalProgress(
      goalId: goal.id,
      name: goal.name,
      targetPoisha: goal.targetPoisha,
      savedPoisha: saved,
      isCompleted: goal.isCompleted,
      targetDate: goal.targetDate,
      walletId: goal.walletId,
      walletName: walletName,
      colorValue: goal.colorValue,
      note: goal.note,
    );
  }

  Future<List<GoalProgress>> progressList() async {
    final goals = await list();
    final result = <GoalProgress>[];
    for (final goal in goals) {
      result.add(await progressFor(goal));
    }
    return result;
  }

  Stream<List<GoalProgress>> watchProgressList() =>
      watchRows().asyncMap((goals) async {
        final result = <GoalProgress>[];
        for (final goal in goals) {
          result.add(await progressFor(goal));
        }
        return result;
      });
}
