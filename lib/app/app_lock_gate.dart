import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/lock/presentation/lock_screen.dart';
import 'providers.dart';

/// Wraps the whole routed app and covers it with the lock screen when a PIN is
/// configured and the app has been away for longer than the auto-lock delay.
///
/// The child is *always* part of the tree — the lock is an overlay, not a
/// replacement — so locking and unlocking never resets the navigation stack.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _checked = false;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_lockOnColdStart());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A PIN-protected install starts locked: reopening the app from the
  /// launcher must not reveal the previous screen.
  Future<void> _lockOnColdStart() async {
    final settings = ref.read(appSettingsProvider).value;
    if (settings == null) {
      if (mounted) setState(() => _checked = true);
      return;
    }
    if (!settings.appLockEnabled) {
      if (mounted) setState(() => _checked = true);
      return;
    }
    final hasPin = await ref.read(pinServiceProvider).hasPin();
    if (!mounted) return;
    setState(() {
      _checked = true;
      _locked = hasPin;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _leftAt ??= ref.read(clockProvider).now();
      case AppLifecycleState.resumed:
        final leftAt = _leftAt;
        _leftAt = null;
        if (leftAt == null || _locked) return;
        final settings = ref.read(appSettingsProvider).value;
        if (settings == null || !settings.appLockEnabled) return;
        final delay = Duration(minutes: settings.autoLockMinutes);
        final away = ref.read(clockProvider).now().difference(leftAt);
        if (settings.autoLockMinutes <= 0 || away >= delay) {
          setState(() => _locked = true);
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        if (_locked)
          Positioned.fill(
            child: LockScreen(
              onUnlocked: () => setState(() => _locked = false),
            ),
          ),
      ],
    );
  }

  /// Whether the cold-start check has completed. Exposed for tests.
  bool get isChecked => _checked;
}
