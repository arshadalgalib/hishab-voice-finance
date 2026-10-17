import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/security/pin_service.dart';
import '../../../domain/models/app_settings.dart';

/// PIN management and the app lock.
///
/// The PIN is never stored or shown: [PinService] keeps only a PBKDF2 verifier
/// in secure storage, and this screen only ever sends the typed value straight
/// to that service.
class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _currentController = TextEditingController();
  final TextEditingController _newController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _hasPin = false;
  bool _pinLoaded = false;

  @override
  void initState() {
    super.initState();
    _refreshPinState();
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _refreshPinState() async {
    final hasPin = await ref.read(pinServiceProvider).hasPin();
    if (!mounted) return;
    setState(() {
      _hasPin = hasPin;
      _pinLoaded = true;
    });
  }

  void _clearPinFields() {
    _currentController.clear();
    _newController.clear();
    _confirmController.clear();
  }

  Future<void> _setPin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      await ref.read(pinServiceProvider).setPin(_newController.text);
      // Setting a PIN is what turns the lock on.
      await ref
          .read(settingsRepositoryProvider)
          .update((current) => current.copyWith(appLockEnabled: true));
      _clearPinFields();
      await _refreshPinState();
      if (!mounted) return;
      showAppMessage(context, 'PIN set. The app lock is now on.');
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    } on Exception {
      if (!mounted) return;
      showAppMessage(context, 'Could not save the PIN on this device.');
    }
  }

  Future<void> _changePin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      await ref
          .read(pinServiceProvider)
          .changePin(
            currentPin: _currentController.text,
            newPin: _newController.text,
          );
      _clearPinFields();
      if (!mounted) return;
      showAppMessage(context, 'PIN changed.');
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    } on Exception {
      if (!mounted) return;
      showAppMessage(context, 'Could not change the PIN.');
    }
  }

  Future<void> _removePin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove PIN?'),
        content: const Text(
          'The app lock will be turned off. You can set a new PIN at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(pinServiceProvider).clearPin();
      await ref
          .read(settingsRepositoryProvider)
          .update((current) => current.copyWith(appLockEnabled: false));
      _clearPinFields();
      await _refreshPinState();
      if (!mounted) return;
      showAppMessage(context, 'PIN removed. The app lock is off.');
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    } on Exception {
      if (!mounted) return;
      showAppMessage(context, 'Could not remove the PIN.');
    }
  }

  Future<void> _writeLock(bool enabled) async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .update((current) => current.copyWith(appLockEnabled: enabled));
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_pinLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Security & lock')),
        body: const LoadingView(message: 'Checking app lock…'),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Security & lock')),
      body: AsyncView<AppSettings>(
        value: ref.watch(appSettingsProvider),
        loadingMessage: 'Loading security settings…',
        builder: (settings) => Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              SectionCard(
                title: 'App lock',
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.appLockEnabled,
                  title: const Text('Require the PIN when the app is reopened'),
                  subtitle: Text(
                    _hasPin
                        ? 'The lock is available because a PIN is set.'
                        : 'Set a PIN below to turn the lock on.',
                  ),
                  onChanged: (value) {
                    if (value && !_hasPin) {
                      showAppMessage(
                        context,
                        'Set a PIN first — the PIN is what turns the lock on.',
                      );
                      return;
                    }
                    _writeLock(value);
                  },
                ),
              ),
              const SizedBox(height: 16),
              if (!_hasPin) _buildSetPinCard() else _buildChangePinCard(),
              const SizedBox(height: 16),
              const SectionCard(
                title: 'What the lock does',
                child: Text(
                  'With the lock on, the app asks for your PIN every time it is '
                  'reopened, so someone holding your unlocked phone cannot '
                  'browse your finances. The PIN is kept only as a verifier on '
                  'this device — there is no way to look it up. If you forget '
                  'it, the password on your encrypted backup is unrecoverable '
                  'too, so keep an unencrypted copy of your data somewhere safe.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSetPinCard() {
    return SectionCard(
      title: 'Set a PIN',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pinField(
            controller: _newController,
            label: 'New PIN',
            validator: _validateNewPin,
          ),
          const SizedBox(height: 12),
          _pinField(
            controller: _confirmController,
            label: 'Confirm PIN',
            validator: _validateConfirmation,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _setPin, child: const Text('Set PIN')),
        ],
      ),
    );
  }

  Widget _buildChangePinCard() {
    return SectionCard(
      title: 'Change PIN',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pinField(
            controller: _currentController,
            label: 'Current PIN',
            validator: (value) => (value ?? '').length < PinService.minLength
                ? 'Enter your current PIN.'
                : null,
          ),
          const SizedBox(height: 12),
          _pinField(
            controller: _newController,
            label: 'New PIN',
            validator: _validateNewPin,
          ),
          const SizedBox(height: 12),
          _pinField(
            controller: _confirmController,
            label: 'Confirm new PIN',
            validator: _validateConfirmation,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _changePin, child: const Text('Change PIN')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _removePin,
            icon: const Icon(Icons.lock_open),
            label: const Text('Remove PIN'),
          ),
        ],
      ),
    );
  }

  Widget _pinField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(PinService.maxLength),
      ],
      decoration: InputDecoration(
        labelText: label,
        helperText: '${PinService.minLength}–${PinService.maxLength} digits',
      ),
      validator: validator,
    );
  }

  String? _validateNewPin(String? value) {
    final pin = value ?? '';
    if (pin.length < PinService.minLength) {
      return 'Use at least ${PinService.minLength} digits.';
    }
    if (RegExp(r'^(.)\1+$').hasMatch(pin)) {
      return 'Do not repeat a single digit.';
    }
    return null;
  }

  String? _validateConfirmation(String? value) {
    if ((value ?? '') != _newController.text) {
      return 'The two PINs do not match.';
    }
    return null;
  }
}
