import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/utils/date_x.dart';
import 'package:personal_finance_manager/domain/enums.dart';
import 'package:personal_finance_manager/domain/models/transaction_draft.dart';
import 'package:personal_finance_manager/features/voice/domain/category_matcher.dart';
import 'package:personal_finance_manager/features/voice/domain/voice_parse_result.dart';
import 'package:personal_finance_manager/features/voice/domain/voice_transaction_parser.dart';
import 'package:personal_finance_manager/features/voice/domain/wallet_alias_matcher.dart';

/// Wallets the corpus is written against. Kept deterministic so an expected
/// wallet id is meaningful.
const List<WalletCandidate> _wallets = <WalletCandidate>[
  WalletCandidate(id: 'w-cash', name: 'Cash', type: WalletType.cash),
  WalletCandidate(id: 'w-bkash', name: 'bKash', type: WalletType.bkash),
  WalletCandidate(id: 'w-nagad', name: 'Nagad', type: WalletType.nagad),
  WalletCandidate(id: 'w-rocket', name: 'Rocket', type: WalletType.rocket),
  WalletCandidate(id: 'w-bank', name: 'City Bank', type: WalletType.bank),
  WalletCandidate(id: 'w-savings', name: 'Savings', type: WalletType.savings),
];

const List<CategoryCandidate> _categories = <CategoryCandidate>[
  CategoryCandidate(
    id: 'c-food',
    name: 'Food & Dining',
    kind: CategoryKind.expense,
    keywords: <String>['খাবার', 'বাজার', 'লাঞ্চ', 'lunch', 'restaurant'],
  ),
  CategoryCandidate(
    id: 'c-transport',
    name: 'Transport',
    kind: CategoryKind.expense,
    keywords: <String>['রিকশা', 'বাস', 'সিএনজি', 'bus', 'rickshaw'],
  ),
  CategoryCandidate(
    id: 'c-bills',
    name: 'Bills & Utilities',
    kind: CategoryKind.expense,
    keywords: <String>['বিদ্যুৎ বিল', 'কারেন্ট বিল', 'বিল'],
  ),
  CategoryCandidate(
    id: 'c-salary',
    name: 'Salary',
    kind: CategoryKind.income,
    keywords: <String>['বেতন', 'salary', 'মাইনে'],
  ),
  CategoryCandidate(
    id: 'c-gift',
    name: 'Gift',
    kind: CategoryKind.income,
    keywords: <String>['উপহার', 'gift'],
  ),
];

ParserContext _context({DateTime? now}) => ParserContext(
  wallets: _wallets,
  categories: _categories,
  now: now ?? DateTime(2026, 3, 11, 10, 30),
);

/// A context with a default wallet for each direction, used by the tests that
/// exercise the fallback path.
ParserContext _contextWithDefaults() => ParserContext(
  wallets: _wallets,
  categories: _categories,
  now: DateTime(2026, 3, 11, 10, 30),
  defaultIncomeWalletId: 'w-bank',
  defaultExpenseWalletId: 'w-cash',
);

ParsedTransaction _parse(String text, {ParserContext? context}) =>
    VoiceTransactionParser(context ?? _context()).parse(text);

void main() {
  group('Bengali expense', () {
    final parsed = _parse('বিকাশ থেকে ২৫০ টাকা বাজার করেছি');

    test('is an expense', () => expect(parsed.type, TransactionType.expense));
    test('reads the amount', () => expect(parsed.amountPoisha, 25000));
    test('uses the spoken wallet', () => expect(parsed.walletId, 'w-bkash'));
    test(
      'matches the spoken category',
      () => expect(parsed.categoryId, 'c-food'),
    );
    test(
      'is complete and produces a draft',
      () => expect(parsed.toDraft(fallbackWalletId: null), isNotNull),
    );
  });

  group('Banglish expense with recognition noise', () {
    // "teke"/"khoroch" are exactly the spellings a Bengali recogniser emits.
    final parsed = _parse('aj bikash teke 300 taka bazar khoroch korlam');

    test('is an expense', () => expect(parsed.type, TransactionType.expense));
    test('reads the amount', () => expect(parsed.amountPoisha, 30000));
    test('resolves the wallet', () => expect(parsed.walletId, 'w-bkash'));
    test('records the date as today', () {
      expect(dayKeyOf(parsed.occurredAt!), '2026-03-11');
    });
  });

  group('English expense', () {
    final parsed = _parse('I spent 180 taka on lunch from cash');

    test('is an expense', () => expect(parsed.type, TransactionType.expense));
    test('reads the amount', () => expect(parsed.amountPoisha, 18000));
    test('resolves the cash wallet', () => expect(parsed.walletId, 'w-cash'));
    test(
      'matches the lunch category',
      () => expect(parsed.categoryId, 'c-food'),
    );
  });

  group('Bengali income', () {
    final parsed = _parse('বেতন পেলাম ৩০০০০ টাকা ব্যাংকে');

    test('is income', () => expect(parsed.type, TransactionType.income));
    test('reads the amount', () => expect(parsed.amountPoisha, 3000000));
    test('uses the spoken wallet', () => expect(parsed.walletId, 'w-bank'));
    test(
      'matches the salary category',
      () => expect(parsed.categoryId, 'c-salary'),
    );
  });

  group('number variations', () {
    test('"দেড় হাজার" is 1,500', () {
      expect(_parse('দেড় হাজার টাকা খরচ').amountPoisha, 150000);
    });

    test('"পাঁচশো" is 500', () {
      expect(_parse('পাঁচশো টাকা খরচ').amountPoisha, 50000);
    });

    test('"2.5 hajar" is 2,500', () {
      expect(_parse('2.5 hajar taka khoroch').amountPoisha, 250000);
    });

    test('plain digits are read as taka', () {
      expect(_parse('500 taka khoroch').amountPoisha, 50000);
    });

    test('a mishearing of "দেড়" as "দের" still yields 1,500', () {
      // Recognisers frequently drop the candrabindu.
      expect(_parse('দের হাজার টাকা খরচ').amountPoisha, 150000);
    });
  });

  group('missing wallet', () {
    final parsed = _parse('৫০০ টাকা বাজার করেছি');

    test('records the expense and amount', () {
      expect(parsed.type, TransactionType.expense);
      expect(parsed.amountPoisha, 50000);
    });

    test('flags the wallet as unresolved', () {
      expect(parsed.unresolved, contains(VoiceField.wallet));
    });

    test('never builds a half-filled draft', () {
      expect(parsed.toDraft(fallbackWalletId: null), isNull);
    });

    test('uses the default wallet when one is configured', () {
      final context = _contextWithDefaults();
      final parser = VoiceTransactionParser(context);
      final parsed = parser.parse('৫০০ টাকা বাজার করেছি');
      final draft = parser.buildDraft(parsed);
      expect(draft?.walletId, 'w-cash');
    });
  });

  group('ambiguous wallet', () {
    test('"নগদ" with both Cash and Nagad refuses to guess', () {
      final parsed = _parse('নগদ থেকে ৫০০ টাকা খরচ');
      expect(parsed.walletId, isNull);
      expect(parsed.unresolved, contains(VoiceField.wallet));
      expect(parsed.toDraft(fallbackWalletId: null), isNull);
    });
  });

  group('transfers', () {
    final parsed = _parse('বিকাশ থেকে রকেটে ৫০০০ টাকা পাঠিয়েছি');

    test('is a transfer, not an expense', () {
      expect(parsed.type, TransactionType.transfer);
    });

    test('reads source and destination wallets', () {
      expect(parsed.walletId, 'w-bkash');
      expect(parsed.toWalletId, 'w-rocket');
    });

    test('builds a single transfer draft', () {
      final draft = parsed.toDraft(fallbackWalletId: null);
      expect(draft?.type, TransactionType.transfer);
      expect(draft?.walletId, 'w-bkash');
      expect(draft?.toWalletId, 'w-rocket');
      expect(draft?.categoryId, isNull);
    });

    test('a transfer never gets a category', () {
      // Even though "বাজার" appears, a transfer draft must not be categorised.
      final withCategoryWord = _parse(
        'বিকাশ থেকে রকেটে ৫০০০ টাকা বাজার পাঠিয়েছি',
      );
      expect(withCategoryWord.type, TransactionType.transfer);
      final draft = withCategoryWord.toDraft(fallbackWalletId: null);
      expect(draft?.categoryId, isNull);
    });
  });

  group('relative dates', () {
    test('"গতকাল দুপুরে" resolves to yesterday', () {
      final parsed = _parse('গতকাল দুপুরে ৩০০ টাকা খাবার খরচ');
      expect(dayKeyOf(parsed.occurredAt!), '2026-03-10');
      expect(parsed.occurredAt!.hour, 13);
      expect(parsed.amountPoisha, 30000);
    });

    test('"আজ নয় গতকাল" is understood as yesterday', () {
      final parsed = _parse('আজ নয় গতকাল ৪০০ টাকা খরচ');
      expect(dayKeyOf(parsed.occurredAt!), '2026-03-10');
      expect(parsed.warnings, isNotEmpty);
    });
  });

  group('no direction', () {
    test('a bare amount is left unresolved rather than guessed', () {
      final parsed = _parse('৫০০ টাকা');
      expect(parsed.type, isNull);
      expect(parsed.unresolved, contains(VoiceField.type));
      expect(parsed.toDraft(fallbackWalletId: null), isNull);
    });
  });

  group('draft construction', () {
    test('builds a voice-sourced draft from a complete parse', () {
      final parsed = _parse('বিকাশ থেকে ২৫০ টাকা বাজার করেছি');
      final draft = parsed.toDraft(fallbackWalletId: null);
      expect(draft, isA<TransactionDraft>());
      expect(draft!.source, TransactionSource.voice);
      expect(draft.amountPoisha, 25000);
      expect(draft.walletId, 'w-bkash');
    });

    test('confidence is bounded and never claims certainty', () {
      final parsed = _parse('বিকাশ থেকে ২৫০ টাকা বাজার করেছি');
      expect(parsed.confidence, greaterThan(0));
      expect(parsed.confidence, lessThanOrEqualTo(0.99));
    });
  });
}
