import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/errors/app_exception.dart';
import 'package:personal_finance_manager/domain/enums.dart';
import 'package:personal_finance_manager/domain/models/date_range.dart';
import 'package:personal_finance_manager/domain/models/transaction_draft.dart';

import '../helpers/test_env.dart';

/// Ledger invariants exercised against a real in-memory SQLite database.
void main() {
  late TestEnv env;

  setUp(() => env = TestEnv.create());
  tearDown(() => env.dispose());

  group('wallet balances', () {
    test('are derived from the opening balance plus transactions', () async {
      final cash = await env.addWallet('Cash', openingBalancePoisha: 100000);
      await env.transactionService.createExpense(
        amountPoisha: 25000,
        walletId: cash,
        description: 'lunch',
      );
      await env.transactionService.createIncome(
        amountPoisha: 50000,
        walletId: cash,
        description: 'gift',
      );
      expect(await env.balanceOf(cash), 125000);
    });

    test('a zero-opening wallet starts empty', () async {
      final cash = await env.addWallet('Cash');
      expect(await env.balanceOf(cash), 0);
    });
  });

  group('transfers', () {
    test('move money and never count as income or expense', () async {
      final cash = await env.addWallet('Cash', openingBalancePoisha: 200000);
      final bank = await env.addWallet('Bank', type: WalletType.bank);

      final id = await env.transactionService.createTransfer(
        amountPoisha: 50000,
        fromWalletId: cash,
        toWalletId: bank,
      );

      expect(await env.balanceOf(cash), 150000);
      expect(await env.balanceOf(bank), 50000);

      final summary = await env.transactions.summary(
        DateRange.month(env.clock.now()),
      );
      expect(summary.incomePoisha, 0);
      expect(summary.expensePoisha, 0);
      expect(summary.transferVolumePoisha, 50000);

      // A transfer is one logical record, not a pair of rows.
      final row = await env.transactions.findRow(id);
      expect(row!.type, TransactionType.transfer);
      expect(row.toWalletId, bank);
      final group = await env.transactions.rowsByGroup(row.transferGroupId!);
      expect(group.length, 1);
    });

    test('a transfer fee becomes one real expense row', () async {
      final cash = await env.addWallet('Cash', openingBalancePoisha: 200000);
      final bank = await env.addWallet('Bank', type: WalletType.bank);
      final feeCategory = await env.addCategory(
        'Fees & Charges',
        CategoryKind.expense,
      );

      final id = await env.transactionService.createTransfer(
        amountPoisha: 50000,
        fromWalletId: cash,
        toWalletId: bank,
        feePoisha: 1000,
      );

      expect(await env.balanceOf(cash), 149000);
      expect(await env.balanceOf(bank), 50000);

      final summary = await env.transactions.summary(
        DateRange.month(env.clock.now()),
      );
      expect(summary.expensePoisha, 1000);
      expect(summary.transferVolumePoisha, 50000);

      final row = await env.transactions.findRow(id);
      final group = await env.transactions.rowsByGroup(row!.transferGroupId!);
      expect(group.length, 2);
      final fee = group.firstWhere((r) => r.id != id);
      expect(fee.categoryId, feeCategory);
      expect(fee.amountPoisha, 1000);
      expect(fee.type, TransactionType.expense);
    });

    test('deleting a transfer removes its linked fee too', () async {
      final cash = await env.addWallet('Cash', openingBalancePoisha: 200000);
      final bank = await env.addWallet('Bank', type: WalletType.bank);
      await env.addCategory('Fees & Charges', CategoryKind.expense);

      final id = await env.transactionService.createTransfer(
        amountPoisha: 50000,
        fromWalletId: cash,
        toWalletId: bank,
        feePoisha: 1000,
      );
      await env.transactionService.delete(id);

      expect(await env.balanceOf(cash), 200000);
      expect(await env.balanceOf(bank), 0);
      final summary = await env.transactions.summary(
        DateRange.month(env.clock.now()),
      );
      expect(summary.transactionCount, 0);
    });
  });

  group('validation', () {
    test('rejects a transfer to the same wallet and writes nothing', () async {
      final cash = await env.addWallet('Cash', openingBalancePoisha: 100000);
      await expectLater(
        env.transactionService.createTransfer(
          amountPoisha: 1000,
          fromWalletId: cash,
          toWalletId: cash,
        ),
        throwsA(isA<ValidationException>()),
      );
      final summary = await env.transactions.summary(
        DateRange.month(env.clock.now()),
      );
      expect(summary.transactionCount, 0);
      expect(await env.balanceOf(cash), 100000);
    });

    test('rejects a category whose kind does not match the type', () async {
      final cash = await env.addWallet('Cash');
      final salary = await env.addCategory('Salary', CategoryKind.income);
      await expectLater(
        env.transactionService.createExpense(
          amountPoisha: 1000,
          walletId: cash,
          categoryId: salary,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects a non-positive amount', () async {
      final cash = await env.addWallet('Cash');
      await expectLater(
        env.transactionService.createExpense(amountPoisha: 0, walletId: cash),
        throwsA(isA<ValidationException>()),
      );
    });

    test('an archived wallet cannot receive a new transaction', () async {
      final cash = await env.addWallet('Cash', openingBalancePoisha: 50000);
      await env.wallets.setArchived(cash, true);
      await expectLater(
        env.transactionService.createExpense(
          amountPoisha: 1000,
          walletId: cash,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('archiving a wallet keeps its history in reports', () async {
      final cash = await env.addWallet('Cash', openingBalancePoisha: 100000);
      await env.transactionService.createExpense(
        amountPoisha: 20000,
        walletId: cash,
      );
      await env.wallets.setArchived(cash, true);
      final summary = await env.transactions.summary(
        DateRange.month(env.clock.now()),
      );
      expect(summary.expensePoisha, 20000);
    });
  });

  group('duplicate prevention', () {
    test('refuses a probable duplicate, then allows it on request', () async {
      final cash = await env.addWallet('Cash');
      final tx = env.transactionService;
      await tx.createExpense(
        amountPoisha: 25000,
        walletId: cash,
        description: 'lunch',
      );

      await expectLater(
        tx.createExpense(
          amountPoisha: 25000,
          walletId: cash,
          description: 'lunch',
        ),
        throwsA(isA<DuplicateTransactionException>()),
      );

      final second = await tx.createExpense(
        amountPoisha: 25000,
        walletId: cash,
        description: 'lunch',
        allowDuplicate: true,
      );
      expect(second, isNotEmpty);
      final summary = await env.transactions.summary(
        DateRange.month(env.clock.now()),
      );
      expect(summary.expenseCount, 2);
    });

    test('a different amount is not treated as a duplicate', () async {
      final cash = await env.addWallet('Cash');
      final tx = env.transactionService;
      await tx.createExpense(amountPoisha: 25000, walletId: cash);
      await tx.createExpense(amountPoisha: 35000, walletId: cash);
      final summary = await env.transactions.summary(
        DateRange.month(env.clock.now()),
      );
      expect(summary.expenseCount, 2);
    });
  });

  group('edit, delete and undo', () {
    test('editing an expense re-derives the balance', () async {
      final cash = await env.addWallet('Cash', openingBalancePoisha: 100000);
      final id = await env.transactionService.createExpense(
        amountPoisha: 20000,
        walletId: cash,
      );
      await env.transactionService.update(
        id,
        TransactionDraft.expense(
          amountPoisha: 35000,
          walletId: cash,
          occurredAt: env.clock.now(),
        ),
      );
      expect(await env.balanceOf(cash), 65000);
    });

    test(
      'deleting restores the balance and undo re-applies it exactly',
      () async {
        final cash = await env.addWallet('Cash', openingBalancePoisha: 100000);
        final id = await env.transactionService.createExpense(
          amountPoisha: 20000,
          walletId: cash,
        );
        expect(await env.balanceOf(cash), 80000);

        final removed = await env.transactionService.delete(id);
        expect(removed.length, 1);
        expect(await env.balanceOf(cash), 100000);

        await env.transactionService.restoreRows(removed);
        expect(await env.balanceOf(cash), 80000);
      },
    );

    test(
      'editing a transfer rebuilds its fee without duplicating it',
      () async {
        final cash = await env.addWallet('Cash', openingBalancePoisha: 200000);
        final bank = await env.addWallet('Bank', type: WalletType.bank);
        await env.addCategory('Fees & Charges', CategoryKind.expense);

        final id = await env.transactionService.createTransfer(
          amountPoisha: 50000,
          fromWalletId: cash,
          toWalletId: bank,
          feePoisha: 1000,
        );
        await env.transactionService.update(
          id,
          TransactionDraft.transfer(
            amountPoisha: 50000,
            fromWalletId: cash,
            toWalletId: bank,
            occurredAt: env.clock.now(),
            feePoisha: 2000,
          ),
        );

        final row = await env.transactions.findRow(id);
        final group = await env.transactions.rowsByGroup(row!.transferGroupId!);
        expect(group.length, 2, reason: 'exactly one fee row after an edit');
        expect(await env.balanceOf(cash), 148000);
      },
    );
  });

  group('opening balance audit trail', () {
    test(
      'adjusting the opening balance is recorded in the audit log',
      () async {
        final cash = await env.addWallet('Cash', openingBalancePoisha: 10000);
        await env.wallets.adjustOpeningBalance(
          walletId: cash,
          newOpeningBalancePoisha: 50000,
          reason: 'corrected a typo',
        );
        expect(await env.balanceOf(cash), 50000);

        final logs = await env.db.watchAuditLogs().first;
        final walletLogs = logs
            .where((log) => log.entityType == 'wallet' && log.entityId == cash)
            .toList();
        expect(walletLogs, isNotEmpty);
      },
    );
  });

  group('persistence', () {
    test(
      'rows survive across repository instances on the same database',
      () async {
        final cash = await env.addWallet('Cash', openingBalancePoisha: 50000);
        await env.transactionService.createExpense(
          amountPoisha: 15000,
          walletId: cash,
        );

        final counts = await env.db.tableCounts();
        expect(counts['wallets'], 1);
        expect(counts['transactions'], 1);

        final integrity = await env.db.integrityCheck();
        expect(integrity.toLowerCase(), 'ok');
      },
    );
  });
}
