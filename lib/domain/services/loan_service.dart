import 'package:meta/meta.dart';

import '../../data/repositories/loan_repository.dart';
import '../enums.dart';
import 'transaction_service.dart';

/// Result of recording a loan or a repayment.
@immutable
class LoanOperationResult {
  const LoanOperationResult({required this.id, this.transactionId});

  final String id;

  /// Set only when the user asked for the cash movement to be recorded.
  final String? transactionId;

  bool get recordedCashMovement => transactionId != null;
}

/// Lending and borrowing.
///
/// ## Why the principal is bookkeeping by default
/// Lending money does not reduce your net worth; it converts cash into a
/// receivable. Recording it as an expense would make a month look bad for a
/// decision that lost nothing. So a loan is stored in its own ledger, and
/// `netOutstandingPoisha()` reports the position separately.
///
/// When the user explicitly asks to record the cash movement, the money really
/// did leave or enter a wallet, so it is written as an **uncategorised** income
/// or expense. It is left uncategorised on purpose: the app does not pretend a
/// loan is salary or a bill, and it shows up in the "needs review" queue where
/// the user can re-categorise it if they want to.
class LoanService {
  LoanService({
    required LoanRepository loans,
    required TransactionService transactions,
  }) : _loans = loans,
       _transactions = transactions;

  final LoanRepository _loans;
  final TransactionService _transactions;

  Future<LoanOperationResult> createLoan({
    required String counterparty,
    required LoanDirection direction,
    required int principalPoisha,
    required DateTime occurredAt,
    DateTime? dueDate,
    String? walletId,
    String? note,
    bool recordCashMovement = false,
  }) async {
    final id = await _loans.create(
      counterparty: counterparty,
      direction: direction,
      principalPoisha: principalPoisha,
      occurredAt: occurredAt,
      dueDate: dueDate,
      walletId: walletId,
      note: note,
    );

    String? transactionId;
    if (recordCashMovement && walletId != null) {
      transactionId = direction == LoanDirection.borrowed
          ? await _transactions.createIncome(
              amountPoisha: principalPoisha,
              walletId: walletId,
              occurredAt: occurredAt,
              description: 'Loan received from $counterparty',
              note: note,
            )
          : await _transactions.createExpense(
              amountPoisha: principalPoisha,
              walletId: walletId,
              occurredAt: occurredAt,
              description: 'Money lent to $counterparty',
              note: note,
            );
    }

    return LoanOperationResult(id: id, transactionId: transactionId);
  }

  /// Records a repayment.
  ///
  /// The repository refuses to accept more than the outstanding amount, so a
  /// loan can never be over-repaid.
  Future<LoanOperationResult> addPayment({
    required String loanId,
    required int amountPoisha,
    required DateTime occurredAt,
    String? walletId,
    String? note,
    bool recordCashMovement = false,
  }) async {
    final loan = await _loans.find(loanId);
    if (loan == null) {
      throw StateError('Loan $loanId does not exist');
    }

    final id = await _loans.addPayment(
      loanId: loanId,
      amountPoisha: amountPoisha,
      occurredAt: occurredAt,
      walletId: walletId,
      note: note,
    );

    String? transactionId;
    if (recordCashMovement && walletId != null) {
      transactionId = loan.direction == LoanDirection.borrowed
          // Repaying what you owe: money leaves the wallet.
          ? await _transactions.createExpense(
              amountPoisha: amountPoisha,
              walletId: walletId,
              occurredAt: occurredAt,
              description: 'Loan repayment to ${loan.counterparty}',
              note: note,
            )
          // Being repaid: money arrives in the wallet.
          : await _transactions.createIncome(
              amountPoisha: amountPoisha,
              walletId: walletId,
              occurredAt: occurredAt,
              description: 'Repayment from ${loan.counterparty}',
              note: note,
            );
    }

    return LoanOperationResult(id: id, transactionId: transactionId);
  }

  Future<void> deleteLoan(String id) => _loans.delete(id);

  Future<void> deletePayment({
    required String paymentId,
    required String loanId,
  }) => _loans.deletePayment(paymentId, loanId: loanId);

  /// Positive when people owe the user more than the user owes.
  Future<int> netOutstandingPoisha() => _loans.netOutstandingPoisha();
}
