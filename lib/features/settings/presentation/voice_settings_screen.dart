import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../domain/models/app_settings.dart';

/// Voice and notification preferences.
///
/// Only the fields [AppSettings] genuinely has are exposed: an offline/online
/// switch, the cloud endpoint, the language code, the on-device locale and the
/// notification switches. The API token is the single secret handled here, and
/// it is only ever written to (or deleted from) secure storage — never shown
/// back to the user.
class VoiceSettingsScreen extends ConsumerStatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  ConsumerState<VoiceSettingsScreen> createState() =>
      _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends ConsumerState<VoiceSettingsScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _endpointController = TextEditingController();
  final TextEditingController _languageController = TextEditingController();
  final TextEditingController _localeController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();

  /// Whether a token currently exists. The value itself is never read into a
  /// field or rendered.
  bool? _tokenSaved;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _refreshTokenState();
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _languageController.dispose();
    _localeController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _refreshTokenState() async {
    try {
      final token = await ref
          .read(secureStoreProvider)
          .read(SecureKeys.cloudSpeechToken);
      if (!mounted) return;
      setState(() => _tokenSaved = token != null && token.isNotEmpty);
    } on Exception {
      if (!mounted) return;
      setState(() => _tokenSaved = false);
    }
  }

  /// Copies the stored settings into the fields exactly once, so a later
  /// stream emission cannot overwrite what the user is typing.
  void _seed(AppSettings settings) {
    if (_seeded) return;
    _seeded = true;
    _endpointController.text = settings.cloudSpeechEndpoint ?? '';
    _languageController.text = settings.cloudSpeechLanguageCode;
    _localeController.text = settings.voiceLocaleId;
  }

  Future<void> _saveSettings() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final endpoint = _endpointController.text.trim();
    final language = _languageController.text.trim();
    final locale = _localeController.text.trim();
    try {
      await ref
          .read(settingsRepositoryProvider)
          .update(
            (current) => current.copyWith(
              cloudSpeechEndpoint: endpoint,
              clearCloudSpeechEndpoint: endpoint.isEmpty,
              cloudSpeechLanguageCode: language,
              voiceLocaleId: locale,
            ),
          );
      if (!mounted) return;
      showAppMessage(context, 'Voice settings saved.');
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    } on Exception {
      if (!mounted) return;
      showAppMessage(context, 'Could not save those settings.');
    }
  }

  Future<void> _writeProviderMode(bool online) async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .update(
            (current) =>
                current.copyWith(voiceProviderId: online ? 'cloud' : 'native'),
          );
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    }
  }

  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      showAppMessage(context, 'Enter the token first.');
      return;
    }
    try {
      await ref
          .read(secureStoreProvider)
          .write(SecureKeys.cloudSpeechToken, token);
      // Drop the copy the user typed; the value now lives only in secure
      // storage and is never shown again.
      _tokenController.clear();
      await _refreshTokenState();
      if (!mounted) return;
      showAppMessage(context, 'Token saved.');
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    } on Exception {
      if (!mounted) return;
      showAppMessage(context, 'Could not save the token on this device.');
    }
  }

  Future<void> _removeToken() async {
    try {
      await ref.read(secureStoreProvider).delete(SecureKeys.cloudSpeechToken);
      if (!mounted) return;
      setState(() => _tokenSaved = false);
      showAppMessage(context, 'Token removed.');
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    } on Exception {
      if (!mounted) return;
      showAppMessage(context, 'Could not remove the token.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice entry')),
      body: AsyncView<AppSettings>(
        value: ref.watch(appSettingsProvider),
        loadingMessage: 'Loading voice settings…',
        builder: (settings) {
          _seed(settings);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                SectionCard(
                  title: 'Interpretation mode',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: settings.voiceProviderId == 'cloud',
                        title: const Text('Online interpretation'),
                        subtitle: const Text(
                          'Sends the recognised text — never the audio — to '
                          'the endpoint you configure below.',
                        ),
                        onChanged: _writeProviderMode,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        onlineInterpretationActive(settings)
                            ? 'Online interpretation is active. On-device '
                                  'recognition still runs first.'
                            : 'Online interpretation is off. The app works '
                                  'fully offline.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Endpoint',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _endpointController,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Endpoint URL',
                          hintText: 'https://example.com/interpret',
                          helperText: 'Must start with http:// or https://',
                        ),
                        validator: _validateEndpoint,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _languageController,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Language code',
                          hintText: 'bn-BD',
                          helperText: 'Language sent with the transcript',
                        ),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Enter a language code.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _localeController,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'On-device recognition locale',
                          hintText: 'bn_BD',
                          helperText:
                              'Used by the offline recogniser, e.g. bn_BD',
                        ),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Enter a locale.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _saveSettings,
                        child: const Text('Save voice settings'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'API token',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _tokenSaved == null
                            ? 'Checking…'
                            : (_tokenSaved! ? 'Token saved' : 'No token saved'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _tokenController,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'New token',
                          helperText:
                              'Stored in this device’s secure storage; it is '
                              'never shown again.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: _saveToken,
                              child: const Text('Save token'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _removeToken,
                              child: const Text('Remove token'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Notifications',
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: settings.notificationsEnabled,
                        title: const Text('Notifications'),
                        subtitle: const Text('Allow the app to post alerts'),
                        onChanged: (value) => _writePreference(
                          (current) =>
                              current.copyWith(notificationsEnabled: value),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: settings.budgetAlertsEnabled,
                        title: const Text('Budget alerts'),
                        subtitle: const Text(
                          'Warn when a budget is nearly used up',
                        ),
                        onChanged: (value) => _writePreference(
                          (current) =>
                              current.copyWith(budgetAlertsEnabled: value),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: settings.reminderAlertsEnabled,
                        title: const Text('Reminder alerts'),
                        subtitle: const Text('Remind me when a bill is due'),
                        onChanged: (value) => _writePreference(
                          (current) =>
                              current.copyWith(reminderAlertsEnabled: value),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const SectionCard(
                  title: 'How this works',
                  child: Text(
                    'On-device recognition always runs first: your speech is '
                    'turned into text by the phone itself. Online mode only '
                    're-reads that transcript to fill in the details the '
                    'on-device parser could not work out. It never uploads your '
                    'audio, and it can only add fields the local parser left '
                    'empty — it never overrides anything you said. Leave it off '
                    'for a completely offline app.',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _writePreference(
    AppSettings Function(AppSettings current) transform,
  ) async {
    try {
      await ref.read(settingsRepositoryProvider).update(transform);
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    }
  }

  String? _validateEndpoint(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      return 'The URL must start with http:// or https://';
    }
    return null;
  }
}
