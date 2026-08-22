import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/knowledge_entry.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/services/api_service.dart';
import 'package:lynai/services/memory_card_generation_service.dart';

import 'support/memory_repositories.dart';

class _FakeApiService extends ApiService {
  _FakeApiService(this.responses);

  final List<ChatResponse> responses;
  int requestCount = 0;
  void Function(int requestIndex)? onRequest;

  @override
  Future<ChatResponse> sendChatRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
    List<Map<String, dynamic>> tools = const [],
    Object? toolChoice,
  }) async {
    onRequest?.call(requestCount);
    final index = requestCount;
    requestCount++;
    if (index >= responses.length) {
      return const ChatResponse(content: '{"cards":[]}');
    }
    return responses[index];
  }
}

KnowledgeEntry _entry(String id, {String content = ''}) => KnowledgeEntry(
  id: id,
  knowledgeBaseId: 'base-1',
  title: '条目 $id',
  content: content.isEmpty ? '条目 $id 的正文内容' : content,
  enabled: true,
  sortOrder: 0,
  createdAt: DateTime.utc(2026, 8, 16),
  updatedAt: DateTime.utc(2026, 8, 16),
);

Future<MemoryCardGenerationService> _service(_FakeApiService api) async {
  final repository = MemoryModelConfigRepository()
    ..seed([
      ModelConfig(
        id: 'model-1',
        name: 'model-1',
        endpoint: 'https://example.com',
        apiKey: 'key',
        modelName: 'model-1',
        apiType: 'openai',
        priority: 0,
      ),
    ]);
  final modelConfigs = ModelConfigProvider(repository: repository);
  await modelConfigs.loadModels();
  return MemoryCardGenerationService(
    api: api,
    modelConfigs: modelConfigs,
    settings: memorySettingsProvider(),
  );
}

void main() {
  test('每个条目生成且只生成 1 张卡片，并完成来源覆盖核账', () async {
    final api = _FakeApiService([
      const ChatResponse(
        content:
            '{"cards":['
            '{"front":"q1","back":"a1","sourceEntryId":"e1"},'
            '{"front":"q2","back":"a2","sourceEntryId":"e2"},'
            '{"front":"q3","back":"a3","sourceEntryId":"e3"}'
            ']}',
      ),
    ]);
    final service = await _service(api);

    final result = await service.generate(
      entries: [_entry('e1'), _entry('e2'), _entry('e3')],
    );

    expect(result.cards, hasLength(3));
    expect(result.coveredEntryIds.toSet(), {'e1', 'e2', 'e3'});
    expect(result.missingEntryIds, isEmpty);
    expect(result.cards.map((card) => card.sourceEntryId).toSet(), {
      'e1',
      'e2',
      'e3',
    });
  });

  test('模型给同一来源多张卡片时只保留第一张，并标记缺失条目', () async {
    final api = _FakeApiService([
      const ChatResponse(
        content:
            '{"cards":['
            '{"front":"q1a","back":"a1a","sourceEntryId":"e1"},'
            '{"front":"q1b","back":"a1b","sourceEntryId":"e1"},'
            '{"front":"q2","back":"a2","sourceEntryId":"e2"},'
            '{"front":"bad","back":"bad","sourceEntryId":"e99"}'
            ']}',
      ),
    ]);
    final service = await _service(api);

    final result = await service.generate(
      entries: [_entry('e1'), _entry('e2'), _entry('e3')],
    );

    expect(result.cards, hasLength(2));
    expect(result.coveredEntryIds.toSet(), {'e1', 'e2'});
    expect(result.missingEntryIds, ['e3']);
    expect(result.warnings, isNotEmpty);
  });

  test('模型不返回 sourceEntryId 时整批视为无效并抛出可读错误', () async {
    final api = _FakeApiService([
      const ChatResponse(
        content:
            '{"cards":[{"front":"q1","back":"a1"},'
            '{"front":"q2","back":"a2"}]}',
      ),
    ]);
    final service = await _service(api);

    await expectLater(
      service.generate(entries: [_entry('e1'), _entry('e2')]),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('sourceEntryId'),
        ),
      ),
    );
  });

  test('分批生成时支持进度回调，并在取消后停止', () async {
    final longContent = '知识内容' * 6000;
    final api = _FakeApiService([
      ChatResponse(
        content: '{"cards":[{"front":"q1","back":"a1","sourceEntryId":"e1"}]}',
      ),
    ]);
    var cancelled = false;
    api.onRequest = (index) {
      if (index >= 0) cancelled = true;
    };
    final service = await _service(api);
    final entries = [
      _entry('e1', content: longContent),
      _entry('e2', content: longContent),
      _entry('e3', content: longContent),
      _entry('e4', content: longContent),
      _entry('e5', content: longContent),
    ];
    final progress = <(int, int)>[];

    await expectLater(
      service.generate(
        entries: entries,
        onBatchProgress: (done, total) => progress.add((done, total)),
        isCancelled: () => cancelled,
      ),
      throwsA(
        isA<StateError>().having((error) => error.message, 'message', '生成已取消'),
      ),
    );
    expect(progress, isNotEmpty);
    expect(progress.first.$2, 5);
  });
}
