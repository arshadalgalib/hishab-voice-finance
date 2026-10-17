import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../data/local/seed_data.dart';

/// First run.
///
/// Deliberately short: it explains the voice promise, lets the user add the
/// wallets they actually use, and nothing is created that the user did not
/// pick. The `Cash` wallet already exists from seeding, so it is shown as a
/// fact rather than offered as a choice.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.onFinished});

  /// Called once onboarding has been recorded. The routed version navigates;
  /// the gate-free version lets the settings stream rebuild the app.
  final VoidCallback? onFinished;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final Set<String> _selected = <String>{};
  bool _saving = false;

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    final seed = ref.read(seedServiceProvider);
    try {
      final chosen = seed.walletTemplates.where(
        (template) => _selected.contains(template.name),
      );
      await seed.createChosenWallets(chosen);
      await ref
          .read(settingsRepositoryProvider)
          .update((current) => current.copyWith(onboardingCompleted: true));
      if (!mounted) return;
      widget.onFinished?.call();
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider).value;
    final templates = ref
        .watch(seedServiceProvider)
        .walletTemplates
        .where((template) => template.name != 'Cash')
        .toList(growable: false);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(20),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.seed.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  size: 52,
                  color: AppColors.seed,
                ),
              ),
            ),
            Text(
              'Hishab',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Say it. Check it. It is recorded.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            SectionCard(
              title: 'HOW IT WORKS',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const <Widget>[
                  _Point(
                    icon: Icons.record_voice_over_outlined,
                    text:
                        'Speak in Bangla, Banglish or English — for example '
                        '“বিকাশ থেকে ৫০০ টাকা কফি” or “cash 250 rickshaw”.',
                  ),
                  _Point(
                    icon: Icons.fact_check_outlined,
                    text:
                        'Hishab shows every entry back to you before it is '
                        'saved. Anything it could not understand is left blank '
                        'for you to fill in — it never guesses silently.',
                  ),
                  _Point(
                    icon: Icons.phonelink_lock_outlined,
                    text:
                        'Everything is stored on this phone. No account, no '
                        'sign-up, and nothing is sent anywhere unless you '
                        'switch online interpretation on yourself.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'YOUR WALLETS',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'A Cash wallet has already been created. Tap any others '
                    'you use so voice entries land in the right place.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final DefaultWalletTemplate template in templates)
                        FilterChip(
                          label: Text(template.name),
                          selected: _selected.contains(template.name),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _selected.add(template.name);
                            } else {
                              _selected.remove(template.name);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'DISPLAY',
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: SwitchListTile(
                value: settings?.useBengaliDigits ?? false,
                onChanged: (value) => ref
                    .read(settingsRepositoryProvider)
                    .update(
                      (current) => current.copyWith(useBengaliDigits: value),
                    ),
                title: const Text('Show numbers in Bengali digits'),
                subtitle: const Text(
                  'Amounts appear as ১,২৫০ instead of 1,250. This only '
                  'changes how they look — the stored value is unchanged.',
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _finish,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Start using Hishab'),
            ),
            const SizedBox(height: 12),
            Text(
              'Hishab gives you tracking and reports, not financial advice.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
