import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

/// Immutable snapshot of every user preference.
///
/// The repository persists this as individual rows in `app_settings` so a
/// single corrupted value can never take down the whole settings screen.
@immutable
class AppSettings {
  const AppSettings({
    this.onboardingCompleted = false,
    this.seedVersion = 0,
    this.defaultIncomeWalletId,
    this.defaultExpenseWalletId,
    this.useBengaliDigits = false,
    this.bangladeshiGrouping = true,
    this.dateFormatStyle = 'd MMM yyyy',
    this.themeMode = ThemeMode.system,
    this.languageCode = 'en',
    this.voiceLocaleId = 'bn_BD',
    this.voiceProviderId = 'native',
    this.voiceAutoConfirmThreshold = AppDefaults.voiceConfirmThreshold,
    this.voiceListenForSeconds = AppDefaults.voiceListenSeconds,
    this.voicePauseForSeconds = AppDefaults.voicePauseSeconds,
    this.cloudSpeechEndpoint,
    this.cloudSpeechLanguageCode = 'bn-BD',
    this.notificationsEnabled = true,
    this.budgetAlertsEnabled = true,
    this.reminderAlertsEnabled = true,
    this.appLockEnabled = false,
    this.biometricEnabled = false,
    this.autoLockMinutes = AppDefaults.autoLockMinutes,
    this.lastBackupAt,
    this.lastExportAt,
  });

  static const AppSettings initial = AppSettings();

  final bool onboardingCompleted;
  final int seedVersion;
  final String? defaultIncomeWalletId;
  final String? defaultExpenseWalletId;
  final bool useBengaliDigits;
  final bool bangladeshiGrouping;
  final String dateFormatStyle;
  final ThemeMode themeMode;
  final String languageCode;

  /// Platform speech locale id, e.g. `bn_BD`, `bn_IN`, `en_US`.
  final String voiceLocaleId;

  /// `native` or `cloud`.
  final String voiceProviderId;

  final double voiceAutoConfirmThreshold;
  final int voiceListenForSeconds;
  final int voicePauseForSeconds;

  /// Base URL of a user-controlled backend that proxies cloud speech
  /// recognition. Never contains a credential: the token lives in secure
  /// storage and is attached as a bearer header at request time.
  final String? cloudSpeechEndpoint;
  final String cloudSpeechLanguageCode;

  final bool notificationsEnabled;
  final bool budgetAlertsEnabled;
  final bool reminderAlertsEnabled;
  final bool appLockEnabled;
  final bool biometricEnabled;
  final int autoLockMinutes;

  final DateTime? lastBackupAt;
  final DateTime? lastExportAt;

  bool get usesCloudSpeech =>
      voiceProviderId == 'cloud' &&
      cloudSpeechEndpoint != null &&
      cloudSpeechEndpoint!.trim().isNotEmpty;

  AppSettings copyWith({
    bool? onboardingCompleted,
    int? seedVersion,
    String? defaultIncomeWalletId,
    bool clearDefaultIncomeWallet = false,
    String? defaultExpenseWalletId,
    bool clearDefaultExpenseWallet = false,
    bool? useBengaliDigits,
    bool? bangladeshiGrouping,
    String? dateFormatStyle,
    ThemeMode? themeMode,
    String? languageCode,
    String? voiceLocaleId,
    String? voiceProviderId,
    double? voiceAutoConfirmThreshold,
    int? voiceListenForSeconds,
    int? voicePauseForSeconds,
    String? cloudSpeechEndpoint,
    bool clearCloudSpeechEndpoint = false,
    String? cloudSpeechLanguageCode,
    bool? notificationsEnabled,
    bool? budgetAlertsEnabled,
    bool? reminderAlertsEnabled,
    bool? appLockEnabled,
    bool? biometricEnabled,
    int? autoLockMinutes,
    DateTime? lastBackupAt,
    DateTime? lastExportAt,
  }) {
    return AppSettings(
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      seedVersion: seedVersion ?? this.seedVersion,
      defaultIncomeWalletId: clearDefaultIncomeWallet
          ? null
          : (defaultIncomeWalletId ?? this.defaultIncomeWalletId),
      defaultExpenseWalletId: clearDefaultExpenseWallet
          ? null
          : (defaultExpenseWalletId ?? this.defaultExpenseWalletId),
      useBengaliDigits: useBengaliDigits ?? this.useBengaliDigits,
      bangladeshiGrouping: bangladeshiGrouping ?? this.bangladeshiGrouping,
      dateFormatStyle: dateFormatStyle ?? this.dateFormatStyle,
      themeMode: themeMode ?? this.themeMode,
      languageCode: languageCode ?? this.languageCode,
      voiceLocaleId: voiceLocaleId ?? this.voiceLocaleId,
      voiceProviderId: voiceProviderId ?? this.voiceProviderId,
      voiceAutoConfirmThreshold:
          voiceAutoConfirmThreshold ?? this.voiceAutoConfirmThreshold,
      voiceListenForSeconds:
          voiceListenForSeconds ?? this.voiceListenForSeconds,
      voicePauseForSeconds: voicePauseForSeconds ?? this.voicePauseForSeconds,
      cloudSpeechEndpoint: clearCloudSpeechEndpoint
          ? null
          : (cloudSpeechEndpoint ?? this.cloudSpeechEndpoint),
      cloudSpeechLanguageCode:
          cloudSpeechLanguageCode ?? this.cloudSpeechLanguageCode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      budgetAlertsEnabled: budgetAlertsEnabled ?? this.budgetAlertsEnabled,
      reminderAlertsEnabled:
          reminderAlertsEnabled ?? this.reminderAlertsEnabled,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      lastExportAt: lastExportAt ?? this.lastExportAt,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'onboardingCompleted': onboardingCompleted,
    'seedVersion': seedVersion,
    'defaultIncomeWalletId': defaultIncomeWalletId,
    'defaultExpenseWalletId': defaultExpenseWalletId,
    'useBengaliDigits': useBengaliDigits,
    'bangladeshiGrouping': bangladeshiGrouping,
    'dateFormatStyle': dateFormatStyle,
    'themeMode': themeMode.name,
    'languageCode': languageCode,
    'voiceLocaleId': voiceLocaleId,
    'voiceProviderId': voiceProviderId,
    'voiceAutoConfirmThreshold': voiceAutoConfirmThreshold,
    'voiceListenForSeconds': voiceListenForSeconds,
    'voicePauseForSeconds': voicePauseForSeconds,
    'cloudSpeechEndpoint': cloudSpeechEndpoint,
    'cloudSpeechLanguageCode': cloudSpeechLanguageCode,
    'notificationsEnabled': notificationsEnabled,
    'budgetAlertsEnabled': budgetAlertsEnabled,
    'reminderAlertsEnabled': reminderAlertsEnabled,
    'appLockEnabled': appLockEnabled,
    'biometricEnabled': biometricEnabled,
    'autoLockMinutes': autoLockMinutes,
    'lastBackupAt': lastBackupAt?.toIso8601String(),
    'lastExportAt': lastExportAt?.toIso8601String(),
  };

  static AppSettings fromJson(Map<String, Object?> json) {
    T? read<T>(String key) {
      final value = json[key];
      if (value is T) return value;
      if (value is num && T == double) return value.toDouble() as T;
      if (value is num && T == int) return value.toInt() as T;
      if (value is String && T == bool) return (value == 'true') as T;
      return null;
    }

    DateTime? readDate(String key) {
      final raw = json[key];
      if (raw is! String) return null;
      return DateTime.tryParse(raw);
    }

    ThemeMode parseThemeMode(String? name) {
      return ThemeMode.values.firstWhere(
        (mode) => mode.name == name,
        orElse: () => ThemeMode.system,
      );
    }

    return AppSettings(
      onboardingCompleted: read<bool>('onboardingCompleted') ?? false,
      seedVersion: read<int>('seedVersion') ?? 0,
      defaultIncomeWalletId: read<String>('defaultIncomeWalletId'),
      defaultExpenseWalletId: read<String>('defaultExpenseWalletId'),
      useBengaliDigits: read<bool>('useBengaliDigits') ?? false,
      bangladeshiGrouping: read<bool>('bangladeshiGrouping') ?? true,
      dateFormatStyle: read<String>('dateFormatStyle') ?? 'd MMM yyyy',
      themeMode: parseThemeMode(read<String>('themeMode')),
      languageCode: read<String>('languageCode') ?? 'en',
      voiceLocaleId: read<String>('voiceLocaleId') ?? 'bn_BD',
      voiceProviderId: read<String>('voiceProviderId') ?? 'native',
      voiceAutoConfirmThreshold:
          read<double>('voiceAutoConfirmThreshold') ??
          AppDefaults.voiceConfirmThreshold,
      voiceListenForSeconds:
          read<int>('voiceListenForSeconds') ?? AppDefaults.voiceListenSeconds,
      voicePauseForSeconds:
          read<int>('voicePauseForSeconds') ?? AppDefaults.voicePauseSeconds,
      cloudSpeechEndpoint: read<String>('cloudSpeechEndpoint'),
      cloudSpeechLanguageCode:
          read<String>('cloudSpeechLanguageCode') ?? 'bn-BD',
      notificationsEnabled: read<bool>('notificationsEnabled') ?? true,
      budgetAlertsEnabled: read<bool>('budgetAlertsEnabled') ?? true,
      reminderAlertsEnabled: read<bool>('reminderAlertsEnabled') ?? true,
      appLockEnabled: read<bool>('appLockEnabled') ?? false,
      biometricEnabled: read<bool>('biometricEnabled') ?? false,
      autoLockMinutes:
          read<int>('autoLockMinutes') ?? AppDefaults.autoLockMinutes,
      lastBackupAt: readDate('lastBackupAt'),
      lastExportAt: readDate('lastExportAt'),
    );
  }

  /// Serialises to the flat key/value shape used by the `app_settings` table.
  /// Every value is stored as a string so the table stays schema-stable.
  Map<String, String> toFlatRows() {
    final encoded = toJson();
    return encoded.map((key, value) => MapEntry(key, jsonEncode(value)));
  }

  static AppSettings mergeFlatRows(Map<String, String> rows) {
    final decoded = <String, Object?>{};
    rows.forEach((key, value) {
      try {
        decoded[key] = jsonDecode(value);
      } on FormatException {
        decoded[key] = value;
      }
    });
    return AppSettings.fromJson(decoded);
  }
}
