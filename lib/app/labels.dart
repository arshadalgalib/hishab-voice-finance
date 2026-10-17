import 'package:flutter/material.dart';

import '../domain/enums.dart';

/// Human labels and glyphs for the shared enums.
///
/// Kept in one place so a wallet called "bKash" is drawn with the same icon and
/// described with the same words in the picker, the wallet list, the reports
/// and the settings screens.
class WalletIcons {
  const WalletIcons._();

  static IconData resolve(WalletType type) {
    switch (type) {
      case WalletType.cash:
        return Icons.payments_outlined;
      case WalletType.bank:
        return Icons.account_balance;
      case WalletType.bkash:
      case WalletType.nagad:
      case WalletType.rocket:
      case WalletType.mfs:
        return Icons.smartphone;
      case WalletType.savings:
        return Icons.savings_outlined;
      case WalletType.custom:
        return Icons.account_balance_wallet_outlined;
    }
  }
}

String walletTypeLabel(WalletType type) {
  switch (type) {
    case WalletType.cash:
      return 'Cash';
    case WalletType.bank:
      return 'Bank account';
    case WalletType.bkash:
      return 'bKash';
    case WalletType.nagad:
      return 'Nagad';
    case WalletType.rocket:
      return 'Rocket';
    case WalletType.mfs:
      return 'Mobile wallet';
    case WalletType.savings:
      return 'Savings';
    case WalletType.custom:
      return 'Wallet';
  }
}

String categoryKindLabel(CategoryKind kind) =>
    kind == CategoryKind.income ? 'Income' : 'Expense';

String transactionTypeLabel(TransactionType type) {
  switch (type) {
    case TransactionType.income:
      return 'Income';
    case TransactionType.expense:
      return 'Expense';
    case TransactionType.transfer:
      return 'Transfer';
  }
}

String budgetPeriodLabel(BudgetPeriod period) {
  switch (period) {
    case BudgetPeriod.weekly:
      return 'Every week';
    case BudgetPeriod.monthly:
      return 'Every month';
    case BudgetPeriod.quarterly:
      return 'Every quarter';
    case BudgetPeriod.yearly:
      return 'Every year';
    case BudgetPeriod.custom:
      return 'Custom dates';
  }
}

String recurrenceLabel(RecurrenceFrequency frequency) {
  switch (frequency) {
    case RecurrenceFrequency.daily:
      return 'Day(s)';
    case RecurrenceFrequency.weekly:
      return 'Week(s)';
    case RecurrenceFrequency.monthly:
      return 'Month(s)';
    case RecurrenceFrequency.yearly:
      return 'Year(s)';
  }
}

String loanDirectionLabel(LoanDirection direction) =>
    direction == LoanDirection.lent ? 'You lent' : 'You borrowed';

/// How a record came into existence. Shown on the transaction detail screen so
/// a voice entry is always identifiable.
String transactionSourceLabel(TransactionSource source) {
  switch (source) {
    case TransactionSource.manual:
      return 'Entered by hand';
    case TransactionSource.voice:
      return 'Recorded by voice';
    case TransactionSource.recurring:
      return 'Posted by a recurring rule';
    case TransactionSource.import_:
      return 'Imported';
    case TransactionSource.goal:
      return 'Goal contribution';
    case TransactionSource.system:
      return 'Recorded automatically by Hishab';
  }
}

/// Palette offered when the user picks a colour for a wallet or category.
const List<int> kPickerColors = <int>[
  0xFF00695C,
  0xFF1565C0,
  0xFF6A1B9A,
  0xFFC62828,
  0xFFEF6C00,
  0xFF2E7D32,
  0xFF00838F,
  0xFF5D4037,
  0xFF455A64,
  0xFFAD1457,
];
