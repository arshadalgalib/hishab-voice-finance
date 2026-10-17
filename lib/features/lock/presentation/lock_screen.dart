import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';

/// Full-screen PIN prompt.
///
/// Shown *over* the running app rather than instead of it, so the navigation
/// stack survives a lock/unlock cycle and the user returns to exactly where
/// they were.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  static const int _attemptsBeforeCooldown = 5;
  static const int _cooldownSeconds = 30;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String? _error;
  bool _checking = false;
  int _failures = 0;
  int _cooldownRemaining = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_checking || _cooldownRemaining > 0) return;
    final pin = _controller.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = 'Enter your PIN to continue.');
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
    });

    var unlocked = false;
    try {
      unlocked = await ref.read(pinServiceProvider).verify(pin);
    } catch (_) {
      // Secure storage can be unavailable (for example on a device whose
      // keystore was reset). That is a failed unlock, never a crash.
      unlocked = false;
    }
    if (!mounted) return;

    _controller.clear();
    if (unlocked) {
      widget.onUnlocked();
      return;
    }

    _failures += 1;
    setState(() {
      _checking = false;
      _error = 'That PIN is not correct.';
    });
    if (_failures >= _attemptsBeforeCooldown) {
      _startCooldown();
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() {
      _failures = 0;
      _cooldownRemaining = _cooldownSeconds;
      _error = 'Too many attempts. Wait $_cooldownSeconds seconds.';
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldownRemaining -= 1;
        if (_cooldownRemaining <= 0) {
          _cooldownRemaining = 0;
          _error = null;
          timer.cancel();
          _focusNode.requestFocus();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cooling = _cooldownRemaining > 0;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(20),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.lock_outline,
                      size: 56,
                      color: AppColors.seed,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hishab is locked',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your PIN to see your accounts.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    enabled: !cooling,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    maxLength: 12,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      counterText: '',
                      prefixIcon: const Icon(Icons.password),
                      errorText: _error,
                      helperText: cooling
                          ? 'Try again in $_cooldownRemaining s'
                          : null,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: cooling || _checking ? null : _submit,
                    icon: _checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_open),
                    label: Text(cooling ? 'Locked' : 'Unlock'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'The PIN protects the app screen only. It cannot be '
                    'recovered, and neither can an encrypted backup made with '
                    'a passphrase you have forgotten.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
