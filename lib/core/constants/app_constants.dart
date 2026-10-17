/// Storage keys and defaults for user preferences.
///
/// Only non-sensitive values live in this table. PIN hashes, biometric flags
/// and cloud credentials are stored through `flutter_secure_storage` instead.
class SettingKeys {
  const SettingKeys._();

  static const String onboardingCompleted = 'onboarding_completed';
  static const String seedVersion = 'seed_version';

  static const String defaultIncomeWalletId = 'default_income_wallet_id';
  static const String defaultExpenseWalletId = 'default_expense_wallet_id';

  static const String useBengaliDigits = 'use_bengali_digits';
  static const String bangladeshiGrouping = 'bangladeshi_grouping';
  static const String dateFormatStyle = 'date_format_style';
  static const String themeMode = 'theme_mode';
  static const String languageCode = 'language_code';

  static const String voiceLocaleId = 'voice_locale_id';
  static const String voiceProviderId = 'voice_provider_id';
  static const String voiceAutoConfirmThreshold =
      'voice_auto_confirm_threshold';
  static const String voiceListenForSeconds = 'voice_listen_for_seconds';
  static const String voicePauseForSeconds = 'voice_pause_for_seconds';
  static const String cloudSpeechEndpoint = 'cloud_speech_endpoint';
  static const String cloudSpeechLanguageCode = 'cloud_speech_language_code';

  static const String notificationsEnabled = 'notifications_enabled';
  static const String budgetAlertsEnabled = 'budget_alerts_enabled';
  static const String reminderAlertsEnabled = 'reminder_alerts_enabled';

  static const String appLockEnabled = 'app_lock_enabled';
  static const String biometricEnabled = 'biometric_enabled';
  static const String autoLockMinutes = 'auto_lock_minutes';

  static const String lastBackupAt = 'last_backup_at';
  static const String lastExportAt = 'last_export_at';

  /// Bumped whenever the built-in category / wallet templates change so the
  /// seeder can top up an existing install without duplicating rows.
  static const int currentSeedVersion = 1;
}

/// Values that are only ever stored in secure storage.
class SecureKeys {
  const SecureKeys._();

  static const String pinHash = 'pfm_pin_hash_v1';
  static const String pinSalt = 'pfm_pin_salt_v1';
  static const String cloudSpeechToken = 'pfm_cloud_speech_token_v1';
  static const String backupPassphraseHint = 'pfm_backup_passphrase_hint_v1';
}

class AppDefaults {
  const AppDefaults._();

  static const String currencySymbol = '\u09F3';
  static const String currencyCode = 'BDT';
  static const int decimalPlaces = 2;

  /// Confidence (0..1) at or above which the voice flow still *always* asks for
  /// confirmation, but shows fewer correction prompts. Nothing is ever saved
  /// without an explicit user confirmation.
  static const double voiceConfirmThreshold = 0.75;

  static const int voiceListenSeconds = 20;
  static const int voicePauseSeconds = 3;

  /// Default auto-lock delay in minutes.
  static const int autoLockMinutes = 5;
}
