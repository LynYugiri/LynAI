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
              relayProviderId: 'provider-1',
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

      expect(requestBody?['providerId'], 'provider-1');
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
    unawaited(
      server.first.then((request) async {
        requestPath = request.uri.path;
        await utf8.decoder.bind(request).join();
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
      relayProviderId: 'vivo-provider',
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
    } finally {
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
  relayProviderId: 'provider-1',
  extraParams: extraParams,
);
