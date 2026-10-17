import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/money.dart';
import '../../../domain/enums.dart';
import '../../../domain/models/aggregates.dart';
import '../../../domain/models/budget_progress.dart';

/// Opens the create / edit sheet for a loan.
///
/// Editing adjusts the bookkeeping fields only: the direction and whether the
/// cash movement was recorded are facts from the moment the loan was created,
/// so they are fixed afterwards.
Future<void> showLoanFormSheet(
  BuildContext context,
  WidgetRef ref, {
  LoanProgress? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _LoanForm(existing: existing),
  );
}

class _LoanForm extends ConsumerStatefulWidget {
  const _LoanForm({this.existing});

  final LoanProgress? existing;

  @override
  ConsumerState<_LoanForm> createState() => _LoanFormState();
}

class _LoanFormState extends ConsumerState<_LoanForm> {
  late final TextEditingController _counterparty;
  late final TextEditingController _principal;
  late final TextEditingController _note;
  LoanDirection _direction = LoanDirection.lent;
  late DateTime _occurredAt;
  DateTime? _dueDate;
  bool _recordCashMovement = false;
  String? _walletId;
  String? _counterpartyError;
  String? _principalError;
  String? _walletError;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _counterparty = TextEditingController(text: existing?.counterparty ?? '');
    _principal = TextEditingController(
      // Storage form keeps the poisha value intact when the user edits it back.
      text: existing == null
          ? ''
          : Money(existing.principalPoisha).toStorageString(),
    );
    _note = TextEditingController(text: existing?.note ?? '');
    _direction = existing?.direction ?? LoanDirection.lent;
    _occurredAt = existing?.occurredAt ?? DateTime.now();
    _dueDate = existing?.dueDate;
  }

  @override
  void dispose() {
    _counterparty.dispose();
    _principal.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallets =
        ref.watch(activeWalletBalancesProvider).value ??
        const <WalletBalance>[];
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        // Keep the focused field above the keyboard.
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEdit ? 'Edit loan' : 'New loan',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            FormDropdown<LoanDirection>(
              label: 'Direction',
              value: _direction,
              enabled: !_isEdit,
              helperText: _isEdit
                  ? 'Direction cannot be changed after the loan is created.'
                  : null,
              items: const <DropdownMenuItem<LoanDirection>>[
                DropdownMenuItem<LoanDirection>(
                  value: LoanDirection.lent,
                  child: Text('I lent money out'),
                ),
                DropdownMenuItem<LoanDirection>(
                  value: LoanDirection.borrowed,
                  child: Text('I borrowed money'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _direction = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _counterparty,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Counterparty',
                errorText: _counterpartyError,
                helperText: 'Who the money went to or came from.',
              ),
            ),
            const SizedBox(height: 12),
            AmountField(
              controller: _principal,
              label: 'Principal amount',
              errorText: _principalError,
            ),
            const SizedBox(height: 12),
            DateFieldButton(
              value: _occurredAt,
              onChanged: (value) => setState(() => _occurredAt = value),
              label: 'Date lent / borrowed',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DateFieldButton(
                    value: _dueDate ?? _occurredAt,
                    onChanged: (value) => setState(() => _dueDate = value),
                    label: 'Due date (optional)',
                  ),
                ),
                if (_dueDate != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => setState(() => _dueDate = null),
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear due date',
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _recordCashMovement,
                onChanged: (value) => setState(() {
                  _recordCashMovement = value;
                  if (!value) _walletId = null;
                }),
                title: const Text('Also record this cash movement in a wallet'),
                subtitle: const Text(
                  'By default a loan is bookkeeping only and does not touch '
                  'wallet balances. When you record the cash movement it is '
                  'saved as an uncategorised income or expense — never as '
                  'salary or a bill.',
                ),
              ),
              if (_recordCashMovement) ...[
                const SizedBox(height: 12),
                WalletPickerField(
                  wallets: wallets,
                  value: _walletId,
                  onChanged: (value) => setState(() {
                    _walletId = value;
                    _walletError = null;
                  }),
                  label: 'Wallet',
                  errorText: _walletError,
                  helperText: 'The wallet the money actually left or entered.',
                ),
              ],
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEdit ? 'Save changes' : 'Create loan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final counterparty = _counterparty.text.trim();
    final principal = Money.tryParse(_principal.text)?.poisha;
    setState(() {
      _counterpartyError = counterparty.isEmpty
          ? 'Enter who this loan is with.'
          : null;
      _principalError = (principal == null || principal <= 0)
          ? 'Enter an amount greater than zero.'
          : null;
      _walletError = _recordCashMovement && _walletId == null
          ? 'Choose the wallet the money moved through.'
          : null;
    });
    if (_counterpartyError != null ||
        _principalError != null ||
        _walletError != null) {
      return;
    }

    setState(() => _saving = true);
    final note = _note.text.trim();
    try {
      if (_isEdit) {
        await ref
            .read(loanRepositoryProvider)
            .update(
              widget.existing!.loanId,
              counterparty: counterparty,
              principalPoisha: principal,
              occurredAt: _occurredAt,
              dueDate: _dueDate,
              clearDueDate: _dueDate == null,
              note: note.isEmpty ? null : note,
            );
      } else {
        await ref
            .read(loanServiceProvider)
            .createLoan(
              counterparty: counterparty,
              direction: _direction,
              principalPoisha: principal!,
              occurredAt: _occurredAt,
              dueDate: _dueDate,
              walletId: _recordCashMovement ? _walletId : null,
              note: note.isEmpty ? null : note,
              recordCashMovement: _recordCashMovement,
            );
      }
      if (!mounted) return;
      // The list is a FutureProvider, so it has to be told to re-read.
      ref.invalidate(loanProgressProvider);
      Navigator.pop(context);
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, error.message);
    }
  }
}
