import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/models/roleplay.dart';
import 'package:lynai/services/api_service.dart';
import 'package:lynai/services/roleplay_service.dart';

void main() {
  test('speaker reads latest knowledge annotation prompt every turn', () async {
    final api = _CapturingApiService();
    var prompt = 'first annotation prompt';
    final service = RoleplayService(
      api: api,
      knowledgeAnnotationPrompt: () => prompt,
    );

    await service.speak(
      thread: _thread,
      participant: _participant,
      model: _model,
    );
    prompt = 'second annotation prompt';
    await service.speak(
      thread: _thread,
      participant: _participant,
      model: _model,
    );

    expect(
      api.requests[0].first['content'],
      contains('first annotation prompt'),
    );
    expect(
      api.requests[0].first['content'],
      isNot(contains('second annotation prompt')),
    );
    expect(
      api.requests[1].first['content'],
      contains('second annotation prompt'),
    );
  });

  test(
    'director prompt does not include knowledge annotation prompt',
    () async {
      final api = _CapturingApiService(
        response: '{"action":"wait_user","reason":"done"}',
      );
      final service = RoleplayService(
        api: api,
        knowledgeAnnotationPrompt: () => 'annotation marker',
      );

      await service.decideNext(thread: _thread, model: _model);

      expect(
        api.requests.single.map((message) => message['content']).join('\n'),
        isNot(contains('annotation marker')),
      );
    },
  );
}

class _CapturingApiService extends ApiService {
  _CapturingApiService({this.response = 'reply'});

  final String response;
  final List<List<Map<String, dynamic>>> requests = [];

  @override
  Future<ChatResponse> sendChatRequest(
    ModelConfig config,
    List<Map<String, dynamic>> messages, {
    bool thinking = false,
    List<Map<String, dynamic>> tools = const [],
    Object? toolChoice,
  }) async {
    requests.add(messages);
    return ChatResponse(content: response);
  }
}

final _now = DateTime(2026, 7, 29);

const _participant = RoleplayParticipant(
  id: 'character',
  name: 'Character',
  systemPrompt: 'Stay in character.',
);

final _thread = RoleplayThread(
  id: 'thread',
  scenarioId: 'scenario',
  title: 'Thread',
  scenarioTitle: 'Scenario',
  scenario: 'A test scene.',
  director: const RoleplayDirector(),
  participants: const [_participant],
  playerParticipantId: '',
  createdAt: _now,
  updatedAt: _now,
);

final _model = ModelConfig(
  id: 'model',
  name: 'Model',
  endpoint: 'https://example.com',
  apiKey: '',
  modelName: 'test',
  apiType: 'openai',
  priority: 0,
);
