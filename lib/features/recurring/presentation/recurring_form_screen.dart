import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/money.dart';
import '../../../data/local/app_database.dart';
import '../../../domain/enums.dart';
import '../../../domain/models/aggregates.dart';

/// Create / edit form for a recurring rule.
///
/// [ruleId] arrives through go_router's `extra`; `null` means a new rule.
class RecurringFormScreen extends ConsumerStatefulWidget {
  const RecurringFormScreen({super.key, this.ruleId});

  final String? ruleId;

  @override
  ConsumerState<RecurringFormScreen> createState() =>
      _RecurringFormScreenState();
}

class _RecurringFormScreenState extends ConsumerState<RecurringFormScreen> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _intervalController = TextEditingController();

  TransactionType _type = TransactionType.expense;
  RecurrenceFrequency _frequency = RecurrenceFrequency.monthly;
  String? _walletId;
  String? _categoryId;
  late DateTime _dueDate;
  late DateTime _originalDueDate;
  DateTime? _endDate;

  String? _amountError;
  bool _prefilled = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider).now();
    _dueDate = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    _originalDueDate = _dueDate;
    _intervalController.text = '1';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  /// Copies the stored rule into the fields once, before any field is built, so
  /// no controller listener fires mid-build.
  void _prefill(RecurringRuleRow rule) {
    _prefilled = true;
    _type = rule.type;
    _frequency = rule.frequency;
    _walletId = rule.walletId;
    _categoryId = rule.categoryId;
    _dueDate = rule.nextDueDate;
    _originalDueDate = rule.nextDueDate;
    _endDate = rule.endDate;
    _nameController.text = rule.name;
    _descriptionController.text = rule.description ?? '';
    _amountController.text = Money(rule.amountPoisha).toStorageString();
    _intervalController.text = rule.intervalCount.toString();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.ruleId != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit rule' : 'New rule')),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    final walletsAsync = ref.watch(activeWalletBalancesProvider);
    final ruleId = widget.ruleId;
    if (ruleId == null) {
      return AsyncView<List<WalletBalance>>(
        value: walletsAsync,
        loadingMessage: 'Loading wallets…',
        onRetry: () => ref.invalidate(activeWalletBalancesProvider),
        builder: (wallets) => _form(wallets, null),
      );
    }
    return AsyncView<List<RecurringRuleRow>>(
      value: ref.watch(recurringRulesProvider),
      loadingMessage: 'Loading rule…',
      onRetry: () => ref.invalidate(recurringRulesProvider),
      isEmpty: (rules) => !rules.any((rule) => rule.id == ruleId),
      empty: EmptyState(
        icon: Icons.search_off,
        title: 'Rule not found',
        message: 'This recurring rule may have been deleted.',
        action: FilledButton(
          onPressed: () => context.pop(),
          child: const Text('Close'),
        ),
      ),
      builder: (rules) {
        final rule = rules.firstWhere((candidate) => candidate.id == ruleId);
        if (!_prefilled) _prefill(rule);
        return AsyncView<List<WalletBalance>>(
          value: walletsAsync,
          loadingMessage: 'Loading wallets…',
          onRetry: () => ref.invalidate(activeWalletBalancesProvider),
          builder: (wallets) => _form(wallets, rule),
        );
      },
    );
  }

  Widget _form(List<WalletBalance> wallets, RecurringRuleRow? existing) {
    final categoryAsync = _type == TransactionType.income
        ? ref.watch(incomeCategoriesProvider)
        : ref.watch(expenseCategoriesProvider);
    final categories = categoryAsync.value ?? const <CategoryRow>[];
    final categoryItems = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(value: null, child: Text('No category')),
      for (final category in categories)
        DropdownMenuItem<String?>(
          value: category.id,
          child: Text(category.name),
        ),
    ];
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TransactionTypeSelector(
            value: _type,
            allowTransfer: false,
            onChanged: (type) => setState(() {
              _type = type;
              // Categories are kind-specific, so the old choice no longer fits.
              _categoryId = null;
            }),
          ),
          const SizedBox(height: 16),
          AmountField(
            controller: _amountController,
            errorText: _amountError,
            onChanged: (_) {
              if (_amountError != null) {
                setState(() => _amountError = null);
              }
            },
          ),
          const SizedBox(height: 16),
          WalletPickerField(
            wallets: wallets,
            value: _walletId,
            onChanged: (walletId) => setState(() => _walletId = walletId),
          ),
          const SizedBox(height: 16),
          FormDropdown<String?>(
            label: 'Category',
            value: _categoryId,
            items: categoryItems,
            enabled: !categoryAsync.isLoading,
            onChanged: (categoryId) => setState(() => _categoryId = categoryId),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
            ),
          ),
          const SizedBox(height: 16),
          FormDropdown<RecurrenceFrequency>(
            label: 'Frequency',
            value: _frequency,
            prefixIcon: Icons.repeat,
            items: [
              for (final frequency in RecurrenceFrequency.values)
                DropdownMenuItem(
                  value: frequency,
                  child: Text(_frequencyLabel(frequency)),
                ),
            ],
            onChanged: (frequency) {
              if (frequency != null) setState(() => _frequency = frequency);
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _intervalController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Repeat every',
              helperText:
                  'Number of periods between each occurrence (1 or more).',
            ),
          ),
          const SizedBox(height: 16),
          DateFieldButton(
            value: _dueDate,
            includeTime: true,
            label: 'Next due date',
            onChanged: (value) => setState(() => _dueDate = value),
          ),
          const SizedBox(height: 16),
          _endDateField(),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : () => _save(existing),
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _endDateField() {
    final endDate = _endDate;
    if (endDate == null) {
      return OutlinedButton.icon(
        onPressed: () => setState(() => _endDate = _dueDate),
        icon: const Icon(Icons.event_busy),
        label: const Text('Add an end date'),
      );
    }
    return Row(
      children: [
        Expanded(
          child: DateFieldButton(
            value: endDate,
            label: 'End date',
            onChanged: (value) => setState(() => _endDate = value),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => setState(() => _endDate = null),
          icon: const Icon(Icons.clear),
          tooltip: 'Clear end date',
        ),
      ],
    );
  }

  static String _frequencyLabel(RecurrenceFrequency frequency) {
    switch (frequency) {
      case RecurrenceFrequency.daily:
        return 'Daily';
      case RecurrenceFrequency.weekly:
        return 'Weekly';
      case RecurrenceFrequency.monthly:
        return 'Monthly';
      case RecurrenceFrequency.yearly:
        return 'Yearly';
    }
  }

  Future<void> _save(RecurringRuleRow? existing) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showAppMessage(context, 'Enter a name for this rule.');
      return;
    }
    final amount = Money.tryParse(_amountController.text)?.poisha;
    if (amount == null || amount <= 0) {
      setState(() => _amountError = 'Enter an amount greater than zero.');
      return;
    }
    _amountError = null;
    final walletId = _walletId;
    if (walletId == null) {
      showAppMessage(context, 'Choose the wallet this rule uses.');
      return;
    }
    final interval = int.tryParse(_intervalController.text.trim());
    if (interval == null || interval < 1) {
      showAppMessage(context, 'Repeat interval must be at least 1.');
      return;
    }
    final description = _descriptionController.text.trim();

    // `update` has no `nextDueDate` parameter, so an edited date is only written
    // when it actually changed; otherwise the stored start date is left alone.
    final dateChanged = existing == null || _dueDate != _originalDueDate;

    setState(() => _saving = true);
    try {
      final repository = ref.read(recurringRepositoryProvider);
      if (existing == null) {
        await repository.create(
          name: name,
          type: _type,
          amountPoisha: amount,
          walletId: walletId,
          frequency: _frequency,
          startDate: _dueDate,
          categoryId: _categoryId,
          description: description,
          intervalCount: interval,
          endDate: _endDate,
        );
      } else {
        await repository.update(
          existing.id,
          name: name,
          amountPoisha: amount,
          walletId: walletId,
          categoryId: _categoryId,
          clearCategory: _categoryId == null,
          description: description,
          frequency: _frequency,
          intervalCount: interval,
          startDate: dateChanged ? _dueDate : null,
          endDate: _endDate,
          clearEndDate: _endDate == null,
        );
      }
      if (!mounted) return;
      context.pop(true);
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, error.message);
    }
  }
}
