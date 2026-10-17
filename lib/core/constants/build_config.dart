/// Compile-time configuration injected with `--dart-define`.
///
/// ## What belongs here (and what must not)
/// A `--dart-define` value is compiled *into* the app bundle and can be
/// extracted from the APK, so this class is deliberately limited to
/// **non-secret** values. The bearer token for the optional online interpreter
/// is **not** supported here: it is entered by the user at runtime and kept in
/// the platform keystore (see `SecureKeys.cloudSpeechToken`).
///
/// The only supported defines are optional *defaults* for the online
/// interpretation endpoint and its language code. They exist so an operator can
/// ship a custom build with the endpoint pre-filled; the feature still stays off
/// until the user enables it, and the token is still entered by hand.
///
/// ```bash
/// flutter build apk --release \
///   --dart-define=PFM_CLOUD_SPEECH_ENDPOINT=https://your-server.example/interpret \
///   --dart-define=PFM_CLOUD_SPEECH_LANGUAGE=bn-BD
/// ```
class BuildConfig {
  const BuildConfig._();

  /// Default online-interpretation endpoint, or an empty string when the app
  /// was built without one.
  static const String cloudSpeechEndpoint = String.fromEnvironment(
    'PFM_CLOUD_SPEECH_ENDPOINT',
  );

  /// Default language code sent with an online interpretation request.
  static const String cloudSpeechLanguage = String.fromEnvironment(
    'PFM_CLOUD_SPEECH_LANGUAGE',
    defaultValue: 'bn-BD',
  );

  /// Whether this build was compiled with a default endpoint.
  static bool get hasCloudSpeechEndpoint =>
      cloudSpeechEndpoint.trim().isNotEmpty;

  /// Resolves the endpoint actually used: the value the user configured in
  /// Settings wins, otherwise the compile-time default, otherwise `null`.
  static String? resolveCloudSpeechEndpoint(String? configured) {
    final trimmed = configured?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return hasCloudSpeechEndpoint ? cloudSpeechEndpoint.trim() : null;
  }
}
