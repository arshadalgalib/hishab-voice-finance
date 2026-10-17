import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../domain/models/app_settings.dart';

/// Top level settings hub: display preferences, sub-screen navigation and an
/// honest summary of where the data lives.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AsyncView<AppSettings>(
        value: ref.watch(appSettingsProvider),
        loadingMessage: 'Loading settings…',
        builder: (settings) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            SectionCard(
              title: 'Display',
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.useBengaliDigits,
                    title: const Text('Bengali digits'),
                    subtitle: const Text('Show amounts and dates using ০–৯'),
                    onChanged: (value) => _writeSettings(
                      context,
                      ref,
                      (current) => current.copyWith(useBengaliDigits: value),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.bangladeshiGrouping,
                    title: const Text('Lakh / crore grouping'),
                    subtitle: const Text(
                      'Group digits as 1,23,456 instead of 123,456',
                    ),
                    onChanged: (value) => _writeSettings(
                      context,
                      ref,
                      (current) => current.copyWith(bangladeshiGrouping: value),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Theme',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<ThemeMode>(
                    segments: const <ButtonSegment<ThemeMode>>[
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.system,
                        label: Text('System'),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.light,
                        label: Text('Light'),
                      ),
                      ButtonSegment<ThemeMode>(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                      ),
                    ],
                    selected: <ThemeMode>{settings.themeMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) => _writeSettings(
                      context,
                      ref,
                      (current) => current.copyWith(themeMode: selection.first),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Voice & security',
              child: Column(
                children: [
                  _NavTile(
                    icon: Icons.mic_none,
                    title: 'Voice entry',
                    subtitle: onlineInterpretationActive(settings)
                        ? 'Online interpretation is on'
                        : 'On-device recognition only',
                    onTap: () => context.push('/settings/voice'),
                  ),
                  _NavTile(
                    icon: Icons.lock_outline,
                    title: 'Security & lock',
                    subtitle: 'PIN and app lock',
                    onTap: () => context.push('/settings/security'),
                  ),
                  _NavTile(
                    icon: Icons.inventory_2_outlined,
                    title: 'Data, backup & export',
                    subtitle: 'Backups, CSV exports and storage',
                    onTap: () => context.push('/settings/data'),
                  ),
                  _NavTile(
                    icon: Icons.history,
                    title: 'Activity log',
                    subtitle: 'Audited changes and restores',
                    onTap: () => context.push('/settings/audit'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Setup',
              child: Column(
                children: [
                  _NavTile(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Wallets',
                    subtitle: 'Cash, bank and mobile wallets',
                    onTap: () => context.push('/wallets'),
                  ),
                  _NavTile(
                    icon: Icons.category_outlined,
                    title: 'Categories',
                    subtitle: 'Income and expense categories',
                    onTap: () => context.push('/categories'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionCard(
              title: 'About',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hishab — Voice Finance',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text('Version 1.0.0+1'),
                  SizedBox(height: 12),
                  Text(
                    'Everything you record is stored on this device, in a local '
                    'database and local secure storage. Nothing is uploaded. '
                    'Cloud interpretation of your speech transcript is off by '
                    'default; if you ever turn it on it is entirely opt-in, and '
                    'you can turn it off again at any time.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Persists a settings change and reports domain failures instead of
  /// throwing them at the framework.
  Future<void> _writeSettings(
    BuildContext context,
    WidgetRef ref,
    AppSettings Function(AppSettings current) transform,
  ) async {
    try {
      await ref.read(settingsRepositoryProvider).update(transform);
    } on AppException catch (error) {
      if (!context.mounted) return;
      showAppMessage(context, error.message);
    }
  }
}

/// A settings row that navigates somewhere else.
class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
