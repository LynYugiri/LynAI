import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/services/agent_cancellation.dart';
import 'package:lynai/services/agent_tool_registry.dart';
import 'package:lynai/services/mcp/mcp_client.dart';
import 'package:lynai/services/mcp/mcp_tool_source.dart';
import 'package:lynai/services/mcp/mcp_transport.dart';

void main() {
  test('registers namespaced tools and refreshes changed lists', () async {
    final transport = _ToolTransport();
    final registry = AgentToolRegistry();
    final source = McpToolSource(
      serverId: 'weather',
      client: McpClient(transport: transport),
      registry: registry,
    );
    await source.start();
    final registration = registry.registration('mcp_weather_forecast')!;
    expect(registration.descriptor.source, AgentToolSource.mcp);
    final value = await registration.handler(
      AgentToolInvocation(id: 'call', name: registration.descriptor.name),
      AgentCancellationSource().token,
    );
    expect((value as Map)['isError'], isFalse);

    transport.toolName = 'alerts';
    transport.notifyChanged();
    await Future<void>.delayed(Duration.zero);
    await source.refresh();
    expect(registry.registration('mcp_weather_forecast'), isNull);
    expect(registry.registration('mcp_weather_alerts'), isNotNull);
    await source.dispose();
  });
}

class _ToolTransport implements McpTransport {
  final StreamController<Map<String, dynamic>> controller =
      StreamController.broadcast();
  String toolName = 'forecast';

  @override
  Stream<Map<String, dynamic>> get messages => controller.stream;

  @override
  Stream<McpTransportStatus> get statuses => const Stream.empty();

  @override
  McpTransportStatus get status =>
      const McpTransportStatus(McpTransportState.connected);

  @override
  Future<void> start() async {}

  @override
  Future<void> send(Map<String, dynamic> message) async {
    final id = message['id'];
    final method = message['method'];
    if (id is! int) return;
    Map<String, dynamic> result;
    if (method == 'initialize') {
      result = {'protocolVersion': '2025-06-18'};
    } else if (method == 'tools/list') {
      result = {
        'tools': [
          {
            'name': toolName,
            'description': 'Weather',
            'inputSchema': {
              r'$schema': 'https://json-schema.org/draft/2020-12/schema',
              'type': 'object',
              'properties': <String, dynamic>{},
            },
          },
        ],
      };
    } else {
      result = {
        'content': [
          {'type': 'text', 'text': 'ok'},
        ],
        'isError': false,
      };
    }
    scheduleMicrotask(
      () => controller.add({'jsonrpc': '2.0', 'id': id, 'result': result}),
    );
  }

  void notifyChanged() => controller.add({
    'jsonrpc': '2.0',
    'method': 'notifications/tools/list_changed',
  });

  @override
  Future<void> dispose() => controller.close();
}
