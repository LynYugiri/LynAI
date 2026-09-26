import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/services/api_service.dart';

/// 抓一次 Anthropic 流式请求体，用来锁「thinking 只在显式 opt-in 时才发」。
Future<Map<String, dynamic>> _body({
  required Map<String, dynamic> extraParams,
  bool thinking = true,
}) => _capture(
  extraParams: extraParams,
  thinking: thinking,
);

Future<Map<String, dynamic>> _capture({
  Map<String, dynamic> extraParams = const {},
  bool thinking = true,
  double? temperature,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final captured = Completer<Map<String, dynamic>>();
  unawaited(
    server.first.then((request) async {
      final raw = await utf8.decoder.bind(request).join();
      captured.complete(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.write(
        'event: message_stop\r\ndata: {"type":"message_stop"}\r\n\r\n',
      );
      await request.response.close();
    }),
  );
  final config = ModelConfig(
    id: 'anthropic',
    name: 'anthropic',
    endpoint: 'http://${server.address.host}:${server.port}',
    apiKey: 'k',
    modelName: 'claude-x',
    apiType: 'anthropic',
    priority: 0,
    extraParams: extraParams,
    temperature: temperature,
  );
  try {
    await ApiService()
        .sendStreamRequest(config, const [
          {'role': 'user', 'content': '你好'},
        ], thinking: thinking)
        .toList();
    return await captured.future;
  } finally {
    await server.close(force: true);
  }
}


/// 抓一次请求体，用来验证 thinking 与 temperature 的互斥。
Future<Map<String, dynamic>> _bodyWithTemperature({bool thinking = true}) =>
    _capture(temperature: 0.3, thinking: thinking);

void main() {
  test('思考按钮开启时 Anthropic 收到标准 thinking 结构', () async {
    // Anthropic 与 OpenAI 兼容系的差别只在于「必须显式声明」，复用同一个
    // 思考开关，不需要用户再开第二个开关。
    final body = await _body(extraParams: const {});
    expect(body['thinking'], {'type': 'enabled', 'budget_tokens': 1024});
  });

  test('思考按钮关闭时不发送 thinking', () async {
    final body = await _body(extraParams: const {}, thinking: false);
    expect(body.containsKey('thinking'), isFalse);
  });

  test('预设显式关掉 thinking 时即使按钮开着也不发', () async {
    final body = await _body(extraParams: const {'thinking': false});
    expect(body.containsKey('thinking'), isFalse);
  });

  test('预设给了完整 thinking 对象时原样沿用', () async {
    final body = await _body(
      extraParams: const {
        'thinking': {'type': 'enabled', 'budget_tokens': 2048},
      },
    );
    expect(body['thinking'], {'type': 'enabled', 'budget_tokens': 2048});
  });

  test('thinkingBudgetTokens 覆盖默认预算', () async {
    final body = await _body(
      extraParams: const {'thinkingBudgetTokens': 4096},
    );
    final thinking = body['thinking'] as Map;
    expect(thinking['type'], 'enabled');
    // 预算被夹在 max_tokens 之内，避免 Anthropic 因 max_tokens 不足而拒绝。
    expect(thinking['budget_tokens'], lessThan(body['max_tokens'] as int));
  });

  test('思考开启时不发送 temperature（Anthropic 要求该值为 1）', () async {
    final body = await _bodyWithTemperature();
    expect(body.containsKey('thinking'), isTrue);
    expect(body.containsKey('temperature'), isFalse);

    // 思考关闭时 temperature 照常生效。
    final plain = await _bodyWithTemperature(thinking: false);
    expect(plain['temperature'], 0.3);
  });
}
