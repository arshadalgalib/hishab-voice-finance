import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/app/providers.dart';
import 'package:personal_finance_manager/core/utils/date_x.dart';
import 'package:personal_finance_manager/domain/enums.dart';
import 'package:personal_finance_manager/domain/models/date_range.dart';
import 'package:personal_finance_manager/domain/models/transaction_filter.dart';
import 'package:personal_finance_manager/features/voice/application/speech_recognizer.dart';
import 'package:personal_finance_manager/features/voice/presentation/voice_capture_screen.dart';

import '../helpers/fake_speech_recognizer.dart';
import '../helpers/test_env.dart';

/// End-to-end widget tests for the voice flow.
///
/// These mount the *real* `VoiceCaptureScreen`, the real `VoiceController` and
/// the real parser, and drive them through the real in-memory database. The
/// only thing replaced is the speech engine, because a microphone cannot exist
/// in a widget test. Everything else is the production path.
void main() {
  late TestEnv env;
  late FakeSpeechRecognizer recognizer;

  setUp(() {
    env = TestEnv.create();
    recognizer = FakeSpeechRecognizer();
  });

  tearDown(() => env.dispose());

  /// Wraps `testWidgets` so the `ProviderScope` is unmounted *inside* the test
  /// body. drift cancels its query streams with a zero-duration timer, and the
  /// binding checks for pending timers before the tear-downs run, so the timer
  /// has to be flushed while the frame is still alive.
  void voiceTest(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(description, (tester) async {
      // A tall surface keeps the whole confirmation form on screen, so the
      // assertions do not depend on where the list happens to be scrolled.
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 50));
      }
    });
  }

  Future<void> seedCategories() => env.categories.ensureDefaultCategories();

  /// Cash is the default expense wallet and bKash/Rocket exist so the corpus
  /// transcripts resolve deterministically.
  Future<Map<String, String>> seedWallets({
    bool cashDefaultExpense = true,
    int cashOpening = 500000,
  }) async {
    final cash = await env.addWallet(
      'Cash',
      openingBalancePoisha: cashOpening,
      isDefaultIncome: true,
      isDefaultExpense: cashDefaultExpense,
    );
    final bkash = await env.addWallet(
      'bKash',
      type: WalletType.bkash,
      openingBalancePoisha: 100000,
    );
    final nagad = await env.addWallet('Nagad', type: WalletType.nagad);
    final rocket = await env.addWallet(
      'Rocket',
      type: WalletType.rocket,
      openingBalancePoisha: 200000,
    );
    return <String, String>{
      'cash': cash,
      'bkash': bkash,
      'nagad': nagad,
      'rocket': rocket,
    };
  }

  Widget app() => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(env.db),
      clockProvider.overrideWithValue(env.clock),
      idGeneratorProvider.overrideWithValue(env.ids),
      speechRecognizerProvider.overrideWithValue(recognizer),
      onlineInterpreterFactoryProvider.overrideWithValue(() async => null),
    ],
    child: const MaterialApp(home: VoiceCaptureScreen()),
  );

  /// Pumps until the tree is stable, with a short timeout so a stuck frame
  /// fails the test instead of hanging for ten minutes.
  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 20),
  );

  Future<void> speak(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Start listening'));
    await settle(tester);
  }

  Future<void> typeAndUnderstand(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.tap(find.byTooltip('Understand this text'));
    await settle(tester);
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await settle(tester);
    await tester.tap(find.text(label));
    await settle(tester);
  }

  Future<int> expenseTotal() async => (await env.transactions.summary(
    DateRange.month(env.clock.now()),
  )).expensePoisha;

  Future<int> transactionCount() async => (await env.transactions.summary(
    DateRange.month(env.clock.now()),
  )).transactionCount;

  group('microphone flow', () {
    voiceTest('a Bengali expense is heard, confirmed and saved', (
      tester,
    ) async {
      await seedCategories();
      final wallets = await seedWallets();
      recognizer.transcript = 'বিকাশ থেকে ২৫০ টাকা বাজার করেছি';

      await tester.pumpWidget(app());
      await speak(tester);

      // The confirmation form is shown, not a silent save.
      expect(find.text('Check and confirm'), findsWidgets);
      expect(find.textContaining('বাজার'), findsWidgets);
      expect(await transactionCount(), 0, reason: 'nothing saved yet');

      await tapButton(tester, 'Save transaction');

      expect(find.textContaining('Saved'), findsWidgets);
      expect(await expenseTotal(), 25000);
      expect(await env.balanceOf(wallets['bkash']!), 75000);

      final row = (await env.transactions.list(
        const TransactionFilter(),
      )).single;
      expect(row.source, TransactionSource.voice);
      expect(row.type, TransactionType.expense);
      expect(row.walletId, wallets['bkash']);
    });

    voiceTest('the recogniser is biased with the user\'s own wallet names', (
      tester,
    ) async {
      await seedCategories();
      await seedWallets();
      recognizer.transcript = 'CASH থেকে ১০০ টাকা খাবার খরচ';

      await tester.pumpWidget(app());
      await speak(tester);

      expect(recognizer.lastContextualPhrases, contains('bKash'));
      expect(recognizer.lastContextualPhrases, contains('Rocket'));
      expect(find.text('Check and confirm'), findsWidgets);
    });

    voiceTest('an empty transcript is reported, never saved', (tester) async {
      await seedCategories();
      await seedWallets();
      recognizer.transcript = '';

      await tester.pumpWidget(app());
      await speak(tester);

      expect(find.textContaining('did not catch that'), findsOneWidget);
      expect(find.text('Check and confirm'), findsNothing);
      expect(await transactionCount(), 0);
    });

    voiceTest('an unavailable engine falls back to typing', (tester) async {
      await seedCategories();
      await seedWallets();
      recognizer.availability = SpeechAvailability.unavailable;

      await tester.pumpWidget(app());
      await speak(tester);

      expect(
        find.textContaining('microphone is not available'),
        findsOneWidget,
      );
      expect(await transactionCount(), 0);

      // Typing still works through the same parser.
      await typeAndUnderstand(tester, 'I spent 180 taka on lunch from cash');
      await tapButton(tester, 'Save transaction');
      expect(await expenseTotal(), 18000);
    });
  });

  group('typed entry', () {
    voiceTest('Banglish with recognition noise resolves the wallet', (
      tester,
    ) async {
      await seedCategories();
      final wallets = await seedWallets();

      await tester.pumpWidget(app());
      await typeAndUnderstand(
        tester,
        'aj bikash teke 300 taka bazar khoroch korlam',
      );
      await tapButton(tester, 'Save transaction');

      expect(await expenseTotal(), 30000);
      expect(await env.balanceOf(wallets['bkash']!), 70000);
    });

    voiceTest('English entry matches a category, not just a wallet', (
      tester,
    ) async {
      await seedCategories();
      final wallets = await seedWallets();

      await tester.pumpWidget(app());
      await typeAndUnderstand(tester, 'I spent 180 taka on lunch from cash');
      await tapButton(tester, 'Save transaction');

      final row = (await env.transactions.list(
        const TransactionFilter(),
      )).single;
      expect(row.amountPoisha, 18000);
      expect(row.walletId, wallets['cash']);
      expect(row.categoryName, 'Food & Dining');
    });

    voiceTest('a spoken-word amount ("দেড় হাজার") is 1,500 taka', (
      tester,
    ) async {
      await seedCategories();
      await seedWallets();

      await tester.pumpWidget(app());
      await typeAndUnderstand(tester, 'দেড় হাজার টাকা খাবার খরচ');
      await tapButton(tester, 'Save transaction');

      expect(await expenseTotal(), 150000);
    });

    voiceTest('a relative date moves the transaction to yesterday', (
      tester,
    ) async {
      await seedCategories();
      await seedWallets();

      await tester.pumpWidget(app());
      await typeAndUnderstand(tester, 'গতকাল দুপুরে ৩০০ টাকা খাবার খরচ');
      await tapButton(tester, 'Save transaction');

      final row = (await env.transactions.list(
        const TransactionFilter(),
      )).single;
      expect(dayKeyOf(row.occurredAt), '2026-03-10');
      expect(row.occurredAt.hour, 13);
    });
  });

  group('never save something ambiguous', () {
    voiceTest('a missing wallet is flagged and save is disabled', (
      tester,
    ) async {
      await seedCategories();
      // No default expense wallet, so nothing can be assumed.
      await seedWallets(cashDefaultExpense: false);

      await tester.pumpWidget(app());
      await typeAndUnderstand(tester, '৫০০ টাকা বাজার করেছি');

      expect(find.text('Which wallet was this?'), findsOneWidget);
      final saveButton = find.ancestor(
        of: find.text('Save transaction'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(tester.widget<ButtonStyleButton>(saveButton).onPressed, isNull);
      expect(await transactionCount(), 0);
    });

    voiceTest('an ambiguous category is flagged rather than guessed', (
      tester,
    ) async {
      await seedCategories();
      await seedWallets();
      // Two distinct expense categories sharing one spoken keyword.
      await env.addCategory(
        'Home Tools',
        CategoryKind.expense,
        keywords: <String>['যন্ত্রপাতি'],
      );
      await env.addCategory(
        'Office Tools',
        CategoryKind.expense,
        keywords: <String>['যন্ত্রপাতি'],
      );

      await tester.pumpWidget(app());
      await typeAndUnderstand(tester, '৩০০ টাকা যন্ত্রপাতি খরচ');

      expect(find.textContaining('more than one category'), findsOneWidget);
      expect(await transactionCount(), 0);
    });
  });

  group('transfers', () {
    voiceTest('move money without counting as income or expense', (
      tester,
    ) async {
      await seedCategories();
      final wallets = await seedWallets();

      await tester.pumpWidget(app());
      await typeAndUnderstand(tester, 'বিকাশ থেকে রকেটে ৫০০ টাকা পাঠিয়েছি');
      await tapButton(tester, 'Save transaction');

      final summary = await env.transactions.summary(
        DateRange.month(env.clock.now()),
      );
      expect(summary.incomePoisha, 0);
      expect(summary.expensePoisha, 0);
      expect(summary.transferVolumePoisha, 50000);
      expect(await env.balanceOf(wallets['bkash']!), 50000);
      expect(await env.balanceOf(wallets['rocket']!), 250000);

      final row = (await env.transactions.list(
        const TransactionFilter(),
      )).single;
      expect(row.type, TransactionType.transfer);
      expect(row.toWalletId, wallets['rocket']);
    });
  });

  group('duplicate and undo', () {
    voiceTest('a probable duplicate must be confirmed before it is saved', (
      tester,
    ) async {
      await seedCategories();
      await seedWallets();

      await tester.pumpWidget(app());

      await typeAndUnderstand(tester, '৫০০ টাকা বাজার করেছি');
      await tapButton(tester, 'Save transaction');
      expect(await transactionCount(), 1);

      // Record the exact same thing again.
      await tapButton(tester, 'Record another');
      await typeAndUnderstand(tester, '৫০০ টাকা বাজার করেছি');
      // Press save again; this is what triggers the duplicate check.
      await tapButton(tester, 'Save transaction');

      expect(await transactionCount(), 1, reason: 'the duplicate is blocked');
      expect(find.text('Possible duplicate'), findsOneWidget);
      // Saving anyway is an explicit choice, never the default.
      await tapButton(tester, 'Save it anyway');

      expect(await transactionCount(), 2);
    });

    voiceTest('a saved voice transaction can be undone from the screen', (
      tester,
    ) async {
      await seedCategories();
      await seedWallets();

      await tester.pumpWidget(app());
      await typeAndUnderstand(tester, '৫০০ টাকা বাজার করেছি');
      await tapButton(tester, 'Save transaction');
      expect(await transactionCount(), 1);

      await tapButton(tester, 'Undo');

      expect(await transactionCount(), 0, reason: 'undo reverses the write');
      expect(find.text('Check and confirm'), findsNothing);
    });
  });
}
