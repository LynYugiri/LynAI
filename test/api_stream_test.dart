import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/services/api_service.dart';

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
