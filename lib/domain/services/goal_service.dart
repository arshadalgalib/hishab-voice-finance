import 'package:meta/meta.dart';

import '../../data/repositories/goal_repository.dart';
import '../enums.dart';
import 'transaction_service.dart';

/// Result of adding money to a savings goal.
@immutable
class GoalContributionResult {
  const GoalContributionResult({
    required this.contributionId,
    this.transferId,
    this.goalCompleted = false,
  });

  final String contributionId;

  /// Set when the contribution also moved money between wallets, which is the
  /// only case where a wallet balance changes.
  final String? transferId;

  final bool goalCompleted;

  bool get movedMoney => transferId != null;
}

/// Savings goals.
///
/// A goal can be linked to a wallet (progress = that wallet's balance) or track
/// explicit contributions. When it *is* linked and the user says the money came
/// out of another wallet, the money is moved with a real **transfer**, never an
/// expense — putting money aside is not spending, and counting it as an expense
/// would make every goal look like a bill.
class GoalService {
  GoalService({
    required GoalRepository goals,
    required TransactionService transactions,
  }) : _goals = goals,
       _transactions = transactions;

  final GoalRepository _goals;
  final TransactionService _transactions;

  /// Adds [amountPoisha] to [goalId].
  ///
  /// * [fromWalletId] null → history-only contribution (no wallet changes).
  /// * [fromWalletId] set and the goal is linked to a *different* wallet → a
  ///   transfer is created first, then the contribution references it.
  /// * [fromWalletId] equal to the linked wallet → history-only, because a
  ///   wallet cannot transfer to itself.
  Future<GoalContributionResult> contribute({
    required String goalId,
    required int amountPoisha,
    required DateTime occurredAt,
    String? fromWalletId,
    String? note,
  }) async {
    final goal = await _goals.find(goalId);
    if (goal == null) {
      throw StateError('Savings goal $goalId does not exist');
    }

    final linkedWallet = goal.walletId;
    String? transferId;

    if (fromWalletId != null &&
        linkedWallet != null &&
        fromWalletId != linkedWallet) {
      transferId = await _transactions.createTransfer(
        amountPoisha: amountPoisha,
        fromWalletId: fromWalletId,
        toWalletId: linkedWallet,
        occurredAt: occurredAt,
        description: 'Savings: ${goal.name}',
        note: note,
        source: TransactionSource.goal,
      );
    } else if (fromWalletId != null && linkedWallet == null) {
      // The goal has no wallet of its own, so there is nowhere to transfer the
      // money *to*. Record the contribution only and let the user link a wallet
      // if they want the cash movement tracked.
      transferId = null;
    }

    final contributionId = await _goals.addContribution(
      goalId: goalId,
      amountPoisha: amountPoisha,
      occurredAt: occurredAt,
      fromWalletId: fromWalletId,
      transferId: transferId,
      note: note,
    );

    final progress = await _goals.progressFor(goal);
    return GoalContributionResult(
      contributionId: contributionId,
      transferId: transferId,
      goalCompleted: progress.isReached,
    );
  }

  /// Removes a contribution. When it was funded by a transfer, the transfer is
  /// removed too, so wallet balances return to where they started.
  Future<void> removeContribution({
    required String goalId,
    required String contributionId,
  }) async {
    final contributions = await _goals.contributions(goalId);
    final transferId = contributions
        .where((row) => row.id == contributionId)
        .map((row) => row.transferId)
        .firstOrNull;

    await _goals.deleteContribution(contributionId);
    if (transferId != null) {
      await _transactions.delete(transferId);
    }
  }

  /// Marks a goal complete without moving any money — the user often reaches the
  /// target some other way.
  Future<void> setCompleted(String goalId, bool completed) =>
      _goals.update(goalId, isCompleted: completed);
}
