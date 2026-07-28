import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/services/agent_cancellation.dart';
import 'package:lynai/services/agent_tool_registry.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';
import 'package:lynai/services/mcp/mcp_client.dart';
import 'package:lynai/services/mcp/mcp_tool_importer.dart';
import 'package:lynai/services/mcp/mcp_tool_source.dart';
import 'package:lynai/services/mcp/mcp_transport.dart';
import 'package:lynai/services/tool_call_service.dart';

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
    final forecastName = canonicalMcpToolName('weather', 'forecast');
    final alertsName = canonicalMcpToolName('weather', 'alerts');
    final registration = registry.registration(forecastName)!;
    expect(registration.descriptor.source, AgentToolSource.mcp);
    final value = await registration.handler(
      AgentToolInvocation(id: 'call', name: registration.descriptor.name),
      AgentToolExecutionContext(
        identity: AgentToolExecutionIdentity(
          runId: 'run',
          turnId: 'turn',
          turnIndex: 0,
          invocationId: 'call',
          toolName: registration.descriptor.name,
        ),
        permissionSnapshot: AgentPermissionSnapshot(permissions: const []),
        cancellationToken: AgentCancellationSource().token,
        snapshot: registry.snapshot(),
        deadline: DateTime.now().add(const Duration(seconds: 30)),
      ),
    );
    expect((value as Map)['isError'], isFalse);

    transport.toolName = 'alerts';
    transport.notifyChanged();
    await Future<void>.delayed(Duration.zero);
    await source.refresh();
    expect(registry.registration(forecastName), isNull);
    expect(registry.registration(alertsName), isNotNull);
    await source.dispose();
  });

  test(
    'rejects unsupported schema without replacing old registrations',
    () async {
      final transport = _ToolTransport();
      final registry = AgentToolRegistry();
      final source = McpToolSource(
        serverId: 'weather',
        client: McpClient(transport: transport),
        registry: registry,
      );
      await source.start();
      final name = canonicalMcpToolName('weather', 'forecast');
      final original = registry.registration(name)!;

      transport.inputSchema = {
        'type': 'object',
        'properties': <String, dynamic>{},
        'dependentRequired': {
          'city': ['country'],
        },
      };

      await expectLater(
        source.refresh(),
        throwsA(
          isA<McpToolSchemaException>().having(
            (error) => error.toString(),
            'message',
            contains('dependentRequired'),
          ),
        ),
      );
      expect(registry.registration(name), same(original));
      await source.dispose();
    },
  );

  test(
    'model snapshot stays fixed while live execution fails closed after dispose',
    () async {
      final transport = _ToolTransport();
      final registry = AgentToolRegistry();
      final source = McpToolSource(
        serverId: 'weather',
        client: McpClient(transport: transport),
        registry: registry,
      );
      await source.start();
      final name = canonicalMcpToolName('weather', 'forecast');
      final snapshot = registry.snapshot();
      final captured = snapshot[name]!;

      expect(snapshot[name], same(captured));
      await source.dispose();
      expect(registry.registration(name), isNull);
      await expectLater(
        captured.handler(
          AgentToolInvocation(id: 'old-call', name: name),
          AgentToolExecutionContext(
            identity: AgentToolExecutionIdentity(
              runId: 'run',
              turnId: 'turn',
              turnIndex: 0,
              invocationId: 'old-call',
              toolName: name,
            ),
            permissionSnapshot: AgentPermissionSnapshot(permissions: const []),
            cancellationToken: AgentCancellationSource().token,
            snapshot: snapshot,
            deadline: DateTime.now().add(const Duration(seconds: 30)),
          ),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'run snapshot keeps MCP schema but resolves the live registration',
    () async {
      final external = AgentToolRegistry();
      final name = canonicalMcpToolName('weather', 'forecast');
      external.register(
        AgentToolDescriptor(
          name: name,
          description: 'Weather',
          source: AgentToolSource.mcp,
          sideEffect: AgentToolSideEffect.external,
          concurrency: AgentToolConcurrency.parallelSafe,
        ),
        (invocation, cancellationToken) async => const {'version': 1},
      );
      final service = ToolCallService(
        FeatureProvider(),
        externalToolRegistry: external,
        externalToolSnapshot: external.snapshot(),
        permissionSnapshot: AgentPermissionSnapshot(
          permissions: const [LynAIPermissions.networkAccess],
        ),
      );
      final runSnapshot = service.createRunSnapshot(
        agentEnabled: false,
        imageGenerationEnabled: false,
      );
      expect(
        runSnapshot.openAITools.singleWhere(
          (tool) => (tool['function'] as Map)['name'] == name,
        ),
        isNotNull,
      );

      external.unregister(name);
      external.register(
        AgentToolDescriptor(
          name: name,
          description: 'Weather v2',
          source: AgentToolSource.mcp,
          sideEffect: AgentToolSideEffect.external,
          concurrency: AgentToolConcurrency.parallelSafe,
        ),
        (invocation, cancellationToken) async => const {'version': 2},
      );
      final results = await service.executeCapturedBatch(
        runSnapshot,
        [AgentToolInvocation(id: 'call', name: name)],
        identity: const AgentTurnIdentity(
          runId: 'run',
          turnId: 'turn',
          turnIndex: 0,
        ),
        cancellationToken: AgentCancellationSource().token,
      );
      expect(results.single.value, {'version': 2});

      external.unregister(name);
      final unavailable = await service.executeCapturedBatch(
        runSnapshot,
        [AgentToolInvocation(id: 'call-2', name: name)],
        identity: const AgentTurnIdentity(
          runId: 'run',
          turnId: 'turn-2',
          turnIndex: 1,
        ),
        cancellationToken: AgentCancellationSource().token,
      );
      expect(unavailable.single.status, AgentToolResultStatus.failure);
    },
  );
}

class _ToolTransport implements McpTransport {
  final StreamController<Map<String, dynamic>> controller =
      StreamController.broadcast();
  String toolName = 'forecast';
  Map<String, dynamic> inputSchema = {
    'type': 'object',
    'properties': <String, dynamic>{},
  };

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
  Future<void> send(
    Map<String, dynamic> message, {
    McpTransportCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
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
            'inputSchema': inputSchema,
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
