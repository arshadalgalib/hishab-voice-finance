import 'package:flutter_test/flutter_test.dart';
import 'package:personal_finance_manager/features/voice/domain/bengali_number_parser.dart';

void main() {
  group('BengaliNumberParser.parseTokens', () {
    test('adds units and hundreds within a scale', () {
      expect(
        BengaliNumberParser.parseTokens(<String>['দুই', 'শো', 'পাঁচশো']),
        700,
      );
    });

    test('multiplies by a scale word', () {
      expect(BengaliNumberParser.parseTokens(<String>['দুই', 'হাজার']), 2000);
    });

    test('reads "দেড় হাজার" as one and a half thousand', () {
      expect(BengaliNumberParser.parseTokens(<String>['দেড়', 'হাজার']), 1500);
    });

    test('applies a relative quarter modifier', () {
      expect(
        BengaliNumberParser.parseTokens(<String>['সোয়া', 'দুই', 'হাজার']),
        2250,
      );
      expect(
        BengaliNumberParser.parseTokens(<String>['পৌনে', 'তিন', 'হাজার']),
        2750,
      );
    });

    test('reads combined contractions', () {
      expect(BengaliNumberParser.parseTokens(<String>['আড়াইশো']), 250);
      expect(BengaliNumberParser.parseTokens(<String>['দেড়শো']), 150);
    });

    test('handles latin spellings from a Banglish transcript', () {
      expect(BengaliNumberParser.parseTokens(<String>['dui', 'hazar']), 2000);
      expect(BengaliNumberParser.parseTokens(<String>['ponchash']), 50);
    });

    test('mixes digits and words', () {
      expect(BengaliNumberParser.parseTokens(<String>['2', 'হাজার']), 2000);
    });

    test('reads digit suffixes', () {
      expect(BengaliNumberParser.parseTokens(<String>['2.5k']), 2500);
      expect(BengaliNumberParser.parseTokens(<String>['1lakh']), 100000);
    });

    test('returns null when a token is not a number', () {
      expect(BengaliNumberParser.parseTokens(<String>['দুই', 'বাজার']), isNull);
      expect(BengaliNumberParser.parseTokens(<String>[]), isNull);
    });
  });

  group('BengaliNumberParser.findAmount', () {
    test('finds the amount before a currency word', () {
      final match = BengaliNumberParser.findAmount(<String>[
        'বাজার',
        'করেছি',
        'দুই',
        'হাজার',
        'পাঁচশো',
        'টাকা',
      ]);
      expect(match?.taka, 2500);
      expect(match?.adjacentToCurrencyWord, isTrue);
    });

    test('finds a plain digit run', () {
      final match = BengaliNumberParser.findAmount(<String>['250', 'taka']);
      expect(match?.taka, 250);
    });

    test('prefers a currency-adjacent phrase over a bare number', () {
      // A date-like "11" must not win over "৫০০ টাকা".
      final match = BengaliNumberParser.findAmount(<String>[
        '১১',
        'তারিখে',
        '৫০০',
        'টাকা',
        'খরচ',
      ]);
      expect(match?.taka, 500);
    });

    test('returns null when nothing numeric is present', () {
      expect(BengaliNumberParser.findAmount(<String>['খাবার', 'খরচ']), isNull);
    });
  });
}
