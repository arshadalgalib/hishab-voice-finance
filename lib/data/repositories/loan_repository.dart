import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/enums.dart';
import '../../domain/models/budget_progress.dart';
import '../local/app_database.dart';

/// Lending and borrowing records with an explicit repayment ledger.
///
/// The loan itself is bookkeeping: it does not touch wallet balances. The
/// optional linked `transactions` row (created by `LoanService`) is what moves
/// money, so a loan can never be double counted.
class LoanRepository {
  LoanRepository({
    required AppDatabase db,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = db,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;

  Stream<List<LoanRow>> watch() => _db.watchLoans();

  Future<List<LoanRow>> list() => _db.getLoans();

  Future<LoanRow?> find(String id) => _db.findLoan(id);

  Stream<List<LoanPaymentRow>> watchPayments(String loanId) =>
      _db.watchLoanPayments(loanId);

  Future<String> create({
    required String counterparty,
    required LoanDirection direction,
    required int principalPoisha,
    required DateTime occurredAt,
    DateTime? dueDate,
    String? walletId,
    String? note,
  }) async {
    final trimmed = counterparty.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException(
        'Name is required.',
        field: 'counterparty',
      );
    }
    if (principalPoisha <= 0) {
      throw const ValidationException(
        'Amount must be greater than zero.',
        field: 'amount',
      );
    }
    final id = _ids.next();
    final now = _clock.now();
    await _db.upsertLoan(
      LoansCompanion.insert(
        id: id,
        counterparty: trimmed,
        direction: direction,
        principalPoisha: principalPoisha,
        occurredAt: occurredAt,
        dueDate: Value(dueDate),
        walletId: Value(walletId),
        note: Value(note?.trim()),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> update(
    String id, {
    String? counterparty,
    int? principalPoisha,
    DateTime? occurredAt,
    DateTime? dueDate,
    bool clearDueDate = false,
    String? note,
    bool? isSettled,
  }) async {
    final existing = await _db.findLoan(id);
    if (existing == null) {
      throw const NotFoundException('That record no longer exists.');
    }
    if (principalPoisha != null && principalPoisha <= 0) {
      throw const ValidationException(
        'Amount must be greater than zero.',
        field: 'amount',
      );
    }
    await _db.upsertLoan(
      LoansCompanion(
        id: Value(id),
        counterparty: counterparty == null
            ? const Value.absent()
            : Value(counterparty.trim()),
        principalPoisha: principalPoisha == null
            ? const Value.absent()
            : Value(principalPoisha),
        occurredAt: occurredAt == null
            ? const Value.absent()
            : Value(occurredAt),
        dueDate: clearDueDate
            ? const Value(null)
            : (dueDate == null ? const Value.absent() : Value(dueDate)),
        note: note == null ? const Value.absent() : Value(note.trim()),
        isSettled: isSettled == null ? const Value.absent() : Value(isSettled),
        updatedAt: Value(_clock.now()),
      ),
    );
  }

  Future<void> delete(String id) => _db.deleteLoan(id);

  Future<String> addPayment({
    required String loanId,
    required int amountPoisha,
    required DateTime occurredAt,
    String? walletId,
    String? note,
  }) async {
    if (amountPoisha <= 0) {
      throw const ValidationException(
        'Payment must be greater than zero.',
        field: 'amount',
      );
    }
    final loan = await _db.findLoan(loanId);
    if (loan == null) {
      throw const NotFoundException('That record no longer exists.');
    }
    final repaid = await _db.totalLoanPayments(loanId);
    if (repaid + amountPoisha > loan.principalPoisha) {
      throw ValidationException(
        'That is more than the outstanding ৳'
        '${((loan.principalPoisha - repaid) / 100).toStringAsFixed(2)}.',
        field: 'amount',
      );
    }
    final id = _ids.next();
    await _db.upsertLoanPayment(
      LoanPaymentsCompanion.insert(
        id: id,
        loanId: loanId,
        amountPoisha: amountPoisha,
        occurredAt: occurredAt,
        walletId: Value(walletId),
        note: Value(note?.trim()),
        createdAt: _clock.now(),
      ),
    );
    final totalPaid = repaid + amountPoisha;
    await _db.upsertLoan(
      LoansCompanion(
        id: Value(loanId),
        isSettled: Value(totalPaid >= loan.principalPoisha),
        updatedAt: Value(_clock.now()),
      ),
    );
    return id;
  }

  Future<void> deletePayment(String id, {required String loanId}) async {
    await _db.deleteLoanPayment(id);
    final loan = await _db.findLoan(loanId);
    if (loan == null) return;
    final repaid = await _db.totalLoanPayments(loanId);
    await _db.upsertLoan(
      LoansCompanion(
        id: Value(loanId),
        isSettled: Value(repaid >= loan.principalPoisha),
        updatedAt: Value(_clock.now()),
      ),
    );
  }

  Future<LoanProgress> progressFor(LoanRow loan) async {
    final repaid = await _db.totalLoanPayments(loan.id);
    return LoanProgress(
      loanId: loan.id,
      counterparty: loan.counterparty,
      direction: loan.direction,
      principalPoisha: loan.principalPoisha,
      repaidPoisha: repaid,
      occurredAt: loan.occurredAt,
      dueDate: loan.dueDate,
      isSettled: loan.isSettled,
      note: loan.note,
    );
  }

  Future<List<LoanProgress>> progressList() async {
    final loans = await list();
    final result = <LoanProgress>[];
    for (final loan in loans) {
      result.add(await progressFor(loan));
    }
    return result;
  }

  /// Net position: money owed *to* the user minus money the user owes.
  Future<int> netOutstandingPoisha() async {
    final progress = await progressList();
    var net = 0;
    for (final loan in progress) {
      if (loan.direction == LoanDirection.lent) {
        net += loan.outstandingPoisha;
      } else {
        net -= loan.outstandingPoisha;
      }
    }
    return net;
  }
}
