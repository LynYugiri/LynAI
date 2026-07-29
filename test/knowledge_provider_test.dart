import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/knowledge_base.dart';
import 'package:lynai/models/knowledge_category.dart';
import 'package:lynai/models/knowledge_entry.dart';
import 'package:lynai/models/knowledge_explanation.dart';
import 'package:lynai/models/knowledge_source.dart';
import 'package:lynai/models/knowledge_settings.dart';
import 'package:lynai/providers/knowledge_provider.dart';
import 'package:lynai/repositories/knowledge_repository.dart';

void main() {
  test(
    'defaultCategory prefers one explicit default then enabled order',
    () async {
      final repository = _KnowledgeRepository();
      final provider = KnowledgeProvider(repository: repository);
      final baseId = await provider.addKnowledgeBase(name: 'Base');
      final firstId = await provider.addCategory(
        knowledgeBaseId: baseId,
        name: 'First',
        alias: 'first',
        autoAnnotate: true,
      );
      final secondId = await provider.addCategory(
        knowledgeBaseId: baseId,
        name: 'Second',
        alias: 'second',
        isDefault: true,
        autoAnnotate: true,
      );

      expect(provider.defaultCategoryForBase(baseId)?.id, secondId);
      expect(provider.defaultCategory()?.id, secondId);
      expect(provider.categoryByAlias('second')?.id, secondId);
      expect(provider.categories.where((item) => item.isDefault), hasLength(1));

      await provider.updateCategory(
        provider.categoryById(secondId)!.copyWith(enabled: false),
      );
      expect(provider.defaultCategoryForBase(baseId)?.id, firstId);
      expect(provider.categoryById(secondId)?.isDefault, isFalse);
    },
  );

  test('deleting a base explicitly deletes every child row', () async {
    final repository = _KnowledgeRepository();
    final provider = KnowledgeProvider(repository: repository);
    final baseId = await provider.addKnowledgeBase(name: 'Base');
    final categoryId = await provider.addCategory(
      knowledgeBaseId: baseId,
      name: 'Category',
      alias: 'category',
    );
    final entryId = await provider.addEntry(
      knowledgeBaseId: baseId,
      categoryId: categoryId,
      title: 'Entry',
    );
    final now = DateTime(2026, 7, 29);
    await provider.upsertSource(
      KnowledgeSource(
        id: 'source',
        knowledgeBaseId: baseId,
        entryId: entryId,
        title: 'Source',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await provider.upsertExplanation(
      KnowledgeExplanation(
        id: 'explanation',
        knowledgeBaseId: baseId,
        entryId: entryId,
        title: 'Explanation',
        content: 'Content',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await provider.deleteKnowledgeBase(baseId);

    expect(repository.lastDeleteBaseIds, [baseId]);
    expect(repository.lastDeleteCategoryIds, [categoryId]);
    expect(repository.lastDeleteEntryIds, [entryId]);
    expect(repository.lastDeleteSourceIds, ['source']);
    expect(repository.lastDeleteExplanationIds, ['explanation']);
  });

  test(
    'default falls back deterministically after auto annotate changes',
    () async {
      final repository = _KnowledgeRepository();
      final provider = KnowledgeProvider(repository: repository);
      final firstBase = await provider.addKnowledgeBase(name: 'First');
      final secondBase = await provider.addKnowledgeBase(name: 'Second');
      final firstId = await provider.addCategory(
        knowledgeBaseId: firstBase,
        name: 'First category',
        alias: 'fallback_first',
        autoAnnotate: true,
      );
      final secondId = await provider.addCategory(
        knowledgeBaseId: secondBase,
        name: 'Second category',
        alias: 'fallback_second',
        autoAnnotate: true,
        isDefault: true,
      );

      await provider.updateCategory(
        provider.categoryById(secondId)!.copyWith(autoAnnotate: false),
      );

      expect(provider.settings.defaultKnowledgeBaseId, firstBase);
      expect(provider.settings.defaultCategoryId, firstId);
      expect(provider.categoryById(firstId)?.isDefault, isTrue);
      expect(provider.categoryById(secondId)?.isDefault, isFalse);
      expect(repository.lastSettings?.defaultCategoryId, firstId);
    },
  );

  test(
    'category alias is globally unique and builds prompt snapshot',
    () async {
      final provider = KnowledgeProvider(repository: _KnowledgeRepository());
      final firstBase = await provider.addKnowledgeBase(name: 'First base');
      final secondBase = await provider.addKnowledgeBase(name: 'Second base');
      await provider.addCategory(
        knowledgeBaseId: firstBase,
        name: '人物',
        alias: 'person',
        annotationRule: '只标注有明确身份的人名',
        explanationPrompt: '解释人物背景',
        colorValue: 0xff123456,
        autoAnnotate: true,
        isDefault: true,
      );

      await expectLater(
        provider.addCategory(
          knowledgeBaseId: secondBase,
          name: '重复',
          alias: 'person',
        ),
        throwsArgumentError,
      );
      await expectLater(
        provider.addCategory(
          knowledgeBaseId: secondBase,
          name: '无效',
          alias: 'Person',
        ),
        throwsArgumentError,
      );

      final snapshot = provider.annotationPromptSnapshot;
      expect(snapshot.defaultCategory, 'person');
      expect(snapshot.categories.single.category, 'person');
      expect(snapshot.categories.single.aliases, isEmpty);
      expect(snapshot.categories.single.rule, '只标注有明确身份的人名');
      expect(provider.explanationPromptForAlias('person'), '解释人物背景');
    },
  );

  test('default knowledge base selects its first eligible category', () async {
    final provider = KnowledgeProvider(repository: _KnowledgeRepository());
    final firstBase = await provider.addKnowledgeBase(name: 'First');
    final secondBase = await provider.addKnowledgeBase(name: 'Second');
    await provider.addCategory(
      knowledgeBaseId: firstBase,
      name: 'First category',
      alias: 'base_api_first',
      autoAnnotate: true,
    );
    final manualId = await provider.addCategory(
      knowledgeBaseId: secondBase,
      name: 'Manual',
      alias: 'base_api_manual',
    );
    final eligibleId = await provider.addCategory(
      knowledgeBaseId: secondBase,
      name: 'Eligible',
      alias: 'base_api_eligible',
      autoAnnotate: true,
    );

    await provider.setDefaultKnowledgeBase(secondBase);

    expect(provider.defaultKnowledgeBase?.id, secondBase);
    expect(provider.settings.defaultCategoryId, eligibleId);
    await expectLater(
      provider.setDefaultCategory(manualId),
      throwsArgumentError,
    );
  });

  test('source and explanation must match the entry knowledge base', () async {
    final provider = KnowledgeProvider(repository: _KnowledgeRepository());
    final firstBase = await provider.addKnowledgeBase(name: 'First');
    final secondBase = await provider.addKnowledgeBase(name: 'Second');
    final entryId = await provider.addEntry(
      knowledgeBaseId: firstBase,
      title: 'Entry',
    );
    final now = DateTime(2026, 7, 29);

    await expectLater(
      provider.upsertSource(
        KnowledgeSource(
          id: 'source',
          knowledgeBaseId: secondBase,
          entryId: entryId,
          title: 'Source',
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      provider.upsertExplanation(
        KnowledgeExplanation(
          id: 'explanation',
          knowledgeBaseId: secondBase,
          entryId: entryId,
          title: 'Explanation',
          content: 'Content',
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('default category is unique globally across knowledge bases', () async {
    final provider = KnowledgeProvider(repository: _KnowledgeRepository());
    final firstBase = await provider.addKnowledgeBase(name: 'First');
    final secondBase = await provider.addKnowledgeBase(name: 'Second');
    final firstId = await provider.addCategory(
      knowledgeBaseId: firstBase,
      name: 'First category',
      alias: 'first_global',
      isDefault: true,
      autoAnnotate: true,
    );
    final secondId = await provider.addCategory(
      knowledgeBaseId: secondBase,
      name: 'Second category',
      alias: 'second_global',
      isDefault: true,
      autoAnnotate: true,
    );

    expect(provider.categoryById(firstId)?.isDefault, isFalse);
    expect(provider.categoryById(secondId)?.isDefault, isTrue);
    expect(provider.defaultCategory()?.id, secondId);
    expect(provider.defaultCategory(firstBase)?.id, firstId);
    expect(provider.defaultCategory(secondBase)?.id, secondId);

    await provider.deleteCategory(secondId);

    expect(provider.defaultCategory()?.id, firstId);
    expect(provider.categoryById(firstId)?.isDefault, isTrue);
  });

  test('load normalizes multiple defaults to one global default', () async {
    final now = DateTime(2026, 7, 29);
    final repository = _KnowledgeRepository(
      loadResult: KnowledgeLoadResult(
        bases: [
          KnowledgeBase(
            id: 'base-a',
            name: 'A',
            enabled: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
          KnowledgeBase(
            id: 'base-b',
            name: 'B',
            enabled: true,
            sortOrder: 1,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        categories: [
          KnowledgeCategory(
            id: 'category-a',
            knowledgeBaseId: 'base-a',
            name: 'A',
            alias: 'load_a',
            isDefault: true,
            autoAnnotate: true,
            enabled: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
          KnowledgeCategory(
            id: 'category-b',
            knowledgeBaseId: 'base-b',
            name: 'B',
            alias: 'load_b',
            isDefault: true,
            autoAnnotate: true,
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

    expect(provider.categories.where((item) => item.isDefault), hasLength(1));
    expect(provider.defaultCategory()?.id, 'category-a');
    expect(provider.defaultCategory('base-b')?.id, 'category-b');
  });

  test(
    'annotation snapshot and resolver use enabled auto-annotate categories',
    () async {
      final now = DateTime(2026, 7, 29);
      final provider = KnowledgeProvider(
        repository: _KnowledgeRepository(
          loadResult: KnowledgeLoadResult(
            bases: [
              KnowledgeBase(
                id: 'disabled-base',
                name: 'Disabled',
                enabled: false,
                sortOrder: 0,
                createdAt: now,
                updatedAt: now,
              ),
              KnowledgeBase(
                id: 'enabled-base',
                name: 'Enabled',
                enabled: true,
                sortOrder: 1,
                createdAt: now,
                updatedAt: now,
              ),
            ],
            categories: [
              KnowledgeCategory(
                id: 'disabled-base-category',
                knowledgeBaseId: 'disabled-base',
                name: 'Disabled base category',
                alias: 'disabled_base',
                autoAnnotate: true,
                isDefault: true,
                enabled: true,
                sortOrder: 0,
                createdAt: now,
                updatedAt: now,
              ),
              KnowledgeCategory(
                id: 'manual-category',
                knowledgeBaseId: 'enabled-base',
                name: 'Manual only',
                alias: 'manual_only',
                autoAnnotate: false,
                isDefault: false,
                enabled: true,
                sortOrder: 0,
                createdAt: now,
                updatedAt: now,
              ),
              KnowledgeCategory(
                id: 'person-category',
                knowledgeBaseId: 'enabled-base',
                name: '人物',
                alias: 'person',
                autoAnnotate: true,
                isDefault: false,
                enabled: true,
                sortOrder: 1,
                createdAt: now,
                updatedAt: now,
              ),
              KnowledgeCategory(
                id: 'place-category',
                knowledgeBaseId: 'enabled-base',
                name: '地点',
                alias: 'place',
                autoAnnotate: true,
                isDefault: false,
                enabled: true,
                sortOrder: 2,
                createdAt: now,
                updatedAt: now,
              ),
            ],
            entries: const [],
            sources: const [],
            explanations: const [],
          ),
        ),
      );

      await provider.load();

      expect(provider.annotationPromptSnapshot.defaultCategory, 'person');
      expect(
        provider.annotationPromptSnapshot.categories.map(
          (item) => item.category,
        ),
        ['person', 'place'],
      );
      expect(provider.resolveAnnotationCategory('person'), 'person-category');
      expect(provider.resolveAnnotationCategory('人物'), 'person-category');
      expect(provider.resolveAnnotationCategory('地点'), 'person-category');
      expect(provider.resolveAnnotationCategory('place'), 'place-category');
      expect(provider.resolveAnnotationCategory('unknown'), 'person-category');
      expect(
        provider.resolveAnnotationCategory('manual_only'),
        'person-category',
      );
    },
  );

  test('add base rolls memory back when persistence fails', () async {
    final repository = _KnowledgeRepository()..failNextSave = true;
    final provider = KnowledgeProvider(repository: repository);
    var notifications = 0;
    provider.addListener(() => notifications++);

    await expectLater(
      provider.addKnowledgeBase(name: 'Unsaved'),
      throwsA(isA<StateError>()),
    );

    expect(provider.knowledgeBases, isEmpty);
    expect(notifications, 2);

    final id = await provider.addKnowledgeBase(name: 'Saved');
    expect(provider.knowledgeBaseById(id)?.name, 'Saved');
    expect(repository.lastUpsertBases.single.id, id);
  });

  test('queued mutation runs after failed mutation rollback', () async {
    final repository = _KnowledgeRepository()..failNextSave = true;
    final provider = KnowledgeProvider(repository: repository);

    final failed = provider.addKnowledgeBase(name: 'Failed');
    final saved = provider.addKnowledgeBase(name: 'Saved');

    await expectLater(failed, throwsStateError);
    final savedId = await saved;
    expect(provider.knowledgeBases.map((item) => item.name), ['Saved']);
    expect(provider.knowledgeBases.single.id, savedId);
    expect(repository.lastUpsertBases.single.id, savedId);
  });

  test('failed category default update is atomic and retryable', () async {
    final repository = _KnowledgeRepository();
    final provider = KnowledgeProvider(repository: repository);
    final baseId = await provider.addKnowledgeBase(name: 'Base');
    final firstId = await provider.addCategory(
      knowledgeBaseId: baseId,
      name: 'First',
      alias: 'atomic_first',
      autoAnnotate: true,
    );
    final secondId = await provider.addCategory(
      knowledgeBaseId: baseId,
      name: 'Second',
      alias: 'atomic_second',
      autoAnnotate: true,
    );
    final update = provider.categoryById(secondId)!.copyWith(isDefault: true);
    repository.failNextSave = true;

    await expectLater(provider.updateCategory(update), throwsStateError);

    expect(provider.settings.defaultCategoryId, firstId);
    expect(provider.categoryById(firstId)?.isDefault, isTrue);
    expect(provider.categoryById(secondId)?.isDefault, isFalse);

    await provider.updateCategory(update);
    expect(provider.settings.defaultCategoryId, secondId);
    expect(provider.categoryById(secondId)?.isDefault, isTrue);
    expect(repository.lastSettings?.defaultCategoryId, secondId);
  });

  test('failed explanation bundle retry persists every new row', () async {
    final repository = _KnowledgeRepository();
    final provider = KnowledgeProvider(repository: repository);
    final baseId = await provider.addKnowledgeBase(name: 'Base');
    final categoryId = await provider.addCategory(
      knowledgeBaseId: baseId,
      name: 'People',
      alias: 'bundle_people',
      autoAnnotate: true,
    );
    repository.failNextSave = true;

    Future<({KnowledgeEntry entry, KnowledgeExplanation explanation})> save() =>
        provider.saveExplanationBundle(
          categoryId: categoryId,
          title: 'Ada',
          entryContent: 'Mathematician',
          explanation: 'Pioneer',
          sourceTitle: 'Biography',
          sourceUrl: 'https://example.com/ada',
        );

    await expectLater(save(), throwsStateError);
    expect(provider.entries, isEmpty);
    expect(provider.sources, isEmpty);
    expect(provider.explanations, isEmpty);

    final saved = await save();
    expect(provider.entries.single.id, saved.entry.id);
    expect(repository.lastUpsertEntries, hasLength(1));
    expect(repository.lastUpsertSources, hasLength(1));
    expect(repository.lastUpsertExplanations, hasLength(1));
    expect(repository.lastUpsertSources.single.entryId, saved.entry.id);
    expect(repository.lastUpsertExplanations.single.entryId, saved.entry.id);
  });
}

class _KnowledgeRepository extends KnowledgeRepository {
  _KnowledgeRepository({this.loadResult}) : super();

  final KnowledgeLoadResult? loadResult;

  List<String> lastDeleteBaseIds = [];
  List<String> lastDeleteCategoryIds = [];
  List<String> lastDeleteEntryIds = [];
  List<String> lastDeleteSourceIds = [];
  List<String> lastDeleteExplanationIds = [];
  KnowledgeSettings? lastSettings;
  bool failNextSave = false;
  List<KnowledgeBase> lastUpsertBases = [];
  List<KnowledgeEntry> lastUpsertEntries = [];
  List<KnowledgeSource> lastUpsertSources = [];
  List<KnowledgeExplanation> lastUpsertExplanations = [];

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
  Future<void> replace(KnowledgeLoadResult value) async {}

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
    KnowledgeSettings? settings,
  }) async {
    lastUpsertBases = upsertBases.toList();
    lastUpsertEntries = upsertEntries.toList();
    lastUpsertSources = upsertSources.toList();
    lastUpsertExplanations = upsertExplanations.toList();
    lastDeleteBaseIds = deleteBaseIds.toList();
    lastDeleteCategoryIds = deleteCategoryIds.toList();
    lastDeleteEntryIds = deleteEntryIds.toList();
    lastDeleteSourceIds = deleteSourceIds.toList();
    lastDeleteExplanationIds = deleteExplanationIds.toList();
    lastSettings = settings;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('injected save failure');
    }
  }
}
