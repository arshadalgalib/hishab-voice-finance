/// Text preparation shared by every part of the voice pipeline.
///
/// Speech recognition output for Bangladeshi users arrives as one of:
/// * Bengali script — `আজ বিকাশ থেকে ২৫০ টাকা বাজার করেছি।`
/// * Banglish — `aj bikash theke 250 taka bazar korechi`
/// * English — `I spent 180 taka on lunch from cash`
/// * a mixture of all three.
///
/// Normalisation makes those four shapes comparable *without* discarding the
/// information the parser needs:
/// * Bengali digits become ASCII digits so one numeric parser covers both
///   scripts;
/// * thousands separators are removed but decimal points are preserved;
/// * punctuation is stripped because recognisers punctuate inconsistently;
/// * a small, unambiguous table maps common Banglish spellings onto the
///   Bengali word they mean (`bikash` → `বিকাশ`, `khoroch` → `খরচ`), so the
///   matchers only ever need to know the Bengali and English forms.
library;

import '../../../core/utils/bengali_digits.dart';

/// The result of normalising one recognition result or typed sentence.
class NormalizedText {
  const NormalizedText({
    required this.raw,
    required this.normalized,
    required this.tokens,
  });

  /// Exactly what the recogniser returned (or the user typed).
  final String raw;

  /// Lower-cased, punctuation-free, whitespace-collapsed text.
  final String normalized;

  /// `normalized` split on whitespace.
  final List<String> tokens;

  bool get isEmpty => tokens.isEmpty;

  /// The substring covering tokens `[startToken, endToken)`.
  String span(int startToken, int endToken) =>
      tokens.sublist(startToken, endToken).join(' ');
}

class TextNormalizer {
  const TextNormalizer._();

  /// Banglish spelling variants mapped to one canonical spelling.
  ///
  /// Kept deliberately small and unambiguous — only variants that cannot mean a
  /// different word are listed, so normalisation never changes meaning.
  /// Canonical targets are either a Bengali word or a plain English word.
  static const Map<String, String> _aliases = <String, String>{
    // ── wallets / institutions ─────────────────────────────────────────────
    'bikash': 'বিকাশ',
    'bikashi': 'বিকাশ',
    'bkass': 'বিকাশ',
    'b-cash': 'বিকাশ',
    'bcash': 'বিকাশ',
    'b-kash': 'বিকাশ',
    'nagod': 'নগদ',
    'nagodh': 'নগদ',
    'nagad': 'নগদ',
    'ruket': 'রকেট',
    'roket': 'রকেট',
    'rokit': 'রকেট',
    'banke': 'ব্যাংক',
    'byank': 'ব্যাংক',
    'bank': 'ব্যাংক',
    'byanku': 'ব্যাংক',
    'acount': 'account',
    'akaunt': 'account',
    'kas': 'cash',
    'kash': 'cash',
    'kesh': 'cash',

    // ── currency / number words ────────────────────────────────────────────
    'tka': 'taka',
    'takaa': 'taka',
    'taaka': 'taka',
    'takaay': 'taka',
    'hajar': 'hazar',
    'hazzar': 'hazar',
    'hazaar': 'hazar',
    'hazr': 'hazar',
    'lak': 'lakh',
    'lakhs': 'lakh',

    // ── verbs and nouns ───────────────────────────────────────────────────
    'khoroch': 'খরচ',
    'khoroc': 'খরচ',
    'kharch': 'খরচ',
    'kharcha': 'খরচ',
    'kharoch': 'খরচ',
    'bazar': 'বাজার',
    'bajar': 'বাজার',
    'bayar': 'বাজার',
    'koreci': 'korechi',
    'korchi': 'korechi',
    'korsi': 'korechi',
    'korechhi': 'korechi',
    'korlam': 'korechi',
    'korelam': 'korechi',
    'korlaam': 'korechi',
    'pelam': 'peyechi',
    'pailam': 'peyechi',
    'paichi': 'peyechi',
    'paisi': 'peyechi',
    'peyechi': 'peyechi',
    'pathalam': 'pathiyechi',
    'pathailam': 'pathiyechi',
    'pathiyechi': 'pathiyechi',
    'pathaisi': 'pathiyechi',
    'tranfer': 'transfer',
    'transfer': 'transfer',
    'theke': 'theke',
    'teke': 'theke',
    'thake': 'theke',
    'theka': 'theke',
    'gotokal': 'গতকাল',
    'gotokkal': 'গতকাল',
    'gathokal': 'গতকাল',
    'kalke': 'গতকাল',
    'kal': 'গতকাল',
    'aj': 'আজ',
    'aaj': 'আজ',
    'ajke': 'আজ',
    'khawa': 'খাওয়া',
    'khaowa': 'খাওয়া',
    'khalan': 'খাওয়া',
    'kheychi': 'খাওয়া',
    'richarge': 'রিচার্জ',
    'recharge': 'রিচার্জ',
    'dukan': 'দোকান',
    'bhai': 'ভাই',
    'bonduk': 'বন্ধু',
  };

  /// The ASCII sentinel used to protect decimal points during cleaning.
  static const String _decimalSentinel = '\u0001';

  /// The sentinel used for thousands separators that must be deleted.
  static const String _thousandsSentinel = '\u0002';

  /// Normalises [raw] into a [NormalizedText].
  static NormalizedText normalize(String raw) {
    var text = raw
        // Bengali danda / double danda
        .replaceAll(RegExp('[\u0964\u0965]'), ' ')
        // quotes, brackets, question/exclamation marks
        .replaceAll(RegExp(r'[!?;:"“”‘’()\[\]{}]'), ' ')
        .replaceAll(RegExp('[\u2013\u2014]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Protect decimal points ("1.5"), remove thousands separators ("1,234").
    var previous = '';
    while (previous != text) {
      previous = text;
      text = text.replaceAllMapped(
        RegExp(r'(\d),(\d{3})'),
        (match) => '${match[1]}$_thousandsSentinel${match[2]}',
      );
    }
    text = text.replaceAllMapped(
      RegExp(r'(\d)\.(\d)'),
      (match) => '${match[1]}$_decimalSentinel${match[2]}',
    );

    text = text.replaceAll(',', ' ').replaceAll('.', ' ');
    text = text
        .replaceAll(_decimalSentinel, '.')
        .replaceAll(_thousandsSentinel, '');

    // Bengali digits → ASCII so one numeric parser covers both scripts.
    final ascii = toAsciiDigits(text).toLowerCase();

    final tokens = <String>[];
    for (final piece in ascii.split(' ')) {
      final token = _applyAlias(piece);
      if (token.isNotEmpty) tokens.add(token);
    }

    return NormalizedText(
      raw: raw,
      normalized: tokens.join(' '),
      tokens: List.unmodifiable(tokens),
    );
  }

  static String _applyAlias(String token) => _aliases[token] ?? token;

  /// Canonicalises a single token (used by the number parser and matchers).
  static String canonical(String token) =>
      _applyAlias(token.trim().toLowerCase());

  /// True when [token] is a currency word.
  static bool isCurrencyWord(String token) {
    const words = <String>{
      'টাকা',
      'টাকায়',
      'টাকার',
      'tk',
      'taka',
      'bdt',
      '\u09F3',
      'poisha',
      'পয়সা',
    };
    return words.contains(_applyAlias(token));
  }
}
