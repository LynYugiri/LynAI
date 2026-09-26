import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/services/api_service.dart';

const _canonicalStream = '''
event: message_start
data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-x","content":[],"usage":{"input_tokens":10,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: ping
data: {"type":"ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"你"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"好"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":5}}

event: message_stop
data: {"type":"message_stop"}

''';

ModelConfig _config(HttpServer server) => ModelConfig(
  id: 'anthropic',
  name: 'anthropic',
  endpoint: 'http://${server.address.host}:${server.port}',
  apiKey: 'test-key',
  modelName: 'claude-x',
  apiType: 'anthropic',
  priority: 0,
);

/// 用给定 SSE 负载起一个一次性假 Anthropic 服务并跑一次流式请求。
Future<(List<StreamChunk>?, Object?)> runStream(String payload) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(
    server.first.then((request) async {
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.write(payload);
      await request.response.close();
    }),
  );
  try {
    final chunks = await ApiService()
        .sendStreamRequest(_config(server), const [
          {'role': 'user', 'content': '你好'},
        ])
        .toList();
    return (chunks, null);
  } catch (error) {
    return (null, error);
  } finally {
    await server.close(force: true);
  }
}

void main() {
  test('标准 Anthropic SSE（含 message_stop）正常出字', () async {
    final (chunks, error) = await runStream(_canonicalStream);
    expect(error, isNull);
    final text = chunks!
        .where((chunk) => chunk.content != null)
        .map((chunk) => chunk.content)
        .join();
    expect(text, '你好');
    expect(chunks.last.isDone, isTrue);
  });

  test('官方 message_stop 之前就断流时不应丢字', () async {
    // 中转/代理常直接关闭连接而不补 message_stop；此时已经收到的正文必须保留，
    // 不能因为缺少终态标记就整体失败。
    final truncated = _canonicalStream.split('event: message_stop').first;
    final (chunks, error) = await runStream(truncated);
    final text = chunks
        ?.where((chunk) => chunk.content != null)
        .map((chunk) => chunk.content)
        .join();
    expect(
      error,
      isNull,
      reason: '断流不应让整次回复失败（已收到：$text）',
    );
    expect(text, '你好');
  });

  test('CRLF 分隔的 SSE 正常解析', () async {
    final (chunks, error) = await runStream(
      _canonicalStream.replaceAll('\n', '\r\n'),
    );
    expect(error, isNull);
    expect(
      chunks!
          .where((chunk) => chunk.content != null)
          .map((chunk) => chunk.content)
          .join(),
      '你好',
    );
  });

  test('服务端返回 error 事件时给出可读错误', () async {
    final (_, error) = await runStream(
      'event: error\r\n'
      'data: {"type":"error","error":{"type":"invalid_request_error","message":"bad key"}}\r\n\r\n',
    );
    expect(error, isNotNull);
    expect(error.toString(), contains('bad key'));
  });
}
