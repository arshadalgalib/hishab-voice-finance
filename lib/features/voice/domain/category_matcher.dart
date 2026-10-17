import 'package:meta/meta.dart';

import '../../../domain/enums.dart';
import 'text_normalizer.dart';

/// Minimal view of a category that the parser needs.
@immutable
class CategoryCandidate {
  const CategoryCandidate({
    required this.id,
    required this.name,
    required this.kind,
    this.keywords = const <String>[],
  });

  final String id;
  final String name;
  final CategoryKind kind;

  /// User-visible synonyms plus the built-in keyword list.
  final List<String> keywords;
}

/// One category mention found in the sentence.
@immutable
class CategoryMatch {
  const CategoryMatch({
    required this.categoryId,
    required this.categoryName,
    required this.kind,
    required this.matchedText,
    required this.startToken,
    required this.endToken,
    required this.score,
  });

  final String categoryId;
  final String categoryName;
  final CategoryKind kind;
  final String matchedText;
  final int startToken;
  final int endToken;

  /// Higher is more specific (longer keyword phrases win over single words).
  final int score;

  /// Direction evidence contributed by this match. Multi-word phrases are
  /// stronger evidence than a single generic word.
  double get specificityWeight => (endToken - startToken) >= 2 ? 3.0 : 2.0;
}

/// Maps spoken words onto the user's real categories.
///
/// Matching is phrase based and longest-match-first, so `বাসা ভাড়া` (House
/// Rent) beats a bare `ভাড়া`, and `মোবাইল রিচার্জ` (Mobile Recharge) beats a
/// generic `রিচার্জ`. Categories whose kind does not match the sentence's
/// transaction type are ignored.
class CategoryMatcher {
  CategoryMatcher(List<CategoryCandidate> categories)
    : _entries = _build(categories),
      _categories = categories;

  final List<CategoryCandidate> _categories;
  final List<_CategoryAlias> _entries;

  List<CategoryCandidate> get categories => _categories;

  /// All matches, best first.
  List<CategoryMatch> findAll(NormalizedText text, {CategoryKind? kind}) {
    final results = <CategoryMatch>[];
    final tokens = text.tokens;

    for (var start = 0; start < tokens.length; start++) {
      for (final entry in _entries) {
        if (kind != null && entry.kind != kind) continue;
        final length = entry.matchLengthAt(tokens, start);
        if (length == 0) continue;
        results.add(
          CategoryMatch(
            categoryId: entry.categoryId,
            categoryName: entry.categoryName,
            kind: entry.kind,
            matchedText: text.span(start, start + length),
            startToken: start,
            endToken: start + length,
            score: entry.specificity * 100 + length,
          ),
        );
      }
    }

    results.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.startToken.compareTo(b.startToken);
    });
    return results;
  }

  CategoryMatch? findBest(NormalizedText text, {CategoryKind? kind}) {
    final matches = findAll(text, kind: kind);
    return matches.isEmpty ? null : matches.first;
  }

  /// True when two different categories scored equally best — the UI should ask
  /// rather than guess.
  bool hasAmbiguousTopMatch(NormalizedText text, {CategoryKind? kind}) {
    final matches = findAll(text, kind: kind);
    if (matches.length < 2) return false;
    final top = matches[0];
    final second = matches[1];
    return top.score == second.score && top.categoryId != second.categoryId;
  }

  static List<_CategoryAlias> _build(List<CategoryCandidate> categories) {
    final result = <_CategoryAlias>[];
    for (final category in categories) {
      final aliases = <String>{category.name, ...category.keywords};
      final seen = <String>{};
      for (final alias in aliases) {
        final tokens = TextNormalizer.normalize(alias).tokens
            .where((t) => !_ignoredTokens.contains(t))
            .toList(growable: false);
        if (tokens.isEmpty) continue;
        final key = tokens.join(' ');
        if (!seen.add(key)) continue;
        result.add(
          _CategoryAlias(
            tokens: tokens,
            categoryId: category.id,
            categoryName: category.name,
            kind: category.kind,
            specificity: tokens.length,
          ),
        );
      }
    }
    return result;
  }

  /// Very generic words that would produce false positives on their own.
  static const Set<String> _ignoredTokens = <String>{
    'the',
    'a',
    'on',
    'for',
    'my',
    'করেছি',
    'খরচ',
  };
}

class _CategoryAlias {
  _CategoryAlias({
    required this.tokens,
    required this.categoryId,
    required this.categoryName,
    required this.kind,
    required this.specificity,
  });

  final List<String> tokens;
  final String categoryId;
  final String categoryName;
  final CategoryKind kind;
  final int specificity;

  int matchLengthAt(List<String> text, int start) {
    if (start + tokens.length > text.length) return 0;
    for (var index = 0; index < tokens.length; index++) {
      if (!WalletAliasMatcherTokens.match(text[start + index], tokens[index])) {
        return 0;
      }
    }
    return tokens.length;
  }
}

/// Token comparison shared with the wallet matcher, exposed so category and
/// wallet matching stay behaviourally identical.
class WalletAliasMatcherTokens {
  const WalletAliasMatcherTokens._();

  static const List<String> suffixes = <String>[
    'ের',
    'ে',
    'তে',
    'কে',
    'য়',
    'য়ে',
    'টা',
    'টি',
    'গুলো',
  ];

  static bool match(String actual, String expected) {
    if (actual == expected) return true;
    for (final suffix in suffixes) {
      if (actual.length > expected.length && actual.endsWith(suffix)) {
        if (actual.substring(0, actual.length - suffix.length) == expected) {
          return true;
        }
      }
    }
    return false;
  }
}
