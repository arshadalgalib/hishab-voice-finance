import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../domain/enums.dart';

/// Income and expense categories, including the keywords the voice parser
/// listens for.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  CategoryKind _kind = CategoryKind.expense;

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on AppException catch (error) {
      if (!mounted) return;
      showAppMessage(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(allCategoriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/categories/new?kind=${_kind.name}'),
        icon: const Icon(Icons.add),
        label: const Text('New category'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SegmentedButton<CategoryKind>(
              segments: const <ButtonSegment<CategoryKind>>[
                ButtonSegment<CategoryKind>(
                  value: CategoryKind.expense,
                  label: Text('Expense'),
                  icon: Icon(Icons.north_east, size: 18),
                ),
                ButtonSegment<CategoryKind>(
                  value: CategoryKind.income,
                  label: Text('Income'),
                  icon: Icon(Icons.south_west, size: 18),
                ),
              ],
              selected: <CategoryKind>{_kind},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _kind = selection.first),
            ),
          ),
          Expanded(
            child: AsyncView<List<CategoryRow>>(
              value: categories,
              onRetry: () => ref.invalidate(allCategoriesProvider),
              builder: (rows) {
                final visible = rows
                    .where((row) => row.kind == _kind)
                    .toList(growable: false);
                if (visible.isEmpty) {
                  return const EmptyState(
                    icon: Icons.category_outlined,
                    title: 'No categories here yet',
                    message: 'Create one to sort this kind of money movement.',
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  children: <Widget>[
                    for (final row in visible)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _CategoryTile(
                          category: row,
                          onEdit: () => context.push<String?>(
                            '/categories/new',
                            extra: row.id,
                          ),
                          onArchive: () => _run(
                            () => ref
                                .read(categoryRepositoryProvider)
                                .update(row.id, isArchived: !row.isArchived),
                          ),
                          onDelete: () async {
                            final confirmed = await _confirmDelete(row);
                            if (!confirmed) return;
                            await _run(
                              () => ref
                                  .read(categoryRepositoryProvider)
                                  .delete(row.id),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(CategoryRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${row.name}”?'),
        content: const Text(
          'Past transactions are kept and become uncategorised, which reports '
          'show explicitly rather than hiding.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.onEdit,
    required this.onArchive,
    required this.onDelete,
  });

  final CategoryRow category;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Color(category.colorValue ?? AppColors.seed.toARGB32());
    final keywords = CategoryRepository.keywordsOf(category);

    return Opacity(
      opacity: category.isArchived ? 0.55 : 1,
      child: Card(
        child: ListTile(
          onTap: onEdit,
          leading: CircleAvatar(
            backgroundColor: accent.withValues(alpha: 0.14),
            child: Icon(
              CategoryIcons.resolve(category.iconName),
              size: 20,
              color: accent,
            ),
          ),
          title: Text(category.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 2),
              Text(
                keywords.isEmpty
                    ? 'No spoken keywords yet'
                    : 'Hears: ${keywords.take(4).join(', ')}'
                          '${keywords.length > 4 ? ' …' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              if (category.isDefault || category.isArchived) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  <String>[
                    if (category.isDefault) 'Built-in',
                    if (category.isArchived) 'Archived',
                  ].join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  onEdit();
                case 'archive':
                  onArchive();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
              PopupMenuItem<String>(
                value: 'archive',
                child: Text(category.isArchived ? 'Unarchive' : 'Archive'),
              ),
              if (!category.isDefault)
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Text('Delete'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
