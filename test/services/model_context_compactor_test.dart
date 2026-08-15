import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/services/agent_context_builder.dart';
import 'package:lynai/services/agent_cancellation.dart';
import 'package:lynai/services/api_service.dart';
import 'package:lynai/services/model_context_compactor.dart';

class _FakeApiService extends ApiService {
  _FakeApiService({this.failures = 0});

  int failures;
  int calls = 0;

  @override
  Future<ChatResponse> sendChatRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
    List<Map<String, dynamic>> tools = const [],
    Object? toolChoice,
  }) async {
    calls++;
    if (failures > 0) {
      failures--;
      throw Exception('boom');
    }
    return const ChatResponse(content: '压缩摘要');
  }
}

void main() {
  final model = ModelConfig(
    id: '1',
    name: 'Provider',
    endpoint: 'https://example.com',
    apiKey: 'key',
    modelName: 'model-a',
    apiType: 'openai',
    priority: 0,
  );
  final source = AgentCancellationSource();

  test('compactor returns a bounded checkpoint on success', () async {
    final api = _FakeApiService();
    final compactor = ModelContextCompactor(api: api, model: model);
    final result = await compactor.compact(
      AgentCompactionRequest(
        droppedMessages: const [
          {'role': 'user', 'content': '旧消息'},
        ],
        targetTokens: 512,
        cancellationToken: source.token,
      ),
    );

    expect(result, isNotNull);
    expect(result!.summary, '压缩摘要');
    expect(api.calls, 1);
  });

  test('compactor returns null and keeps run alive on failure', () async {
    final api = _FakeApiService(failures: 1);
    final compactor = ModelContextCompactor(api: api, model: model);
    final result = await compactor.compact(
      AgentCompactionRequest(
        droppedMessages: const [
          {'role': 'user', 'content': '旧消息'},
        ],
        targetTokens: 512,
        cancellationToken: source.token,
      ),
    );

    expect(result, isNull);
  });
}
