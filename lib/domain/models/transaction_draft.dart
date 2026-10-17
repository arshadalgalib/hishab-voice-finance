import 'package:meta/meta.dart';

import '../enums.dart';

/// A validated, ready-to-persist transaction.
///
/// Both the manual forms and the voice confirmation screen build one of these
/// and hand it to `TransactionService`, which is what guarantees that voice and
/// manual entry obey exactly the same financial rules.
@immutable
class TransactionDraft {
  const TransactionDraft({
    required this.type,
    required this.amountPoisha,
    required this.walletId,
    required this.occurredAt,
    this.toWalletId,
    this.categoryId,
    this.description,
    this.merchant,
    this.counterparty,
    this.note,
    this.tags = const <String>[],
    this.feePoisha = 0,
    this.source = TransactionSource.manual,
    this.transferGroupId,
    this.recurringRuleId,
  });

  final TransactionType type;
  final int amountPoisha;

  /// Income destination wallet, or the source wallet for expense / transfer.
  final String walletId;

  /// Required for transfers, must be null otherwise.
  final String? toWalletId;

  final String? categoryId;
  final DateTime occurredAt;
  final String? description;
  final String? merchant;
  final String? counterparty;
  final String? note;
  final List<String> tags;

  /// Transfer fee in poisha; recorded as a linked expense row when > 0.
  final int feePoisha;

  final TransactionSource source;
  final String? transferGroupId;
  final String? recurringRuleId;

  factory TransactionDraft.income({
    required int amountPoisha,
    required String walletId,
    DateTime? occurredAt,
    String? categoryId,
    String? description,
    String? payer,
    String? note,
    List<String> tags = const <String>[],
    TransactionSource source = TransactionSource.manual,
  }) {
    return TransactionDraft(
      type: TransactionType.income,
      amountPoisha: amountPoisha,
      walletId: walletId,
      occurredAt: occurredAt ?? DateTime.now(),
      categoryId: categoryId,
      description: description,
      counterparty: payer,
      note: note,
      tags: tags,
      source: source,
    );
  }

  factory TransactionDraft.expense({
    required int amountPoisha,
    required String walletId,
    DateTime? occurredAt,
    String? categoryId,
    String? description,
    String? merchant,
    String? note,
    List<String> tags = const <String>[],
    TransactionSource source = TransactionSource.manual,
  }) {
    return TransactionDraft(
      type: TransactionType.expense,
      amountPoisha: amountPoisha,
      walletId: walletId,
      occurredAt: occurredAt ?? DateTime.now(),
      categoryId: categoryId,
      description: description,
      merchant: merchant,
      note: note,
      tags: tags,
      source: source,
    );
  }

  factory TransactionDraft.transfer({
    required int amountPoisha,
    required String fromWalletId,
    required String toWalletId,
    DateTime? occurredAt,
    String? description,
    String? note,
    int feePoisha = 0,
    TransactionSource source = TransactionSource.manual,
  }) {
    return TransactionDraft(
      type: TransactionType.transfer,
      amountPoisha: amountPoisha,
      walletId: fromWalletId,
      toWalletId: toWalletId,
      occurredAt: occurredAt ?? DateTime.now(),
      description: description,
      note: note,
      feePoisha: feePoisha,
      source: source,
    );
  }

  TransactionDraft copyWith({
    TransactionType? type,
    int? amountPoisha,
    String? walletId,
    String? toWalletId,
    bool clearToWallet = false,
    String? categoryId,
    bool clearCategory = false,
    DateTime? occurredAt,
    String? description,
    bool clearDescription = false,
    String? merchant,
    String? counterparty,
    String? note,
    List<String>? tags,
    int? feePoisha,
    TransactionSource? source,
    String? transferGroupId,
    String? recurringRuleId,
  }) {
    return TransactionDraft(
      type: type ?? this.type,
      amountPoisha: amountPoisha ?? this.amountPoisha,
      walletId: walletId ?? this.walletId,
      toWalletId: clearToWallet ? null : (toWalletId ?? this.toWalletId),
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      occurredAt: occurredAt ?? this.occurredAt,
      description: clearDescription ? null : (description ?? this.description),
      merchant: merchant ?? this.merchant,
      counterparty: counterparty ?? this.counterparty,
      note: note ?? this.note,
      tags: tags ?? this.tags,
      feePoisha: feePoisha ?? this.feePoisha,
      source: source ?? this.source,
      transferGroupId: transferGroupId ?? this.transferGroupId,
      recurringRuleId: recurringRuleId ?? this.recurringRuleId,
    );
  }

  /// A short, human summary used by the undo snackbar and the confirmation
  /// screen header.
  String summary() {
    final label = switch (type) {
      TransactionType.income => 'Income',
      TransactionType.expense => 'Expense',
      TransactionType.transfer => 'Transfer',
    };
    final extras = <String>[
      if (description != null && description!.trim().isNotEmpty)
        description!.trim(),
      if (note != null && note!.trim().isNotEmpty) note!.trim(),
    ];
    return extras.isEmpty ? label : '$label · ${extras.first}';
  }
}
