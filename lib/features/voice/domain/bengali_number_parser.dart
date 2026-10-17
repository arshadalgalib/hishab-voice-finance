/// Bengali and Banglish *word* number parsing.
///
/// Speech recognisers rarely return digits for Bengali speech: they return
/// words such as "দেড় হাজার" or "আড়াইশো". This parser turns those word
/// sequences (and mixed digit/word forms such as "1.5 thousand", "2k",
/// "২,৫০০") into a numeric taka value.
///
/// ## Grammar
/// The parser walks the token list with a small accumulator:
///
/// * a plain number word (`দুই`, `বিশ`, `পঁচিশ`, `250`) adds to the current
///   *pending* value;
/// * `শো` / `শ` / `hundred` multiplies the pending value by 100;
/// * `হাজার` / `লাখ` / `কোটি` (and `thousand` / `lakh` / `crore` / `k` / `m`)
///   multiply the pending value (defaulting to 1) and flush it into the total;
/// * `দেড়` (1.5) and `আড়াই` (2.5) are *absolute* values;
/// * `সোয়া` (+0.25) and `পৌনে` (−0.25) are *relative* modifiers applied to the
///   value they precede.
///
/// So `দুই হাজার পাঁচশো` → 2×1000 + 5×100 = 2500, `সোয়া দুই হাজার` → 2250 and
/// `পৌনে তিন হাজার` → 2750.
library;

import '../../../core/utils/bengali_digits.dart';

/// A numeric value found inside a token list.
class AmountMatch {
  const AmountMatch({
    required this.taka,
    required this.startToken,
    required this.endToken,
    required this.sourceText,
    this.adjacentToCurrencyWord = false,
  });

  /// End-exclusive token index.
  final int startToken;
  final int endToken;

  /// Parsed value in taka (may contain a .25/.5/.75 fraction).
  final double taka;

  final String sourceText;

  /// True when the phrase was immediately followed (or preceded) by a currency
  /// word such as `টাকা`, `taka` or `৳`. Used only to raise confidence.
  final bool adjacentToCurrencyWord;

  int get tokenCount => endToken - startToken;
}

enum _Kind {
  /// An absolute small value, e.g. `দুই` (2) or `বিশ` (20).
  value,

  /// A multiplier, e.g. `শো` (100), `হাজার` (1000).
  multiply,

  /// An absolute fractional value: `দেড়` (1.5), `আড়াই` (2.5).
  absolute,

  /// A relative modifier: `সোয়া` (+0.25), `পৌনে` (−0.25).
  delta,
}

class _NumWord {
  const _NumWord(this.kind, this.amount);

  final _Kind kind;
  final double amount;
}

class BengaliNumberParser {
  const BengaliNumberParser._();

  static const Set<String> currencyWords = <String>{
    'টাকা',
    'টাকায়',
    'টাকার',
    'tk',
    'taka',
    'takar',
    'taka.',
    '৳',
    'bdt',
    'poisha',
    'পয়সা',
    'পয়সায়',
    'ta',
    'ট',
  };

  /// Absolute values 0..100.
  static final Map<String, _NumWord> _words = _buildWords();

  /// Returns the value of a token list that consists *only* of number words, or
  /// `null` when the sequence contains anything else or is not a valid number.
  static double? parseTokens(List<String> tokens) {
    if (tokens.isEmpty) return null;
    var total = 0.0;
    var pending = 0.0;
    var pendingSet = false;
    var delta = 0.0;
    var sawAnything = false;

    for (final rawToken in tokens) {
      // Parse digits from a decimal-preserving form first: `_canonical` strips
      // punctuation, which would silently turn "2.5" into "25". Fall back to
      // the canonical form so trailing punctuation is still tolerated.
      final trimmed = rawToken.trim().toLowerCase();
      final direct =
          _parseDigitToken(trimmed) ?? _parseDigitToken(_canonical(rawToken));
      if (direct != null) {
        pending += direct;
        pendingSet = true;
        sawAnything = true;
        continue;
      }

      final token = _canonical(rawToken);
      if (token.isEmpty) continue;

      final word = _words[token];
      if (word == null) return null;
      sawAnything = true;

      switch (word.kind) {
        case _Kind.value:
          pending += word.amount;
          pendingSet = true;
        case _Kind.absolute:
          pending += word.amount;
          pendingSet = true;
        case _Kind.delta:
          delta += word.amount;
        case _Kind.multiply:
          final base = pendingSet ? pending : 1.0;
          total += (base + delta) * word.amount;
          pending = 0;
          pendingSet = false;
          delta = 0;
      }
    }

    if (!sawAnything) return null;
    final result = total + pending + delta;
    if (result <= 0) return null;
    return result;
  }

  /// Scans [tokens] for the most credible amount.
  ///
  /// Preference order:
  /// 1. a numeric phrase immediately followed or preceded by a currency word;
  /// 2. the longest numeric phrase that contains at least one number word;
  /// 3. a plain digit run.
  static AmountMatch? findAmount(List<String> tokens) {
    final candidates = <AmountMatch>[];

    for (var start = 0; start < tokens.length; start++) {
      if (!_startsNumber(tokens[start])) continue;
      // Longest match wins, up to 6 tokens ("এক কোটি বিশ লাখ পাঁচ হাজার টাকা").
      for (var length = 6; length >= 1; length--) {
        final end = start + length;
        if (end > tokens.length) continue;
        final slice = tokens.sublist(start, end);
        final value = parseTokens(slice);
        if (value == null) continue;
        final before = start > 0 ? _canonical(tokens[start - 1]) : '';
        final after = end < tokens.length ? _canonical(tokens[end]) : '';
        final currencyAdjacent =
            currencyWords.contains(before) || currencyWords.contains(after);
        candidates.add(
          AmountMatch(
            taka: value,
            startToken: start,
            endToken: end,
            sourceText: slice.join(' '),
            adjacentToCurrencyWord: currencyAdjacent,
          ),
        );
        break; // longest match for this start
      }
    }

    if (candidates.isEmpty) return null;

    final withCurrency = candidates
        .where((c) => c.adjacentToCurrencyWord)
        .toList();
    if (withCurrency.isNotEmpty) {
      // Among currency-adjacent candidates prefer the longest phrase.
      withCurrency.sort((a, b) => b.tokenCount.compareTo(a.tokenCount));
      return withCurrency.first;
    }

    // Otherwise prefer the longest word-based phrase, falling back to digits.
    candidates.sort((a, b) {
      final byWords = _wordCount(b).compareTo(_wordCount(a));
      if (byWords != 0) return byWords;
      return b.tokenCount.compareTo(a.tokenCount);
    });
    return candidates.first;
  }

  static int _wordCount(AmountMatch match) {
    final text = match.sourceText.split(' ');
    var count = 0;
    for (final token in text) {
      if (_words.containsKey(_canonical(token))) count++;
    }
    return count;
  }

  static bool _startsNumber(String rawToken) {
    final token = _canonical(rawToken);
    if (token.isEmpty) return false;
    if (_parseDigitToken(token) != null) return true;
    return _words.containsKey(token);
  }

  /// Parses a token that is (or contains) digits: `250`, `2,500`, `1.5`,
  /// `2k`, `2.5k`, `1lakh`, `২৫০`.
  static double? _parseDigitToken(String token) {
    final ascii = toAsciiDigits(token);
    final lowered = ascii.toLowerCase();

    final suffixMultipliers = <String, double>{
      'k': 1000,
      'hazar': 1000,
      'thousand': 1000,
      'lakh': 100000,
      'lac': 100000,
      'lakhs': 100000,
      'm': 1000000,
      'million': 1000000,
      'crore': 10000000,
      'cr': 10000000,
    };

    for (final entry in suffixMultipliers.entries) {
      final suffix = entry.key;
      if (!lowered.endsWith(suffix)) continue;
      final numericPart = lowered.substring(0, lowered.length - suffix.length);
      if (numericPart.isEmpty) continue;
      final value = _parsePlainNumber(numericPart);
      if (value != null) return value * entry.value;
    }

    return _parsePlainNumber(lowered);
  }

  static double? _parsePlainNumber(String text) {
    if (text.isEmpty) return null;
    // Reject anything that is not digits plus at most one separator.
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(text)) return null;
    return double.tryParse(text);
  }

  /// Lower-cases ASCII and strips a few punctuation marks that recognisers add.
  static String _canonical(String token) {
    var value = token.trim().toLowerCase();
    value = value.replaceAll(RegExp(r'''[.,!?;:"'()।]'''), '');
    return value;
  }

  /// Public helper used by tests and by the normaliser.
  static bool isNumberWord(String token) =>
      _words.containsKey(_canonical(token)) ||
      _parseDigitToken(_canonical(token)) != null;

  /// All recognised number words. Exposed for the parser test corpus.
  static Set<String> get knownWords => _words.keys.toSet();

  static Map<String, _NumWord> _buildWords() {
    final map = <String, _NumWord>{};

    void put(String text, _Kind kind, double amount) {
      map[text] = _NumWord(kind, amount);
    }

    void value(double amount, List<String> spellings) {
      for (final spelling in spellings) {
        put(spelling, _Kind.value, amount);
      }
    }

    // Multipliers -----------------------------------------------------------
    for (final spelling in [
      'শো',
      'শ',
      'শত',
      'শয়',
      'sho',
      'shou',
      'so',
      'shu',
      'sh',
      'hundred',
    ]) {
      put(spelling, _Kind.multiply, 100);
    }
    for (final spelling in [
      'হাজার',
      'হাযার',
      'হাজর',
      'hazar',
      'hajar',
      'hazaar',
      'thousand',
      'k',
      'hazr',
    ]) {
      put(spelling, _Kind.multiply, 1000);
    }
    for (final spelling in [
      'লাখ',
      'লক্ষ',
      'lakh',
      'lac',
      'lakhs',
      'lakhs.',
      'lac.',
    ]) {
      put(spelling, _Kind.multiply, 100000);
    }
    for (final spelling in ['কোটি', 'koti', 'crore', 'cr', 'kror', 'koti.']) {
      put(spelling, _Kind.multiply, 10000000);
    }

    // Fractions ------------------------------------------------------------
    for (final spelling in ['দেড়', 'দের', 'dedh', 'dher', 'ded', 'derh']) {
      put(spelling, _Kind.absolute, 1.5);
    }
    for (final spelling in [
      'আড়াই',
      'আরাই',
      'arai',
      'aarai',
      'aray',
      'arahi',
      'arai.',
    ]) {
      put(spelling, _Kind.absolute, 2.5);
    }
    for (final spelling in [
      'আড়াইশো',
      'আড়াইশ',
      'araisho',
      'araishou',
      'araiso',
    ]) {
      put(spelling, _Kind.value, 250);
    }
    for (final spelling in ['দেড়শো', 'দেড়শ', 'dersho', 'dhersho', 'dedsho']) {
      put(spelling, _Kind.value, 150);
    }
    for (final spelling in ['সোয়া', 'shoya', 'soya', 'sowa', 'showa']) {
      put(spelling, _Kind.delta, 0.25);
    }
    for (final spelling in ['পৌনে', 'poune', 'poney', 'pone', 'pounay']) {
      put(spelling, _Kind.delta, -0.25);
    }
    for (final spelling in ['আধা', 'আধ', 'adha', 'ardhek', 'half']) {
      put(spelling, _Kind.delta, 0.5);
    }

    // Units 0..20 ----------------------------------------------------------
    value(0, ['শূন্য', 'শুন্য', 'sunno', 'shunno', 'zero']);
    value(1, ['এক', 'একটা', 'ek', 'ekta', 'one', 'একটি']);
    value(2, ['দুই', 'দু', 'দুটো', 'dui', 'du', 'doe', 'two', 'dutoo']);
    value(3, ['তিন', 'তিনটা', 'tin', 'three', 'tinta']);
    value(4, ['চার', 'চারটা', 'char', 'chaar', 'four', 'charta']);
    value(5, ['পাঁচ', 'পাচ', 'পাঁচটা', 'panch', 'pach', 'paanch', 'five']);
    value(6, ['ছয়', 'ছয়টা', 'choy', 'chhoy', 'soy', 'six']);
    value(7, ['সাত', 'সাতটা', 'sat', 'saat', 'seven']);
    value(8, ['আট', 'আটটা', 'aat', 'ath', 'at', 'eight']);
    value(9, ['নয়', 'নয়টা', 'noy', 'noi', 'nine']);
    value(10, ['দশ', 'দশটা', 'dosh', 'dosh', 'dus', 'ten']);
    value(11, ['এগারো', 'এগার', 'এগারই', 'egaro', 'egar', 'eleven']);
    value(12, ['বারো', 'বার', 'baro', 'bar', 'twelve']);
    value(13, ['তেরো', 'তের', 'tero', 'ter', 'thirteen']);
    value(14, ['চৌদ্দ', 'চোদ্দ', 'chouddo', 'choddo', 'chauddo', 'fourteen']);
    value(15, ['পনেরো', 'পনের', 'ponero', 'poner', 'fifteen']);
    value(16, ['ষোল', 'ষোলো', 'sholo', 'solo', 'sholo.', 'sixteen']);
    value(17, ['সতেরো', 'সতের', 'shotero', 'sotero', 'seventeen']);
    value(18, ['আঠারো', 'আঠার', 'atharo', 'ataro', 'eighteen']);
    value(19, ['উনিশ', 'ঊনিশ', 'unish', 'unnish', 'nineteen']);
    value(20, ['বিশ', 'কুড়ি', 'bish', 'kuri', 'twenty']);

    // 21..29 ---------------------------------------------------------------
    value(21, ['একুশ', 'ekush', 'ekus', 'একুশে']);
    value(22, ['বাইশ', 'বাইস', 'baish', 'bais', 'bais.']);
    value(23, ['তেইশ', 'teish', 'teis']);
    value(24, ['চব্বিশ', 'চবিশ', 'chobbish', 'chobish', 'chabbish']);
    value(25, ['পঁচিশ', 'পচিশ', 'ponchish', 'pochish', 'pachish']);
    value(26, ['ছাব্বিশ', 'ছাবিশ', 'chabbish', 'chhabbish', 'chabish']);
    value(27, ['সাতাশ', 'সাতাশ', 'satash', 'sataash']);
    value(28, ['আটাশ', 'আঠাশ', 'atash', 'atash']);
    value(29, ['ঊনত্রিশ', 'উনত্রিশ', 'unotrish', 'untrish']);

    // 30..39 ---------------------------------------------------------------
    value(30, ['ত্রিশ', 'তিরিশ', 'trish', 'tirish', 'tris']);
    value(31, ['একত্রিশ', 'একতিরিশ', 'ektrish', 'ektirish']);
    value(32, ['বত্রিশ', 'বতিরিশ', 'botrish', 'batrish']);
    value(33, ['তেত্রিশ', 'তেতিরিশ', 'tetrish', 'tetirish']);
    value(34, ['চৌত্রিশ', 'চৌতিরিশ', 'choutrish', 'chautrish']);
    value(35, ['পঁয়ত্রিশ', 'পঁয়তিরিশ', 'poytrish', 'poytirish']);
    value(36, ['ছত্রিশ', 'ছতিরিশ', 'chotrish', 'chhotrish']);
    value(37, ['সাঁইত্রিশ', 'সাঁইতিরিশ', 'saitrish', 'saitirish']);
    value(38, ['আটত্রিশ', 'আটতিরিশ', 'attrish', 'attirish']);
    value(39, ['ঊনচল্লিশ', 'উনচল্লিশ', 'unochollish', 'unchollish']);

    // 40..49 ---------------------------------------------------------------
    value(40, ['চল্লিশ', 'চল্লিশ', 'chollish', 'challish', 'cholish']);
    value(41, ['একচল্লিশ', 'একচল্লিশ', 'ekchollish', 'ekchallish']);
    value(42, ['বিয়াল্লিশ', 'বেয়াল্লিশ', 'biallish', 'bealish']);
    value(43, ['তেতাল্লিশ', 'তেতালিশ', 'tetallish', 'tetalish']);
    value(44, ['চুয়াল্লিশ', 'চুয়ালিশ', 'chuallish', 'chuyalish']);
    value(45, ['পঁয়তাল্লিশ', 'পঁয়তালিশ', 'poytallish', 'poytalish']);
    value(46, ['ছেচল্লিশ', 'ছেচল্লিশ', 'chechollish', 'chhechollish']);
    value(47, ['সাতচল্লিশ', 'সাতচল্লিশ', 'satchollish', 'satchallish']);
    value(48, ['আটচল্লিশ', 'আটচল্লিশ', 'atchollish', 'atchallish']);
    value(49, ['ঊনপঞ্চাশ', 'উনপঞ্চাশ', 'unoponchash', 'unponchash']);

    // 50..59 ---------------------------------------------------------------
    value(50, ['পঞ্চাশ', 'পঞ্চাশ', 'ponchash', 'pachash', 'ponchas']);
    value(51, ['একান্ন', 'একান্ন', 'ekanno', 'ekann']);
    value(52, ['বায়ান্ন', 'বায়ান্ন', 'bayanno', 'bayann']);
    value(53, ['তিপ্পান্ন', 'তিপ্পান্ন', 'tippanno', 'tippann']);
    value(54, ['চুয়ান্ন', 'চুয়ান্ন', 'chuanno', 'chuyann']);
    value(55, ['পঞ্চান্ন', 'পঞ্চান্ন', 'ponchanno', 'ponchann']);
    value(56, ['ছাপ্পান্ন', 'ছাপ্পান্ন', 'chappanno', 'chhappann']);
    value(57, ['সাতান্ন', 'সাতান্ন', 'satanno', 'satann']);
    value(58, ['আটান্ন', 'আটান্ন', 'atanno', 'atann']);
    value(59, ['ঊনষাট', 'উনষাট', 'unoshsat', 'unshaat']);

    // 60..69 ---------------------------------------------------------------
    value(60, ['ষাট', 'সাট', 'shat', 'sat.', 'shaath']);
    value(61, ['একষট্টি', 'একষট্টি', 'ekshoti', 'ekshotti']);
    value(62, ['বাষট্টি', 'বাষট্টি', 'boshotti', 'bashotti']);
    value(63, ['তেষট্টি', 'তেষট্টি', 'teshotti', 'teshoti']);
    value(64, ['চৌষট্টি', 'চৌষট্টি', 'choushoti', 'chaushoti']);
    value(65, ['পঁয়ষট্টি', 'পঁয়ষট্টি', 'poyshoti', 'poyshotti']);
    value(66, ['ছেষট্টি', 'ছেষট্টি', 'cheshoti', 'chheshoti']);
    value(67, ['সাতষট্টি', 'সাতষট্টি', 'satshoti', 'satshoti']);
    value(68, ['আটষট্টি', 'আটষট্টি', 'atshoti', 'atshoti']);
    value(69, ['ঊনসত্তর', 'উনসত্তর', 'unoshottor', 'unsottor']);

    // 70..79 ---------------------------------------------------------------
    value(70, ['সত্তর', 'সত্তর', 'shottor', 'sottor']);
    value(71, ['একাত্তর', 'একাত্তর', 'ekattor', 'ekattor']);
    value(72, ['বাহাত্তর', 'বাহাত্তর', 'bahattor', 'bahattor']);
    value(73, ['তিয়াত্তর', 'তিয়াত্তর', 'tiyattor', 'tiyattor']);
    value(74, ['চুয়াত্তর', 'চুয়াত্তর', 'chuyattor', 'chuattor']);
    value(75, ['পঁচাত্তর', 'পঁচাত্তর', 'ponchattor', 'pochattor']);
    value(76, ['ছিয়াত্তর', 'ছিয়াত্তর', 'chiyattor', 'chhiyattor']);
    value(77, ['সাতাত্তর', 'সাতাত্তর', 'satattor', 'satattor']);
    value(78, ['আটাত্তর', 'আটাত্তর', 'atattor', 'atattor']);
    value(79, ['ঊনআশি', 'উনআশি', 'unashi', 'unashi']);

    // 80..89 ---------------------------------------------------------------
    value(80, ['আশি', 'আশি', 'ashi', 'ashi']);
    value(81, ['একাশি', 'একাশি', 'ekashi', 'ekashi']);
    value(82, ['বিরাশি', 'বিরাশি', 'birashi', 'birashi']);
    value(83, ['তিরাশি', 'তিরাশি', 'tirashi', 'tirashi']);
    value(84, ['চুরাশি', 'চুরাশি', 'churashi', 'churashi']);
    value(85, ['পঁচাশি', 'পঁচাশি', 'ponchashi', 'pochashi']);
    value(86, ['ছিয়াশি', 'ছিয়াশি', 'chiyashi', 'chhiyashi']);
    value(87, ['সাতাশি', 'সাতাশি', 'satashi', 'satashi']);
    value(88, ['আটাশি', 'আটাশি', 'atashi', 'atashi']);
    value(89, ['ঊননব্বই', 'উননব্বই', 'unonobboi', 'unnobboi']);

    // 90..100 --------------------------------------------------------------
    value(90, ['নব্বই', 'নব্বই', 'nobboi', 'nobboi']);
    value(91, ['একানব্বই', 'একানব্বই', 'ekanobboi', 'ekanobboi']);
    value(92, ['বিরানব্বই', 'বিরানব্বই', 'biranobboi', 'biranobboi']);
    value(93, ['তিরানব্বই', 'তিরানব্বই', 'tiranobboi', 'tiranobboi']);
    value(94, ['চুরানব্বই', 'চুরানব্বই', 'churanobboi', 'churanobboi']);
    value(95, ['পঁচানব্বই', 'পঁচানব্বই', 'ponchanobboi', 'pochanobboi']);
    value(96, ['ছিয়ানব্বই', 'ছিয়ানব্বই', 'chiyanobboi', 'chhiyanobboi']);
    value(97, ['সাতানব্বই', 'সাতানব্বই', 'satanobboi', 'satanobboi']);
    value(98, ['আটানব্বই', 'আটানব্বই', 'atanobboi', 'atanobboi']);
    value(99, ['নিরানব্বই', 'নিরানব্বই', 'niranobboi', 'niranobboi']);
    value(100, ['একশো', 'একশ', 'একশত', 'eksho', 'eksho.', 'hundred.']);

    // Common "<unit>শো" contractions: দুইশো = 200, পাঁচশো = 500 ...
    const contractions = <int, List<String>>{
      2: ['দুইশো', 'দুশো', 'দুইশ', 'duisho', 'dusho', 'duishou'],
      3: ['তিনশো', 'তিনশ', 'tinsho', 'tinshou'],
      4: ['চারশো', 'চারশ', 'charsho', 'charshou'],
      5: ['পাঁচশো', 'পাচশো', 'পাঁচশ', 'pachsho', 'pachshou', 'panchsho'],
      6: ['ছয়শো', 'ছয়শ', 'choysho', 'chhoysho'],
      7: ['সাতশো', 'সাতশ', 'satsho', 'satshou'],
      8: ['আটশো', 'আটশ', 'atsho', 'atshou'],
      9: ['নয়শো', 'নয়শ', 'noysho', 'noyshou'],
      10: ['দশশো', 'দশশ', 'dossho'],
    };
    contractions.forEach((unit, spellings) {
      for (final spelling in spellings) {
        put(spelling, _Kind.value, unit * 100);
      }
    });

    return map;
  }
}
