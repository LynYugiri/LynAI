import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/knowledge_base.dart';
import 'package:lynai/models/knowledge_category.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/providers/knowledge_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/repositories/knowledge_repository.dart';
import 'package:lynai/services/api_service.dart';
import 'package:lynai/services/knowledge_explanation_service.dart';
import 'package:lynai/widgets/knowledge_explanation_dialog.dart';

void main() {
  testWidgets('changing category discards the old generated explanation', (
    tester,
  ) async {
    final api = _DeferredApi();
    final knowledge = await _knowledge();
    final service = KnowledgeExplanationService(
      api: api,
      modelConfigs: _ModelProvider(),
      settings: SettingsProvider(),
      knowledge: knowledge,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KnowledgeExplanationDialog(
            service: service,
            knowledge: knowledge,
            text: '条目',
            initialCategoryId: 'first',
            sourceContext: '',
            sourceTitle: '',
            sourceUrl: '',
            saveAutomatically: false,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump();
    await tester.tap(find.text('第二类').last);
    await tester.pump();
    expect(api.requests, ['first', 'second']);

    api.complete('first', '旧类别解释');
    await tester.pump();
    expect(find.textContaining('旧类别解释'), findsNothing);

    api.complete('second', '新类别解释');
    await tester.pumpAndSettle();
    expect(find.textContaining('新类别解释'), findsWidgets);
    expect(find.textContaining('旧类别解释'), findsNothing);
  });

  testWidgets('closing before generation completes does not save', (
    tester,
  ) async {
    final api = _DeferredApi();
    final repository = _Repository();
    final knowledge = await _knowledge(repository: repository);
    final service = KnowledgeExplanationService(
      api: api,
      modelConfigs: _ModelProvider(),
      settings: SettingsProvider(),
      knowledge: knowledge,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KnowledgeExplanationDialog(
            service: service,
            knowledge: knowledge,
            text: '条目',
            initialCategoryId: 'first',
            sourceContext: '',
            sourceTitle: '',
            sourceUrl: '',
            saveAutomatically: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('关闭'));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    api.complete('first', '晚到解释');
    await tester.pump();
    expect(repository.bundleWrites, 0);
  });
}

Future<KnowledgeProvider> _knowledge({_Repository? repository}) async {
  final provider = KnowledgeProvider(repository: repository ?? _Repository());
  final now = DateTime(2026, 7, 29);
  await provider.replaceAll(
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
        id: 'first',
        knowledgeBaseId: 'base',
        name: '第一类',
        alias: 'first',
        explanationPrompt: '第一',
        enabled: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
      KnowledgeCategory(
        id: 'second',
        knowledgeBaseId: 'base',
        name: '第二类',
        alias: 'second',
        explanationPrompt: '第二',
        enabled: true,
        sortOrder: 1,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    entries: const [],
    sources: const [],
    explanations: const [],
  );
  return provider;
}

class _ModelProvider extends ModelConfigProvider {
  @override
  List<ModelConfig> enabledModelsByCategory(String category) => [_model];
}

final _model = ModelConfig(
  id: 'model',
  name: 'Model',
  endpoint: 'https://example.com',
  apiKey: '',
  modelName: 'model',
  apiType: 'openai',
  priority: 0,
);

class _DeferredApi extends ApiService {
  final requests = <String>[];
  final _completers = <String, Completer<ChatResponse>>{};

  @override
  Future<ChatResponse> sendChatRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
    List<Map<String, dynamic>> tools = const [],
    Object? toolChoice,
  }) {
    final system = messages.first['content'].toString();
    final category = system.contains('第二') ? 'second' : 'first';
    requests.add(category);
    return (_completers[category] = Completer<ChatResponse>()).future;
  }

  void complete(String category, String content) {
    _completers[category]!.complete(ChatResponse(content: content));
  }
}

class _Repository extends KnowledgeRepository {
  int bundleWrites = 0;

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
  }) async {
    if (upsertExplanations.isNotEmpty) bundleWrites++;
  }
}
