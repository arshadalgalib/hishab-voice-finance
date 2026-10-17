import 'package:meta/meta.dart';

import '../enums.dart';
import 'date_range.dart';

/// Sort orders supported by the transaction history screen.
enum TransactionSort {
  dateDesc,
  dateAsc,
  amountDesc,
  amountAsc;

  String get sql {
    switch (this) {
      case TransactionSort.dateDesc:
        return 't.occurred_at DESC, t.created_at DESC';
      case TransactionSort.dateAsc:
        return 't.occurred_at ASC, t.created_at ASC';
      case TransactionSort.amountDesc:
        return 't.amount_poisha DESC, t.occurred_at DESC';
      case TransactionSort.amountAsc:
        return 't.amount_poisha ASC, t.occurred_at DESC';
    }
  }

  String get label {
    switch (this) {
      case TransactionSort.dateDesc:
        return 'Newest first';
      case TransactionSort.dateAsc:
        return 'Oldest first';
      case TransactionSort.amountDesc:
        return 'Highest amount';
      case TransactionSort.amountAsc:
        return 'Lowest amount';
    }
  }
}

/// Declarative filter for the transaction list. Kept free of SQL so it can be
/// persisted, serialised into a shareable report file, or snapshot in a test.
@immutable
class TransactionFilter {
  const TransactionFilter({
    this.range,
    this.types = const <TransactionType>{},
    this.walletIds = const <String>{},
    this.categoryIds = const <String>{},
    this.unresolvedCategoryOnly = false,
    this.searchText,
    this.tags = const <String>{},
    this.minAmountPoisha,
    this.maxAmountPoisha,
    this.sort = TransactionSort.dateDesc,
  });

  /// Inclusive date window. `null` means "all time".
  final DateRange? range;

  /// Empty means "any type". Transfers can be included or excluded explicitly,
  /// which is how reports keep internal movement out of income/expense.
  final Set<TransactionType> types;

  /// Matches either the source or the destination wallet of a transfer.
  final Set<String> walletIds;
  final Set<String> categoryIds;

  /// When true, only transactions with no category are returned (useful for a
  /// "needs review" queue).
  final bool unresolvedCategoryOnly;

  final String? searchText;
  final Set<String> tags;
  final int? minAmountPoisha;
  final int? maxAmountPoisha;
  final TransactionSort sort;

  bool get isEmpty =>
      range == null &&
      types.isEmpty &&
      walletIds.isEmpty &&
      categoryIds.isEmpty &&
      !unresolvedCategoryOnly &&
      (searchText == null || searchText!.trim().isEmpty) &&
      tags.isEmpty &&
      minAmountPoisha == null &&
      maxAmountPoisha == null;

  int get activeFilterCount {
    var count = 0;
    if (range != null) count++;
    if (types.isNotEmpty) count++;
    if (walletIds.isNotEmpty) count++;
    if (categoryIds.isNotEmpty) count++;
    if (unresolvedCategoryOnly) count++;
    if (searchText != null && searchText!.trim().isNotEmpty) count++;
    if (tags.isNotEmpty) count++;
    if (minAmountPoisha != null || maxAmountPoisha != null) count++;
    return count;
  }

  TransactionFilter copyWith({
    DateRange? range,
    bool clearRange = false,
    Set<TransactionType>? types,
    Set<String>? walletIds,
    Set<String>? categoryIds,
    bool? unresolvedCategoryOnly,
    String? searchText,
    bool clearSearch = false,
    Set<String>? tags,
    int? minAmountPoisha,
    int? maxAmountPoisha,
    bool clearAmountBounds = false,
    TransactionSort? sort,
  }) {
    return TransactionFilter(
      range: clearRange ? null : (range ?? this.range),
      types: types ?? this.types,
      walletIds: walletIds ?? this.walletIds,
      categoryIds: categoryIds ?? this.categoryIds,
      unresolvedCategoryOnly:
          unresolvedCategoryOnly ?? this.unresolvedCategoryOnly,
      searchText: clearSearch ? null : (searchText ?? this.searchText),
      tags: tags ?? this.tags,
      minAmountPoisha: clearAmountBounds
          ? null
          : (minAmountPoisha ?? this.minAmountPoisha),
      maxAmountPoisha: clearAmountBounds
          ? null
          : (maxAmountPoisha ?? this.maxAmountPoisha),
      sort: sort ?? this.sort,
    );
  }
}
