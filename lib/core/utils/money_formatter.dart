import 'bengali_digits.dart';
import 'money.dart';

/// Formats [Money-like] integer poisha values for display.
///
/// Bangladeshi users read numbers grouped in lakh / crore style
/// (`12,34,567.00`), so the formatter supports both that and the plain
/// international grouping. Number *storage* is always plain ASCII digits so
/// that CSV/JSON consumers never have to parse Bengali numerals.
class MoneyFormatter {
  const MoneyFormatter({
    this.symbol = '\u09F3',
    this.useBengaliDigits = false,
    this.bangladeshiGrouping = true,
    this.decimalPlaces = 2,
    this.showSymbol = true,
    this.alwaysShowDecimals = true,
  });

  /// Convenience instance used by most widgets.
  static const MoneyFormatter standard = MoneyFormatter();

  final String symbol;

  /// When true, `1234` renders as `১,২৩৪`. Input parsing is unaffected.
  final bool useBengaliDigits;

  /// When true groups as `1,23,456` instead of `123,456`.
  final bool bangladeshiGrouping;

  final int decimalPlaces;
  final bool showSymbol;

  /// When false, `.00` is dropped for whole amounts (`\u09F3250` not `\u09F3250.00`).
  final bool alwaysShowDecimals;

  MoneyFormatter copyWith({
    String? symbol,
    bool? useBengaliDigits,
    bool? bangladeshiGrouping,
    int? decimalPlaces,
    bool? showSymbol,
    bool? alwaysShowDecimals,
  }) {
    return MoneyFormatter(
      symbol: symbol ?? this.symbol,
      useBengaliDigits: useBengaliDigits ?? this.useBengaliDigits,
      bangladeshiGrouping: bangladeshiGrouping ?? this.bangladeshiGrouping,
      decimalPlaces: decimalPlaces ?? this.decimalPlaces,
      showSymbol: showSymbol ?? this.showSymbol,
      alwaysShowDecimals: alwaysShowDecimals ?? this.alwaysShowDecimals,
    );
  }

  /// Formats a signed poisha amount.
  String format(int poisha, {bool withSign = false}) {
    final negative = poisha < 0;
    final absPoisha = poisha.abs();
    final scale = _pow10(decimalPlaces);
    final whole = absPoisha ~/ Money.poishaPerTaka;
    final fractionPoisha = absPoisha % Money.poishaPerTaka;
    final fraction = decimalPlaces == 0
        ? 0
        : (fractionPoisha * scale) ~/ Money.poishaPerTaka;

    final wholeText = _group(whole.toString());
    final showFraction =
        decimalPlaces > 0 && (alwaysShowDecimals || fraction != 0);
    final fractionText = showFraction
        ? '.${fraction.toString().padLeft(decimalPlaces, '0')}'
        : '';

    var body = '$wholeText$fractionText';
    if (useBengaliDigits) body = toBengaliDigits(body);

    final prefix = showSymbol ? symbol : '';
    final sign = withSign
        ? (negative ? '\u2212' : '+')
        : (negative ? '\u2212' : '');
    return '$sign$prefix$body';
  }

  /// Compact representation used in dense chips and chart axes:
  /// `\u09F31.2\u09B9` (hazar), `\u09F32.5\u09B2` (lakh), `\u09F31.1\u0995\u09CB` (crore).
  String formatCompact(int poisha) {
    final negative = poisha < 0;
    final absPoisha = poisha.abs();
    final symbolText = showSymbol ? symbol : '';
    final sign = negative ? '\u2212' : '';

    String body;
    if (absPoisha >= 100000 * Money.poishaPerTaka * 100) {
      // crore
      body = '${_trimZero((absPoisha / (Money.poishaPerTaka * 10000000)))}কো';
    } else if (absPoisha >= 100000 * Money.poishaPerTaka) {
      body = '${_trimZero((absPoisha / (Money.poishaPerTaka * 100000)))}ল';
    } else if (absPoisha >= 1000 * Money.poishaPerTaka) {
      body = '${_trimZero((absPoisha / (Money.poishaPerTaka * 1000)))}হ';
    } else {
      return format(poisha);
    }
    if (useBengaliDigits) body = toBengaliDigits(body);
    return '$sign$symbolText$body';
  }

  static String _trimZero(double value) {
    final text = value.toStringAsFixed(value.abs() >= 100 ? 0 : 1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  String _group(String digits) {
    if (!bangladeshiGrouping || digits.length <= 3) return digits;
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last3';
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }
}
