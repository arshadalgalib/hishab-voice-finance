import 'package:flutter/foundation.dart';

/// One reversible action offered through the snackbar.
class UndoEntry {
  UndoEntry({
    required this.id,
    required this.description,
    required this.createdAt,
    required this.undo,
  });

  final String id;

  /// Short, user-facing text, e.g. "Expense of ৳350 saved".
  final String description;
  final DateTime createdAt;
  final Future<void> Function() undo;

  bool isExpired(DateTime now, Duration window) =>
      now.difference(createdAt) > window;
}

/// Holds the most recent reversible action.
///
/// Only the *last* action is offered, matching the single "Undo" button in the
/// snackbar. The window is deliberately short: undoing yesterday's salary edit
/// without noticing would be worse than asking the user to do it from history.
///
/// Deleting a transaction is the case that matters most — `TransactionService`
/// returns the raw rows it removed, so an undo restores exactly what was there,
/// including a transfer's linked fee row.
class UndoService {
  UndoService({
    this.window = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration window;
  final DateTime Function() _now;

  final ValueNotifier<UndoEntry?> pendingNotifier = ValueNotifier<UndoEntry?>(
    null,
  );

  UndoEntry? get pending {
    final entry = pendingNotifier.value;
    if (entry == null) return null;
    if (entry.isExpired(_now(), window)) {
      pendingNotifier.value = null;
      return null;
    }
    return entry;
  }

  bool get canUndo => pending != null;

  /// Registers an action. Any previously pending action is discarded, because
  /// the snackbar can only ever show one.
  void push({
    required String description,
    required Future<void> Function() undo,
    String? id,
  }) {
    pendingNotifier.value = UndoEntry(
      id: id ?? 'undo-${_now().microsecondsSinceEpoch}',
      description: description,
      createdAt: _now(),
      undo: undo,
    );
  }

  /// Runs the pending undo. Returns false when there was nothing (or it had
  /// expired), so the caller can show a friendly message instead of nothing.
  Future<bool> undo() async {
    final entry = pending;
    if (entry == null) return false;
    pendingNotifier.value = null;
    await entry.undo();
    return true;
  }

  void clear() => pendingNotifier.value = null;

  void dispose() => pendingNotifier.dispose();
}
