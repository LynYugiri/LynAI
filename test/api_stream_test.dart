import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/services/api_service.dart';
import 'package:lynai/services/backend_client.dart';

void main() {
  test(
    'OpenAI-compatible stream preserves basic StreamChunk semantics',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(
        server.first.then((request) async {
          await utf8.decoder.bind(request).join();
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );
          request.response.write(
            ': ping\r\ndata: {"choices":[{"delta":{"content":"hello"},\r\n'
            'data: "finish_reason":null}]}\r\n\r\n'
            'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\r\n\r\n',
          );
          await request.response.close();
        }),
      );

      try {
        final chunks = await ApiService().sendStreamRequest(
          _model(server, 'openai'),
          const [
            {'role': 'user', 'content': 'hello'},
          ],
        ).toList();

        expect(
          chunks.where((chunk) => chunk.content != null).single.content,
          'hello',
        );
        expect(chunks.last.isDone, isTrue);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test('Anthropic stream preserves text, thinking, and done chunks', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.first.then((request) async {
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write(
          'event: content_block_delta\r\n'
          'data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"think"}}\r\n\r\n'
          'event: content_block_delta\r\n'
          'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"answer"}}\r\n\r\n'
          'event: message_stop\r\n'
          'data: {"type":"message_stop"}\r\n\r\n',
        );
        await request.response.close();
      }),
    );

    try {
      final chunks = await ApiService().sendStreamRequest(
        _model(server, 'anthropic'),
        const [
          {'role': 'user', 'content': 'hello'},
        ],
      ).toList();

      expect(chunks[0].reasoningContent, 'think');
      expect(chunks[1].content, 'answer');
      expect(chunks.last.isDone, isTrue);
    } finally {
      await server.close(force: true);
    }
  });

  test('valid non-object stream JSON reports a protocol error', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.first.then((request) async {
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write('data: []\n\n');
        await request.response.close();
      }),
    );

    try {
      await expectLater(
        ApiService()
            .sendStreamRequest(_model(server, 'openai'), const [])
            .toList(),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('顶层 JSON 必须是 object'),
          ),
        ),
      );
    } finally {
      await server.close(force: true);
    }
  });

  test('malformed OpenAI SSE JSON is not skipped', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.first.then((request) async {
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write('data: {invalid}\n\n');
        await request.response.close();
      }),
    );

    try {
      await expectLater(
        ApiService()
            .sendStreamRequest(_model(server, 'openai'), const [])
            .toList(),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('OpenAI SSE 格式错误'),
          ),
        ),
      );
    } finally {
      await server.close(force: true);
    }
  });

  test('malformed streamed tool arguments fail the stream', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.first.then((request) async {
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write(
          'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call-1","function":{"name":"tool","arguments":"{"}}]},"finish_reason":"tool_calls"}]}\n\n',
        );
        await request.response.close();
      }),
    );

    try {
      await expectLater(
        ApiService()
            .sendStreamRequest(_model(server, 'openai'), const [])
            .toList(),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('工具参数不是合法 JSON'),
          ),
        ),
      );
    } finally {
      await server.close(force: true);
    }
  });

  test('OpenAI stream rejects EOF before a completion marker', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.first.then((request) async {
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write(
          'data: {"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}\n\n',
        );
        await request.response.close();
      }),
    );

    try {
      await expectLater(
        ApiService()
            .sendStreamRequest(_model(server, 'openai'), const [])
            .toList(),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('完成标记前结束'),
          ),
        ),
      );
    } finally {
      await server.close(force: true);
    }
  });

  test('managed stream parses canonical SSE only', () async {
    final fixture =
        jsonDecode(
              await File('test/fixtures/canonical_chat.json').readAsString(),
            )
            as Map<String, dynamic>;
    final sse = fixture['sse'] as List<dynamic>;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? requestBody;
    unawaited(
      server.first.then((request) async {
        expect(request.uri.path, '/relay/chat');
        requestBody =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        for (final chunk in sse) {
          request.response.write(
            'event: chunk\ndata: ${jsonEncode(chunk)}\n\n',
          );
        }
        await request.response.close();
      }),
    );
    final backend = BackendClient()
      ..configure('http://${server.address.host}:${server.port}')
      ..setTokens('token', 'refresh-token');

    try {
      final chunks = await ApiService(backend: backend)
          .sendStreamRequest(
            ModelConfig(
              id: 'managed',
              name: 'managed',
              endpoint: 'http://${server.address.host}:${server.port}/relay',
              apiKey: '',
              modelName: 'test-model',
              apiType: '',
              priority: 0,
              managed: true,
            ),
            const [
              {'role': 'user', 'content': 'hello'},
            ],
            thinking: true,
            tools: const [
              {
                'type': 'function',
                'function': {
                  'name': 'done',
                  'description': 'Finish',
                  'parameters': {'type': 'object'},
                },
              },
            ],
            toolChoice: const {'name': 'done'},
          )
          .toList();

      expect(requestBody?.containsKey('providerId'), isFalse);
      expect(requestBody?['model'], 'test-model');
      expect(requestBody?['reasoning'], {'enabled': true});
      expect(requestBody?['tools'], [
        {
          'name': 'done',
          'description': 'Finish',
          'parameters': {'type': 'object'},
        },
      ]);
      expect(requestBody?['toolChoice'], {'name': 'done'});
      expect(chunks[0].reasoningContent, 'check');
      expect(chunks[0].content, 'sun');
      expect(chunks[1].content, 'ny');
      expect(chunks.last.toolCalls.single.name, 'weather');
      expect(chunks.last.isDone, isTrue);
    } finally {
      backend.dispose();
      await server.close(force: true);
    }
  });

  test('managed speech uses active model Vivo LASR workflow', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? requestPath;
    Map<String, dynamic>? requestBody;
    unawaited(
      server.first.then((request) async {
        requestPath = request.uri.path;
        requestBody =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        request.response.statusCode = 500;
        await request.response.close();
      }),
    );
    final backend = BackendClient()
      ..configure('http://${server.address.host}:${server.port}')
      ..setTokens('token', 'refresh-token');
    final model = ModelConfig(
      id: 'managed-speech',
      name: 'managed-speech',
      category: ModelConfig.categorySpeech,
      endpoint: 'http://${server.address.host}:${server.port}/relay',
      apiKey: '',
      modelName: 'vivo-lasr',
      apiType: '',
      priority: 0,
      managed: true,
      models: [
        ModelEntry(name: 'vivo-lasr', enabled: true, workflow: 'vivo_lasr'),
        ModelEntry(name: 'generic-asr', enabled: true),
      ],
    );

    try {
      await expectLater(
        ApiService(
          backend: backend,
        ).transcribeAudio(model, Uint8List.fromList([1, 2, 3])),
        throwsException,
      );
      expect(requestPath, '/relay/speech/create');
      expect(requestBody?['model'], 'vivo-lasr');
      expect(requestBody?.containsKey('providerId'), isFalse);
    } finally {
      backend.dispose();
      await server.close(force: true);
    }
  });

  test('managed media requests send model without providerId', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String, String>{};
    unawaited(() async {
      await for (final request in server) {
        final body = await utf8.decoder.bind(request).join();
        requests[request.uri.path] = body;
        request.response.headers.contentType = ContentType.json;
        switch (request.uri.path) {
          case '/relay/ocr':
            request.response.write(jsonEncode({'text': 'ocr'}));
          case '/relay/transcribe':
            request.response.write(jsonEncode({'text': 'speech'}));
          case '/relay/images/generations':
            request.response.write(
              jsonEncode({
                'data': [
                  {'url': 'https://example.com/image.png'},
                ],
              }),
            );
        }
        await request.response.close();
      }
    }());
    final backend = BackendClient()
      ..configure('http://${server.address.host}:${server.port}')
      ..setTokens('token', 'refresh-token');
    final api = ApiService(backend: backend);

    try {
      final ocrModel = _managedModel(
        server,
        modelName: 'ocr-model',
      ).copyWith(category: ModelConfig.categoryOcr);
      final speechModel = _managedModel(
        server,
        modelName: 'speech-model',
      ).copyWith(category: ModelConfig.categorySpeech);
      final imageModel = _managedModel(
        server,
        modelName: 'image-model',
      ).copyWith(category: ModelConfig.categoryImageGeneration);

      expect(
        await api.recognizeImageText(ocrModel, Uint8List.fromList([1, 2, 3])),
        'ocr',
      );
      expect(
        await api.transcribeAudio(speechModel, Uint8List.fromList([1, 2, 3])),
        'speech',
      );
      expect(await api.generateImages(imageModel, 'cat'), [
        'https://example.com/image.png',
      ]);

      final ocrBody = requests['/relay/ocr']!;
      expect(ocrBody, contains('name="model"'));
      expect(ocrBody, contains('ocr-model'));
      expect(ocrBody, isNot(contains('providerId')));

      final transcriptionBody = requests['/relay/transcribe']!;
      expect(transcriptionBody, contains('name="model"'));
      expect(transcriptionBody, contains('speech-model'));
      expect(transcriptionBody, isNot(contains('providerId')));

      final imageBody =
          jsonDecode(requests['/relay/images/generations']!)
              as Map<String, dynamic>;
      expect(imageBody['model'], 'image-model');
      expect(imageBody.containsKey('providerId'), isFalse);
    } finally {
      api.dispose();
      backend.dispose();
      await server.close(force: true);
    }
  });

  test('managed stream rejects EOF before canonical done', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.first.then((request) async {
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write('event: chunk\ndata: {"content":"partial"}\n\n');
        await request.response.close();
      }),
    );
    final backend = BackendClient()
      ..configure('http://${server.address.host}:${server.port}')
      ..setTokens('token', 'refresh-token');

    try {
      await expectLater(
        ApiService(
          backend: backend,
        ).sendStreamRequest(_managedModel(server), const []).toList(),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('done=true 前结束'),
          ),
        ),
      );
    } finally {
      backend.dispose();
      await server.close(force: true);
    }
  });

  test('managed non-stream response uses nested message contract', () async {
    final fixture =
        jsonDecode(
              await File('test/fixtures/canonical_chat.json').readAsString(),
            )
            as Map<String, dynamic>;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? requestBody;
    unawaited(
      server.first.then((request) async {
        requestBody =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(fixture['response']));
        await request.response.close();
      }),
    );
    final backend = BackendClient()
      ..configure('http://${server.address.host}:${server.port}')
      ..setTokens('token', 'refresh-token');

    try {
      final response = await ApiService(backend: backend).sendChatRequest(
        _managedModel(
          server,
          modelName: 'model-1',
          extraParams: const {'thinkingBudgetTokens': 2048},
        ),
        const [
          {'role': 'user', 'content': 'weather?'},
        ],
        thinking: true,
        tools: const [
          {
            'type': 'function',
            'function': {
              'name': 'weather',
              'description': 'Get weather',
              'parameters': {
                'type': 'object',
                'properties': {
                  'city': {'type': 'string'},
                },
                'required': ['city'],
              },
            },
          },
        ],
        toolChoice: const {'name': 'weather'},
      );
      expect(requestBody, fixture['request']);
      expect(response.content, 'sunny');
      expect(response.reasoning, 'checked forecast');
      expect(response.toolCalls.single.name, 'weather');
      expect(response.toolCalls.single.arguments, {'city': 'Shanghai'});
    } finally {
      backend.dispose();
      await server.close(force: true);
    }
  });

  test(
    'managed request converts multimodal and tool content to canonical parts',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Map<String, dynamic>? requestBody;
      unawaited(
        server.first.then((request) async {
          requestBody =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '{"message":{"role":"assistant","content":"ok"},"finishReason":"stop"}',
          );
          await request.response.close();
        }),
      );
      final backend = BackendClient()
        ..configure('http://${server.address.host}:${server.port}')
        ..setTokens('token', 'refresh-token');

      try {
        await ApiService(
          backend: backend,
        ).sendChatRequest(_managedModel(server), [
          {
            'role': 'user',
            'content': ApiService.chatContentWithFiles('inspect', [
              ChatFileInput(
                bytes: Uint8List.fromList([1, 2, 3]),
                mimeType: 'image/png',
                name: 'pixel.png',
              ),
            ]),
          },
          {'role': 'tool', 'tool_call_id': 'call-1', 'content': 'tool result'},
        ]);

        expect(requestBody?['messages'], [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'inspect'},
              {
                'type': 'inputFile',
                'file': {
                  'name': 'pixel.png',
                  'mimeType': 'image/png',
                  'dataBase64': 'AQID',
                },
              },
            ],
          },
          {
            'role': 'tool',
            'content': [
              {'type': 'text', 'text': 'tool result'},
            ],
            'toolCallId': 'call-1',
          },
        ]);
      } finally {
        backend.dispose();
        await server.close(force: true);
      }
    },
  );
}

ModelConfig _model(HttpServer server, String apiType) => ModelConfig(
  id: apiType,
  name: apiType,
  endpoint: 'http://${server.address.host}:${server.port}',
  apiKey: '',
  modelName: 'test-model',
  apiType: apiType,
  priority: 0,
);

ModelConfig _managedModel(
  HttpServer server, {
  String modelName = 'test-model',
  Map<String, dynamic> extraParams = const {},
}) => ModelConfig(
  id: 'managed',
  name: 'managed',
  endpoint: 'http://${server.address.host}:${server.port}/relay',
  apiKey: '',
  modelName: modelName,
  apiType: '',
  priority: 0,
  managed: true,
  extraParams: extraParams,
);
