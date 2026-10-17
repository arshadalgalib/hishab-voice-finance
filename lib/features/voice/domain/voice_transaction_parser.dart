import '../../../domain/enums.dart';
import '../../../domain/models/transaction_draft.dart';
import 'bengali_number_parser.dart';
import 'category_matcher.dart';
import 'relative_date_parser.dart';
import 'text_normalizer.dart';
import 'transaction_type_classifier.dart';
import 'voice_parse_result.dart';
import 'wallet_alias_matcher.dart';

/// Converts recognised Bengali / Banglish / English text into a structured
/// transaction draft.
///
/// The parser is deliberately rule based: it is fast, works entirely offline,
/// and every decision is explainable through [ParsedTransaction.evidence]. It
/// never reaches into a database — callers pass [ParserContext] with the wallets
/// and categories that exist right now — so it can be tested exhaustively and
/// reused by a different UI.
///
/// It is *not* a speech recogniser: recognition accuracy depends on the device
/// or cloud engine, while interpretation accuracy is what this class owns.
class VoiceTransactionParser {
  VoiceTransactionParser(this.context)
    : _walletMatcher = WalletAliasMatcher(context.wallets),
      _categoryMatcher = CategoryMatcher(context.categories),
      _dateParser = RelativeDateParser(now: context.now);

  final ParserContext context;
  final WalletAliasMatcher _walletMatcher;
  final CategoryMatcher _categoryMatcher;
  final RelativeDateParser _dateParser;

  static const List<String> _fromMarkers = <String>[
    'থেকে',
    'theke',
    'teke',
    'from',
    'হতে',
  ];

  /// Words that carry no descriptive value once they have done their job.
  static const Set<String> _noiseTokens = <String>{
    'আমি',
    'আমার',
    'আমাকে',
    'আমরা',
    'i',
    'my',
    'me',
    'the',
    'a',
    'an',
    'on',
    'in',
    'at',
    'for',
    'to',
    'and',
    'এবং',
    'আর',
    'টি',
    'একটা',
    'এর',
    'কে',
    'তে',
    'থেকে',
    'theke',
    'from',
    'করেছি',
    'করলাম',
    'করছি',
    'করা',
    'হলো',
    'হয়েছে',
    'did',
    'done',
    'made',
    'spent',
    'spend',
    'paid',
    'pay',
    'got',
    'received',
    'buy',
    'bought',
    'পেলাম',
    'পেয়েছি',
    'খরচ',
    'টাকা',
    'taka',
    'tk',
    '৳',
    'bdt',
    'টা',
  };

  ParsedTransaction parse(String rawText) {
    final text = TextNormalizer.normalize(rawText);
    final tokens = text.tokens.toList(growable: false);
    final warnings = <String>[];
    final unresolved = <VoiceField>{};

    // ── amount ─────────────────────────────────────────────────────────────
    final amountMatch = BengaliNumberParser.findAmount(tokens);
    final amountPoisha = amountMatch == null
        ? null
        : (amountMatch.taka * 100).round();
    if (amountPoisha == null || amountPoisha <= 0) {
      unresolved.add(VoiceField.amount);
    } else if (!amountMatch!.adjacentToCurrencyWord) {
      warnings.add(
        'The amount was read as “${amountMatch.sourceText}” without the word '
        'টাকা — please double-check it.',
      );
    }

    // ── wallets ────────────────────────────────────────────────────────────
    final walletMatches = _walletMatcher.findAll(text);

    // ── date ───────────────────────────────────────────────────────────────
    final dateResult = _dateParser.parse(text);
    if (dateResult.note != null) warnings.add(dateResult.note!);
    if (dateResult.hadNegatedCandidate &&
        dateResult.date != null &&
        dateResult.explicit) {
      warnings.add('Assuming ${_describe(dateResult.date!, context.now)}.');
    }

    // ── category (untyped pass, used as direction evidence) ────────────────
    final untypedCategory = _categoryMatcher.findBest(text);

    // ── type ───────────────────────────────────────────────────────────────
    final classification = TransactionTypeClassifier.classify(
      tokens: tokens,
      walletMatches: walletMatches,
      categoryMatch: untypedCategory,
    );
    final type = classification.type;
    if (type == null) unresolved.add(VoiceField.type);

    // Re-run the category search restricted to the resolved kind.
    CategoryMatch? category;
    if (type == TransactionType.income) {
      category = _categoryMatcher.findBest(text, kind: CategoryKind.income);
    } else if (type == TransactionType.expense) {
      category = _categoryMatcher.findBest(text, kind: CategoryKind.expense);
    }
    if (category == null) {
      unresolved.add(VoiceField.category);
    } else if (_categoryMatcher.hasAmbiguousTopMatch(
      text,
      kind: type == TransactionType.income
          ? CategoryKind.income
          : CategoryKind.expense,
    )) {
      warnings.add(
        '“${category.matchedText}” could map to more than one category — '
        'please confirm.',
      );
    }

    // ── wallet roles ───────────────────────────────────────────────────────
    final fromIndex = tokens.indexWhere(_fromMarkers.contains);
    String? walletId;
    String? walletName;
    String? toWalletId;
    String? toWalletName;
    var walletAlternatives = <String>[];
    var toWalletAlternatives = <String>[];
    var walletByTypeAlias = false;

    if (type == TransactionType.transfer) {
      if (walletMatches.length >= 2) {
        final roleAssignment = _assignTransferWallets(
          walletMatches,
          fromIndex: fromIndex,
        );
        _applyWallet(
          roleAssignment.source,
          isDestination: false,
          setPrimary: (id, name, alternatives, byAlias) {
            walletId = id;
            walletName = name;
            walletAlternatives = alternatives;
            walletByTypeAlias = byAlias;
          },
        );
        _applyWallet(
          roleAssignment.destination,
          isDestination: true,
          setPrimary: (id, name, alternatives, byAlias) {
            toWalletId = id;
            toWalletName = name;
            toWalletAlternatives = alternatives;
          },
        );
      } else if (walletMatches.length == 1) {
        final only = walletMatches.single;
        // "বিকাশ থেকে ২০০০ টাকা পাঠিয়েছি" names only the source.
        if (fromIndex >= 0 && only.endToken <= fromIndex + 1) {
          _applyWallet(
            only,
            isDestination: false,
            setPrimary: (id, name, alternatives, byAlias) {
              walletId = id;
              walletName = name;
              walletAlternatives = alternatives;
              walletByTypeAlias = byAlias;
            },
          );
        } else {
          _applyWallet(
            only,
            isDestination: true,
            setPrimary: (id, name, alternatives, byAlias) {
              toWalletId = id;
              toWalletName = name;
              toWalletAlternatives = alternatives;
            },
          );
        }
        warnings.add('Only one wallet was named for a transfer.');
      } else {
        warnings.add('No wallet was named for a transfer.');
      }
      if (walletId == null) unresolved.add(VoiceField.wallet);
      if (toWalletId == null) unresolved.add(VoiceField.destinationWallet);
    } else if (walletMatches.isNotEmpty) {
      final chosen = _pickPrimaryWallet(
        type: type,
        matches: walletMatches,
        fromIndex: fromIndex,
      );
      _applyWallet(
        chosen,
        isDestination: type == TransactionType.income,
        setPrimary: (id, name, alternatives, byAlias) {
          walletId = id;
          walletName = name;
          walletAlternatives = alternatives;
          walletByTypeAlias = byAlias;
        },
      );
      if (walletId == null) {
        // The wallet was mentioned but the word maps to more than one wallet
        // (for example নগদ = cash or Nagad). Mark it unresolved so the
        // confirmation screen asks instead of silently dropping it.
        unresolved.add(VoiceField.wallet);
        warnings.add(
          '“${chosen.matchedText}” could refer to more than one wallet — '
          'please choose.',
        );
      }
      if (walletMatches.length > 1) {
        warnings.add(
          'More than one wallet was mentioned; '
          '“${chosen.matchedText}” was used.',
        );
      }
    } else {
      unresolved.add(VoiceField.wallet);
    }

    // ── amount sanity ──────────────────────────────────────────────────────
    if (amountPoisha != null && amountPoisha > 100000000000) {
      unresolved.add(VoiceField.amount);
      warnings.add('That amount looks unrealistic — please check it.');
    }

    // ── description ────────────────────────────────────────────────────────
    final description = _buildDescription(
      text: text,
      consumedRanges: <List<int>>[
        if (amountMatch != null)
          <int>[amountMatch.startToken, amountMatch.endToken],
        for (final match in walletMatches)
          <int>[match.startToken, match.endToken],
        if (category != null) <int>[category.startToken, category.endToken],
        if (dateResult.startToken != null && dateResult.endToken != null)
          <int>[dateResult.startToken!, dateResult.endToken!],
      ],
    );

    // ── confidence ─────────────────────────────────────────────────────────
    var confidence = 0.3;
    if (amountPoisha != null && amountPoisha > 0) {
      confidence += 0.25;
      if (amountMatch?.adjacentToCurrencyWord ?? false) confidence += 0.05;
    }
    if (type != null) {
      confidence += 0.2;
      confidence += (classification.margin / 20).clamp(0, 0.1);
    }
    if (walletId != null) confidence += 0.1;
    if (type == TransactionType.transfer && toWalletId != null) {
      confidence += 0.05;
    }
    if (category != null) confidence += 0.05;
    if (dateResult.explicit) confidence += 0.05;
    if (classification.ambiguous) confidence -= 0.15;
    if (unresolved.isNotEmpty) confidence -= 0.1 * unresolved.length;
    confidence = confidence.clamp(0.0, 0.99);

    return ParsedTransaction(
      rawText: rawText,
      normalizedText: text.normalized,
      type: type,
      amountPoisha: (amountPoisha != null && amountPoisha > 0)
          ? amountPoisha
          : null,
      currency: amountMatch != null ? 'BDT' : null,
      walletId: walletId,
      walletName: walletName,
      walletAlternatives: walletAlternatives,
      walletMatchedByTypeAlias: walletByTypeAlias,
      toWalletId: toWalletId,
      toWalletName: toWalletName,
      toWalletAlternatives: toWalletAlternatives,
      categoryId: category?.categoryId,
      categoryName: category?.categoryName,
      occurredAt: dateResult.date,
      dateWasExplicit: dateResult.explicit,
      description: description,
      confidence: confidence,
      unresolved: unresolved,
      warnings: warnings,
      evidence: classification.evidence,
      amountSourceText: amountMatch?.sourceText,
    );
  }

  /// Picks which of several wallet mentions is *the* wallet for a
  /// non-transfer sentence.
  WalletMatch _pickPrimaryWallet({
    required TransactionType? type,
    required List<WalletMatch> matches,
    required int fromIndex,
  }) {
    if (type == TransactionType.income && fromIndex >= 0) {
      // Money arriving: prefer a wallet mentioned *after* "থেকে".
      final after = matches.where((m) => m.startToken > fromIndex).toList();
      if (after.isNotEmpty) return after.first;
    }
    if (type == TransactionType.expense && fromIndex >= 0) {
      final before = matches.where((m) => m.endToken <= fromIndex + 1).toList();
      if (before.isNotEmpty) return before.last;
    }
    // Otherwise prefer the mention that resolves to exactly one wallet.
    for (final match in matches) {
      if (match.isResolved) return match;
    }
    return matches.first;
  }

  _TransferRoles _assignTransferWallets(
    List<WalletMatch> matches, {
    required int fromIndex,
  }) {
    if (fromIndex >= 0) {
      final before = matches.where((m) => m.endToken <= fromIndex + 1).toList();
      final after = matches.where((m) => m.startToken > fromIndex).toList();
      if (before.isNotEmpty && after.isNotEmpty) {
        return _TransferRoles(source: before.last, destination: after.first);
      }
    }
    // Fall back to textual order: the first wallet is the source.
    final sorted = [...matches]
      ..sort((a, b) => a.startToken.compareTo(b.startToken));
    return _TransferRoles(source: sorted.first, destination: sorted[1]);
  }

  void _applyWallet(
    WalletMatch match, {
    required bool isDestination,
    required void Function(
      String? id,
      String? name,
      List<String> alternatives,
      bool byTypeAlias,
    )
    setPrimary,
  }) {
    setPrimary(
      match.resolvedId,
      match.resolvedName,
      match.isAmbiguous ? match.candidateNames : const <String>[],
      match.matchedByTypeAlias,
    );
  }

  /// Joins every token that no other component claimed and that is not noise.
  String? _buildDescription({
    required NormalizedText text,
    required List<List<int>> consumedRanges,
  }) {
    final consumed = List<bool>.filled(text.tokens.length, false);
    for (final range in consumedRanges) {
      for (
        var index = range[0];
        index < range[1] && index < consumed.length;
        index++
      ) {
        consumed[index] = true;
      }
    }
    final remaining = <String>[];
    for (var index = 0; index < text.tokens.length; index++) {
      if (consumed[index]) continue;
      final token = text.tokens[index];
      if (_noiseTokens.contains(token)) continue;
      if (BengaliNumberParser.isNumberWord(token)) continue;
      if (TextNormalizer.isCurrencyWord(token)) continue;
      remaining.add(token);
    }
    final joined = remaining.join(' ').trim();
    if (joined.isEmpty) return null;
    return joined.length > 120 ? joined.substring(0, 120) : joined;
  }

  static String _describe(DateTime date, DateTime now) {
    final difference = date
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (difference == 0) return 'today';
    if (difference == -1) return 'yesterday';
    if (difference == -2) return 'the day before yesterday';
    if (difference == 1) return 'tomorrow';
    return '${date.day}/${date.month}/${date.year}';
  }

  /// Builds a draft from a parse result, applying the configured default wallet
  /// only for the role where that is appropriate.
  TransactionDraft? buildDraft(
    ParsedTransaction parsed, {
    TransactionSource source = TransactionSource.voice,
  }) {
    final fallback = switch (parsed.type) {
      TransactionType.income => context.defaultIncomeWalletId,
      TransactionType.expense ||
      TransactionType.transfer => context.defaultExpenseWalletId,
      null => null,
    };
    // A sentence with no date defaults to the app clock (`context.now`), not the
    // wall clock: every other draft in the app is stamped from the same clock,
    // and it keeps the flow reproducible on a device with the wrong clock.
    final dated = parsed.occurredAt == null
        ? parsed.copyWith(occurredAt: context.now)
        : parsed;
    return dated.toDraft(fallbackWalletId: fallback, source: source);
  }
}

class _TransferRoles {
  const _TransferRoles({required this.source, required this.destination});

  final WalletMatch source;
  final WalletMatch destination;
}
