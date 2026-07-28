import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/agent_cancellation.dart';
import 'package:lynai/services/mcp/mcp_client.dart';
import 'package:lynai/services/mcp/mcp_transport.dart';

void main() {
  test(
    'initializes, paginates tools, calls tools, and emits list changes',
    () async {
      final transport = _FakeTransport((message, transport) {
        switch (message['method']) {
          case 'initialize':
            transport.respond(message['id'] as int, {
              'protocolVersion': '2025-06-18',
              'capabilities': {},
            });
          case 'tools/list':
            final cursor = (message['params'] as Map)['cursor'];
            transport.respond(
              message['id'] as int,
              cursor == null
                  ? {
                      'tools': [_tool('first')],
                      'nextCursor': 'next',
                    }
                  : {
                      'tools': [_tool('second')],
                    },
            );
          case 'tools/call':
            transport.respond(message['id'] as int, {
              'content': [
                {'type': 'text', 'text': 'ok'},
              ],
              'isError': false,
            });
        }
      });
      final client = McpClient(transport: transport);
      await client.initialize();
      expect((await client.listTools()).map((tool) => tool.name), [
        'first',
        'second',
      ]);
      expect((await client.callTool('first', const {})).isError, isFalse);
      final changed = expectLater(client.toolsChanged, emits(null));
      transport.notify('notifications/tools/list_changed');
      await changed;
      await client.dispose();
    },
  );

  test(
    'cancellation sends notifications/cancelled and completes the request',
    () async {
      final transport = _FakeTransport((message, transport) {
        if (message['method'] == 'initialize') {
          transport.respond(message['id'] as int, {
            'protocolVersion': '2025-06-18',
          });
        }
      });
      final client = McpClient(transport: transport);
      await client.initialize();
      final cancellation = AgentCancellationSource();
      final future = client.callTool(
        'wait',
        const {},
        cancellationToken: cancellation.token,
      );
      cancellation.cancel();
      await expectLater(future, throwsA(isA<AgentCancellationException>()));
      expect(
        transport.sent.any(
          (message) => message['method'] == 'notifications/cancelled',
        ),
        isTrue,
      );
      await client.dispose();
    },
  );

  test('times out pending requests and reports cancellation', () async {
    final transport = _FakeTransport((message, transport) {
      if (message['method'] == 'initialize') {
        transport.respond(message['id'] as int, {
          'protocolVersion': '2025-06-18',
        });
      }
    });
    final client = McpClient(
      transport: transport,
      requestTimeout: const Duration(milliseconds: 5),
    );
    await client.initialize();
    await expectLater(
      client.callTool('wait', const {}),
      throwsA(isA<TimeoutException>()),
    );
    expect(
      transport.sent.any(
        (message) => message['method'] == 'notifications/cancelled',
      ),
      isTrue,
    );
    await client.dispose();
  });
}

Map<String, dynamic> _tool(String name) => {
  'name': name,
  'description': name,
  'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
};

class _FakeTransport implements McpTransport {
  final void Function(Map<String, dynamic>, _FakeTransport) onSend;
  final StreamController<Map<String, dynamic>> _messages =
      StreamController.broadcast();
  final List<Map<String, dynamic>> sent = [];
  McpTransportStatus _status = const McpTransportStatus(McpTransportState.idle);

  _FakeTransport(this.onSend);

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  @override
  Stream<McpTransportStatus> get statuses => const Stream.empty();

  @override
  McpTransportStatus get status => _status;

  @override
  Future<void> start() async {
    _status = const McpTransportStatus(McpTransportState.connected);
  }

  @override
  Future<void> send(
    Map<String, dynamic> message, {
    McpTransportCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    sent.add(message);
    onSend(message, this);
  }

  void respond(int id, Map<String, dynamic> result) {
    scheduleMicrotask(
      () => _messages.add({'jsonrpc': '2.0', 'id': id, 'result': result}),
    );
  }

  void notify(String method) =>
      _messages.add({'jsonrpc': '2.0', 'method': method});

  @override
  Future<void> dispose() => _messages.close();
}
