import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../data/local/app_database.dart';
import '../../../domain/enums.dart';
import '../../../domain/models/aggregates.dart';
import '../../../domain/models/budget_progress.dart';
import 'loan_form_sheet.dart';

/// The loan repository exposes repayments through the public `watchPayments`
/// stream (there is no `payments()` future), so a family provider is the
/// natural way to list them and keep the list live after a repayment.
final _loanPaymentsProvider =
    StreamProvider.family<List<LoanPaymentRow>, String>(
      (ref, loanId) => ref.watch(loanRepositoryProvider).watchPayments(loanId),
    );

/// A single loan with its repayment history.
class LoanDetailScreen extends ConsumerStatefulWidget {
  const LoanDetailScreen({super.key, required this.loanId});

  final String loanId;

  @override
  ConsumerState<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends ConsumerState<LoanDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final loans = ref.watch(loanProgressProvider);
    final loan = _resolve(loans.value);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loan'),
        actions: loan == null
            ? null
            : [
                PopupMenuButton<_LoanDetailAction>(
                  tooltip: 'Loan actions',
                  onSelected: (action) => _handleAction(action, loan),
                  itemBuilder: (context) => <PopupMenuEntry<_LoanDetailAction>>[
                    const PopupMenuItem<_LoanDetailAction>(
                      value: _LoanDetailAction.edit,
                      child: Text('Edit'),
                    ),
                    PopupMenuItem<_LoanDetailAction>(
                      value: _LoanDetailAction.settle,
                      child: Text(loan.isSettled ? 'Reopen' : 'Mark settled'),
                    ),
                    const PopupMenuItem<_LoanDetailAction>(
                      value: _LoanDetailAction.delete,
                      child: Text('Delete loan'),
                    ),
                  ],
                ),
              ],
      ),
      body: AsyncView<List<LoanProgress>>(
        value: loans,
        loadingMessage: 'Loading loan…',
        onRetry: () => ref.invalidate(loanProgressProvider),
        builder: (list) {
          final resolved = _resolve(list);
          if (resolved == null) {
            // The id can vanish from the list after a delete; an empty state is
            // safer than dereferencing a missing loan.
            return const EmptyState(
              icon: Icons.handshake_outlined,
              title: 'Loan not found',
              message: 'This loan record was removed.',
            );
          }
          return _LoanDetailBody(loan: resolved);
        },
      ),
    );
  }

  /// Manual lookup so the screen does not depend on `package:collection`.
  LoanProgress? _resolve(List<LoanProgress>? loans) {
    if (loans == null) return null;
    for (final loan in loans) {
      if (loan.loanId == widget.loanId) return loan;
    }
    return null;
  }

  Future<void> _handleAction(
    _LoanDetailAction action,
    LoanProgress loan,
  ) async {
    switch (action) {
      case _LoanDetailAction.edit:
        await showLoanFormSheet(context, ref, existing: loan);
      case _LoanDetailAction.settle:
        try {
          await ref
              .read(loanRepositoryProvider)
              .update(loan.loanId, isSettled: !loan.isSettled);
          if (!mounted) return;
          ref.invalidate(loanProgressProvider);
        } on AppException catch (error) {
          if (!mounted) return;
          showAppMessage(context, error.message);
        }
      case _LoanDetailAction.delete:
        final confirmed = await _confirmDeleteLoan(context, loan.counterparty);
        if (!confirmed || !mounted) return;
        try {
          await ref.read(loanServiceProvider).deleteLoan(loan.loanId);
          if (!mounted) return;
          context.pop();
        } on AppException catch (error) {
          if (!mounted) return;
          showAppMessage(context, error.message);
        }
    }
  }
}

enum _LoanDetailAction { edit, settle, delete }

/// Header, repayment action and repayment history for one loan.
class _LoanDetailBody extends ConsumerWidget {
  const _LoanDetailBody({required this.loan});

  final LoanProgress loan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Full wallet list (including archived) so old repayments can still name
    // the wallet they moved through.
    final wallets =
        ref.watch(walletBalancesProvider).value ?? const <WalletBalance>[];
    final payments = ref.watch(_loanPaymentsProvider(loan.loanId));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        SectionCard(
          title: _directionLabel(loan.direction),
          action: loan.isSettled ? const _SettledBadge() : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loan.counterparty,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  MoneyText(
                    loan.repaidPoisha,
                    showSign: false,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    ' of ',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  MoneyText(
                    loan.principalPoisha,
                    showSign: false,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    ' repaid',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: loan.ratio,
                minHeight: 10,
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(height: 12),
              LabeledRow(
                label: 'Principal',
                value: '',
                valueWidget: MoneyText(loan.principalPoisha, showSign: false),
              ),
              LabeledRow(
                label: 'Repaid',
                value: '',
                valueWidget: MoneyText(loan.repaidPoisha, showSign: false),
              ),
              LabeledRow(
                label: 'Outstanding',
                value: '',
                valueWidget: MoneyText(loan.outstandingPoisha, showSign: false),
                emphasise: true,
              ),
              LabeledRow(label: 'Occurred', value: formatDate(loan.occurredAt)),
              if (loan.dueDate != null)
                LabeledRow(label: 'Due', value: formatDate(loan.dueDate!)),
              if (loan.note != null && loan.note!.trim().isNotEmpty)
                LabeledRow(label: 'Note', value: loan.note!.trim()),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _addRepayment(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Add repayment'),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Repayments',
          child: AsyncView<List<LoanPaymentRow>>(
            value: payments,
            loadingMessage: 'Loading repayments…',
            onRetry: () => ref.invalidate(_loanPaymentsProvider(loan.loanId)),
            empty: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No repayments recorded yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            isEmpty: (rows) => rows.isEmpty,
            // Read-only: the repository can delete a repayment, but that would
            // leave the optional cash transaction it created behind, so the
            // screen does not offer it.
            builder: (rows) => Column(
              children: [
                for (final row in rows)
                  _RepaymentTile(
                    payment: row,
                    walletName: _walletName(wallets, row.walletId),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addRepayment(BuildContext context, WidgetRef ref) async {
    final input = await showDialog<_PaymentInput>(
      context: context,
      builder: (context) => _RepaymentDialog(loan: loan),
    );
    if (input == null) return;
    try {
      final result = await ref
          .read(loanServiceProvider)
          .addPayment(
            loanId: loan.loanId,
            amountPoisha: input.amountPoisha,
            occurredAt: input.occurredAt,
            walletId: input.walletId,
            recordCashMovement: input.recordCashMovement,
          );
      if (!context.mounted) return;
      // The list is a FutureProvider, so it has to be told to re-read.
      ref.invalidate(loanProgressProvider);
      showAppMessage(
        context,
        result.recordedCashMovement
            ? 'Repayment added and the cash movement was recorded.'
            : 'Repayment added.',
      );
    } on AppException catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, error.message);
    }
  }

  static String _directionLabel(LoanDirection direction) => switch (direction) {
    LoanDirection.lent => 'You lent out',
    LoanDirection.borrowed => 'You borrowed',
  };

  static String? _walletName(List<WalletBalance> wallets, String? walletId) {
    if (walletId == null) return null;
    for (final wallet in wallets) {
      if (wallet.walletId == walletId) return wallet.name;
    }
    return null;
  }
}

/// What the repayment dialog hands back to the screen.
class _PaymentInput {
  const _PaymentInput({
    required this.amountPoisha,
    required this.occurredAt,
    this.walletId,
    this.recordCashMovement = false,
  });

  final int amountPoisha;
  final DateTime occurredAt;
  final String? walletId;
  final bool recordCashMovement;
}

class _RepaymentDialog extends ConsumerStatefulWidget {
  const _RepaymentDialog({required this.loan});

  final LoanProgress loan;

  @override
  ConsumerState<_RepaymentDialog> createState() => _RepaymentDialogState();
}

class _RepaymentDialogState extends ConsumerState<_RepaymentDialog> {
  late final TextEditingController _amount;
  late DateTime _date;
  String? _walletId;
  String? _error;
  String? _walletError;
  bool _recordCashMovement = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController();
    _date = DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallets =
        ref.watch(activeWalletBalancesProvider).value ??
        const <WalletBalance>[];
    return AlertDialog(
      title: const Text('Add repayment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AmountField(
              controller: _amount,
              label: 'Amount',
              autofocus: true,
              errorText: _error,
            ),
            const SizedBox(height: 12),
            WalletPickerField(
              wallets: wallets,
              value: _walletId,
              onChanged: (value) => setState(() {
                _walletId = value;
                _walletError = null;
              }),
              label: 'Wallet (optional)',
              errorText: _walletError,
              helperText: 'The wallet the money really moved through.',
            ),
            const SizedBox(height: 12),
            DateFieldButton(
              value: _date,
              onChanged: (value) => setState(() => _date = value),
              label: 'Date',
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _recordCashMovement,
              onChanged: (value) => setState(() {
                _recordCashMovement = value;
                if (!value) _walletError = null;
              }),
              title: const Text('Also record this cash movement'),
              subtitle: Text(
                'Off by default: the repayment is bookkeeping only. When '
                'recorded it is saved as an uncategorised income or expense — '
                'never as salary or a bill.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }

  void _submit() {
    final amount = Money.tryParse(_amount.text)?.poisha;
    setState(() {
      _error = (amount == null || amount <= 0)
          ? 'Enter an amount greater than zero.'
          : null;
      _walletError = _recordCashMovement && _walletId == null
          ? 'Choose the wallet the money moved through.'
          : null;
    });
    if (_error != null || _walletError != null) return;
    Navigator.pop(
      context,
      _PaymentInput(
        amountPoisha: amount!,
        occurredAt: _date,
        walletId: _walletId,
        recordCashMovement: _recordCashMovement,
      ),
    );
  }
}

/// One repayment row with the wallet it moved through when known.
class _RepaymentTile extends StatelessWidget {
  const _RepaymentTile({required this.payment, this.walletName});

  final LoanPaymentRow payment;
  final String? walletName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[
      formatDate(payment.occurredAt),
      if (walletName != null) 'via $walletName',
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.payments_outlined),
      title: MoneyText(payment.amountPoisha, showSign: false),
      subtitle: Text(
        parts.join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A compact "Settled" pill for the loan header.
class _SettledBadge extends StatelessWidget {
  const _SettledBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Settled',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Confirms removing a loan. Wallet transactions already recorded stay put.
Future<bool> _confirmDeleteLoan(
  BuildContext context,
  String counterparty,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete loan?'),
      content: Text(
        'The record with “$counterparty” will be removed. Cash transactions '
        'already recorded in a wallet are not removed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
