import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/money.dart';
import '../../../domain/models/aggregates.dart';
import '../../../domain/models/budget_progress.dart';

/// Opens the create / edit sheet for a savings goal.
///
/// Creating and editing share one form so the field set and its wording can
/// never drift apart between the two paths.
Future<void> showGoalFormSheet(
  BuildContext context,
  WidgetRef ref, {
  GoalProgress? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _GoalForm(existing: existing),
  );
}

class _GoalForm extends ConsumerStatefulWidget {
  const _GoalForm({this.existing});

  final GoalProgress? existing;

  @override
  ConsumerState<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends ConsumerState<_GoalForm> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  late final TextEditingController _note;
  String? _walletId;
  DateTime? _targetDate;
  String? _nameError;
  String? _targetError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _target = TextEditingController(
      // Storage form keeps the poisha value intact when the user edits it back.
      text: existing == null
          ? ''
          : Money(existing.targetPoisha).toStorageString(),
    );
    _note = TextEditingController(text: existing?.note ?? '');
    _walletId = existing?.walletId;
    _targetDate = existing?.targetDate;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallets =
        ref.watch(activeWalletBalancesProvider).value ??
        const <WalletBalance>[];
    final isEdit = widget.existing != null;
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
              isEdit ? 'Edit goal' : 'New goal',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 12),
            AmountField(
              controller: _target,
              label: 'Target amount',
              errorText: _targetError,
              helperText: 'The total you want to put aside.',
            ),
            const SizedBox(height: 12),
            WalletPickerField(
              wallets: wallets,
              value: _walletId,
              onChanged: (value) => setState(() => _walletId = value),
              label: 'Linked wallet (optional)',
              helperText:
                  'With a wallet linked, money can be moved into the goal from '
                  'another wallet. That is recorded as a transfer — money '
                  'changing wallet — never as spending.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DateFieldButton(
                    value: _targetDate ?? DateTime.now(),
                    onChanged: (value) => setState(() => _targetDate = value),
                    label: 'Target date (optional)',
                  ),
                ),
                if (_targetDate != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => setState(() => _targetDate = null),
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear target date',
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
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEdit ? 'Save changes' : 'Create goal'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final target = Money.tryParse(_target.text)?.poisha;
    setState(() {
      _nameError = name.isEmpty ? 'Enter a name.' : null;
      _targetError = (target == null || target <= 0)
          ? 'Enter an amount greater than zero.'
          : null;
    });
    if (_nameError != null || _targetError != null) return;

    setState(() => _saving = true);
    final note = _note.text.trim();
    final repository = ref.read(goalRepositoryProvider);
    try {
      final existing = widget.existing;
      if (existing == null) {
        await repository.create(
          name: name,
          targetPoisha: target!,
          targetDate: _targetDate,
          walletId: _walletId,
          note: note.isEmpty ? null : note,
        );
      } else {
        await repository.update(
          existing.goalId,
          name: name,
          targetPoisha: target,
          targetDate: _targetDate,
          clearTargetDate: _targetDate == null,
          walletId: _walletId,
          clearWallet: _walletId == null,
          note: note.isEmpty ? null : note,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, error.message);
    }
  }
}
