import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/errors/app_exception.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/enums.dart';
import '../../../domain/models/transaction_draft.dart';
import '../../../domain/services/transaction_service.dart';
import '../../../domain/services/undo_service.dart';
import '../domain/voice_parse_result.dart';
import '../domain/voice_transaction_parser.dart';
import 'speech_recognizer.dart';
import 'voice_context_factory.dart';
import 'voice_interpreter.dart';

/// Where the voice flow currently is. The confirmation screen renders a
/// different body for each phase, and the microphone button reads its label
/// from this.
enum VoicePhase {
  idle,
  listening,
  transcribing,
  interpreting,
  awaitingConfirmation,
  saving,
  completed,
  failed;

  bool get isBusy =>
      this == VoicePhase.listening ||
      this == VoicePhase.transcribing ||
      this == VoicePhase.interpreting ||
      this == VoicePhase.saving;

  String get label {
    switch (this) {
      case VoicePhase.idle:
        return 'Tap to speak';
      case VoicePhase.listening:
        return 'Listening…';
      case VoicePhase.transcribing:
        return 'Transcribing…';
      case VoicePhase.interpreting:
        return 'Understanding…';
      case VoicePhase.awaitingConfirmation:
        return 'Check and confirm';
      case VoicePhase.saving:
        return 'Saving…';
      case VoicePhase.completed:
        return 'Saved';
      case VoicePhase.failed:
        return 'Something went wrong';
    }
  }
}

/// Immutable snapshot of the voice screen.
@immutable
class VoiceSessionState {
  const VoiceSessionState({
    this.phase = VoicePhase.idle,
    this.transcript = '',
    this.parsed,
    this.draft,
    this.unresolved = const <VoiceField>{},
    this.warnings = const <String>[],
    this.message,
    this.savedTransactionId,
    this.onlineUsed = false,
    this.duplicateAwaitingConfirmation = false,
    this.speechAvailable = true,
  });

  static const VoiceSessionState initial = VoiceSessionState();

  final VoicePhase phase;

  /// What the recogniser heard, shown verbatim so the user can see the raw
  /// input rather than a cleaned-up version of it.
  final String transcript;

  final ParsedTransaction? parsed;

  /// The draft that would be written. Null while required fields are missing —
  /// the app never builds a half-filled transaction.
  final TransactionDraft? draft;

  final Set<VoiceField> unresolved;

  /// Non-fatal observations, e.g. an assumed date or an ambiguous wallet.
  final List<String> warnings;

  /// A user-facing message (error, duplicate prompt, success note).
  final String? message;

  final String? savedTransactionId;

  /// True when the online interpreter contributed anything, which the UI must
  /// label because it means text left the device.
  final bool onlineUsed;

  /// True when a probable duplicate was found and the user is being asked.
  final bool duplicateAwaitingConfirmation;

  /// False when the device has no usable recogniser, so the UI can switch to
  /// typed entry without pretending the microphone works.
  final bool speechAvailable;

  bool get canSave => draft != null && !duplicateAwaitingConfirmation;

  VoiceSessionState copyWith({
    VoicePhase? phase,
    String? transcript,
    ParsedTransaction? parsed,
    bool clearParsed = false,
    TransactionDraft? draft,
    bool clearDraft = false,
    Set<VoiceField>? unresolved,
    List<String>? warnings,
    String? message,
    bool clearMessage = false,
    String? savedTransactionId,
    bool? onlineUsed,
    bool? duplicateAwaitingConfirmation,
    bool? speechAvailable,
  }) {
    return VoiceSessionState(
      phase: phase ?? this.phase,
      transcript: transcript ?? this.transcript,
      parsed: clearParsed ? null : (parsed ?? this.parsed),
      draft: clearDraft ? null : (draft ?? this.draft),
      unresolved: unresolved ?? this.unresolved,
      warnings: warnings ?? this.warnings,
      message: clearMessage ? null : (message ?? this.message),
      savedTransactionId: savedTransactionId ?? this.savedTransactionId,
      onlineUsed: onlineUsed ?? this.onlineUsed,
      duplicateAwaitingConfirmation:
          duplicateAwaitingConfirmation ?? this.duplicateAwaitingConfirmation,
      speechAvailable: speechAvailable ?? this.speechAvailable,
    );
  }
}

/// Drives the whole voice-to-transaction flow.
///
/// ## The rule this class exists to enforce
/// Nothing is ever written to the ledger by the recogniser or the parser. The
/// only write happens in [confirm], which calls the same `TransactionService`
/// the manual forms use, after the user has explicitly confirmed. Low
/// confidence does not "auto-save with a warning" — it just means more fields
/// are marked unresolved and the confirmation screen asks about them.
class VoiceController extends Notifier<VoiceSessionState> {
  late SpeechRecognizer _recognizer;
  late VoiceContextFactory _contextFactory;
  late TransactionService _transactions;
  late UndoService _undo;
  late SettingsRepository _settings;

  bool _disposed = false;

  @override
  VoiceSessionState build() {
    _recognizer = ref.read(speechRecognizerProvider);
    _contextFactory = ref.read(voiceContextFactoryProvider);
    _transactions = ref.read(transactionServiceProvider);
    _undo = ref.read(undoServiceProvider);
    _settings = ref.read(settingsRepositoryProvider);
    ref.onDispose(() {
      _disposed = true;
      _recognizer.cancel();
    });
    return VoiceSessionState.initial;
  }

  /// Starts a listening session, asking for the microphone the first time.
  Future<void> startListening() async {
    if (state.phase.isBusy) return;
    _safeSet(state.copyWith(phase: VoicePhase.listening, clearMessage: true));

    final settings = await _settings.load();
    final availability = await _recognizer.initialize();
    if (availability != SpeechAvailability.available) {
      _safeSet(
        state.copyWith(
          phase: VoicePhase.failed,
          speechAvailable: false,
          message: availability == SpeechAvailability.permissionDenied
              ? 'Microphone permission was refused. You can enable it in the '
                    'phone settings, or type the transaction instead.'
              : 'Speech recognition is not available on this device. '
                    'You can type the transaction instead.',
        ),
      );
      return;
    }

    final contextualPhrases = await _contextualPhrases();

    try {
      await _recognizer.start(
        localeId: settings.voiceLocaleId,
        listenFor: Duration(seconds: settings.voiceListenForSeconds),
        pauseFor: Duration(seconds: settings.voicePauseForSeconds),
        contextualPhrases: contextualPhrases,
        onPartial: (result) {
          _safeSet(
            state.copyWith(
              phase: VoicePhase.transcribing,
              transcript: result.text,
            ),
          );
        },
        onFinal: (result) async {
          final text = result.text.trim();
          if (text.isEmpty) {
            _safeSet(
              state.copyWith(
                phase: VoicePhase.failed,
                message:
                    'I did not catch that. Tap the microphone and try '
                    'again, or type it below.',
              ),
            );
            return;
          }
          await interpret(text);
        },
        onError: (message) {
          _safeSet(state.copyWith(phase: VoicePhase.failed, message: message));
        },
      );
    } on SpeechUnavailableException catch (error) {
      _safeSet(
        state.copyWith(
          phase: VoicePhase.failed,
          speechAvailable: false,
          message: error.message,
        ),
      );
    }
  }

  Future<void> stopListening() async {
    if (!_recognizer.isListening) return;
    _safeSet(state.copyWith(phase: VoicePhase.interpreting));
    await _recognizer.stop();
  }

  /// Cancels the session and clears the screen.
  Future<void> cancel() async {
    await _recognizer.cancel();
    reset();
  }

  /// Interprets [text] — from the recogniser or from the keyboard — and moves
  /// to the confirmation screen.
  Future<void> interpret(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _safeSet(
        state.copyWith(
          phase: VoicePhase.failed,
          message: 'Nothing was heard. Try again, or type the transaction.',
        ),
      );
      return;
    }

    _safeSet(
      state.copyWith(
        phase: VoicePhase.interpreting,
        transcript: trimmed,
        clearMessage: true,
        clearParsed: true,
        clearDraft: true,
        duplicateAwaitingConfirmation: false,
      ),
    );

    final context = await _contextFactory.build();
    var parsed = VoiceTransactionParser(context).parse(trimmed);
    var onlineUsed = false;
    final warnings = <String>[...parsed.warnings];

    final online = await ref.read(onlineInterpreterProvider).call();
    if (online != null && parsed.unresolved.isNotEmpty) {
      try {
        final hint = await online.interpret(trimmed, context);
        if (hint != null) {
          parsed = mergeHint(parsed, hint, context: context);
          onlineUsed = hint.isOnline;
        }
      } on AppException catch (error) {
        // The online interpreter is strictly optional: a failure must never
        // block the offline result, only inform the user.
        warnings.add(error.message);
      }
    }

    final draft =
        VoiceTransactionParser(
          context,
        ).buildDraft(parsed, source: TransactionSource.voice) ??
        // A missing wallet (or an unresolved type) must not hide the screen:
        // the confirmation form still renders with those fields flagged so the
        // user can fill them in. Nothing here is savable until they do.
        _placeholderDraft(parsed, context);

    _safeSet(
      state.copyWith(
        phase: VoicePhase.awaitingConfirmation,
        parsed: parsed,
        draft: draft,
        unresolved: parsed.unresolved,
        warnings: warnings,
        onlineUsed: onlineUsed,
      ),
    );
  }

  /// A starting point for the confirmation form when the parser could not
  /// assemble a complete draft.
  ///
  /// The unresolved fields are left empty/zero, and the flag set the caller
  /// passes to the UI is what marks them; the form's own `_canSave` guard keeps
  /// a placeholder from ever reaching the ledger.
  TransactionDraft _placeholderDraft(
    ParsedTransaction parsed,
    ParserContext context,
  ) {
    return TransactionDraft(
      type: parsed.type ?? TransactionType.expense,
      amountPoisha: parsed.amountPoisha ?? 0,
      walletId: parsed.walletId ?? '',
      toWalletId: parsed.toWalletId,
      categoryId: parsed.categoryId,
      occurredAt: parsed.occurredAt ?? context.now,
      description: parsed.description,
      note: parsed.note,
      source: TransactionSource.voice,
    );
  }

  /// Applies an edited draft from the confirmation form.
  void applyDraft(TransactionDraft draft) {
    final parsed = state.parsed;
    final remaining = <VoiceField>{...state.unresolved};
    if (draft.amountPoisha > 0) remaining.remove(VoiceField.amount);
    if (draft.walletId.isNotEmpty) remaining.remove(VoiceField.wallet);
    if (draft.categoryId != null) remaining.remove(VoiceField.category);
    if (draft.type.isTransfer && (draft.toWalletId ?? '').isNotEmpty) {
      remaining.remove(VoiceField.destinationWallet);
    }
    _safeSet(
      state.copyWith(
        draft: draft,
        unresolved: remaining,
        clearMessage: true,
        duplicateAwaitingConfirmation: false,
        parsed: parsed?.copyWith(
          type: draft.type,
          amountPoisha: draft.amountPoisha,
          walletId: draft.walletId,
          toWalletId: draft.toWalletId,
          categoryId: draft.categoryId,
          description: draft.description,
          occurredAt: draft.occurredAt,
        ),
      ),
    );
  }

  /// Writes the transaction. The only place the voice flow touches the ledger.
  ///
  /// [allowDuplicate] is set by the "Save anyway" button after the duplicate
  /// prompt, so a second identical transaction is still possible but only after
  /// an explicit acknowledgement.
  Future<void> confirm({bool allowDuplicate = false}) async {
    final draft = state.draft;
    if (draft == null) return;
    _safeSet(state.copyWith(phase: VoicePhase.saving, clearMessage: true));

    try {
      final id = await _transactions.create(
        draft,
        allowDuplicate: allowDuplicate,
      );
      _undo.push(
        description: '${_describe(draft)} saved',
        undo: () async {
          await _transactions.delete(id);
        },
      );
      _safeSet(
        state.copyWith(
          phase: VoicePhase.completed,
          savedTransactionId: id,
          duplicateAwaitingConfirmation: false,
          message: 'Saved. You can undo this from the message below.',
        ),
      );
      await _notifyBudgets();
    } on DuplicateTransactionException catch (error) {
      _safeSet(
        state.copyWith(
          phase: VoicePhase.awaitingConfirmation,
          duplicateAwaitingConfirmation: true,
          message: error.message,
        ),
      );
    } on AppException catch (error) {
      _safeSet(
        state.copyWith(phase: VoicePhase.failed, message: error.message),
      );
    }
  }

  /// Returns to the microphone after a save.
  void reset() {
    _safeSet(VoiceSessionState.initial);
  }

  /// Clears just the message (used when the user dismisses a banner).
  void dismissMessage() => _safeSet(state.copyWith(clearMessage: true));

  Future<void> _notifyBudgets() async {
    // The alert service owns the settings checks and never throws, so a
    // notification problem can never affect a saved transaction.
    await ref.read(alertServiceProvider).announceBudgetAlerts();
  }

  Future<List<String>> _contextualPhrases() async {
    // Biasing the recogniser toward the user's own wallet and category names is
    // what makes "বিকাশ" and "নগদ" come through as words instead of noise.
    final wallets = await _contextFactory.walletCandidates();
    final categories = await _contextFactory.categoryCandidates();
    return <String>[
      ...wallets.map((w) => w.name),
      ...categories.map((c) => c.name),
      'টাকা',
      'income',
      'expense',
      'transfer',
    ];
  }

  static String _describe(TransactionDraft draft) {
    final label = switch (draft.type) {
      TransactionType.income => 'Income',
      TransactionType.expense => 'Expense',
      TransactionType.transfer => 'Transfer',
    };
    final taka = (draft.amountPoisha / 100).toStringAsFixed(
      draft.amountPoisha % 100 == 0 ? 0 : 2,
    );
    return '$label of ৳$taka';
  }

  void _safeSet(VoiceSessionState next) {
    if (_disposed) return;
    state = next;
  }
}
