import 'package:meta/meta.dart';

import '../../../domain/enums.dart';
import '../../../domain/models/transaction_draft.dart';
import 'bengali_number_parser.dart';
import 'category_matcher.dart';
import 'wallet_alias_matcher.dart';

/// Fields the voice flow can fail to resolve. The confirmation screen renders a
/// picker for each one that is still open.
enum VoiceField {
  amount,
  type,
  wallet,
  destinationWallet,
  category,
  date,
  description;

  String get label {
    switch (this) {
      case VoiceField.amount:
        return 'Amount';
      case VoiceField.type:
        return 'Transaction type';
      case VoiceField.wallet:
        return 'Wallet';
      case VoiceField.destinationWallet:
        return 'Destination wallet';
      case VoiceField.category:
        return 'Category';
      case VoiceField.date:
        return 'Date';
      case VoiceField.description:
        return 'Description';
    }
  }
}

/// A single explainable signal that fed the classification.
@immutable
class ParseEvidence {
  const ParseEvidence({
    required this.signal,
    required this.matchedText,
    required this.weight,
  });

  final String signal;
  final String matchedText;
  final double weight;
}

/// Result of interpreting raw recognised text into a transaction draft.
///
/// Nothing here touches the database: wallets and categories are referenced by
/// id, and [unresolved] tells the UI exactly what still needs the user.
@immutable
class ParsedTransaction {
  const ParsedTransaction({
    required this.rawText,
    required this.normalizedText,
    this.type,
    this.amountPoisha,
    this.currency,
    this.walletId,
    this.walletName,
    this.walletAlternatives = const <String>[],
    this.walletMatchedByTypeAlias = false,
    this.toWalletId,
    this.toWalletName,
    this.toWalletAlternatives = const <String>[],
    this.categoryId,
    this.categoryName,
    this.occurredAt,
    this.dateWasExplicit = false,
    this.description,
    this.note,
    this.confidence = 0,
    this.unresolved = const <VoiceField>{},
    this.warnings = const <String>[],
    this.evidence = const <ParseEvidence>[],
    this.amountSourceText,
  });

  final String rawText;
  final String normalizedText;

  final TransactionType? type;
  final int? amountPoisha;
  final String? currency;

  /// Source wallet for expense/transfer, destination wallet for income.
  final String? walletId;
  final String? walletName;

  /// Populated when the spoken wallet word matched more than one wallet.
  final List<String> walletAlternatives;
  final bool walletMatchedByTypeAlias;

  final String? toWalletId;
  final String? toWalletName;
  final List<String> toWalletAlternatives;

  final String? categoryId;
  final String? categoryName;

  final DateTime? occurredAt;
  final bool dateWasExplicit;

  final String? description;
  final String? note;

  /// 0..1. Never presented as a recognition accuracy figure — it is only an
  /// internal confidence used to decide how much the UI should ask about.
  final double confidence;

  final Set<VoiceField> unresolved;

  /// Human readable, non-fatal observations shown on the confirmation screen.
  final List<String> warnings;

  final List<ParseEvidence> evidence;

  /// The exact words the amount was read from, e.g. "দেড় হাজার".
  final String? amountSourceText;

  bool get isComplete =>
      unresolved.isEmpty && type != null && amountPoisha != null;

  ParsedTransaction copyWith({
    TransactionType? type,
    int? amountPoisha,
    String? walletId,
    String? walletName,
    List<String>? walletAlternatives,
    bool? walletMatchedByTypeAlias,
    String? toWalletId,
    String? toWalletName,
    List<String>? toWalletAlternatives,
    String? categoryId,
    String? categoryName,
    DateTime? occurredAt,
    bool? dateWasExplicit,
    String? description,
    String? note,
    double? confidence,
    Set<VoiceField>? unresolved,
    List<String>? warnings,
    List<ParseEvidence>? evidence,
    String? amountSourceText,
  }) {
    return ParsedTransaction(
      rawText: rawText,
      normalizedText: normalizedText,
      type: type ?? this.type,
      amountPoisha: amountPoisha ?? this.amountPoisha,
      currency: currency,
      walletId: walletId ?? this.walletId,
      walletName: walletName ?? this.walletName,
      walletAlternatives: walletAlternatives ?? this.walletAlternatives,
      walletMatchedByTypeAlias:
          walletMatchedByTypeAlias ?? this.walletMatchedByTypeAlias,
      toWalletId: toWalletId ?? this.toWalletId,
      toWalletName: toWalletName ?? this.toWalletName,
      toWalletAlternatives: toWalletAlternatives ?? this.toWalletAlternatives,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      occurredAt: occurredAt ?? this.occurredAt,
      dateWasExplicit: dateWasExplicit ?? this.dateWasExplicit,
      description: description ?? this.description,
      note: note ?? this.note,
      confidence: confidence ?? this.confidence,
      unresolved: unresolved ?? this.unresolved,
      warnings: warnings ?? this.warnings,
      evidence: evidence ?? this.evidence,
      amountSourceText: amountSourceText ?? this.amountSourceText,
    );
  }

  /// Builds a persistable draft. Returns null — never a half-filled draft —
  /// while required fields are still unresolved.
  TransactionDraft? toDraft({
    required String? fallbackWalletId,
    String? fallbackCategoryId,
    TransactionSource source = TransactionSource.voice,
  }) {
    final resolvedType = type;
    final resolvedAmount = amountPoisha;
    final resolvedWallet = walletId ?? fallbackWalletId;
    if (resolvedType == null ||
        resolvedAmount == null ||
        resolvedWallet == null) {
      return null;
    }
    if (resolvedType.isTransfer) {
      final destination = toWalletId;
      if (destination == null || destination == resolvedWallet) return null;
      return TransactionDraft(
        type: TransactionType.transfer,
        amountPoisha: resolvedAmount,
        walletId: resolvedWallet,
        toWalletId: destination,
        occurredAt: occurredAt ?? DateTime.now(),
        description: description,
        note: note,
        source: source,
      );
    }
    return TransactionDraft(
      type: resolvedType,
      amountPoisha: resolvedAmount,
      walletId: resolvedWallet,
      categoryId: categoryId ?? fallbackCategoryId,
      occurredAt: occurredAt ?? DateTime.now(),
      description: description,
      merchant: description,
      note: note,
      source: source,
    );
  }
}

/// Inputs the parser needs. Kept as a plain value so tests are trivial.
@immutable
class ParserContext {
  const ParserContext({
    required this.wallets,
    required this.categories,
    required this.now,
    this.defaultIncomeWalletId,
    this.defaultExpenseWalletId,
  });

  final List<WalletCandidate> wallets;
  final List<CategoryCandidate> categories;
  final DateTime now;
  final String? defaultIncomeWalletId;
  final String? defaultExpenseWalletId;
}

/// The number parser is re-exported so callers only import one file.
typedef ParseAmounts = BengaliNumberParser;

/// Convenience holder for amounts, kept for readability at call sites.
class NumberParser {
  const NumberParser._();

  static AmountMatch? findAmount(List<String> tokens) =>
      BengaliNumberParser.findAmount(tokens);
}
