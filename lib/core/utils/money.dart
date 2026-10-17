import 'package:meta/meta.dart';

import 'bengali_digits.dart';

/// Immutable monetary value stored as an integer number of **poisha**.
///
/// Bangladesh uses 1 BDT = 100 poisha. All financial arithmetic in this
/// application is performed on integers so that no floating point rounding
/// error can ever change a wallet balance.
@immutable
class Money implements Comparable<Money> {
  const Money(this.poisha);

  const Money.zero() : poisha = 0;

  /// Creates a value from a decimal taka amount, rounding half away from zero.
  factory Money.fromTaka(num taka) => Money((taka * poishaPerTaka).round());

  /// Parses free-form user input such as `1,250`, `৳ 1200.50`, `২৫০`.
  ///
  /// Throws [FormatException] when nothing numeric can be read.
  factory Money.parse(String raw) {
    final parsed = tryParse(raw);
    if (parsed == null) {
      throw FormatException('Not a valid amount', raw);
    }
    return parsed;
  }

  /// Parses [raw] returning `null` instead of throwing.
  static Money? tryParse(String raw) {
    var text = toAsciiDigits(raw).trim();
    if (text.isEmpty) return null;

    // Drop currency symbols / words but keep digits, separators and sign.
    text = text.replaceAll(RegExp(r'[\u09F3$\u20B9]'), '');
    text = text.replaceAll(
      RegExp(
        r'(\u099F\u09BE\u0995\u09BE|taka|tk\.?|bdt)',
        caseSensitive: false,
      ),
      '',
    );
    text = text.trim();

    final negative =
        text.startsWith('-') ||
        text.startsWith('\u2013') ||
        text.startsWith('\u2212');
    text = text.replaceAll(RegExp(r'^[-\u2013\u2212]'), '');

    // Strip everything except digits and the first decimal separator.
    final buffer = StringBuffer();
    var seenSeparator = false;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      if (char == '.' || char == '\u0966') {
        if (seenSeparator) continue;
        seenSeparator = true;
        buffer.write('.');
      } else if (char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39) {
        buffer.write(char);
      }
    }

    final cleaned = buffer.toString();
    if (cleaned.isEmpty || cleaned == '.') return null;

    if (!seenSeparator) {
      final value = int.tryParse(cleaned);
      if (value == null) return null;
      return Money(negative ? -value * poishaPerTaka : value * poishaPerTaka);
    }

    final value = double.tryParse(cleaned);
    if (value == null) return null;
    final result = Money.fromTaka(value);
    return negative ? -result : result;
  }

  static const int poishaPerTaka = 100;

  /// Signed number of poisha. Negative values are permitted for internal
  /// computation (e.g. credit balances) but never for a saved transaction
  /// amount — validation happens in the service layer.
  final int poisha;

  bool get isZero => poisha == 0;
  bool get isNegative => poisha < 0;
  bool get isPositive => poisha > 0;

  /// Decimal taka representation. Only use for display or charting; never for
  /// arithmetic that feeds back into persisted data.
  double get taka => poisha / poishaPerTaka;

  Money operator +(Money other) => Money(poisha + other.poisha);
  Money operator -(Money other) => Money(poisha - other.poisha);
  Money operator -() => Money(-poisha);
  Money operator *(int factor) => Money(poisha * factor);

  bool operator <(Money other) => poisha < other.poisha;
  bool operator <=(Money other) => poisha <= other.poisha;
  bool operator >(Money other) => poisha > other.poisha;
  bool operator >=(Money other) => poisha >= other.poisha;

  Money abs() => Money(poisha.abs());

  Money clampMin(Money minimum) => poisha < minimum.poisha ? minimum : this;

  /// Sums [values]; returns zero for an empty iterable.
  static Money sum(Iterable<Money> values) =>
      values.fold(const Money.zero(), (a, b) => a + b);

  /// Sums [values] extracted from [items].
  static Money totalOf<T>(Iterable<T> items, Money Function(T) selector) =>
      items.fold(const Money.zero(), (acc, item) => acc + selector(item));

  @override
  int compareTo(Money other) => poisha.compareTo(other.poisha);

  @override
  bool operator ==(Object other) => other is Money && other.poisha == poisha;

  @override
  int get hashCode => poisha.hashCode;

  /// Machine readable form used in CSV and JSON exports: `1234.50`.
  String toStorageString() {
    final sign = poisha < 0 ? '-' : '';
    final absPoisha = poisha.abs();
    final whole = absPoisha ~/ poishaPerTaka;
    final fraction = absPoisha % poishaPerTaka;
    return '$sign$whole.${fraction.toString().padLeft(2, '0')}';
  }

  @override
  String toString() => 'Money(${toStorageString()} BDT)';
}
