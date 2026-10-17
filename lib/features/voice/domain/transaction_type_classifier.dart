import 'package:meta/meta.dart';

import '../../../domain/enums.dart';
import 'category_matcher.dart';
import 'voice_parse_result.dart';
import 'wallet_alias_matcher.dart';

/// Weighted marker used by the classifier so every decision is explainable.
class _Marker {
  const _Marker(this.words, this.label, this.weight);

  final List<String> words;
  final String label;
  final double weight;
}

/// Outcome of classifying the sentence.
@immutable
class TypeClassification {
  const TypeClassification({
    required this.type,
    required this.margin,
    required this.evidence,
    required this.ambiguous,
  });

  /// `null` means "could not tell" — the UI must ask.
  final TransactionType? type;

  /// How far ahead the winning type was. A small margin means the sentence was
  /// genuinely mixed and should be clarified.
  final double margin;

  final List<ParseEvidence> evidence;
  final bool ambiguous;
}

/// Decides whether a sentence describes income, expense, transfer or nothing
/// conclusive.
///
/// The rule the brief insists on is that the mere presence of "টাকা" must never
/// be treated as evidence — only *directional* verbs, nouns and structure count.
class TransactionTypeClassifier {
  const TransactionTypeClassifier._();

  /// Verbs that mean "money moved between two of my wallets".
  static const List<_Marker> _transferMarkers = <_Marker>[
    _Marker(
      <String>[
        'পাঠালাম',
        'পাঠিয়েছি',
        'পাঠাইছি',
        'পাঠাইয়াছি',
        'পাঠানো',
        'পাঠাল',
        'পাঠান',
        'pathiyechi',
        'pathalam',
        'pathaichi',
        'pathano',
        'transfer',
        'transferred',
        'ট্রান্সফার',
        'স্থানান্তর',
        'স্থানান্তরিত',
        'সরানো',
        'সরিয়েছি',
        'moved',
        'sent',
        'send',
        'পাঠিয়ে',
      ],
      'transfer verb',
      3,
    ),
  ];

  /// Verbs that mean money arrived.
  static const List<_Marker> _incomeMarkers = <_Marker>[
    _Marker(
      <String>[
        'পেলাম',
        'পেয়েছি',
        'পাইলাম',
        'পাইছি',
        'পাইসি',
        'পেয়েছি',
        'পাবো',
        'peyechi',
        'pelam',
        'pailam',
        'paichi',
        'paisi',
        'received',
        'receive',
        'got',
        'get',
        'earn',
        'earned',
        'credited',
        'credit',
        'জমা',
        'ওঠেছে',
        'ঢুকেছে',
        'বাড়লো',
        'বেড়েছে',
        'এসেছে',
        'found',
      ],
      'income verb',
      3,
    ),
    _Marker(
      <String>[
        'বেতন',
        'স্যালারি',
        'মাইনে',
        'বোনাস',
        'salary',
        'wage',
        'bonus',
        'ইনকাম',
        'আয়',
        'income',
        'ফ্রিল্যান্স',
        'freelance',
        'উপহার',
        'gift',
        'লভ্যাংশ',
        'ডিভিডেন্ড',
        'dividend',
        'সুদ',
        'interest',
        'রিফান্ড',
        'refund',
        'ক্যাশব্যাক',
        'cashback',
        'সম্মানী',
        'honorarium',
        'stipend',
        'অনুদান',
        'grant',
        'পেনশন',
        'pension',
        'প্রফিট',
        'profit',
        'মুনাফা',
        'লাভ',
      ],
      'income noun',
      2,
    ),
  ];

  /// Verbs that mean money left.
  static const List<_Marker> _expenseMarkers = <_Marker>[
    _Marker(
      <String>[
        'খরচ',
        'খরচা',
        'খরচা',
        'কিনলাম',
        'কিনেছি',
        'কিনলাম',
        'কিনা',
        'কিনলো',
        'কিনে',
        'দিলাম',
        'দিয়েছি',
        'দিল',
        'দিয়া',
        'পরিশোধ',
        'শোধ',
        'খেয়েছি',
        'খেলাম',
        'খাইছি',
        'গেল',
        'গেছে',
        'গেলো',
        'লাগল',
        'লেগেছে',
        'কাটলো',
        'কাটা',
        'spent',
        'spend',
        'paid',
        'pay',
        'buy',
        'bought',
        'purchase',
        'purchased',
        'gave',
        'give',
        'কিনলাম',
        'নিলাম',
        'রিচার্জ',
        'রিচার্জ',
        'কাটলাম',
        'debit',
        'debited',
        'lost',
      ],
      'expense verb',
      3,
    ),
    _Marker(
      <String>[
        'বাজার',
        'bill',
        'বিল',
        'fare',
        'ভাড়া',
        'charge',
        'চার্জ',
        'fee',
        'ফি',
        'cost',
        'price',
        'দাম',
        'খরচ',
      ],
      'expense noun',
      2,
    ),
  ];

  /// Verbs so generic they must never decide the direction alone.
  static const List<_Marker> _neutralMarkers = <_Marker>[
    _Marker(
      <String>[
        'করেছি',
        'করলাম',
        'করছি',
        'করা',
        'হলো',
        'হয়েছে',
        'হইলো',
        'did',
        'done',
        'made',
      ],
      'neutral verb',
      0.5,
    ),
  ];

  static const List<String> _fromMarkers = <String>[
    'থেকে',
    'theke',
    'teke',
    'from',
    'হতে',
  ];

  static bool hasFromMarker(List<String> tokens) =>
      tokens.any(_fromMarkers.contains);

  static TypeClassification classify({
    required List<String> tokens,
    required List<WalletMatch> walletMatches,
    CategoryMatch? categoryMatch,
    Set<String> extraIncomeWords = const <String>{},
    Set<String> extraExpenseWords = const <String>{},
    Set<String> extraTransferWords = const <String>{},
  }) {
    var income = 0.0;
    var expense = 0.0;
    var transfer = 0.0;
    final evidence = <ParseEvidence>[];

    void apply(List<_Marker> markers, void Function(double) add) {
      for (final marker in markers) {
        for (final word in marker.words) {
          if (tokens.contains(word)) {
            add(marker.weight);
            evidence.add(
              ParseEvidence(
                signal: marker.label,
                matchedText: word,
                weight: marker.weight,
              ),
            );
            break;
          }
        }
      }
    }

    apply(_transferMarkers, (v) => transfer += v);
    apply(_incomeMarkers, (v) => income += v);
    apply(_expenseMarkers, (v) => expense += v);
    apply(_neutralMarkers, (v) {
      income += v * 0.5;
      expense += v * 0.5;
    });

    // Learned/user-supplied vocabulary from their own category names.
    for (final word in extraIncomeWords) {
      if (tokens.contains(word)) {
        income += 2;
        evidence.add(
          ParseEvidence(signal: 'income keyword', matchedText: word, weight: 2),
        );
      }
    }
    for (final word in extraExpenseWords) {
      if (tokens.contains(word)) {
        expense += 2;
        evidence.add(
          ParseEvidence(
            signal: 'expense keyword',
            matchedText: word,
            weight: 2,
          ),
        );
      }
    }
    for (final word in extraTransferWords) {
      if (tokens.contains(word)) {
        transfer += 2;
        evidence.add(
          ParseEvidence(
            signal: 'transfer keyword',
            matchedText: word,
            weight: 2,
          ),
        );
      }
    }

    // A matched category is direction evidence in its own right.
    if (categoryMatch != null) {
      final weight = categoryMatch.specificityWeight;
      if (categoryMatch.kind == CategoryKind.income) {
        income += weight;
        evidence.add(
          ParseEvidence(
            signal: 'income category',
            matchedText: categoryMatch.matchedText,
            weight: weight,
          ),
        );
      } else {
        expense += weight;
        evidence.add(
          ParseEvidence(
            signal: 'expense category',
            matchedText: categoryMatch.matchedText,
            weight: weight,
          ),
        );
      }
    }

    // Structural evidence: two distinct wallets plus a "from" marker is the
    // canonical Bengali transfer phrasing ("ব্যাংক থেকে বিকাশে …").
    final hasFrom = hasFromMarker(tokens);
    if (walletMatches.length >= 2 && hasFrom) {
      transfer += 3;
      evidence.add(
        const ParseEvidence(
          signal: 'two wallets with "from"',
          matchedText: 'থেকে',
          weight: 3,
        ),
      );
    }

    const threshold = 2.0;
    final scores = <TransactionType, double>{
      TransactionType.income: income,
      TransactionType.expense: expense,
      TransactionType.transfer: transfer,
    };
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.first;
    final secondBest = ranked[1].value;
    final margin = best.value - secondBest;

    if (best.value < threshold) {
      return TypeClassification(
        type: null,
        margin: margin,
        evidence: evidence,
        ambiguous: true,
      );
    }

    // Transfers additionally require an actual movement verb or structure,
    // which the threshold already enforces.
    if (margin < 1.0 && secondBest >= threshold) {
      // Genuinely mixed sentence — for example "বিকাশ থেকে বেতন পেয়েছি" with a
      // transfer verb present. Do not guess.
      return TypeClassification(
        type: null,
        margin: margin,
        evidence: evidence,
        ambiguous: true,
      );
    }

    return TypeClassification(
      type: best.key,
      margin: margin,
      evidence: evidence,
      ambiguous: false,
    );
  }
}
