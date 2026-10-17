import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/core/utils/money.dart';

void main() {
  group('Money.tryParse', () {
    test('reads plain integers as taka', () {
      expect(Money.tryParse('250')?.poisha, 25000);
    });

    test('accepts a thousands separator', () {
      expect(Money.tryParse('1,250')?.poisha, 125000);
    });

    test('accepts the taka symbol', () {
      expect(Money.tryParse('৳ 1200')?.poisha, 120000);
    });

    test('accepts the word taka and a decimal', () {
      expect(Money.tryParse('1200.50 taka')?.poisha, 120050);
    });

    test('reads Bengali digits', () {
      expect(Money.tryParse('২৫০')?.poisha, 25000);
    });

    test('keeps a single fractional digit as tens of poisha', () {
      expect(Money.tryParse('10.5')?.poisha, 1050);
    });

    test('treats a leading minus as negative', () {
      expect(Money.tryParse('-40')?.poisha, -4000);
    });

    test('returns null for text with no number', () {
      expect(Money.tryParse('nothing here'), isNull);
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('.'), isNull);
    });
  });

  group('Money arithmetic', () {
    test('adds and subtracts without floating point drift', () {
      // 0.1 + 0.2 must be exactly 0.30 in poisha.
      final sum = const Money(10) + const Money(20);
      expect(sum.poisha, 30);
    });

    test('toStorageString always keeps two decimals', () {
      expect(const Money(125000).toStorageString(), '1250.00');
      expect(const Money(50).toStorageString(), '0.50');
      expect(const Money(-50).toStorageString(), '-0.50');
    });
  });
}
