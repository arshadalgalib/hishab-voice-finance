/// Bengali / ASCII digit helpers.
///
/// Bangladeshi users type and speak numbers in both scripts, so every numeric
/// input path in the application funnels through these helpers.
library;

const List<String> _bengaliDigits = <String>[
  '\u09E6', // ০
  '\u09E7', // ১
  '\u09E8', // ২
  '\u09E9', // ৩
  '\u09EA', // ৪
  '\u09EB', // ৫
  '\u09EC', // ৬
  '\u09ED', // ৭
  '\u09EE', // ৮
  '\u09EF', // ৯
];

/// Converts every ASCII digit in [input] to its Bengali counterpart.
String toBengaliDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x30 && rune <= 0x39) {
      buffer.write(_bengaliDigits[rune - 0x30]);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// Converts every Bengali digit in [input] to its ASCII counterpart.
///
/// Returns the text unchanged when no Bengali digits are present.
String toAsciiDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x09E6 && rune <= 0x09EF) {
      buffer.writeCharCode(0x30 + (rune - 0x09E6));
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// True when [input] contains at least one Bengali digit.
bool hasBengaliDigits(String input) {
  for (final rune in input.runes) {
    if (rune >= 0x09E6 && rune <= 0x09EF) return true;
  }
  return false;
}

/// Parses an integer written in either script. Returns `null` when [input]
/// does not contain a parsable integer.
int? tryParseInt(String input) => int.tryParse(toAsciiDigits(input).trim());

/// Parses a decimal written in either script. Returns `null` when [input] is
/// not parsable.
double? tryParseDouble(String input) {
  final normalized = toAsciiDigits(input).replaceAll(',', '').trim();
  return double.tryParse(normalized);
}
