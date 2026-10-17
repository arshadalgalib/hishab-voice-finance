import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../domain/enums.dart';
import '../../../domain/models/aggregates.dart';
import '../../../domain/models/transaction_draft.dart';
import '../application/voice_controller.dart';
import '../domain/voice_parse_result.dart';

/// Voice-first transaction entry.
///
/// ## The promise this screen keeps
/// The recogniser and the parser never write anything. They only *propose* a
/// transaction. A record reaches the ledger only after the user has seen the
/// parsed result on the confirmation form and pressed save — low confidence
/// means more fields are marked "please check", never an automatic save.
class VoiceCaptureScreen extends ConsumerStatefulWidget {
  const VoiceCaptureScreen({super.key});

  @override
  ConsumerState<VoiceCaptureScreen> createState() => _VoiceCaptureScreenState();
}

class _VoiceCaptureScreenState extends ConsumerState<VoiceCaptureScreen> {
  final TextEditingController _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  VoiceController get _controller => ref.read(voiceControllerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(voiceControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice entry'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Voice settings',
            icon: const Icon(Icons.tune),
            onPressed: () => context.push('/settings/voice'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          _MicrophonePanel(session: session, onToggle: _toggleListening),
          if (!session.speechAvailable) ...<Widget>[
            const SizedBox(height: 12),
            _Notice(
              icon: Icons.mic_off_outlined,
              text:
                  'The microphone is not available here. You can still type a '
                  'transaction below — it goes through exactly the same parser.',
            ),
          ],
          if (session.transcript.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            SectionCard(
              title: 'What was heard',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '“${session.transcript.trim()}”',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (session.onlineUsed) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      'Part of this was interpreted by your online endpoint. '
                      'The text was sent to the endpoint you configured; no '
                      'audio left the device.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _TypedFallback(
            controller: _typed,
            enabled: !session.phase.isBusy,
            onSubmit: _submitTyped,
          ),
          const SizedBox(height: 20),
          _PhaseBody(
            session: session,
            onChanged: _controller.applyDraft,
            onSave: () => _controller.confirm(),
            onSaveAnyway: () => _controller.confirm(allowDuplicate: true),
            onDiscard: _controller.reset,
            onRetry: _controller.reset,
            onUndo: _undoLast,
          ),
        ],
      ),
    );
  }

  void _toggleListening() {
    final phase = ref.read(voiceControllerProvider).phase;
    if (phase == VoicePhase.listening) {
      _controller.stopListening();
    } else if (!phase.isBusy) {
      _controller.startListening();
    }
  }

  void _submitTyped() {
    final text = _typed.text.trim();
    if (text.isEmpty) {
      showAppMessage(context, 'Type what you spent or received first.');
      return;
    }
    FocusScope.of(context).unfocus();
    _controller.interpret(text);
  }

  /// Reverses the transaction that was just saved and returns to the start.
  ///
  /// The saved id is registered with [UndoService] by `VoiceController.confirm`;
  /// this only exposes it. Undo can legitimately fail (the window closed), so
  /// the result is reported instead of assumed.
  Future<void> _undoLast() async {
    final undone = await ref.read(undoServiceProvider).undo();
    if (!mounted) return;
    _controller.reset();
    showAppMessage(
      context,
      undone ? 'Undone.' : 'That can no longer be undone.',
    );
  }
}

/// The large, phase-aware microphone control.
class _MicrophonePanel extends StatelessWidget {
  const _MicrophonePanel({required this.session, required this.onToggle});

  final VoiceSessionState session;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phase = session.phase;
    final listening = phase == VoicePhase.listening;
    final busy = phase.isBusy;

    return Column(
      children: <Widget>[
        const SizedBox(height: 8),
        IconButton.filled(
          onPressed: session.speechAvailable ? onToggle : null,
          iconSize: 56,
          tooltip: listening ? 'Stop listening' : 'Start listening',
          style: IconButton.styleFrom(
            minimumSize: const Size(132, 132),
            shape: const CircleBorder(),
            backgroundColor: listening
                ? theme.colorScheme.errorContainer
                : null,
            foregroundColor: listening
                ? theme.colorScheme.onErrorContainer
                : null,
          ),
          icon: Icon(listening ? Icons.stop : Icons.mic_none),
        ),
        const SizedBox(height: 14),
        Text(
          phase.label,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (busy && !listening) ...<Widget>[
          const SizedBox(height: 12),
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          session.speechAvailable
              ? 'Say something like “বিকাশ থেকে ৫০০ টাকা খাবার খরচ” or “500 taka '
                    'lunch at Karim\'s”.'
              : 'Type the transaction below.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Keyboard entry that feeds the same parser as the microphone.
class _TypedFallback extends StatelessWidget {
  const _TypedFallback({
    required this.controller,
    required this.enabled,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            textInputAction: TextInputAction.done,
            minLines: 1,
            maxLines: 3,
            onSubmitted: (_) => onSubmit(),
            decoration: const InputDecoration(
              labelText: 'Type instead',
              hintText: 'e.g. 500 taka lunch from bKash',
              prefixIcon: Icon(Icons.keyboard_alt_outlined),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: IconButton.filled(
            onPressed: enabled ? onSubmit : null,
            tooltip: 'Understand this text',
            icon: const Icon(Icons.arrow_forward),
          ),
        ),
      ],
    );
  }
}

/// Renders the region below the microphone for the current phase.
class _PhaseBody extends StatelessWidget {
  const _PhaseBody({
    required this.session,
    required this.onChanged,
    required this.onSave,
    required this.onSaveAnyway,
    required this.onDiscard,
    required this.onRetry,
    required this.onUndo,
  });

  final VoiceSessionState session;
  final ValueChanged<TransactionDraft> onChanged;
  final VoidCallback onSave;
  final VoidCallback onSaveAnyway;
  final VoidCallback onDiscard;
  final VoidCallback onRetry;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    switch (session.phase) {
      case VoicePhase.awaitingConfirmation:
        final draft = session.draft;
        if (draft == null) return const SizedBox.shrink();
        return _VoiceConfirmationForm(
          // Keyed by the transcript so a *new* interpretation reseeds the form,
          // while editing the current one does not wipe the user's input.
          key: ValueKey<String>('confirm:${session.transcript}'),
          initial: draft,
          unresolved: session.unresolved,
          warnings: session.warnings,
          duplicateMessage: session.duplicateAwaitingConfirmation
              ? session.message
              : null,
          onChanged: onChanged,
          onSave: onSave,
          onSaveAnyway: onSaveAnyway,
          onDiscard: onDiscard,
        );
      case VoicePhase.completed:
        return _CompletedPanel(
          session: session,
          onRecordAnother: onDiscard,
          onUndo: onUndo,
        );
      case VoicePhase.failed:
        return _FailedPanel(message: session.message, onRetry: onRetry);
      case VoicePhase.idle:
      case VoicePhase.listening:
      case VoicePhase.transcribing:
      case VoicePhase.interpreting:
      case VoicePhase.saving:
        return const SizedBox.shrink();
    }
  }
}

/// Confirmation form: everything the app understood, editable, with the fields
/// it is unsure about flagged rather than hidden.
class _VoiceConfirmationForm extends ConsumerStatefulWidget {
  const _VoiceConfirmationForm({
    super.key,
    required this.initial,
    required this.unresolved,
    required this.warnings,
    required this.duplicateMessage,
    required this.onChanged,
    required this.onSave,
    required this.onSaveAnyway,
    required this.onDiscard,
  });

  final TransactionDraft initial;
  final Set<VoiceField> unresolved;
  final List<String> warnings;
  final String? duplicateMessage;
  final ValueChanged<TransactionDraft> onChanged;
  final VoidCallback onSave;
  final VoidCallback onSaveAnyway;
  final VoidCallback onDiscard;

  @override
  ConsumerState<_VoiceConfirmationForm> createState() =>
      _VoiceConfirmationFormState();
}

class _VoiceConfirmationFormState
    extends ConsumerState<_VoiceConfirmationForm> {
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
  late int _amountPoisha;
  late int _feePoisha;

  @override
  void initState() {
    super.initState();
    final draft = widget.initial;
    _type = draft.type;
    _walletId = draft.walletId.isEmpty ? null : draft.walletId;
    _toWalletId = draft.toWalletId;
    _categoryId = draft.categoryId;
    _occurredAt = draft.occurredAt;
    _amountPoisha = draft.amountPoisha;
    _feePoisha = draft.feePoisha;

    _amount = TextEditingController(text: _editableAmount(draft.amountPoisha));
    _fee = TextEditingController(text: _editableAmount(draft.feePoisha));
    _description = TextEditingController(text: draft.description ?? '');
    _note = TextEditingController(text: draft.note ?? '');
    _tags = TextEditingController(text: draft.tags.join(', '));
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

  /// A blank string for zero, so an unresolved amount is an empty field rather
  /// than a misleading "0".
  static String _editableAmount(int poisha) {
    if (poisha <= 0) return '';
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
        amountPoisha: _amountPoisha,
        fromWalletId: _walletId ?? '',
        toWalletId: _toWalletId ?? '',
        occurredAt: _occurredAt,
        description: description,
        note: note,
        feePoisha: _feePoisha,
        source: TransactionSource.voice,
      );
    }
    return TransactionDraft(
      type: _type,
      amountPoisha: _amountPoisha,
      walletId: _walletId ?? '',
      categoryId: _categoryId,
      occurredAt: _occurredAt,
      description: description,
      note: note,
      tags: _parsedTags,
      source: TransactionSource.voice,
    );
  }

  void _notify() => widget.onChanged(_buildDraft());

  bool _isFlagged(VoiceField field) => widget.unresolved.contains(field);

  String? _flagText(VoiceField field, String message) =>
      _isFlagged(field) ? message : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallets =
        ref.watch(activeWalletBalancesProvider).value ??
        const <WalletBalance>[];
    final categoryAsync = _type.isIncome
        ? ref.watch(incomeCategoriesProvider)
        : ref.watch(expenseCategoriesProvider);
    final categories = categoryAsync.value ?? const <CategoryRow>[];

    final needsAttention = widget.unresolved.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (needsAttention) ...<Widget>[
          _Notice(
            icon: Icons.checklist_rtl,
            tone: _NoticeTone.warning,
            text:
                'A few things need a quick check before saving: '
                '${widget.unresolved.map((field) => field.label).join(', ')}.',
          ),
          const SizedBox(height: 12),
        ],
        if (widget.duplicateMessage != null) ...<Widget>[
          _DuplicateBanner(
            message: widget.duplicateMessage!,
            onSaveAnyway: widget.onSaveAnyway,
          ),
          const SizedBox(height: 12),
        ],
        for (final warning in widget.warnings) ...<Widget>[
          _Notice(icon: Icons.info_outline, text: warning),
          const SizedBox(height: 8),
        ],
        if (widget.warnings.isNotEmpty) const SizedBox(height: 4),
        SectionCard(
          title: 'Check and confirm',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TransactionTypeSelector(
                value: _type,
                onChanged: (value) => setState(() {
                  _type = value;
                  // A category belongs to one kind only; a transfer has none.
                  _categoryId = null;
                  if (!value.isTransfer) _toWalletId = null;
                  if (value.isTransfer) _feePoisha = 0;
                  _notify();
                }),
              ),
              const SizedBox(height: 16),
              AmountField(
                controller: _amount,
                label: _type.isTransfer ? 'Amount to move' : 'Amount',
                autofocus: _isFlagged(VoiceField.amount),
                errorText: _flagText(
                  VoiceField.amount,
                  'We could not hear a clear amount. Please enter it.',
                ),
                onChanged: (poisha) {
                  _amountPoisha = poisha ?? 0;
                  _notify();
                },
              ),
              const SizedBox(height: 16),
              WalletPickerField(
                wallets: wallets,
                value: _walletId,
                label: _type.isIncome
                    ? 'Wallet the money arrived in'
                    : (_type.isTransfer ? 'From wallet' : 'Wallet'),
                errorText: _flagText(
                  VoiceField.wallet,
                  'Which wallet was this?',
                ),
                onChanged: (value) {
                  setState(() {
                    _walletId = value;
                    if (_toWalletId == value) _toWalletId = null;
                  });
                  _notify();
                },
              ),
              if (_type.isTransfer) ...<Widget>[
                const SizedBox(height: 16),
                WalletPickerField(
                  wallets: wallets,
                  value: _toWalletId,
                  label: 'To wallet',
                  exclude: _walletId,
                  errorText: _flagText(
                    VoiceField.destinationWallet,
                    'Which wallet did the money go to?',
                  ),
                  onChanged: (value) {
                    setState(() => _toWalletId = value);
                    _notify();
                  },
                ),
                const SizedBox(height: 16),
                AmountField(
                  controller: _fee,
                  label: 'Transfer fee (optional)',
                  helperText:
                      'A cash-out charge becomes its own expense entry under '
                      'Fees & Charges.',
                  onChanged: (poisha) {
                    _feePoisha = poisha ?? 0;
                    _notify();
                  },
                ),
              ] else ...<Widget>[
                const SizedBox(height: 16),
                FormDropdown<String?>(
                  label: 'Category',
                  value: _categoryId,
                  prefixIcon: Icons.category_outlined,
                  errorText: _flagText(
                    VoiceField.category,
                    'Pick a category, or leave it uncategorised.',
                  ),
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
                  onChanged: (value) {
                    setState(() => _categoryId = value);
                    _notify();
                  },
                ),
              ],
              const SizedBox(height: 16),
              DateFieldButton(
                value: _occurredAt,
                label: 'When',
                includeTime: true,
                onChanged: (value) {
                  setState(() => _occurredAt = value);
                  _notify();
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
                onChanged: (_) => _notify(),
              ),
              if (!_type.isTransfer) ...<Widget>[
                const SizedBox(height: 16),
                TextField(
                  controller: _tags,
                  decoration: const InputDecoration(
                    labelText: 'Tags (optional)',
                    helperText: 'Comma separated.',
                  ),
                  onChanged: (_) => _notify(),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
                onChanged: (_) => _notify(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _canSave ? widget.onSave : null,
          icon: const Icon(Icons.check),
          label: const Text('Save transaction'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: widget.onDiscard,
          icon: const Icon(Icons.close),
          label: const Text('Discard and start over'),
        ),
        const SizedBox(height: 12),
        Text(
          _type.isTransfer
              ? 'Your wallet balances change; income and expense totals do not.'
              : 'Nothing is saved until you press save. You can undo straight '
                    'afterwards.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// A draft is only savable once the fields the ledger cannot invent are
  /// present. This mirrors `TransactionService.validate` but lets the form
  /// explain the problem before the service throws.
  bool get _canSave {
    if (_amountPoisha <= 0) return false;
    if ((_walletId ?? '').isEmpty) return false;
    if (_type.isTransfer) {
      if ((_toWalletId ?? '').isEmpty) return false;
      if (_toWalletId == _walletId) return false;
    }
    return true;
  }
}

class _CompletedPanel extends StatelessWidget {
  const _CompletedPanel({
    required this.session,
    required this.onRecordAnother,
    required this.onUndo,
  });

  final VoiceSessionState session;
  final VoidCallback onRecordAnother;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final id = session.savedTransactionId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Notice(
          icon: Icons.check_circle_outline,
          tone: _NoticeTone.success,
          text: session.message ?? 'Saved.',
        ),
        const SizedBox(height: 16),
        if (id != null)
          FilledButton.icon(
            onPressed: () => context.push('/transactions/$id'),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('View transaction'),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onUndo,
          icon: const Icon(Icons.undo),
          label: const Text('Undo'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onRecordAnother,
          icon: const Icon(Icons.mic_none),
          label: const Text('Record another'),
        ),
      ],
    );
  }
}

class _FailedPanel extends StatelessWidget {
  const _FailedPanel({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Notice(
          icon: Icons.error_outline,
          tone: _NoticeTone.warning,
          text: message ?? 'That did not work. Please try again.',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}

/// Shown when a probable duplicate was found; saving anyway is an explicit
/// choice, never a default.
class _DuplicateBanner extends StatelessWidget {
  const _DuplicateBanner({required this.message, required this.onSaveAnyway});

  final String message;
  final VoidCallback onSaveAnyway;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.content_copy,
                color: theme.colorScheme.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Possible duplicate',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: onSaveAnyway,
              child: const Text('Save it anyway'),
            ),
          ),
        ],
      ),
    );
  }
}

enum _NoticeTone { neutral, warning, success }

/// A short inline message. Uses colour *and* an icon so it reads without colour.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    this.tone = _NoticeTone.neutral,
  });

  final IconData icon;
  final String text;
  final _NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, foreground) = switch (tone) {
      _NoticeTone.warning => (
        theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        theme.colorScheme.onErrorContainer,
      ),
      _NoticeTone.success => (
        theme.colorScheme.secondaryContainer,
        theme.colorScheme.onSecondaryContainer,
      ),
      _NoticeTone.neutral => (
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
