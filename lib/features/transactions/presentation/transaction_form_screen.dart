import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../data/local/app_database.dart';
import '../../../domain/enums.dart';
import '../../../domain/models/aggregates.dart';
import '../../../domain/models/transaction_draft.dart';

/// Records or edits one transaction by hand.
///
/// Both this screen and the voice flow end up calling the same
/// `TransactionService`, so the financial rules (a transfer is one record, a
/// transfer is never categorised, an amount is always positive) are identical
/// whichever way the data arrives.
class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({
    super.key,
    this.initialType,
    this.transactionId,
  });

  final TransactionType? initialType;

  /// Set when editing an existing transaction.
  final String? transactionId;

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  @override
  Widget build(BuildContext context) {
    final id = widget.transactionId;
    if (id == null) {
      return _TransactionForm(
        existing: null,
        initialType: widget.initialType ?? TransactionType.expense,
      );
    }
    return FutureBuilder<TransactionListItem?>(
      future: ref.read(transactionRepositoryProvider).find(id),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: const Text('Edit transaction')),
            body: const LoadingView(),
          );
        }
        final existing = snapshot.data;
        if (existing == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Edit transaction')),
            body: const EmptyState(
              icon: Icons.error_outline,
              title: 'That transaction no longer exists',
              message: 'It may have been deleted on another screen.',
            ),
          );
        }
        return _TransactionForm(existing: existing, initialType: existing.type);
      },
    );
  }
}

class _TransactionForm extends ConsumerStatefulWidget {
  const _TransactionForm({required this.existing, required this.initialType});

  final TransactionListItem? existing;
  final TransactionType initialType;

  @override
  ConsumerState<_TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends ConsumerState<_TransactionForm> {
  late final TextEditingController _amount;
  late final TextEditingController _fee;
  late final TextEditingController _description;
  late final TextEditingController _note;
  late final TextEditingController _tags;

  late TransactionType _type;
  String? _walletId;
  String? _toWalletId;
  String? _categoryId;
  late DateTime _occurredAt;
  int? _amountPoisha;
  int _feePoisha = 0;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.type ?? widget.initialType;
    _walletId = existing?.walletId;
    _toWalletId = existing?.toWalletId;
    _categoryId = existing?.categoryId;
    _occurredAt = existing?.occurredAt ?? ref.read(clockProvider).now();
    _amountPoisha = existing?.amountPoisha;
    _feePoisha = existing?.feePoisha ?? 0;

    _amount = TextEditingController(
      text: existing == null || existing.amountPoisha <= 0
          ? ''
          : _storageString(existing.amountPoisha),
    );
    _fee = TextEditingController(
      text: existing == null || existing.feePoisha <= 0
          ? ''
          : _storageString(existing.feePoisha),
    );
    _description = TextEditingController(text: existing?.description ?? '');
    _note = TextEditingController(text: existing?.note ?? '');
    _tags = TextEditingController(text: existing?.tags.join(', ') ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _fee.dispose();
    _description.dispose();
    _note.dispose();
    _tags.dispose();
    super.dispose();
  }

  static String _storageString(int poisha) {
    final whole = poisha ~/ 100;
    final fraction = poisha % 100;
    return fraction == 0
        ? whole.toString()
        : '$whole.${fraction.toString().padLeft(2, '0')}';
  }

  static String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  List<String> get _parsedTags => _tags.text
      .split(',')
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);

  TransactionDraft _buildDraft() {
    final description = _blankToNull(_description.text);
    final note = _blankToNull(_note.text);
    if (_type.isTransfer) {
      return TransactionDraft.transfer(
        amountPoisha: _amountPoisha ?? 0,
        fromWalletId: _walletId ?? '',
        toWalletId: _toWalletId ?? '',
        occurredAt: _occurredAt,
        description: description,
        note: note,
        feePoisha: _feePoisha,
        // Editing a voice entry must not silently relabel it as manual.
        source: widget.existing?.source ?? TransactionSource.manual,
      );
    }
    return TransactionDraft(
      type: _type,
      amountPoisha: _amountPoisha ?? 0,
      walletId: _walletId ?? '',
      categoryId: _categoryId,
      occurredAt: _occurredAt,
      description: description,
      note: note,
      tags: _parsedTags,
      source: widget.existing?.source ?? TransactionSource.manual,
    );
  }

  static TransactionDraft _draftFrom(TransactionListItem item) {
    if (item.type.isTransfer) {
      return TransactionDraft.transfer(
        amountPoisha: item.amountPoisha,
        fromWalletId: item.walletId,
        toWalletId: item.toWalletId ?? '',
        occurredAt: item.occurredAt,
        description: item.description,
        note: item.note,
        feePoisha: item.feePoisha,
        source: item.source,
      );
    }
    return TransactionDraft(
      type: item.type,
      amountPoisha: item.amountPoisha,
      walletId: item.walletId,
      categoryId: item.categoryId,
      occurredAt: item.occurredAt,
      description: item.description,
      merchant: item.merchant,
      counterparty: item.counterparty,
      note: item.note,
      tags: item.tags,
      source: item.source,
    );
  }

  Future<void> _save({bool allowDuplicate = false}) async {
    if (_saving) return;
    final draft = _buildDraft();

    if (draft.amountPoisha <= 0) {
      showAppMessage(context, 'Enter an amount greater than zero.');
      return;
    }
    if (draft.walletId.isEmpty) {
      showAppMessage(context, 'Choose a wallet.');
      return;
    }
    if (draft.type.isTransfer) {
      if ((draft.toWalletId ?? '').isEmpty) {
        showAppMessage(context, 'Choose the wallet the money is going to.');
        return;
      }
      if (draft.toWalletId == draft.walletId) {
        showAppMessage(
          context,
          'Source and destination wallets must be different.',
        );
        return;
      }
    }

    setState(() => _saving = true);
    final service = ref.read(transactionServiceProvider);
    final undo = ref.read(undoServiceProvider);
    final existing = widget.existing;

    try {
      if (existing == null) {
        final id = await service.create(draft, allowDuplicate: allowDuplicate);
        undo.push(
          description: '${draft.summary()} saved',
          undo: () => service.delete(id),
        );
        await ref.read(alertServiceProvider).announceBudgetAlerts();
        if (!mounted) return;
        showUndoSnackBar(context, ref, '${draft.summary()} saved');
        context.pop(true);
        return;
      }

      final previous = _draftFrom(existing);
      await service.update(existing.id, draft);
      undo.push(
        description: '${draft.summary()} updated',
        undo: () => service.update(existing.id, previous),
      );
      await ref.read(alertServiceProvider).announceBudgetAlerts();
      if (!mounted) return;
      showUndoSnackBar(context, ref, '${draft.summary()} updated');
      context.pop(true);
    } on DuplicateTransactionException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      final anyway = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save this again?'),
          content: Text(error.message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No, cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes, save it'),
            ),
          ],
        ),
      );
      if (anyway == true) {
        await _save(allowDuplicate: true);
      }
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallets = ref.watch(activeWalletBalancesProvider);
    final walletList = wallets.value ?? const <WalletBalance>[];
    final suggestions =
        ref.watch(frequentTagsProvider).value ?? const <String>[];

    final categoryAsync = _type.isIncome
        ? ref.watch(incomeCategoriesProvider)
        : ref.watch(expenseCategoriesProvider);
    final categories = categoryAsync.value ?? const <CategoryRow>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit transaction' : 'New transaction'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          TransactionTypeSelector(
            value: _type,
            onChanged: (value) => setState(() {
              _type = value;
              // A category belongs to one kind only, so a type switch must not
              // leave a stale id behind.
              _categoryId = null;
              if (!value.isTransfer) _toWalletId = null;
              if (value.isTransfer) _feePoisha = 0;
            }),
          ),
          const SizedBox(height: 20),
          AmountField(
            controller: _amount,
            autofocus: !_isEditing,
            label: _type.isTransfer ? 'Amount to move' : 'Amount',
            onChanged: (poisha) => _amountPoisha = poisha ?? 0,
          ),
          const SizedBox(height: 16),
          WalletPickerField(
            wallets: walletList,
            value: _walletId,
            label: _type.isIncome
                ? 'Wallet the money arrived in'
                : (_type.isTransfer ? 'From wallet' : 'Wallet'),
            onChanged: (value) => setState(() {
              _walletId = value;
              if (_toWalletId == value) _toWalletId = null;
            }),
          ),
          if (_type.isTransfer) ...<Widget>[
            const SizedBox(height: 16),
            WalletPickerField(
              wallets: walletList,
              value: _toWalletId,
              label: 'To wallet',
              exclude: _walletId,
              helperText:
                  'A transfer is recorded once and moves money between your '
                  'own wallets. It is never counted as income or expense.',
              onChanged: (value) => setState(() => _toWalletId = value),
            ),
            const SizedBox(height: 16),
            AmountField(
              controller: _fee,
              label: 'Transfer fee (optional)',
              helperText:
                  'A cash-out charge becomes its own expense entry under '
                  'Fees & Charges, so it appears in your spending exactly '
                  'once.',
              onChanged: (poisha) => _feePoisha = poisha ?? 0,
            ),
          ] else ...<Widget>[
            const SizedBox(height: 16),
            FormDropdown<String?>(
              label: 'Category',
              value: _categoryId,
              prefixIcon: Icons.category_outlined,
              helperText: _type.isIncome
                  ? 'What kind of income this is.'
                  : 'What the money was spent on.',
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('No category (uncategorised)'),
                ),
                for (final category in categories)
                  DropdownMenuItem<String?>(
                    value: category.id,
                    child: Row(
                      children: <Widget>[
                        Icon(
                          CategoryIcons.resolve(category.iconName),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            category.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            ),
          ],
          const SizedBox(height: 16),
          DateFieldButton(
            value: _occurredAt,
            label: 'When',
            includeTime: true,
            onChanged: (value) => setState(() => _occurredAt = value),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _description,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              helperText: 'For example “lunch at Karim’s” or “March salary”.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          if (!_type.isTransfer) ...<Widget>[
            const SizedBox(height: 16),
            TextField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'Tags (optional)',
                helperText: 'Comma separated, for grouping things yourself.',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (suggestions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final tag in suggestions.take(6))
                    ActionChip(
                      label: Text(tag),
                      onPressed: () {
                        final current = _parsedTags;
                        if (current.contains(tag)) return;
                        _tags.text = <String>[...current, tag].join(', ');
                        setState(() {});
                      },
                    ),
                ],
              ),
            ],
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : () => _save(),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_isEditing ? 'Save changes' : 'Save transaction'),
          ),
          const SizedBox(height: 12),
          Text(
            _type.isTransfer
                ? 'Your wallet balances change, your income and expense totals '
                      'do not.'
                : 'Balances and reports update immediately, and you can undo '
                      'straight after saving.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
