import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/utils/date_x.dart';
import 'package:personal_finance_manager/domain/enums.dart';
import 'package:personal_finance_manager/features/voice/domain/category_matcher.dart';
import 'package:personal_finance_manager/features/voice/domain/relative_date_parser.dart';
import 'package:personal_finance_manager/features/voice/domain/text_normalizer.dart';
import 'package:personal_finance_manager/features/voice/domain/wallet_alias_matcher.dart';

void main() {
  group('WalletAliasMatcher', () {
    test('resolves a type word to the only wallet of that type', () {
      final matcher = WalletAliasMatcher(<WalletCandidate>[
        const WalletCandidate(
          id: 'w-cash',
          name: 'Cash',
          type: WalletType.cash,
        ),
      ]);
      final match = matcher.findAll(
        TextNormalizer.normalize('নগদে ৫০০ টাকা খরচ'),
      );
      expect(match, isNotEmpty);
      expect(match.first.isResolved, isTrue);
      expect(match.first.resolvedId, 'w-cash');
    });

    test('resolves a wallet by its own distinctive name', () {
      final matcher = WalletAliasMatcher(<WalletCandidate>[
        const WalletCandidate(
          id: 'w-city',
          name: 'City Bank',
          type: WalletType.bank,
        ),
        const WalletCandidate(
          id: 'w-cash',
          name: 'Cash',
          type: WalletType.cash,
        ),
      ]);
      final match = matcher.findAll(TextNormalizer.normalize('city bank 400'));
      expect(match.first.resolvedId, 'w-city');
    });

    test('refuses to guess when নগদ could be cash or Nagad', () {
      // The whole reason the confirmation screen asks: "নগদ" is the everyday
      // word for cash *and* the brand name Nagad.
      final matcher = WalletAliasMatcher(<WalletCandidate>[
        const WalletCandidate(
          id: 'w-cash',
          name: 'Cash',
          type: WalletType.cash,
        ),
        const WalletCandidate(
          id: 'w-nagad',
          name: 'Nagad',
          type: WalletType.nagad,
        ),
      ]);
      final match = matcher.findAll(TextNormalizer.normalize('নগদ ৫০০'));
      expect(match.first.isAmbiguous, isTrue);
      expect(match.first.resolvedId, isNull);
      expect(
        match.first.candidateIds,
        containsAll(<String>['w-cash', 'w-nagad']),
      );
    });

    test('understands a Banglish wallet word from a transcript', () {
      final matcher = WalletAliasMatcher(<WalletCandidate>[
        const WalletCandidate(
          id: 'w-bkash',
          name: 'bKash',
          type: WalletType.bkash,
        ),
      ]);
      final match = matcher.findAll(
        TextNormalizer.normalize('bikash theke 250 taka'),
      );
      expect(match.first.resolvedId, 'w-bkash');
    });
  });

  group('CategoryMatcher', () {
    final matcher = CategoryMatcher(<CategoryCandidate>[
      const CategoryCandidate(
        id: 'c-food',
        name: 'Food & Dining',
        kind: CategoryKind.expense,
        keywords: <String>['খাবার', 'বাজার', 'লাঞ্চ'],
      ),
      const CategoryCandidate(
        id: 'c-transport',
        name: 'Transport',
        kind: CategoryKind.expense,
        keywords: <String>['রিকশা', 'বাস', 'সিএনজি'],
      ),
      const CategoryCandidate(
        id: 'c-salary',
        name: 'Salary',
        kind: CategoryKind.income,
        keywords: <String>['বেতন', 'salary'],
      ),
    ]);

    test('matches a keyword within the sentence', () {
      final match = matcher.findBest(
        TextNormalizer.normalize('বাজার করেছি ৩০০ টাকা'),
        kind: CategoryKind.expense,
      );
      expect(match?.categoryId, 'c-food');
    });

    test('respects the transaction kind', () {
      final match = matcher.findBest(
        TextNormalizer.normalize('বাজার করেছি'),
        kind: CategoryKind.income,
      );
      expect(match, isNull);
    });

    test('flags an ambiguous top match instead of guessing', () {
      final ambiguous = CategoryMatcher(<CategoryCandidate>[
        const CategoryCandidate(
          id: 'c-a',
          name: 'Utilities',
          kind: CategoryKind.expense,
          keywords: <String>['বিল'],
        ),
        const CategoryCandidate(
          id: 'c-b',
          name: 'Bills',
          kind: CategoryKind.expense,
          keywords: <String>['বিল'],
        ),
      ]);
      final text = TextNormalizer.normalize('বিল দিলাম ৫০০');
      expect(
        ambiguous.hasAmbiguousTopMatch(text, kind: CategoryKind.expense),
        isTrue,
      );
    });
  });

  group('RelativeDateParser', () {
    final now = DateTime(2026, 3, 11, 10, 30);
    final parser = RelativeDateParser(now: now);

    test('defaults to no date when nothing was said', () {
      final result = parser.parse(TextNormalizer.normalize('৫০০ টাকা খরচ'));
      expect(result.date, isNull);
      expect(result.explicit, isFalse);
    });

    test('reads আজ as today', () {
      final result = parser.parse(TextNormalizer.normalize('আজ ৫০০ টাকা'));
      expect(dayKeyOf(result.date!), '2026-03-11');
      expect(result.explicit, isTrue);
    });

    test('reads গতকাল as yesterday', () {
      final result = parser.parse(TextNormalizer.normalize('গতকাল ৫০০ টাকা'));
      expect(dayKeyOf(result.date!), '2026-03-10');
    });

    test(
      'maps the Banglish word kal to yesterday by documented assumption',
      () {
        final result = parser.parse(TextNormalizer.normalize('kal 500 taka'));
        expect(dayKeyOf(result.date!), '2026-03-10');
      },
    );

    test('honours a negated date and picks the other one', () {
      final result = parser.parse(
        TextNormalizer.normalize('আজ নয়, গতকাল ৪০০ টাকা খরচ করেছি'),
      );
      expect(dayKeyOf(result.date!), '2026-03-10');
      expect(result.hadNegatedCandidate, isTrue);
    });

    test('reads an explicit day and Bengali month', () {
      final result = parser.parse(
        TextNormalizer.normalize('১১ মার্চ ৫০০ টাকা'),
      );
      expect(dayKeyOf(result.date!), '2026-03-11');
    });

    test('reads a numeric date', () {
      final result = parser.parse(TextNormalizer.normalize('12/03/2026 500'));
      expect(dayKeyOf(result.date!), '2026-03-12');
    });
  });
}
