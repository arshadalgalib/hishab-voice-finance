import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/date_x.dart';
import '../../../core/utils/money.dart';
import '../../../domain/enums.dart';
import '../../../domain/models/budget_progress.dart';

/// English label for a budget period, shared by the card and the form.
String humanPeriodLabel(BudgetPeriod period) {
  switch (period) {
    case BudgetPeriod.weekly:
      return 'Weekly';
    case BudgetPeriod.monthly:
      return 'Monthly';
    case BudgetPeriod.quarterly:
      return 'Quarterly';
    case BudgetPeriod.yearly:
      return 'Yearly';
    case BudgetPeriod.custom:
      return 'Custom';
  }
}

/// Opens the create / edit budget sheet. [existing] prefills the form.
Future<void> showBudgetFormSheet(
  BuildContext context,
  WidgetRef ref, {
  BudgetProgress? existing,
}) {
  // Capture "now" once so a custom budget's default dates do not drift while
  // the sheet is open.
  final reference = ref.read(clockProvider).now();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _BudgetForm(existing: existing, reference: reference),
  );
}

class _BudgetForm extends ConsumerStatefulWidget {
  const _BudgetForm({required this.existing, required this.reference});

  final BudgetProgress? existing;
  final DateTime reference;

  @override
  ConsumerState<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends ConsumerState<_BudgetForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late BudgetPeriod _period;
  String? _categoryId;
  late double _threshold;
  late DateTime _startDate;
  late DateTime _endDate;
  String? _amountError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _amountController = TextEditingController(
      text: existing == null ? '' : _editableAmount(existing.amountPoisha),
    );
    _period = existing?.period ?? BudgetPeriod.monthly;
    _categoryId = existing?.categoryId;
    _threshold = (existing?.alertThresholdPercent ?? 80).toDouble();
    _startDate = existing?.range.start ?? startOfDay(widget.reference);
    _endDate = existing?.range.end ?? endOfDay(widget.reference);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final amount = Money.tryParse(_amountController.text)?.poisha;
    if (amount == null || amount <= 0) {
      setState(() => _amountError = 'Enter a limit greater than zero.');
      return;
    }
    final isCustom = _period == BudgetPeriod.custom;
    if (isCustom && _endDate.isBefore(_startDate)) {
      showAppMessage(
        context,
        'The end date must be on or after the start date.',
      );
      return;
    }

    setState(() {
      _amountError = null;
      _saving = true;
    });

    final repository = ref.read(budgetRepositoryProvider);
    final existing = widget.existing;
    try {
      if (existing == null) {
        await repository.create(
          name: _nameController.text.trim(),
          amountPoisha: amount,
          period: _period,
          startDate: _startDate,
          categoryId: _categoryId,
          endDate: isCustom ? _endDate : null,
          alertThresholdPercent: _threshold.round(),
        );
      } else {
        await repository.update(
          existing.budgetId,
          name: _nameController.text.trim(),
          amountPoisha: amount,
          period: _period,
          startDate: _startDate,
          endDate: isCustom ? _endDate : null,
          clearEndDate: !isCustom,
          categoryId: _categoryId,
          clearCategory: _categoryId == null,
          alertThresholdPercent: _threshold.round(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;
    return Padding(
      // Keep the save button reachable while the keyboard is up.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEditing ? 'Edit budget' : 'New budget',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Groceries',
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Give the budget a name.'
                    : null,
              ),
              const SizedBox(height: 16),
              AmountField(
                controller: _amountController,
                label: 'Limit',
                autofocus: !isEditing,
                errorText: _amountError,
                onChanged: (poisha) {
                  if (_amountError != null && poisha != null && poisha > 0) {
                    setState(() => _amountError = null);
                  }
                },
              ),
              const SizedBox(height: 16),
              FormDropdown<BudgetPeriod>(
                label: 'Period',
                value: _period,
                items: [
                  for (final period in BudgetPeriod.values)
                    DropdownMenuItem<BudgetPeriod>(
                      value: period,
                      child: Text(humanPeriodLabel(period)),
                    ),
                ],
                onChanged: (period) {
                  if (period == null) return;
                  setState(() => _period = period);
                },
              ),
              const SizedBox(height: 16),
              AsyncView(
                value: ref.watch(expenseCategoriesProvider),
                loadingMessage: 'Loading categories…',
                onRetry: () => ref.invalidate(expenseCategoriesProvider),
                builder: (categories) => FormDropdown<String?>(
                  label: 'Category',
                  value: _categoryId,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All categories'),
                    ),
                    for (final category in categories)
                      DropdownMenuItem<String?>(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Alert at ${_threshold.round()}%',
                style: theme.textTheme.bodyMedium,
              ),
              Slider(
                value: _threshold,
                min: 50,
                max: 100,
                divisions: 10,
                label: '${_threshold.round()}%',
                onChanged: (value) => setState(() => _threshold = value),
              ),
              Text(
                'Hishab warns you once this share of the limit is used.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_period == BudgetPeriod.custom) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DateFieldButton(
                        value: _startDate,
                        label: 'Starts',
                        onChanged: (value) =>
                            setState(() => _startDate = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DateFieldButton(
                        value: _endDate,
                        label: 'Ends',
                        onChanged: (value) => setState(() => _endDate = value),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving
                      ? 'Saving…'
                      : (isEditing ? 'Save changes' : 'Create budget'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Prefills an amount field without a trailing `.00`, so editing a whole taka
/// limit does not look like it needs decimals.
String _editableAmount(int poisha) {
  final storage = Money(poisha).toStorageString();
  return storage.endsWith('.00')
      ? storage.substring(0, storage.length - 3)
      : storage;
}
