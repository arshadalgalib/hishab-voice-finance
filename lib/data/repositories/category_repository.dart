import 'package:drift/drift.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/enums.dart';
import '../local/app_database.dart';
import '../local/seed_data.dart';

/// Category CRUD and the built-in category seeding.
class CategoryRepository {
  CategoryRepository({
    required AppDatabase db,
    required IdGenerator ids,
    required Clock clock,
  }) : _db = db,
       _ids = ids,
       _clock = clock;

  final AppDatabase _db;
  final IdGenerator _ids;
  final Clock _clock;

  Stream<List<CategoryRow>> watch({
    CategoryKind? kind,
    bool includeArchived = false,
  }) => _db.watchCategories(kind: kind, includeArchived: includeArchived);

  Future<List<CategoryRow>> list({
    CategoryKind? kind,
    bool includeArchived = false,
  }) => _db.getCategories(kind: kind, includeArchived: includeArchived);

  Future<CategoryRow?> find(String id) => _db.findCategoryById(id);

  Future<CategoryRow?> findByName(String name, {CategoryKind? kind}) =>
      _db.findCategoryByName(name, kind: kind);

  Future<String> create({
    required String name,
    required CategoryKind kind,
    String? iconName,
    int? colorValue,
    List<String> keywords = const <String>[],
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException(
        'Category name is required.',
        field: 'name',
      );
    }
    if (trimmed.length > 80) {
      throw const ValidationException(
        'Category name must be 80 characters or fewer.',
        field: 'name',
      );
    }
    final existing = await _db.findCategoryByName(trimmed, kind: kind);
    if (existing != null) {
      throw ValidationException(
        'A ${kind.name} category called “${existing.name}” already exists.',
        field: 'name',
      );
    }
    final id = _ids.next();
    final now = _clock.now();
    await _db.upsertCategory(
      CategoriesCompanion.insert(
        id: id,
        name: trimmed,
        kind: kind,
        iconName: Value(iconName),
        colorValue: Value(colorValue),
        keywords: Value(_encodeKeywords(keywords)),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> update(
    String id, {
    String? name,
    String? iconName,
    int? colorValue,
    List<String>? keywords,
    bool? isArchived,
  }) async {
    final category = await _db.findCategoryById(id);
    if (category == null) {
      throw const NotFoundException('That category no longer exists.');
    }
    var newName = category.name;
    if (name != null) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        throw const ValidationException(
          'Category name is required.',
          field: 'name',
        );
      }
      final clash = await _db.findCategoryByName(trimmed, kind: category.kind);
      if (clash != null && clash.id != id) {
        throw ValidationException(
          'A ${category.kind.name} category called “${clash.name}” already exists.',
          field: 'name',
        );
      }
      newName = trimmed;
    }
    await _db.upsertCategory(
      CategoriesCompanion(
        id: Value(id),
        name: Value(newName),
        iconName: iconName == null ? const Value.absent() : Value(iconName),
        colorValue: colorValue == null
            ? const Value.absent()
            : Value(colorValue),
        keywords: keywords == null
            ? const Value.absent()
            : Value(_encodeKeywords(keywords)),
        isArchived: isArchived == null
            ? const Value.absent()
            : Value(isArchived),
        updatedAt: Value(_clock.now()),
      ),
    );
  }

  /// Deletes a custom category. Transactions keep their history — the foreign
  /// key `ON DELETE SET NULL` turns them into "Uncategorised", which is
  /// reported explicitly rather than being hidden.
  Future<void> delete(String id) async {
    final category = await _db.findCategoryById(id);
    if (category == null) return;
    if (category.isDefault) {
      throw const OperationNotAllowedException(
        'Built-in categories can be archived but not deleted, so reports stay comparable.',
      );
    }
    await (_db.delete(_db.categories)..where((t) => t.id.equals(id))).go();
  }

  /// Inserts any built-in category that is missing. Idempotent: matching is by
  /// `(name, kind)`, so an interrupted install is repaired on next launch and
  /// user renames are preserved where the name still matches.
  Future<int> ensureDefaultCategories() async {
    final existing = await _db.getCategories(includeArchived: true);
    final keys = existing
        .map((c) => '${c.kind.name}:${c.name.toLowerCase()}')
        .toSet();
    var inserted = 0;
    final now = _clock.now();
    for (var index = 0; index < kDefaultCategories.length; index++) {
      final template = kDefaultCategories[index];
      final key = '${template.kind.name}:${template.name.toLowerCase()}';
      if (keys.contains(key)) continue;
      await _db.upsertCategory(
        CategoriesCompanion.insert(
          id: _ids.next(),
          name: template.name,
          kind: template.kind,
          iconName: Value(template.iconName),
          colorValue: Value(template.colorValue),
          keywords: Value(_encodeKeywords(template.keywords)),
          isDefault: const Value(true),
          sortOrder: Value(index),
          createdAt: now,
          updatedAt: now,
        ),
      );
      inserted++;
    }
    return inserted;
  }

  /// Returns the keywords declared for a category, for the voice parser.
  static List<String> keywordsOf(CategoryRow category) {
    final raw = category.keywords;
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    return raw
        .split(',')
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList(growable: false);
  }

  static String _encodeKeywords(List<String> keywords) {
    final cleaned = keywords
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toSet()
        .toList(growable: false);
    return cleaned.join(',');
  }
}
