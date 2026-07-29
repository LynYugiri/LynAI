import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/knowledge_base.dart';
import 'package:lynai/models/knowledge_category.dart';
import 'package:lynai/models/knowledge_entry.dart';
import 'package:lynai/models/knowledge_explanation.dart';
import 'package:lynai/models/knowledge_settings.dart';
import 'package:lynai/providers/knowledge_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/repositories/knowledge_repository.dart';
import 'package:lynai/services/api_service.dart';
import 'package:lynai/services/knowledge_explanation_service.dart';

void main() {
  test('buildRequestText includes only provided context fields', () {
    expect(
      KnowledgeExplanationService.buildRequestText(
        text: '光合作用',
        context: '植物生理学段落',
        sourceTitle: '教材',
        sourceUrl: 'https://example.com/book',
      ),
      contains('待解释文本：\n光合作用'),
    );
    expect(
      KnowledgeExplanationService.buildRequestText(
        text: '光合作用',
        context: '植物生理学段落',
        sourceTitle: '教材',
        sourceUrl: 'https://example.com/book',
      ),
      contains('上下文：\n植物生理学段落'),
    );
  });

  test(
    'saveGeneratedExplanation reuses entry source and explanation',
    () async {
      final repository = _KnowledgeRepository();
      final knowledge = KnowledgeProvider(repository: repository);
      final now = DateTime(2026, 7, 29);
      await knowledge.replaceAll(
        knowledgeBases: [
          KnowledgeBase(
            id: 'base',
            name: '知识库',
            enabled: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        categories: [
          KnowledgeCategory(
            id: 'category',
            knowledgeBaseId: 'base',
            name: '概念',
            alias: 'concept',
            isDefault: true,
            enabled: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        entries: const [],
        sources: const [],
        explanations: const [],
      );

      final first = await knowledge.saveExplanationBundle(
        categoryId: 'category',
        title: '光合作用',
        entryContent: '上下文一',
        explanation: '解释一',
        sourceTitle: '教材',
        sourceUrl: 'https://example.com/book',
      );
      final second = await knowledge.saveExplanationBundle(
        categoryId: 'category',
        title: ' 光合作用 ',
        entryContent: '上下文二',
        explanation: '解释二',
        sourceTitle: '教材新版',
        sourceUrl: 'https://example.com/book',
      );

      expect(second.entry.id, first.entry.id);
      expect(knowledge.entries, hasLength(1));
      expect(knowledge.sources, hasLength(1));
      expect(knowledge.sources.single.knowledgeBaseId, 'base');
      expect(knowledge.sources.single.title, '教材新版');
      expect(knowledge.explanations, hasLength(1));
      expect(knowledge.explanations.single.knowledgeBaseId, 'base');
      expect(knowledge.explanations.single.content, '解释二');
      expect(repository.saveCalls, 2);
      expect(repository.lastUpsertEntries, isEmpty);
      expect(repository.lastUpsertSources, hasLength(1));
      expect(repository.lastUpsertExplanations, hasLength(1));
    },
  );

  test('findSaved ignores disabled entry and disabled parents', () async {
    final repository = _KnowledgeRepository();
    final knowledge = KnowledgeProvider(repository: repository);
    final now = DateTime(2026, 7, 29);
    await knowledge.replaceAll(
      knowledgeBases: [
        KnowledgeBase(
          id: 'base',
          name: '知识库',
          enabled: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      categories: [
        KnowledgeCategory(
          id: 'category',
          knowledgeBaseId: 'base',
          name: '概念',
          alias: 'concept',
          isDefault: false,
          enabled: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      entries: [
        KnowledgeEntry(
          id: 'entry',
          knowledgeBaseId: 'base',
          categoryId: 'category',
          title: '光合作用',
          content: '',
          enabled: false,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      sources: const [],
      explanations: [
        KnowledgeExplanation(
          id: 'explanation',
          knowledgeBaseId: 'base',
          entryId: 'entry',
          title: 'AI 释义',
          content: '旧解释',
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    final service = KnowledgeExplanationService(
      api: ApiService(),
      modelConfigs: ModelConfigProvider(),
      settings: SettingsProvider(),
      knowledge: knowledge,
    );

    expect(service.findSaved(categoryId: 'category', text: '光合作用'), isNull);
  });
}

class _KnowledgeRepository extends KnowledgeRepository {
  int saveCalls = 0;
  List lastUpsertEntries = [];
  List lastUpsertSources = [];
  List lastUpsertExplanations = [];

  @override
  Future<void> replace(KnowledgeLoadResult value) async {}

  @override
  Future<void> saveChanges({
    Iterable upsertBases = const [],
    Iterable<String> deleteBaseIds = const [],
    Iterable upsertCategories = const [],
    Iterable<String> deleteCategoryIds = const [],
    Iterable upsertEntries = const [],
    Iterable<String> deleteEntryIds = const [],
    Iterable upsertSources = const [],
    Iterable<String> deleteSourceIds = const [],
    Iterable upsertExplanations = const [],
    Iterable<String> deleteExplanationIds = const [],
    KnowledgeSettings? settings,
  }) async {
    saveCalls++;
    lastUpsertEntries = upsertEntries.toList();
    lastUpsertSources = upsertSources.toList();
    lastUpsertExplanations = upsertExplanations.toList();
  }
}
