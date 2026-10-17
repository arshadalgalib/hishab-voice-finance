import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/labels.dart';
import '../../../app/providers.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/money.dart';
import '../../../data/local/app_database.dart';
import '../../../domain/enums.dart';

/// Creates or edits a wallet.
///
/// The opening balance is the one figure that is *not* derived from
/// transactions, so changing it is deliberately treated as an audited
/// correction rather than a silent edit.
class WalletFormScreen extends ConsumerStatefulWidget {
  const WalletFormScreen({super.key, this.walletId});

  final String? walletId;

  @override
  ConsumerState<WalletFormScreen> createState() => _WalletFormScreenState();
}

class _WalletFormScreenState extends ConsumerState<WalletFormScreen> {
  @override
  Widget build(BuildContext context) {
    final walletId = widget.walletId;
    if (walletId == null) {
      return const _WalletForm(wallet: null);
    }
    return FutureBuilder<WalletRow?>(
      future: ref.read(walletRepositoryProvider).find(walletId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: const Text('Edit wallet')),
            body: const LoadingView(),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Edit wallet')),
            body: ErrorStateView(message: snapshot.error.toString()),
          );
        }
        final wallet = snapshot.data;
        if (wallet == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Edit wallet')),
            body: const EmptyState(
              icon: Icons.error_outline,
              title: 'That wallet no longer exists',
              message: 'It may have been deleted on another screen.',
            ),
          );
        }
        return _WalletForm(wallet: wallet);
      },
    );
  }
}

class _WalletForm extends ConsumerStatefulWidget {
  const _WalletForm({this.wallet});

  final WalletRow? wallet;

  @override
  ConsumerState<_WalletForm> createState() => _WalletFormState();
}

class _WalletFormState extends ConsumerState<_WalletForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _institution;
  late final TextEditingController _opening;
  late final TextEditingController _note;

  late WalletType _type;
  int? _colorValue;
  late bool _defaultIncome;
  late bool _defaultExpense;
  int? _openingPoisha;
  bool _saving = false;

  bool get _isEditing => widget.wallet != null;

  @override
  void initState() {
    super.initState();
    final wallet = widget.wallet;
    _name = TextEditingController(text: wallet?.name ?? '');
    _institution = TextEditingController(text: wallet?.institution ?? '');
    _opening = TextEditingController(
      text: wallet == null
          ? ''
          : (wallet.openingBalancePoisha == 0
                ? ''
                : Money(wallet.openingBalancePoisha).toStorageString()),
    );
    _note = TextEditingController(text: wallet?.note ?? '');
    _type = wallet?.type ?? WalletType.cash;
    _colorValue = wallet?.colorValue;
    _defaultIncome = wallet?.isDefaultIncome ?? false;
    _defaultExpense = wallet?.isDefaultExpense ?? false;
    _openingPoisha = wallet?.openingBalancePoisha ?? 0;
  }

  @override
  void dispose() {
    _name.dispose();
    _institution.dispose();
    _opening.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _name.text.trim();
    final opening = _openingPoisha ?? 0;
    if (opening < 0) {
      showAppMessage(context, 'An opening balance cannot be negative.');
      return;
    }

    setState(() => _saving = true);
    final repository = ref.read(walletRepositoryProvider);
    final institution = _institution.text.trim();
    final note = _note.text.trim();

    try {
      if (!_isEditing) {
        await repository.createWallet(
          name: name,
          type: _type,
          institution: institution.isEmpty ? null : institution,
          openingBalancePoisha: opening,
          colorValue: _colorValue,
          note: note.isEmpty ? null : note,
          isDefaultIncome: _defaultIncome,
          isDefaultExpense: _defaultExpense,
        );
      } else {
        final wallet = widget.wallet!;
        await repository.updateWallet(
          wallet.id,
          name: name,
          type: _type,
          institution: institution,
          colorValue: _colorValue,
          note: note,
        );
        if (opening != wallet.openingBalancePoisha) {
          await repository.adjustOpeningBalance(
            walletId: wallet.id,
            newOpeningBalancePoisha: opening,
            reason: 'Changed on the wallet form',
          );
        }
        await _applyDefault(
          repository,
          CategoryKind.income,
          wallet.isDefaultIncome,
          _defaultIncome,
          wallet.id,
        );
        await _applyDefault(
          repository,
          CategoryKind.expense,
          wallet.isDefaultExpense,
          _defaultExpense,
          wallet.id,
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

  Future<void> _applyDefault(
    dynamic repository,
    CategoryKind kind,
    bool was,
    bool now,
    String walletId,
  ) async {
    if (was == now) return;
    if (now) {
      await repository.setDefault(kind: kind, walletId: walletId);
    } else {
      await repository.clearDefault(kind);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit wallet' : 'New wallet')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                helperText: 'For example “Cash”, “bKash”, “City Bank”',
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'A name is required.' : null,
            ),
            const SizedBox(height: 16),
            FormDropdown<WalletType>(
              label: 'Type',
              value: _type,
              prefixIcon: WalletIcons.resolve(_type),
              items: <DropdownMenuItem<WalletType>>[
                for (final type in WalletType.values)
                  DropdownMenuItem<WalletType>(
                    value: type,
                    child: Row(
                      children: <Widget>[
                        Icon(WalletIcons.resolve(type), size: 18),
                        const SizedBox(width: 10),
                        Text(walletTypeLabel(type)),
                      ],
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _type = value);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _institution,
              decoration: const InputDecoration(
                labelText: 'Institution (optional)',
                helperText: 'The bank or provider, if it has one.',
              ),
            ),
            const SizedBox(height: 16),
            AmountField(
              controller: _opening,
              label: 'Opening balance',
              helperText: _isEditing
                  ? 'Changing this records an audited opening-balance '
                        'correction. Recorded transactions are not touched.'
                  : 'How much is in this wallet right now. It becomes the '
                        'starting point every balance is calculated from.',
              onChanged: (poisha) => _openingPoisha = poisha ?? 0,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'COLOUR',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  for (final value in kPickerColors)
                    GestureDetector(
                      onTap: () => setState(() => _colorValue = value),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Color(value),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _colorValue == value
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SectionCard(
              title: 'DEFAULTS',
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Column(
                children: <Widget>[
                  SwitchListTile(
                    value: _defaultIncome,
                    onChanged: (value) =>
                        setState(() => _defaultIncome = value),
                    title: const Text('Default wallet for income'),
                    subtitle: const Text(
                      'Used when you record income without naming a wallet.',
                    ),
                  ),
                  SwitchListTile(
                    value: _defaultExpense,
                    onChanged: (value) =>
                        setState(() => _defaultExpense = value),
                    title: const Text('Default wallet for expenses'),
                    subtitle: const Text(
                      'Used when you record an expense without naming a '
                      'wallet. Only one wallet can hold each default.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isEditing ? 'Save changes' : 'Create wallet'),
            ),
          ],
        ),
      ),
    );
  }
}
