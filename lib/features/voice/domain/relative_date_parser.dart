import 'package:meta/meta.dart';

import 'text_normalizer.dart';

/// What the date/time parser concluded.
@immutable
class DateParseResult {
  const DateParseResult({
    this.date,
    this.explicit = false,
    this.hadNegatedCandidate = false,
    this.note,
    this.startToken,
    this.endToken,
  });

  /// The resolved local date-time, or null when nothing date-like was said (in
  /// which case the caller should use "now").
  final DateTime? date;

  /// True when the user actually said a date rather than the parser defaulting.
  final bool explicit;

  /// True when a date word was present but explicitly rejected ("আজ নয়").
  /// Surfaced in the UI so the user can see the correction was understood.
  final bool hadNegatedCandidate;

  final String? note;

  /// Token range that the date/time expression occupied, so the description
  /// builder can exclude it. End-exclusive.
  final int? startToken;
  final int? endToken;
}

/// Interprets Bengali, Banglish and English date/time expressions.
///
/// Handles the corrective pattern the brief calls out:
/// `"আজ নয়, গতকাল ৪০০ টাকা খরচ করেছি"` → **yesterday**, because `আজ` is
/// negated and `গতকাল` is not.
class RelativeDateParser {
  RelativeDateParser({required DateTime now}) : _now = now;

  final DateTime _now;

  static const Set<String> _negations = <String>{
    'নয়',
    'না',
    'নাহ',
    'noi',
    'na',
    'no',
    'not',
    'না,',
    'nay',
  };

  /// Rough time-of-day anchors used when the user says "in the morning" etc.
  static const Map<String, int> _timeAnchors = <String, int>{
    'সকাল': 9,
    'সকালে': 9,
    'ভোর': 5,
    'dupure': 13,
    'দুপুর': 13,
    'দুপুরে': 13,
    'noon': 12,
    'বিকেল': 17,
    'বিকেলে': 17,
    'afternoon': 15,
    'সন্ধ্যা': 19,
    'সন্ধ্যায়': 19,
    'evening': 19,
    'রাত': 21,
    'রাতে': 21,
    'রাত্রি': 22,
    'night': 21,
    'morning': 9,
    'lastnight': 22,
  };

  static final Map<String, int> _months = _buildMonths();

  DateParseResult parse(NormalizedText text) {
    final tokens = text.tokens;
    final candidates = <_DateCandidate>[];

    for (var index = 0; index < tokens.length; index++) {
      final token = tokens[index];

      final relative = _relativeOffset(token);
      if (relative != null) {
        final base = _atTime(
          DateTime(
            _now.year,
            _now.month,
            _now.day,
          ).add(Duration(days: relative)),
          _hourFrom(tokens, index),
        );
        candidates.add(
          _DateCandidate(
            index: index,
            date: base,
            explicit: true,
            negated: _isNegated(tokens, index),
          ),
        );
        continue;
      }

      final explicit = _tryExplicitDate(tokens, index);
      if (explicit != null) {
        candidates.add(explicit);
        index = explicit.endIndex - 1;
      }
    }

    final timeOnly = _firstTimeAnchor(tokens);

    if (candidates.isEmpty) {
      if (timeOnly != null) {
        return DateParseResult(
          date: DateTime(_now.year, _now.month, _now.day, timeOnly.value),
          explicit: false,
          note: 'Time of day “${timeOnly.word}” understood; date is today.',
        );
      }
      return const DateParseResult();
    }

    final usable = candidates.where((c) => !c.negated).toList();
    final rejected = candidates.where((c) => c.negated).toList();
    if (usable.isEmpty) {
      // Everything was contradicted — do not guess.
      return DateParseResult(
        hadNegatedCandidate: true,
        note: 'The date you mentioned was ruled out; please confirm the date.',
      );
    }

    usable.sort((a, b) => a.index.compareTo(b.index));
    final chosen = usable.last;
    final hour = _hourFrom(tokens, chosen.index) ?? timeOnly?.value;
    var resolved = chosen.date;
    if (hour != null) {
      resolved = DateTime(resolved.year, resolved.month, resolved.day, hour);
    }

    return DateParseResult(
      date: resolved,
      explicit: true,
      hadNegatedCandidate: rejected.isNotEmpty,
      startToken: chosen.index,
      endToken: chosen.endIndex,
      note: rejected.isNotEmpty
          ? 'Ignored “${text.span(rejected.first.index, rejected.first.index + 1)}” '
                'because it was negated.'
          : null,
    );
  }

  static DateTime _atTime(DateTime day, int? hour) =>
      DateTime(day.year, day.month, day.day, hour ?? 12);

  static int? _hourFrom(List<String> tokens, int index) {
    for (var offset = 1; offset <= 2; offset++) {
      final next = index + offset;
      if (next >= tokens.length) break;
      final anchor = _timeAnchors[tokens[next]];
      if (anchor != null) return anchor;
    }
    return null;
  }

  static _TimeAnchor? _firstTimeAnchor(List<String> tokens) {
    for (final token in tokens) {
      final anchor = _timeAnchors[token];
      if (anchor != null) return _TimeAnchor(token, anchor);
    }
    return null;
  }

  static bool _isNegated(List<String> tokens, int index) {
    for (var offset = 1; offset <= 2; offset++) {
      final next = index + offset;
      if (next >= tokens.length) break;
      if (_negations.contains(tokens[next])) return true;
    }
    return false;
  }

  /// Relative words → day offset from today.
  static int? _relativeOffset(String token) {
    switch (token) {
      case 'আজ':
      case 'today':
      case 'আজকে':
        return 0;
      case 'গতকাল':
      case 'yesterday':
      case 'গতরাতে':
      case 'গতকালকে':
        return -1;
      case 'পরশু':
      case 'পরশুদিন':
        // Bengali "পরশু" is direction-ambiguous; in a past-tense sentence it
        // means the day before yesterday, which is what we assume.
        return -2;
      case 'আগামীকাল':
      case 'tomorrow':
      case 'কাল':
        return 1;
      case 'গত':
        return null;
      case 'lastweek':
        return -7;
      case 'lastmonth':
        return -30;
      default:
        return null;
    }
  }

  static final Map<String, int> _compoundRelative = <String, int>{
    'গত সপ্তাহ': -7,
    'গত মাস': -30,
    'গত বছর': -365,
    'last week': -7,
    'last month': -30,
    'last year': -365,
    'এই মাস': 0,
    'this month': 0,
  };

  /// Recognises `<day> <month> [<year>]`, `<month> <day>`, `12/03/2026` and
  /// `12 03 2026`.
  _DateCandidate? _tryExplicitDate(List<String> tokens, int index) {
    // numeric forms: 12/03/2026 or 2026-03-12 (single token)
    final single = tokens[index];
    final numeric = RegExp(
      r'^(\d{1,4})[-/](\d{1,2})[-/](\d{1,4})$',
    ).firstMatch(single);
    if (numeric != null) {
      final parsed = _fromNumericParts(
        numeric.group(1)!,
        numeric.group(2)!,
        numeric.group(3)!,
      );
      if (parsed != null) {
        return _DateCandidate(
          index: index,
          date: parsed,
          explicit: true,
          negated: _isNegated(tokens, index),
          endIndex: index + 1,
        );
      }
    }

    // "12 03 2026" (three consecutive numeric tokens, 'br' replaced '.')
    if (RegExp(r'^\d{1,2}$').hasMatch(single) && index + 2 < tokens.length) {
      final b = tokens[index + 1];
      final c = tokens[index + 2];
      if (RegExp(r'^\d{1,2}$').hasMatch(b) &&
          RegExp(r'^\d{2,4}$').hasMatch(c)) {
        final parsed = _fromNumericParts(single, b, c);
        if (parsed != null) {
          return _DateCandidate(
            index: index,
            date: parsed,
            explicit: true,
            negated: false,
            endIndex: index + 3,
          );
        }
      }
    }

    // "<day> <month>" or "<day> <month> <year>"
    if (RegExp(r'^\d{1,2}$').hasMatch(single)) {
      final day = int.parse(single);
      if (index + 1 < tokens.length) {
        final month = _months[tokens[index + 1]];
        if (month != null && day >= 1 && day <= 31) {
          var year = _now.year;
          var end = index + 2;
          if (index + 2 < tokens.length) {
            final maybeYear = int.tryParse(tokens[index + 2]);
            if (maybeYear != null && maybeYear >= 1900 && maybeYear <= 2200) {
              year = maybeYear;
              end = index + 3;
            }
          }
          final date = _safeDate(year, month, day);
          if (date != null) {
            return _DateCandidate(
              index: index,
              date: date,
              explicit: true,
              negated: _isNegated(tokens, index),
              endIndex: end,
            );
          }
        }
      }
    }

    // "<month> <day>"
    final month = _months[single];
    if (month != null && index + 1 < tokens.length) {
      final dayText = tokens[index + 1];
      if (RegExp(r'^\d{1,2}$').hasMatch(dayText)) {
        var year = _now.year;
        var end = index + 2;
        if (index + 2 < tokens.length) {
          final maybeYear = int.tryParse(tokens[index + 2]);
          if (maybeYear != null && maybeYear >= 1900 && maybeYear <= 2200) {
            year = maybeYear;
            end = index + 3;
          }
        }
        final date = _safeDate(year, month, int.parse(dayText));
        if (date != null) {
          return _DateCandidate(
            index: index,
            date: date,
            explicit: true,
            negated: _isNegated(tokens, index),
            endIndex: end,
          );
        }
      }
    }

    // compound relative expressions
    if (index + 1 < tokens.length) {
      final phrase = '${tokens[index]} ${tokens[index + 1]}';
      final offset = _compoundRelative[phrase];
      if (offset != null) {
        return _DateCandidate(
          index: index,
          date: DateTime(
            _now.year,
            _now.month,
            _now.day,
          ).add(Duration(days: offset)),
          explicit: true,
          negated: _isNegated(tokens, index),
          endIndex: index + 2,
        );
      }
    }

    return null;
  }

  static DateTime? _fromNumericParts(String a, String b, String c) {
    var day = int.tryParse(a);
    var month = int.tryParse(b);
    var year = int.tryParse(c);
    if (day == null || month == null || year == null) return null;
    // Support yyyy-mm-dd as well.
    if (a.length == 4) {
      year = int.parse(a);
      month = int.parse(b);
      day = int.parse(c);
    }
    if (year < 100) year += 2000;
    return _safeDate(year, month, day);
  }

  static DateTime? _safeDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    // Reject roll-over dates such as 31 February.
    if (date.month != month || date.day != day) return null;
    return date;
  }

  static final Map<String, int> _compoundRelativeCopy = _compoundRelative;
  static Map<String, int> get compoundRelative => _compoundRelativeCopy;

  static Map<String, int> _buildMonths() {
    const english = <String>[
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
    ];
    const bengali = <String>[
      'জানুয়ারি',
      'ফেব্রুয়ারি',
      'মার্চ',
      'এপ্রিল',
      'মে',
      'জুন',
      'জুলাই',
      'আগস্ট',
      'সেপ্টেম্বর',
      'অক্টোবর',
      'নভেম্বর',
      'ডিসেম্বর',
    ];
    const banglish = <String>[
      'jan',
      'feb',
      'mar',
      'apr',
      'may',
      'jun',
      'jul',
      'aug',
      'sep',
      'oct',
      'nov',
      'dec',
    ];
    final map = <String, int>{};
    for (var index = 0; index < 12; index++) {
      final month = index + 1;
      map[english[index]] = month;
      map[english[index].substring(0, 3)] = month;
      map[bengali[index]] = month;
      map[banglish[index]] = month;
    }
    return map;
  }
}

class _DateCandidate {
  _DateCandidate({
    required this.index,
    required this.date,
    required this.explicit,
    required this.negated,
    int? endIndex,
  }) : endIndex = endIndex ?? index + 1;

  final int index;
  final int endIndex;
  final DateTime date;
  final bool explicit;
  final bool negated;
}

class _TimeAnchor {
  const _TimeAnchor(this.word, this.value);

  final String word;
  final int value;
}
