import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_x.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../domain/enums.dart';
import '../../domain/models/aggregates.dart';
import '../providers.dart';
import '../theme.dart';

/// Formats poisha using the user's own preferences (Bengali digits, grouping).
MoneyFormatter formatterFor(WidgetRef ref, {bool withSymbol = true}) {
  final settings = ref.watch(appSettingsProvider).value;
  return MoneyFormatter(
    useBengaliDigits: settings?.useBengaliDigits ?? false,
    bangladeshiGrouping: settings?.bangladeshiGrouping ?? true,
    showSymbol: withSymbol,
  );
}

/// An amount, coloured and signed by transaction type.
class MoneyText extends ConsumerWidget {
  const MoneyText(
    this.poisha, {
    super.key,
    this.type,
    this.style,
    this.showSign = true,
    this.compact = false,
  });

  final int poisha;
  final TransactionType? type;
  final TextStyle? style;
  final bool showSign;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formatter = formatterFor(ref);
    final color = type == null
        ? null
        : (type == TransactionType.income
              ? AppColors.income
              : (type == TransactionType.transfer
                    ? AppColors.transfer
                    : AppColors.expense));
    final signedPrefix = !showSign || type == null
        ? ''
        : (type == TransactionType.income
              ? '+'
              : (type == TransactionType.transfer ? '' : '−'));
    final text = compact
        ? formatter.formatCompact(poisha)
        : formatter.format(poisha);
    return Text(
      '$signedPrefix$text',
      style: (style ?? const TextStyle(fontWeight: FontWeight.w600)).copyWith(
        color: color,
      ),
    );
  }
}

/// A titled card used for every grouped block of content.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.action,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final String? title;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  ?action,
                ],
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// `label` on the left, value on the right.
class LabeledRow extends StatelessWidget {
  const LabeledRow({
    super.key,
    required this.label,
    required this.value,
    this.valueWidget,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final Widget? valueWidget;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Align(
              alignment: Alignment.centerRight,
              child:
                  valueWidget ??
                  Text(
                    value,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: emphasise ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Friendly placeholder for a list with nothing in it.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorStateView extends StatelessWidget {
  const ErrorStateView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: 'Something went wrong',
      message: message,
      action: onRetry == null
          ? null
          : OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(message!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// Renders an [AsyncValue] with sensible loading / error / empty handling so no
/// screen has to repeat the same three branches.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.loadingMessage,
    this.empty,
    this.isEmpty,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final String? loadingMessage;

  /// Shown when [isEmpty] reports true.
  final Widget? empty;
  final bool Function(T data)? isEmpty;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => LoadingView(message: loadingMessage),
      error: (error, _) =>
          ErrorStateView(message: error.toString(), onRetry: onRetry),
      data: (data) {
        if (empty != null && (isEmpty?.call(data) ?? false)) return empty!;
        return builder(data);
      },
    );
  }
}

/// A numeric amount field that understands Bengali digits, grouping commas and
/// a currency symbol, and reports the parsed poisha value.
class AmountField extends StatefulWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.label = 'Amount',
    this.autofocus = false,
    this.onChanged,
    this.errorText,
    this.helperText,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final ValueChanged<int?>? onChanged;
  final String? errorText;
  final String? helperText;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      autofocus: widget.autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixText: '৳ ',
        errorText: widget.errorText,
        helperText: widget.helperText,
        helperMaxLines: 3,
        errorMaxLines: 3,
      ),
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      onChanged: (raw) {
        final money = Money.tryParse(raw);
        widget.onChanged?.call(money?.poisha);
      },
    );
  }
}

/// Fully controlled dropdown built from an [InputDecorator] and a plain
/// [DropdownButton].
///
/// `DropdownButtonFormField` only reads its value once (it seeds a form field),
/// which makes it unreliable for a form that is edited in place — for example
/// swapping source and destination on a transfer. This widget is the one used
/// everywhere instead.
class FormDropdown<T> extends StatelessWidget {
  const FormDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.errorText,
    this.helperText,
    this.prefixIcon,
    this.enabled = true,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? errorText;
  final String? helperText;
  final IconData? prefixIcon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = items.any((item) => item.value == value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            errorText: errorText,
            helperText: helperText,
            helperMaxLines: 3,
            errorMaxLines: 3,
            prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: hasValue ? value : null,
              isExpanded: true,
              isDense: true,
              hint: Text(
                'Select…',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              items: items,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// Wallet picker. Archived wallets are shown disabled rather than hidden, so
/// the reason a wallet cannot be selected is visible.
class WalletPickerField extends StatelessWidget {
  const WalletPickerField({
    super.key,
    required this.wallets,
    required this.value,
    required this.onChanged,
    this.label = 'Wallet',
    this.errorText,
    this.helperText,
    this.exclude,
  });

  final List<WalletBalance> wallets;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  final String? errorText;
  final String? helperText;

  /// Wallet id that must not be selectable (the source of a transfer).
  final String? exclude;

  @override
  Widget build(BuildContext context) {
    final active = wallets.where((w) => !w.isArchived).toList(growable: false);
    return FormDropdown<String>(
      label: label,
      value: value,
      errorText: errorText,
      helperText: helperText,
      prefixIcon: Icons.account_balance_wallet_outlined,
      items: [
        for (final wallet in active)
          DropdownMenuItem(
            value: wallet.walletId,
            enabled: wallet.walletId != exclude,
            child: Row(
              children: [
                Icon(_iconFor(wallet), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    wallet.walletId == exclude
                        ? '${wallet.name} (same as source)'
                        : wallet.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  MoneyFormatter.standard.format(wallet.balancePoisha),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }

  static IconData _iconFor(WalletBalance wallet) {
    switch (wallet.type) {
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

/// Date field that opens a picker and never allows a date before 2000.
class DateFieldButton extends ConsumerWidget {
  const DateFieldButton({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Date',
    this.includeTime = false,
  });

  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final String label;
  final bool includeTime;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bengaliDigits =
        ref.watch(appSettingsProvider).value?.useBengaliDigits ?? false;
    final text = includeTime
        ? formatDateTime(value)
        : formatDate(value, bengaliDigits: bengaliDigits);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2000),
          lastDate: DateTime.now().add(const Duration(days: 366)),
        );
        if (picked == null) return;
        if (!includeTime) {
          onChanged(
            DateTime(
              picked.year,
              picked.month,
              picked.day,
              value.hour,
              value.minute,
            ),
          );
          return;
        }
        if (!context.mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(value),
        );
        onChanged(
          DateTime(
            picked.year,
            picked.month,
            picked.day,
            time?.hour ?? value.hour,
            time?.minute ?? value.minute,
          ),
        );
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: [
            const Icon(Icons.event, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

/// Income / expense / transfer selector.
class TransactionTypeSelector extends StatelessWidget {
  const TransactionTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowTransfer = true,
  });

  final TransactionType value;
  final ValueChanged<TransactionType> onChanged;
  final bool allowTransfer;

  @override
  Widget build(BuildContext context) {
    final types = <TransactionType>[
      TransactionType.expense,
      TransactionType.income,
      if (allowTransfer) TransactionType.transfer,
    ];
    return SegmentedButton<TransactionType>(
      segments: [
        for (final type in types)
          ButtonSegment(
            value: type,
            label: Text(_label(type)),
            icon: Icon(_icon(type), size: 18),
          ),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }

  static String _label(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return 'Income';
      case TransactionType.expense:
        return 'Expense';
      case TransactionType.transfer:
        return 'Transfer';
    }
  }

  static IconData _icon(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return Icons.south_west;
      case TransactionType.expense:
        return Icons.north_east;
      case TransactionType.transfer:
        return Icons.swap_horiz;
    }
  }
}

/// One row in a transaction list.
class TransactionTile extends ConsumerWidget {
  const TransactionTile({
    super.key,
    required this.item,
    this.onTap,
    this.trailing,
  });

  final TransactionListItem item;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final title = item.description?.trim().isNotEmpty == true
        ? item.description!.trim()
        : (item.categoryName ??
              (item.isTransfer ? 'Transfer' : _typeLabel(item.type)));
    final subtitleParts = <String>[
      if (item.isTransfer && item.toWalletName != null)
        '${item.walletName} → ${item.toWalletName}'
      else
        item.walletName,
      if (item.categoryName != null && item.description != null)
        item.categoryName!,
      formatDate(item.occurredAt),
    ];
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: AppColors.forType(item.type).withValues(alpha: 0.14),
        child: Icon(
          _iconFor(item),
          size: 20,
          color: AppColors.forType(item.type),
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitleParts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing:
          trailing ??
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyText(item.amountPoisha, type: item.type),
              if (item.feePoisha > 0)
                Text(
                  'fee ${MoneyFormatter.standard.format(item.feePoisha)}',
                  style: theme.textTheme.labelSmall,
                ),
            ],
          ),
    );
  }

  static String _typeLabel(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return 'Income';
      case TransactionType.expense:
        return 'Expense';
      case TransactionType.transfer:
        return 'Transfer';
    }
  }

  static IconData _iconFor(TransactionListItem item) {
    switch (item.type) {
      case TransactionType.income:
        return Icons.south_west;
      case TransactionType.expense:
        return Icons.north_east;
      case TransactionType.transfer:
        return Icons.swap_horiz;
    }
  }
}

/// Small statistic used on the dashboard and reports.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.valuePoisha,
    this.type,
    this.icon,
    this.helper,
  });

  final String label;
  final int valuePoisha;
  final TransactionType? type;
  final IconData? icon;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        MoneyText(
          valuePoisha,
          type: type,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (helper != null) Text(helper!, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

/// Shows a snackbar and, when the last action is still reversible, an Undo
/// button wired to `UndoService`.
void showUndoSnackBar(BuildContext context, WidgetRef ref, String message) {
  final undo = ref.read(undoServiceProvider);
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 6),
      action: undo.canUndo
          ? SnackBarAction(
              label: 'Undo',
              onPressed: () async {
                final undone = await undo.undo();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      undone ? 'Undone.' : 'That can no longer be undone.',
                    ),
                    duration: const Duration(seconds: 3),
                  ),
                );
              },
            )
          : null,
    ),
  );
}

/// Shows an error message coming from the domain layer.
void showAppMessage(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
  );
}
