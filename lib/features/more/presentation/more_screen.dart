import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/app_widgets.dart';

/// Navigation hub for everything that is not on the bottom bar.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          SectionCard(
            title: 'Total balance',
            child: AsyncView<int>(
              value: ref.watch(totalBalanceProvider),
              loadingMessage: 'Adding up your wallets…',
              builder: (poisha) => Align(
                alignment: Alignment.centerLeft,
                child: MoneyText(
                  poisha,
                  showSign: false,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _MoreGroup(
            title: 'Reports',
            tiles: [
              _MoreTile(
                icon: Icons.insights,
                title: 'Reports',
                subtitle: 'Income, spending and trends',
                route: '/reports',
              ),
              _MoreTile(
                icon: Icons.savings_outlined,
                title: 'Budgets',
                subtitle: 'Set spending limits and track them',
                route: '/budgets',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _MoreGroup(
            title: 'Planning',
            tiles: [
              _MoreTile(
                icon: Icons.flag_outlined,
                title: 'Goals',
                subtitle: 'Save towards a target',
                route: '/goals',
              ),
              _MoreTile(
                icon: Icons.autorenew,
                title: 'Recurring',
                subtitle: 'Rent, bills and salaries that repeat',
                route: '/recurring',
              ),
              _MoreTile(
                icon: Icons.notifications_none,
                title: 'Reminders',
                subtitle: 'Bills and payments not to miss',
                route: '/reminders',
              ),
              _MoreTile(
                icon: Icons.handshake_outlined,
                title: 'Loans',
                subtitle: 'Money you lent or borrowed',
                route: '/loans',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _MoreGroup(
            title: 'Setup',
            tiles: [
              _MoreTile(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Wallets',
                subtitle: 'Cash, bank and mobile wallets',
                route: '/wallets',
              ),
              _MoreTile(
                icon: Icons.category_outlined,
                title: 'Categories',
                subtitle: 'Income and expense categories',
                route: '/categories',
              ),
              _MoreTile(
                icon: Icons.settings_outlined,
                title: 'Settings',
                subtitle: 'Display, voice, security and data',
                route: '/settings',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoreGroup extends StatelessWidget {
  const _MoreGroup({required this.title, required this.tiles});

  final String title;
  final List<_MoreTile> tiles;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      child: Column(
        children: [
          for (final tile in tiles)
            ListTile(
              leading: Icon(tile.icon),
              title: Text(tile.title),
              subtitle: Text(tile.subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, tile.route),
            ),
        ],
      ),
    );
  }

  static void _open(BuildContext context, String route) {
    context.push(route);
  }
}

class _MoreTile {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}
