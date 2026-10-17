import 'package:meta/meta.dart';

import '../enums.dart';

/// A wallet together with its derived balance figures.
@immutable
class WalletBalance {
  const WalletBalance({
    required this.walletId,
    required this.name,
    required this.type,
    required this.openingBalancePoisha,
    required this.balancePoisha,
    required this.inflowPoisha,
    required this.outflowPoisha,
    required this.isArchived,
    required this.isDefaultIncome,
    required this.isDefaultExpense,
    this.institution,
    this.colorValue,
    this.iconCodePoint,
    this.note,
  });

  final String walletId;
  final String name;
  final WalletType type;
  final String? institution;
  final int openingBalancePoisha;

  /// opening balance + inflow - outflow
  final int balancePoisha;

  /// income credited to this wallet + transfers in
  final int inflowPoisha;

  /// expenses paid from this wallet + transfers out
  final int outflowPoisha;

  final bool isArchived;
  final bool isDefaultIncome;
  final bool isDefaultExpense;
  final int? colorValue;
  final int? iconCodePoint;
  final String? note;
}

/// A transaction plus denormalised wallet/category labels for list rendering.
@immutable
class TransactionListItem {
  const TransactionListItem({
    required this.id,
    required this.type,
    required this.amountPoisha,
    required this.occurredAt,
    required this.walletId,
    required this.walletName,
    required this.source,
    this.toWalletId,
    this.toWalletName,
    this.categoryId,
    this.categoryName,
    this.description,
    this.merchant,
    this.counterparty,
    this.note,
    this.tags = const <String>[],
    this.transferGroupId,
    this.feePoisha = 0,
  });

  final String id;
  final TransactionType type;
  final int amountPoisha;
  final DateTime occurredAt;
  final String walletId;
  final String walletName;
  final String? toWalletId;
  final String? toWalletName;
  final String? categoryId;
  final String? categoryName;
  final String? description;
  final String? merchant;
  final String? counterparty;
  final String? note;
  final List<String> tags;
  final String? transferGroupId;
  final int feePoisha;
  final TransactionSource source;

  bool get isTransfer => type == TransactionType.transfer;
}

/// `(categoryId, categoryName, kind, totalPoisha, transactionCount)`.
@immutable
class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.categoryName,
    required this.kind,
    required this.totalPoisha,
    required this.transactionCount,
    this.colorValue,
    this.iconName,
  });

  /// `null` for uncategorised transactions.
  final String? categoryId;
  final String categoryName;
  final CategoryKind kind;
  final int totalPoisha;
  final int transactionCount;
  final int? colorValue;
  final String? iconName;
}

/// A single point on a trend chart.
@immutable
class TrendPoint {
  const TrendPoint({
    required this.bucketKey,
    required this.label,
    required this.incomePoisha,
    required this.expensePoisha,
  });

  /// `2026-03` for monthly buckets, `2026-03-11` for daily ones.
  final String bucketKey;
  final String label;
  final int incomePoisha;
  final int expensePoisha;

  int get netPoisha => incomePoisha - expensePoisha;
}

/// Income / expense / transfer totals for a period.
@immutable
class PeriodSummary {
  const PeriodSummary({
    required this.incomePoisha,
    required this.expensePoisha,
    required this.transferVolumePoisha,
    required this.incomeCount,
    required this.expenseCount,
    required this.transferCount,
  });

  static const PeriodSummary empty = PeriodSummary(
    incomePoisha: 0,
    expensePoisha: 0,
    transferVolumePoisha: 0,
    incomeCount: 0,
    expenseCount: 0,
    transferCount: 0,
  );

  final int incomePoisha;
  final int expensePoisha;

  /// Sum of transfers. Reported separately and **never** mixed into income or
  /// expense because internal movement is not a change in net worth.
  final int transferVolumePoisha;

  final int incomeCount;
  final int expenseCount;
  final int transferCount;

  /// Net cash flow from *external* activity (excludes transfers).
  int get netCashFlowPoisha => incomePoisha - expensePoisha;

  int get transactionCount => incomeCount + expenseCount + transferCount;
}
