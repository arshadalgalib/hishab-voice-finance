import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/utils/date_x.dart';
import '../../../domain/enums.dart';
import '../../../domain/models/budget_progress.dart';
import 'loan_form_sheet.dart';

/// Net outstanding is a single scalar from the repository. Watching the loan
/// list keeps it in step without a second shared provider.
final _netOutstandingProvider = FutureProvider<int>((ref) {
  ref.watch(loanProgressProvider);
  return ref.watch(loanRepositoryProvider).netOutstandingPoisha();
});

/// Money the user lent out and money the user borrowed, grouped by direction.
class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loans')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showLoanFormSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New loan'),
      ),
      body: AsyncView<List<LoanProgress>>(
        value: ref.watch(loanProgressProvider),
        loadingMessage: 'Loading loans…',
        onRetry: () => ref.invalidate(loanProgressProvider),
        empty: EmptyState(
          icon: Icons.handshake_outlined,
          title: 'No loans yet',
          message: 'Track money you lend out or borrow.',
          action: FilledButton.icon(
            onPressed: () => showLoanFormSheet(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('New loan'),
          ),
        ),
        isEmpty: (loans) => loans.isEmpty,
        builder: (loans) {
          final lent = <LoanProgress>[
            for (final loan in loans)
              if (loan.direction == LoanDirection.lent) loan,
          ];
          final borrowed = <LoanProgress>[
            for (final loan in loans)
              if (loan.direction == LoanDirection.borrowed) loan,
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              SectionCard(
                title: 'Net outstanding',
                child: AsyncView<int>(
                  value: ref.watch(_netOutstandingProvider),
                  onRetry: () => ref.invalidate(_netOutstandingProvider),
                  builder: (value) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MoneyText(
                        value,
                        showSign: false,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Positive means people owe you more than you owe. '
                        'Negative means you owe more than people owe you.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _LoanSection(title: 'You lent out', loans: lent),
              const SizedBox(height: 16),
              _LoanSection(title: 'You borrowed', loans: borrowed),
            ],
          );
        },
      ),
    );
  }
}

/// One direction's loans, or a short note when there are none.
class _LoanSection extends StatelessWidget {
  const _LoanSection({required this.title, required this.loans});

  final String title;
  final List<LoanProgress> loans;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: title,
      child: loans.isEmpty
          ? Text(
              'Nothing here yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < loans.length; index++) ...[
                  if (index > 0) const Divider(height: 1),
                  _LoanRow(loan: loans[index]),
                ],
              ],
            ),
    );
  }
}

class _LoanRow extends StatelessWidget {
  const _LoanRow({required this.loan});

  final LoanProgress loan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => context.push('/loans/${loan.loanId}'),
      title: Row(
        children: [
          Expanded(
            child: Text(
              loan.counterparty,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (loan.isFullyRepaid)
            Chip(
              label: const Text('Settled'),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Principal', style: theme.textTheme.bodySmall),
            MoneyText(
              loan.principalPoisha,
              showSign: false,
              style: theme.textTheme.bodySmall,
            ),
            if (loan.dueDate != null)
              Text(
                '· Due ${formatDate(loan.dueDate!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'Outstanding',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          MoneyText(loan.outstandingPoisha, showSign: false),
        ],
      ),
    );
  }
}
