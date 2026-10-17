import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/labels.dart';
import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/app_widgets.dart';
import '../../../core/errors/app_exception.dart';
import '../../../data/local/app_database.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../domain/enums.dart';

/// Creates or edits a category.
///
/// The keyword list is the interesting field: it is what the voice parser
/// matches against, so the helper text says so plainly and the values are
/// allowed to be in Bangla, Banglish or English.
class CategoryFormScreen extends ConsumerStatefulWidget {
  const CategoryFormScreen({super.key, this.categoryId, this.initialKind});

  /// Set when editing an existing category.
  final String? categoryId;

  /// Which kind a brand new category starts as.
  final CategoryKind? initialKind;

  @override
  ConsumerState<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends ConsumerState<CategoryFormScreen> {
  @override
  Widget build(BuildContext context) {
    final id = widget.categoryId;
    if (id == null) {
      return _CategoryForm(
        category: null,
        initialKind: widget.initialKind ?? CategoryKind.expense,
      );
    }
    return FutureBuilder<CategoryRow?>(
      future: ref.read(categoryRepositoryProvider).find(id),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: const Text('Edit category')),
            body: const LoadingView(),
          );
        }
        final category = snapshot.data;
        if (category == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Edit category')),
            body: const EmptyState(
              icon: Icons.error_outline,
              title: 'That category no longer exists',
              message: 'It may have been deleted on another screen.',
            ),
          );
        }
        return _CategoryForm(category: category, initialKind: category.kind);
      },
    );
  }
}

class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({required this.category, required this.initialKind});

  final CategoryRow? category;
  final CategoryKind initialKind;

  @override
  ConsumerState<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<_CategoryForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _keywords;

  late CategoryKind _kind;
  late String _iconName;
  int? _colorValue;
  bool _saving = false;

  bool get _isEditing => widget.category != null;

  @override
  void initState() {
    super.initState();
    final category = widget.category;
    _name = TextEditingController(text: category?.name ?? '');
    _keywords = TextEditingController(
      text: category == null
          ? ''
          : CategoryRepository.keywordsOf(category).join(', '),
    );
    _kind = category?.kind ?? widget.initialKind;
    _iconName = category?.iconName ?? kDefaultIconName;
    _colorValue = category?.colorValue;
  }

  @override
  void dispose() {
    _name.dispose();
    _keywords.dispose();
    super.dispose();
  }

  List<String> get _parsedKeywords => _keywords.text
      .split(',')
      .map((keyword) => keyword.trim())
      .where((keyword) => keyword.isNotEmpty)
      .toList(growable: false);

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final repository = ref.read(categoryRepositoryProvider);
    try {
      if (!_isEditing) {
        await repository.create(
          name: _name.text,
          kind: _kind,
          iconName: _iconName,
          colorValue: _colorValue,
          keywords: _parsedKeywords,
        );
      } else {
        await repository.update(
          widget.category!.id,
          name: _name.text,
          iconName: _iconName,
          colorValue: _colorValue,
          keywords: _parsedKeywords,
        );
      }
      if (!mounted) return;
      context.pop(true);
    } on AppException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit category' : 'New category'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'A name is required.' : null,
            ),
            const SizedBox(height: 16),
            FormDropdown<CategoryKind>(
              label: 'Kind',
              value: _kind,
              enabled: !_isEditing,
              helperText: _isEditing
                  ? 'A category cannot move between income and expense — its '
                        'history would stop adding up.'
                  : null,
              items: const <DropdownMenuItem<CategoryKind>>[
                DropdownMenuItem<CategoryKind>(
                  value: CategoryKind.expense,
                  child: Text('Expense'),
                ),
                DropdownMenuItem<CategoryKind>(
                  value: CategoryKind.income,
                  child: Text('Income'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _kind = value);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _keywords,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Spoken keywords',
                helperText:
                    'Comma separated. These are the words the voice parser '
                    'listens for, in Bangla, Banglish or English — for example '
                    'রিকশা, rickshaw, cng.',
                helperMaxLines: 4,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_parsedKeywords.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final keyword in _parsedKeywords)
                    Chip(
                      label: Text(keyword),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            SectionCard(
              title: 'ICON',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final name in CategoryIcons.names)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _iconName = name),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _iconName == name
                              ? theme.colorScheme.secondaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          CategoryIcons.resolve(name),
                          size: 20,
                          color: _iconName == name
                              ? theme.colorScheme.onSecondaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'COLOUR',
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  for (final value in kPickerColors)
                    GestureDetector(
                      onTap: () => setState(() => _colorValue = value),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Color(value),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _colorValue == value
                                ? theme.colorScheme.onSurface
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_isEditing ? 'Save changes' : 'Create category'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Default glyph for a new category when the user has not chosen one.
const String kDefaultIconName = 'category';
