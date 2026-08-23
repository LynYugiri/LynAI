import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/services/api_service.dart';
import 'package:lynai/services/on_device_llm_service.dart';

import '../support/fake_on_device_llm_backend.dart';

void main() {
  late FakeOnDeviceLlmBackend backend;
  late OnDeviceLlmService service;
  late ApiService api;

  setUp(() {
    backend = FakeOnDeviceLlmBackend(
      status: FakeOnDeviceLlmBackend.readyStatus,
    );
    service = OnDeviceLlmService(backend: backend);
    api = ApiService(localLlm: service);
  });

  tearDown(() {
    service.dispose();
  });

  test(
    'sendStreamRequest uses the same StreamChunk contract for local model',
    () async {
      final chunksFuture = api.sendStreamRequest(ModelConfig.localBlueLm(), [
        {'role': 'user', 'content': '你好'},
      ]).toList();
      await Future<void>.delayed(Duration.zero);
      final generate = backend.calls.firstWhere(
        (call) => call.method == 'generate',
      );
      final requestId = generate.arguments['requestId'] as String;
      backend.emit({'type': 'token', 'requestId': requestId, 'token': '你好'});
      backend.emit({'type': 'completed', 'requestId': requestId});

      final chunks = await chunksFuture;

      expect(
        chunks
            .where((chunk) => chunk.content != null)
            .map((chunk) => chunk.content),
        ['你好'],
      );
      expect(chunks.last.isDone, isTrue);
      expect(generate.arguments['prompt'], '[|Human|]:你好\n[|AI|]:');
    },
  );

  test(
    'sendChatRequest returns a normal ChatResponse for local model',
    () async {
      final responseFuture = api.sendChatRequest(ModelConfig.localBlueLm(), [
        {'role': 'user', 'content': '你好'},
      ]);
      await Future<void>.delayed(Duration.zero);
      final generate = backend.calls.firstWhere(
        (call) => call.method == 'generate',
      );
      final requestId = generate.arguments['requestId'] as String;
      backend.emit({'type': 'token', 'requestId': requestId, 'token': '你'});
      backend.emit({'type': 'token', 'requestId': requestId, 'token': '好'});
      backend.emit({'type': 'completed', 'requestId': requestId});

      final response = await responseFuture;

      expect(response.content, '你好');
      expect(response.toolCalls, isEmpty);
    },
  );

  test('rejects tools with a typed LocalLlmException', () async {
    await expectLater(
      api
          .sendStreamRequest(
            ModelConfig.localBlueLm(),
            [
              {'role': 'user', 'content': '你好'},
            ],
            tools: [
              {
                'type': 'function',
                'function': {'name': 'noop', 'parameters': {}},
              },
            ],
          )
          .toList(),
      throwsA(
        isA<LocalLlmException>().having(
          (error) => error.code,
          'code',
          'tools_not_supported',
        ),
      ),
    );
  });

  test(
    'propagates SDK overflow as LocalLlmException for compaction path',
    () async {
      final chunksFuture = api.sendStreamRequest(ModelConfig.localBlueLm(), [
        {'role': 'user', 'content': 'long context'},
      ]).toList();
      await Future<void>.delayed(Duration.zero);
      final generate = backend.calls.firstWhere(
        (call) => call.method == 'generate',
      );
      final requestId = generate.arguments['requestId'] as String;
      backend.emit({
        'type': 'error',
        'requestId': requestId,
        'code': -3070,
        'message': 'prompt too long',
      });

      await expectLater(
        chunksFuture,
        throwsA(
          isA<LocalLlmException>().having(
            (error) => error.isContextOverflow,
            'overflow',
            isTrue,
          ),
        ),
      );
    },
  );
}
