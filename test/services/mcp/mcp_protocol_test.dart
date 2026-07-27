import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/mcp/mcp_protocol.dart';

void main() {
  test('protocol codec validates JSON-RPC and message bounds', () {
    final encoded = encodeMcpMessage({
      'jsonrpc': '2.0',
      'id': 1,
      'result': {},
    }, 100);
    expect(decodeMcpMessage(encoded, 100)['id'], 1);
    expect(
      () => decodeMcpMessage(utf8.encode('{"id":1}'), 100),
      throwsA(isA<McpProtocolException>()),
    );
    expect(
      () => encodeMcpMessage({'jsonrpc': '2.0', 'value': 'x' * 100}, 20),
      throwsA(isA<McpProtocolException>()),
    );
  });
}
