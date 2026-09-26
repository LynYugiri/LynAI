import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/services/api_service.dart';

/// 抓取一次 Anthropic 流式请求的完整 body，用来对照官方 wire 格式。
Future<Map<String, dynamic>> captureAnthropicBody({
  required List<Map<String, dynamic>> messages,
  bool thinking = false,
  Map<String, dynamic> extraParams = const {},
  int? maxTokens,
  double? temperature,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final captured = Completer<Map<String, dynamic>>();
  unawaited(
    server.first.then((request) async {
      final raw = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(raw);
      captured.complete(
        decoded is Map
            ? decoded.map((key, value) => MapEntry(key.toString(), value))
            : <String, dynamic>{'__not_object__': raw},
      );
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.write(
        'event: content_block_delta\r\n'
        'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"ok"}}\r\n\r\n'
        'event: message_stop\r\n'
        'data: {"type":"message_stop"}\r\n\r\n',
      );
      await request.response.close();
    }),
  );
  final config = ModelConfig(
    id: 'anthropic',
    name: 'anthropic',
    endpoint: 'http://${server.address.host}:${server.port}',
    apiKey: 'test-key',
    modelName: 'test-model',
    apiType: 'anthropic',
    priority: 0,
    maxTokens: maxTokens,
    temperature: temperature,
    extraParams: extraParams,
  );
  try {
    await ApiService()
        .sendStreamRequest(config, messages, thinking: thinking)
        .toList();
    return await captured.future;
  } finally {
    await server.close(force: true);
  }
}

void main() {
  test('普通对话：system 被提到顶层，其余消息保持 user/assistant', () async {
    final body = await captureAnthropicBody(
      messages: const [
        {'role': 'system', 'content': '你是一个助手'},
        {'role': 'user', 'content': '你好'},
        {'role': 'assistant', 'content': '你好，有什么可以帮你'},
        {'role': 'user', 'content': '继续'},
      ],
    );

    expect(body['system'], '你是一个助手');
    final messages = (body['messages'] as List).cast<Map>();
    expect(messages.map((m) => m['role']), ['user', 'assistant', 'user']);
    expect(body.containsKey('system'), isTrue);
    expect(body['stream'], isTrue);
  });

  test('system 内容不是字符串时不应在客户端崩溃', () async {
    // 多模态/OCR 路径下 system 段理论上仍是字符串；这里锁住「不是字符串」
    // 时的行为，避免再出现裸 cast 造成的客户端异常。
    await expectLater(
      captureAnthropicBody(
        messages: const [
          {
            'role': 'system',
            'content': [
              {'type': 'text', 'text': '分段系统提示'},
            ],
          },
          {'role': 'user', 'content': '你好'},
        ],
      ),
      completes,
    );
  });

  test('数组形式的 user 正文原样传递', () async {
    final body = await captureAnthropicBody(
      messages: const [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': '看看这张图'},
          ],
        },
      ],
    );
    final messages = (body['messages'] as List).cast<Map>();
    expect(messages.single['content'], [
      {'type': 'text', 'text': '看看这张图'},
    ]);
  });

  test('显式开启 thinking 时给出 budget_tokens 且不超过 max_tokens', () async {
    final body = await captureAnthropicBody(
      messages: const [
        {'role': 'user', 'content': '你好'},
      ],
      thinking: true,
      maxTokens: 2048,
    );
    final thinkingBody = body['thinking'] as Map?;
    expect(thinkingBody, isNotNull);
    expect(thinkingBody!['type'], 'enabled');
    final budget = thinkingBody['budget_tokens'] as int;
    expect(budget, greaterThan(0));
    expect(budget, lessThan(2048));
  });

  test('开启 thinking 时不再发送 temperature（Anthropic 要求它必须为 1）', () async {
    final body = await captureAnthropicBody(
      messages: const [
        {'role': 'user', 'content': '你好'},
      ],
      thinking: true,
      temperature: 0.3,
    );
    expect(body.containsKey('thinking'), isTrue);
    expect(body.containsKey('temperature'), isFalse);

    // 关闭 thinking 时 temperature 照常生效。
    final plain = await captureAnthropicBody(
      messages: const [
        {'role': 'user', 'content': '你好'},
      ],
      temperature: 0.3,
    );
    expect(plain['temperature'], 0.3);
  });

  test('max_tokens 缺省时使用 4096', () async {
    final body = await captureAnthropicBody(
      messages: const [
        {'role': 'user', 'content': '你好'},
      ],
    );
    expect(body['max_tokens'], 4096);
  });

  test('extraParams 不覆盖 relayer 管理的字段', () async {
    final body = await captureAnthropicBody(
      messages: const [
        {'role': 'user', 'content': '你好'},
      ],
      extraParams: const {'model': 'hacked', 'messages': [], 'stream': false},
    );
    expect(body['model'], 'test-model');
    expect(body['stream'], isTrue);
    expect((body['messages'] as List), hasLength(1));
  });
}
