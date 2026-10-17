import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/errors/app_exception.dart';
import 'package:personal_finance_manager/data/services/backup_service.dart';
import 'package:personal_finance_manager/data/services/csv_export_service.dart';
import 'package:personal_finance_manager/domain/enums.dart';
import 'package:personal_finance_manager/domain/models/date_range.dart';
import 'package:personal_finance_manager/domain/models/transaction_filter.dart';

import '../helpers/test_env.dart';

/// Reports, budgets, goals, loans, recurring rules, backup and CSV — all run
/// against a real in-memory database so the derived figures are the ones the
/// app actually produces.
void main() {
  late TestEnv env;

  setUp(() => env = TestEnv.create());
  tearDown(() => env.dispose());

  DateRange marchRange() => DateRange.month(env.clock.now());

  group('reports', () {
    test('summarise income, expense and transfers separately', () async {
      final cash = await env.addWallet('Cash', openingBalancePoisha: 500000);
      final bank = await env.addWallet('Bank', type: WalletType.bank);
      final food = await env.addCategory('Food & Dining', CategoryKind.expense);
      final transport = await env.addCategory(
        'Transport',
        CategoryKind.expense,
      );
      final salary = await env.addCategory('Salary', CategoryKind.income);

      await env.transactionService.createExpense(
        amountPoisha: 30000,
        walletId: cash,
        categoryId: food,
        occurredAt: env.clock.now(),
      );
      await env.transactionService.createExpense(
        amountPoisha: 20000,
        walletId: cash,
        categoryId: transport,
        occurredAt: env.clock.now(),
      );
      await env.transactionService.createIncome(
        amountPoisha: 100000,
        walletId: bank,
        categoryId: salary,
        occurredAt: env.clock.now(),
      );
      await env.transactionService.createTransfer(
        amountPoisha: 50000,
        fromWalletId: cash,
        toWalletId: bank,
        occurredAt: env.clock.now(),
      );

      final report = await env.reportService.reportFor(marchRange());
      expect(report.summary.incomePoisha, 100000);
      expect(report.summary.expensePoisha, 50000);
      expect(report.summary.transferVolumePoisha, 50000);
      expect(report.netPoisha, 50000);

      // Transfers never appear as a spending category.
      expect(
        report.expenseByCategory.map((c) => c.categoryName),
        containsAll(<String>['Food & Dining', 'Transport']),
      );
      expect(report.expenseByCategory.length, 2);
      expect(report.topExpenseCategory?.categoryName, 'Food & Dining');
    });
  });

  group('budgets', () {
    test(
      'track spending and fire one alert per threshold per period',
      () async {
        final cash = await env.addWallet('Cash', openingBalancePoisha: 500000);
        final food = await env.addCategory(
          'Food & Dining',
          CategoryKind.expense,
        );
        final budgetId = await env.budgets.create(
          name: 'Food',
          amountPoisha: 100000,
          period: BudgetPeriod.monthly,
          startDate: DateTime(2026, 3, 1),
          categoryId: food,
        );

        await env.transactionService.createExpense(
          amountPoisha: 85000,
          walletId: cash,
          categoryId: food,
          occurredAt: env.clock.now(),
        );

        final progress = (await env.budgets.progressList()).firstWhere(
          (p) => p.budgetId == budgetId,
        );
        expect(progress.spentPoisha, 85000);
        expect(progress.percentUsed, 85);
        expect(progress.isOverBudget, isFalse);

        final alerts = await env.budgetService.pending();
        expect(alerts.length, 1);
        expect(alerts.single.thresholdPercent, 80);

        await env.budgetService.consumePending();
        expect(await env.budgetService.pending(), isEmpty);
      },
    );
  });

  group('goals', () {
    test(
      'contributing from another wallet records a transfer, not an expense',
      () async {
        final cash = await env.addWallet('Cash', openingBalancePoisha: 100000);
        final savings = await env.addWallet(
          'Savings',
          type: WalletType.savings,
        );
        final goalId = await env.goals.create(
          name: 'New laptop',
          targetPoisha: 50000,
          walletId: savings,
        );

        final result = await env.goalService.contribute(
          goalId: goalId,
          amountPoisha: 20000,
          occurredAt: env.clock.now(),
          fromWalletId: cash,
        );

        expect(result.movedMoney, isTrue);
        expect(await env.balanceOf(cash), 80000);
        expect(await env.balanceOf(savings), 20000);

        final summary = await env.transactions.summary(marchRange());
        expect(summary.expensePoisha, 0);
        expect(summary.transferVolumePoisha, 20000);

        final contributions = await env.goals.contributions(goalId);
        expect(contributions.length, 1);

        // Removing the contribution reverses the transfer.
        await env.goalService.removeContribution(
          goalId: goalId,
          contributionId: contributions.single.id,
        );
        expect(await env.balanceOf(cash), 100000);
        expect(await env.balanceOf(savings), 0);
        expect(
          (await env.transactions.summary(marchRange())).transactionCount,
          0,
        );
      },
    );
  });

  group('loans', () {
    test('principal is bookkeeping and cash movement is opt-in', () async {
      final cash = await env.addWallet('Cash', openingBalancePoisha: 500000);

      final loan = await env.loanService.createLoan(
        counterparty: 'Rahim',
        direction: LoanDirection.lent,
        principalPoisha: 100000,
        occurredAt: env.clock.now(),
        walletId: cash,
        recordCashMovement: true,
      );
      expect(loan.recordedCashMovement, isTrue);
      expect(await env.balanceOf(cash), 400000);
      expect(await env.loanService.netOutstandingPoisha(), 100000);

      final payment = await env.loanService.addPayment(
        loanId: loan.id,
        amountPoisha: 40000,
        occurredAt: env.clock.now(),
        walletId: cash,
        recordCashMovement: true,
      );
      expect(payment.recordedCashMovement, isTrue);
      expect(await env.balanceOf(cash), 440000);
      expect(await env.loanService.netOutstandingPoisha(), 60000);

      // Both cash movements are left uncategorised on purpose.
      final rows = await env.transactions.list(const TransactionFilter());
      expect(rows.every((r) => r.categoryId == null), isTrue);
    });

    test('refuses to over-repay', () async {
      final loan = await env.loanService.createLoan(
        counterparty: 'Karim',
        direction: LoanDirection.borrowed,
        principalPoisha: 50000,
        occurredAt: env.clock.now(),
      );
      await expectLater(
        env.loanService.addPayment(
          loanId: loan.id,
          amountPoisha: 60000,
          occurredAt: env.clock.now(),
        ),
        throwsA(anything),
      );
    });
  });

  group('recurring rules', () {
    test(
      'posting advances the schedule so a due date is never posted twice',
      () async {
        final cash = await env.addWallet('Cash', openingBalancePoisha: 2000000);
        final rent = await env.addCategory('Rent', CategoryKind.expense);
        final ruleId = await env.recurring.create(
          name: 'House rent',
          type: TransactionType.expense,
          amountPoisha: 1500000,
          walletId: cash,
          categoryId: rent,
          frequency: RecurrenceFrequency.monthly,
          startDate: DateTime(2026, 3, 1),
          autoPost: true,
        );

        final firstPass = await env.recurringService.postDue();
        expect(firstPass.length, 1);
        expect(await env.balanceOf(cash), 500000);

        final secondPass = await env.recurringService.postDue();
        expect(secondPass, isEmpty, reason: 'already posted for this period');

        final summary = await env.transactions.summary(marchRange());
        expect(summary.expensePoisha, 1500000);
        expect(summary.expenseCount, 1);

        final rule = await env.recurring.find(ruleId);
        expect(rule!.nextDueDate.isAfter(env.clock.now()), isTrue);
      },
    );

    test('skipping writes nothing and moves the date forward', () async {
      final cash = await env.addWallet('Cash');
      await env.recurring.create(
        name: 'Internet',
        type: TransactionType.expense,
        amountPoisha: 100000,
        walletId: cash,
        frequency: RecurrenceFrequency.monthly,
        startDate: DateTime(2026, 3, 1),
      );
      final rule = (await env.recurring.due()).single;
      final next = await env.recurringService.skip(rule);
      expect(next.isAfter(rule.nextDueDate), isTrue);
      expect(
        (await env.transactions.summary(marchRange())).transactionCount,
        0,
      );
    });
  });

  group('backup', () {
    test('round-trips every table', () async {
      final cash = await env.addWallet('Cash', openingBalancePoisha: 100000);
      final food = await env.addCategory('Food & Dining', CategoryKind.expense);
      await env.transactionService.createExpense(
        amountPoisha: 20000,
        walletId: cash,
        categoryId: food,
        occurredAt: env.clock.now(),
      );

      final before = await env.db.tableCounts();
      final text = await env.backupService.exportToString();
      final payload = env.backupService.decode(text);
      expect(payload.format, 'personal_finance_manager.backup');
      expect(payload.totalRows, greaterThan(0));

      // Add something that must disappear after the restore.
      await env.addWallet('Extra');
      await env.backupService.restore(payload);

      final after = await env.db.tableCounts();
      expect(after['wallets'], before['wallets']);
      expect(after['transactions'], before['transactions']);
      expect(after['categories'], before['categories']);
    });

    test('encrypts and decrypts with a password', () async {
      await env.addWallet('Cash', openingBalancePoisha: 1000);
      final text = await env.backupService.exportToString(password: 'hunter2');
      expect(
        text.contains(BackupService.format),
        isFalse,
        reason: 'the plaintext payload must not leak into the envelope',
      );

      final payload = env.backupService.decode(text, password: 'hunter2');
      expect(payload.totalRows, greaterThan(0));

      expect(
        () => env.backupService.decode(text),
        throwsA(isA<InvalidFileException>()),
      );
    });

    test('rejects a file that is not a backup', () {
      expect(
        () => env.backupService.decode('{"hello":"world"}'),
        throwsA(isA<InvalidFileException>()),
      );
      expect(
        () => env.backupService.decode('not json at all'),
        throwsA(isA<InvalidFileException>()),
      );
    });
  });

  group('CSV export', () {
    test('writes ASCII amounts, a currency column and the header', () async {
      final cash = await env.addWallet('Cash', openingBalancePoisha: 100000);
      await env.transactionService.createExpense(
        amountPoisha: 123450,
        walletId: cash,
        occurredAt: env.clock.now(),
      );

      final csv = await env.csvService.exportTransactions();
      expect(csv, contains('amount_bdt'));
      expect(csv, contains('1234.50'));
      expect(csv, contains('BDT'));
    });

    test(
      'the summary keeps transfers separate from income and expense',
      () async {
        final cash = await env.addWallet('Cash');
        final bank = await env.addWallet('Bank', type: WalletType.bank);
        await env.transactionService.createTransfer(
          amountPoisha: 25000,
          fromWalletId: cash,
          toWalletId: bank,
          occurredAt: env.clock.now(),
        );
        final csv = await env.csvService.exportSummary(marchRange());
        expect(csv, contains('transfers'));
        expect(csv, contains('250.00'));
      },
    );

    test('names files with a stable date stamp', () {
      expect(
        CsvExportService.fileName('transactions', DateTime(2026, 3, 11)),
        'pfm-transactions-20260311.csv',
      );
    });
  });

  group('seeding', () {
    test('creates defaults once and is safe to run again', () async {
      final first = await env.seedService.ensureSeeded();
      expect(first, isTrue);
      final categories = await env.categories.list();
      expect(categories, isNotEmpty);

      final second = await env.seedService.ensureSeeded();
      expect(second, isFalse);
      expect(await env.categories.list(), hasLength(categories.length));
    });
  });
}
