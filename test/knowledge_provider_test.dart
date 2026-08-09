import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/knowledge_base.dart';
import 'package:lynai/models/knowledge_category.dart';
import 'package:lynai/models/knowledge_entry.dart';
import 'package:lynai/models/knowledge_explanation.dart';
import 'package:lynai/models/knowledge_source.dart';
import 'package:lynai/providers/knowledge_provider.dart';
import 'package:lynai/repositories/knowledge_repository.dart';

void main() {
  test(
    'load idempotently installs the built-in proper noun templates',
    () async {
      final repository = _KnowledgeRepository();
      final provider = KnowledgeProvider(repository: repository);

      await provider.load();
      await provider.load();

      expect(
        provider.knowledgeBases
            .where(
              (item) =>
                  item.id == KnowledgeProvider.builtInProperNounKnowledgeBaseId,
            )
            .single
            .name,
        '专有名词知识库',
      );
      expect(
        provider.categories
            .where(
              (item) =>
                  item.id == KnowledgeProvider.builtInProperNounCategoryId,
            )
            .single
            .alias,
        KnowledgeProvider.properNounAlias,
      );
      expect(repository.replaced?.bases, hasLength(1));
      expect(repository.replaced?.categories, hasLength(1));
    },
  );

  test('replaceAll preserves existing built-in user edits', () async {
    final provider = KnowledgeProvider(repository: _KnowledgeRepository());
    final now = DateTime.utc(2026, 7, 29);
    final editedBase = KnowledgeBase(
      id: KnowledgeProvider.builtInProperNounKnowledgeBaseId,
      name: '我的名词库',
      description: '用户描述',
      enabled: false,
      sortOrder: 7,
      createdAt: now,
      updatedAt: now,
    );
    final editedCategory = KnowledgeCategory(
      id: KnowledgeProvider.builtInProperNounCategoryId,
      knowledgeBaseId: editedBase.id,
      name: '我的类别',
      alias: 'my_terms',
      annotationRule: '用户规则',
      explanationPrompt: '用户提示词',
      autoAnnotate: false,
      enabled: false,
      sortOrder: 3,
      createdAt: now,
      updatedAt: now,
    );

    await provider.replaceAll(
      knowledgeBases: [editedBase],
      categories: [editedCategory],
      entries: const [],
      sources: const [],
      explanations: const [],
    );

    expect(provider.knowledgeBaseById(editedBase.id)?.name, '我的名词库');
    expect(provider.categoryById(editedCategory.id)?.alias, 'my_terms');
    expect(provider.annotationFallbackCategory, isNull);
  });

  test('built-in alias wins conflicts with deterministic renaming', () async {
    final now = DateTime.utc(2026, 7, 29);
    final repository = _KnowledgeRepository(
      loadResult: KnowledgeLoadResult(
        bases: [
          KnowledgeBase(
            id: 'base',
            name: 'Base',
            enabled: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        categories: [
          KnowledgeCategory(
            id: 'category-a',
            knowledgeBaseId: 'base',
            name: 'User category',
            alias: KnowledgeProvider.properNounAlias,
            enabled: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        entries: const [],
        sources: const [],
        explanations: const [],
      ),
    );
    final provider = KnowledgeProvider(repository: repository);

    await provider.load();

    expect(
      provider
          .categoryById(KnowledgeProvider.builtInProperNounCategoryId)
          ?.alias,
      KnowledgeProvider.properNounAlias,
    );
    expect(
      provider.categoryById('category-a')?.alias,
      'proper_noun_category_a',
    );
    expect(provider.categoryById('category-a')?.updatedAt, now);
    expect(
      repository.replaced?.categories.map((item) => item.id),
      containsAll([
        'category-a',
        KnowledgeProvider.builtInProperNounCategoryId,
      ]),
    );
  });

  test('load persists repaired graph rows and fixed built-in parent', () async {
    final now = DateTime.utc(2026, 7, 29);
    final builtInCategory = KnowledgeCategory(
      id: KnowledgeProvider.builtInProperNounCategoryId,
      knowledgeBaseId: 'missing-base',
      name: 'Built in',
      alias: KnowledgeProvider.properNounAlias,
      enabled: true,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    );
    final repository = _KnowledgeRepository(
      loadResult: KnowledgeLoadResult(
        bases: [_base('other-base', now), _base('entry-base', now)],
        categories: [
          builtInCategory,
          _category('cross-category', 'other-base', now, alias: 'cross'),
        ],
        entries: [
          _entry('entry', 'entry-base', 'cross-category', now),
          _entry('valid-entry', 'entry-base', null, now),
        ],
        sources: [
          _source('cross-source', 'other-base', 'valid-entry', now),
          _source('orphan-source', 'entry-base', 'missing', now),
        ],
        explanations: [
          _explanation('cross-explanation', 'other-base', 'valid-entry', now),
        ],
      ),
    );
    final provider = KnowledgeProvider(repository: repository);

    await provider.load();

    expect(
      provider
          .categoryById(KnowledgeProvider.builtInProperNounCategoryId)
          ?.knowledgeBaseId,
      KnowledgeProvider.builtInProperNounKnowledgeBaseId,
    );
    expect(
      provider
          .categoryById(KnowledgeProvider.builtInProperNounCategoryId)
          ?.name,
      'Built in',
    );
    expect(provider.entryById('entry')?.categoryId, isNull);
    expect(provider.sources, isEmpty);
    expect(provider.explanations, isEmpty);
    expect(
      repository.replaced?.entries
          .singleWhere((item) => item.id == 'entry')
          .categoryId,
      isNull,
    );
    expect(repository.replaced?.sources, isEmpty);
    expect(repository.replaced?.explanations, isEmpty);
  });

  test(
    'failed load normalization restores memory and notifies rollback',
    () async {
      final repository = _KnowledgeRepository();
      final provider = KnowledgeProvider(repository: repository);
      await provider.replaceAll(
        knowledgeBases: [_base('existing', DateTime.utc(2026, 7, 28))],
        categories: const [],
        entries: const [],
        sources: const [],
        explanations: const [],
      );
      repository.loadResult = const KnowledgeLoadResult(
        bases: [],
        categories: [],
        entries: [],
        sources: [],
        explanations: [],
      );
      repository.failNextReplace = true;
      var notifications = 0;
      provider.addListener(() => notifications++);

      await expectLater(provider.load(), throwsStateError);

      expect(provider.knowledgeBaseById('existing'), isNotNull);
      expect(notifications, 2);
    },
  );

  test(
    'unknown aliases only fall back to the enabled built-in category',
    () async {
      final provider = KnowledgeProvider(repository: _KnowledgeRepository());
      await provider.load();
      final builtIn = provider.categoryById(
        KnowledgeProvider.builtInProperNounCategoryId,
      )!;
      final baseId = await provider.addKnowledgeBase(name: 'Other');
      final otherId = await provider.addCategory(
        knowledgeBaseId: baseId,
        name: 'Other',
        alias: 'other',
        autoAnnotate: true,
      );

      expect(provider.resolveAnnotationCategory('other'), otherId);
      expect(
        provider.resolveAnnotationCategory('unknown'),
        KnowledgeProvider.builtInProperNounCategoryId,
      );

      await provider.updateCategory(builtIn.copyWith(enabled: false));
      expect(provider.resolveAnnotationCategory('unknown'), isNull);
      expect(provider.resolveAnnotationCategory('other'), otherId);
    },
  );

  test('prompt snapshot exposes the fixed built-in fallback alias', () async {
    final provider = KnowledgeProvider(repository: _KnowledgeRepository());
    await provider.load();

    final snapshot = provider.knowledgeAnnotationPromptSnapshot;

    expect(snapshot.fallbackCategory, KnowledgeProvider.properNounAlias);
    expect(
      snapshot.categories.map((item) => item.category),
      contains(KnowledgeProvider.properNounAlias),
    );
  });

  test('built-in rows cannot be deleted', () async {
    final provider = KnowledgeProvider(repository: _KnowledgeRepository());
    await provider.load();

    await expectLater(
      provider.deleteKnowledgeBase(
        KnowledgeProvider.builtInProperNounKnowledgeBaseId,
      ),
      throwsArgumentError,
    );
    await expectLater(
      provider.deleteCategory(KnowledgeProvider.builtInProperNounCategoryId),
      throwsArgumentError,
    );
  });

  test(
    'category updates keep and validate the previous knowledge base',
    () async {
      final repository = _KnowledgeRepository();
      final provider = KnowledgeProvider(repository: repository);
      final now = DateTime.utc(2026, 7, 29);
      await provider.replaceAll(
        knowledgeBases: [_base('base-a', now)],
        categories: [
          _category('category-a', 'base-a', now, alias: 'category_a'),
        ],
        entries: const [],
        sources: const [],
        explanations: const [],
      );

      final category = provider.categoryById('category-a')!;
      await provider.updateCategory(
        category.copyWith(knowledgeBaseId: 'missing-base', name: 'Updated'),
      );

      expect(provider.categoryById('category-a')?.knowledgeBaseId, 'base-a');
      expect(provider.categoryById('category-a')?.name, 'Updated');
      expect(repository.savedCategories.single.knowledgeBaseId, 'base-a');
    },
  );

  test(
    'entry updates reject categories outside the previous knowledge base',
    () async {
      final repository = _KnowledgeRepository();
      final provider = KnowledgeProvider(repository: repository);
      final now = DateTime.utc(2026, 7, 29);
      await provider.replaceAll(
        knowledgeBases: [_base('base-a', now), _base('base-b', now)],
        categories: [
          _category('category-b', 'base-b', now, alias: 'category_b'),
        ],
        entries: [_entry('entry-a', 'base-a', null, now)],
        sources: const [],
        explanations: const [],
      );

      final entry = provider.entryById('entry-a')!;
      await expectLater(
        provider.updateEntry(
          entry.copyWith(knowledgeBaseId: 'base-b', categoryId: 'category-b'),
        ),
        throwsArgumentError,
      );

      expect(provider.entryById('entry-a')?.knowledgeBaseId, 'base-a');
      expect(provider.entryById('entry-a')?.categoryId, isNull);
      expect(repository.savedEntries, isEmpty);
    },
  );

  test(
    'restoring built-ins preserves state, order, creation and entries',
    () async {
      final provider = KnowledgeProvider(repository: _KnowledgeRepository());
      await provider.load();
      final base = provider.knowledgeBaseById(
        KnowledgeProvider.builtInProperNounKnowledgeBaseId,
      )!;
      final category = provider.categoryById(
        KnowledgeProvider.builtInProperNounCategoryId,
      )!;
      await provider.updateKnowledgeBase(
        base.copyWith(name: 'Edited base', enabled: false),
      );
      await provider.updateCategory(
        category.copyWith(
          name: 'Edited category',
          alias: 'edited_alias',
          enabled: false,
          autoAnnotate: false,
        ),
      );
      final entryId = await provider.addEntry(
        knowledgeBaseId: base.id,
        categoryId: category.id,
        title: 'User entry',
        content: 'User content',
      );

      await provider.restoreBuiltInKnowledgeBase();
      await provider.restoreBuiltInCategory();

      final restoredBase = provider.knowledgeBaseById(base.id)!;
      final restoredCategory = provider.categoryById(category.id)!;
      expect(restoredBase.name, '专有名词知识库');
      expect(restoredBase.enabled, isFalse);
      expect(restoredBase.sortOrder, base.sortOrder);
      expect(restoredBase.createdAt, base.createdAt);
      expect(restoredCategory.name, '专有名词');
      expect(restoredCategory.alias, KnowledgeProvider.properNounAlias);
      expect(restoredCategory.enabled, isFalse);
      expect(restoredCategory.autoAnnotate, isTrue);
      expect(restoredCategory.sortOrder, category.sortOrder);
      expect(restoredCategory.createdAt, category.createdAt);
      expect(provider.entryById(entryId)?.content, 'User content');
    },
  );

  test('failed mutation rolls memory back', () async {
    final repository = _KnowledgeRepository()..failNextSave = true;
    final provider = KnowledgeProvider(repository: repository);

    await expectLater(
      provider.addKnowledgeBase(name: 'Unsaved'),
      throwsStateError,
    );

    expect(provider.knowledgeBases, isEmpty);
  });
}

class _KnowledgeRepository extends KnowledgeRepository {
  _KnowledgeRepository({this.loadResult});

  KnowledgeLoadResult? loadResult;
  bool failNextSave = false;
  bool failNextReplace = false;
  List<KnowledgeBase> savedBases = [];
  List<KnowledgeCategory> savedCategories = [];
  List<KnowledgeEntry> savedEntries = [];
  KnowledgeLoadResult? replaced;

  @override
  Future<KnowledgeLoadResult> load() async =>
      loadResult ??
      const KnowledgeLoadResult(
        bases: [],
        categories: [],
        entries: [],
        sources: [],
        explanations: [],
      );

  @override
  Future<void> replace(KnowledgeLoadResult value) async {
    if (failNextReplace) {
      failNextReplace = false;
      throw StateError('injected replace failure');
    }
    replaced = value;
  }

  @override
  Future<void> saveChanges({
    Iterable<KnowledgeBase> upsertBases = const [],
    Iterable<String> deleteBaseIds = const [],
    Iterable<KnowledgeCategory> upsertCategories = const [],
    Iterable<String> deleteCategoryIds = const [],
    Iterable<KnowledgeEntry> upsertEntries = const [],
    Iterable<String> deleteEntryIds = const [],
    Iterable<KnowledgeSource> upsertSources = const [],
    Iterable<String> deleteSourceIds = const [],
    Iterable<KnowledgeExplanation> upsertExplanations = const [],
    Iterable<String> deleteExplanationIds = const [],
  }) async {
    savedBases = upsertBases.toList();
    savedCategories = upsertCategories.toList();
    savedEntries = upsertEntries.toList();
    if (failNextSave) {
      failNextSave = false;
      throw StateError('injected save failure');
    }
  }
}

KnowledgeBase _base(String id, DateTime now) => KnowledgeBase(
  id: id,
  name: id,
  enabled: true,
  sortOrder: 0,
  createdAt: now,
  updatedAt: now,
);

KnowledgeCategory _category(
  String id,
  String baseId,
  DateTime now, {
  required String alias,
}) => KnowledgeCategory(
  id: id,
  knowledgeBaseId: baseId,
  name: id,
  alias: alias,
  enabled: true,
  sortOrder: 0,
  createdAt: now,
  updatedAt: now,
);

KnowledgeEntry _entry(
  String id,
  String baseId,
  String? categoryId,
  DateTime now,
) => KnowledgeEntry(
  id: id,
  knowledgeBaseId: baseId,
  categoryId: categoryId,
  title: id,
  content: '',
  enabled: true,
  sortOrder: 0,
  createdAt: now,
  updatedAt: now,
);

KnowledgeSource _source(
  String id,
  String baseId,
  String entryId,
  DateTime now,
) => KnowledgeSource(
  id: id,
  knowledgeBaseId: baseId,
  entryId: entryId,
  title: id,
  sortOrder: 0,
  createdAt: now,
  updatedAt: now,
);

KnowledgeExplanation _explanation(
  String id,
  String baseId,
  String entryId,
  DateTime now,
) => KnowledgeExplanation(
  id: id,
  knowledgeBaseId: baseId,
  entryId: entryId,
  title: id,
  content: '',
  sortOrder: 0,
  createdAt: now,
  updatedAt: now,
);
