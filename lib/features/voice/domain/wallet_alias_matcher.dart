import 'package:meta/meta.dart';

import '../../../domain/enums.dart';
import 'text_normalizer.dart';

/// Minimal view of a wallet that the voice parser needs.
///
/// Kept independent of Drift so the parser (and its tests) never touch a
/// database.
@immutable
class WalletCandidate {
  const WalletCandidate({
    required this.id,
    required this.name,
    required this.type,
    this.isArchived = false,
    this.isDefaultIncome = false,
    this.isDefaultExpense = false,
  });

  final String id;
  final String name;
  final WalletType type;
  final bool isArchived;
  final bool isDefaultIncome;
  final bool isDefaultExpense;
}

/// One wallet mention found in the sentence.
@immutable
class WalletMatch {
  const WalletMatch({
    required this.startToken,
    required this.endToken,
    required this.matchedText,
    required this.candidateIds,
    required this.candidateNames,
    required this.matchedByTypeAlias,
  });

  /// End-exclusive token index.
  final int startToken;
  final int endToken;
  final String matchedText;

  /// Wallet ids that this mention could refer to. More than one means the
  /// user must choose.
  final List<String> candidateIds;
  final List<String> candidateNames;

  /// True when the mention came from a wallet *type* word (বিকাশ, ব্যাংক, cash)
  /// rather than the wallet's own name.
  final bool matchedByTypeAlias;

  bool get isResolved => candidateIds.length == 1;
  bool get isAmbiguous => candidateIds.length > 1;

  String? get resolvedId => isResolved ? candidateIds.single : null;
  String? get resolvedName => isResolved ? candidateNames.single : null;
}

/// Matches spoken wallet references against the user's real wallets.
///
/// ## Why the ambiguity matters
/// `নগদ` is both the everyday Bengali word for *cash* and the brand name
/// *Nagad*. When a user has both wallets, the parser refuses to guess and the
/// confirmation screen asks which one is meant.
class WalletAliasMatcher {
  WalletAliasMatcher(List<WalletCandidate> wallets)
    : _entries = _buildEntries(wallets),
      _wallets = wallets;

  final List<WalletCandidate> _wallets;
  final List<_AliasEntry> _entries;

  List<WalletCandidate> get wallets => _wallets;

  /// Bengali case suffixes that recognisers/callers attach to place words:
  /// `বিকাশে`, `ব্যাংক থেকে`, `নগদের` …
  static const List<String> _suffixes = <String>[
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

  /// Words that are too generic to identify a wallet on their own.
  static const Set<String> _stopWords = <String>{
    'my',
    'the',
    'a',
    'আমার',
    'আমি',
    'wallet',
    'ওয়ালেট',
    'account',
    'একাউন্ট',
    'টাকা',
    'taka',
    'from',
    'to',
    'theke',
  };

  /// Type synonyms. Ordered listings here are the *only* source of type
  /// matches — nothing is invented for types the user does not own.
  static const Map<WalletType, List<String>> typeAliases =
      <WalletType, List<String>>{
        WalletType.cash: <String>[
          'cash',
          'ক্যাশ',
          'নগদ',
          'নগদে',
          'নগদে',
          'ক্যাশে',
          'হাতে',
          'হাতের',
          'হাত',
          'hate',
          'hater',
          'pocket',
          'পকেট',
          'জেব',
        ],
        WalletType.bank: <String>[
          'ব্যাংক',
          'ব্যাংকে',
          'ব্যাংকের',
          'bank',
          'banke',
          'account',
          'একাউন্ট',
          'একাউন্টে',
          'একাউন্টের',
          'সঞ্চয়ী',
          'কারেন্ট',
        ],
        WalletType.bkash: <String>[
          'বিকাশ',
          'বিকাশে',
          'বিকাশের',
          'bkash',
          'বিকাশে',
          'বি-ক্যাশ',
        ],
        WalletType.nagad: <String>['নগদ', 'নগদে', 'নগদের', 'nagad', 'নগদ'],
        WalletType.rocket: <String>['রকেট', 'রকেটে', 'রকেটের', 'rocket'],
        WalletType.mfs: <String>[
          'মোবাইল ব্যাংকিং',
          'এমএফএস',
          'mfs',
          'মোবাইল ওয়ালেট',
        ],
        WalletType.savings: <String>[
          'সঞ্চয়',
          'সেভিংস',
          'savings',
          'ডিপিএস',
          'dps',
        ],
      };

  List<WalletMatch> findAll(NormalizedText text) {
    final matches = <WalletMatch>[];
    final tokens = text.tokens;

    for (var start = 0; start < tokens.length; start++) {
      _AliasEntry? best;
      var bestLength = 0;

      for (final entry in _entries) {
        final length = entry.matchLengthAt(tokens, start);
        if (length > bestLength) {
          bestLength = length;
          best = entry;
        }
      }

      if (best != null && bestLength > 0) {
        matches.add(
          WalletMatch(
            startToken: start,
            endToken: start + bestLength,
            matchedText: text.span(start, start + bestLength),
            candidateIds: best.walletIds,
            candidateNames: best.walletNames,
            matchedByTypeAlias: best.fromTypeAlias,
          ),
        );
        start += bestLength - 1;
      }
    }

    return matches;
  }

  /// Convenience: the first mention resolved to a single wallet, or null.
  WalletMatch? firstResolved(NormalizedText text) {
    for (final match in findAll(text)) {
      if (match.isResolved) return match;
    }
    return null;
  }

  static List<_AliasEntry> _buildEntries(List<WalletCandidate> wallets) {
    final byPhrase = <String, _AliasBuilder>{};

    void add(
      List<String> aliasTokens,
      WalletCandidate wallet, {
      required bool fromTypeAlias,
    }) {
      final cleaned = aliasTokens
          .map(TextNormalizer.canonical)
          .where((t) => t.isNotEmpty && !_stopWords.contains(t))
          .toList();
      if (cleaned.isEmpty) return;
      final key = '${cleaned.join(' ')}|$fromTypeAlias';
      (byPhrase[key] ??= _AliasBuilder(cleaned, fromTypeAlias)).add(wallet);
    }

    for (final wallet in wallets) {
      final nameTokens = TextNormalizer.normalize(wallet.name).tokens;
      if (nameTokens.isNotEmpty) {
        add(nameTokens, wallet, fromTypeAlias: false);
        // Individual distinctive words from the name, e.g. "City Bank".
        for (final token in nameTokens) {
          if (token.length >= 3 && !_stopWords.contains(token)) {
            add(<String>[token], wallet, fromTypeAlias: false);
          }
        }
      }
      for (final alias in typeAliases[wallet.type] ?? const <String>[]) {
        add(<String>[alias], wallet, fromTypeAlias: true);
      }
    }

    return byPhrase.values.map((builder) => builder.build()).toList();
  }
}

class _AliasBuilder {
  _AliasBuilder(this.tokens, this.fromTypeAlias);

  final List<String> tokens;
  final bool fromTypeAlias;
  final List<WalletCandidate> wallets = <WalletCandidate>[];

  void add(WalletCandidate wallet) {
    if (wallets.any((w) => w.id == wallet.id)) return;
    wallets.add(wallet);
  }

  _AliasEntry build() => _AliasEntry(
    tokens: tokens,
    fromTypeAlias: fromTypeAlias,
    walletIds: wallets.map((w) => w.id).toList(growable: false),
    walletNames: wallets.map((w) => w.name).toList(growable: false),
  );
}

class _AliasEntry {
  _AliasEntry({
    required this.tokens,
    required this.fromTypeAlias,
    required this.walletIds,
    required this.walletNames,
  });

  final List<String> tokens;
  final bool fromTypeAlias;
  final List<String> walletIds;
  final List<String> walletNames;

  /// Returns the number of tokens consumed at [start], or 0 for no match.
  int matchLengthAt(List<String> text, int start) {
    if (start + tokens.length > text.length) return 0;
    for (var index = 0; index < tokens.length; index++) {
      if (!_tokenMatches(text[start + index], tokens[index])) return 0;
    }
    return tokens.length;
  }

  static bool _tokenMatches(String actual, String expected) {
    if (actual == expected) return true;
    // Tolerate Bengali locative / possessive suffixes: বিকাশে, ব্যাংকের ...
    for (final suffix in WalletAliasMatcher._suffixes) {
      if (actual.length > expected.length && actual.endsWith(suffix)) {
        final stem = actual.substring(0, actual.length - suffix.length);
        if (stem == expected) return true;
      }
      // Banglish suffixes: "bkash e"
    }
    return false;
  }
}
