import 'dart:async';

import '../../models/agent_runtime.dart';
import '../agent_tool_registry.dart';
import 'mcp_client.dart';
import 'mcp_protocol.dart';
import 'mcp_tool_importer.dart';

class McpToolSource {
  static const _schemaImporter = McpToolSchemaImporter();
  final String serverId;
  final McpClient client;
  final AgentToolRegistry registry;
  final AgentToolSideEffect sideEffect;
  final Map<String, AgentToolRegistration> _registrations = {};
  StreamSubscription<void>? _changesSubscription;
  Future<void>? _refreshing;
  bool _disposed = false;

  McpToolSource({
    required this.serverId,
    required this.client,
    required this.registry,
    this.sideEffect = AgentToolSideEffect.external,
  }) {
    if (serverId.trim().isEmpty) {
      throw ArgumentError.value(serverId, 'serverId', 'must not be empty');
    }
  }

  Future<void> start() async {
    await client.initialize();
    await refresh();
    _changesSubscription = client.toolsChanged.listen(
      (_) => unawaited(refresh().catchError((_) {})),
    );
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    final tools = await client.listTools();
    final importedSchemas = {
      for (final tool in tools) tool.name: _schemaImporter.import(tool),
    };
    final nextRegistrations = <String, AgentToolRegistration>{};
    for (final tool in tools) {
      final registeredName = canonicalMcpToolName(serverId, tool.name);
      final existing = registry.registration(registeredName);
      final owned = _registrations[tool.name];
      if (existing != null &&
          (owned == null || existing.registrationId != owned.registrationId)) {
        throw StateError(
          'MCP tool name collides with an existing tool: $registeredName',
        );
      }
      final descriptor = AgentToolDescriptor(
        name: registeredName,
        description: tool.description,
        source: AgentToolSource.mcp,
        sideEffect: sideEffect,
        concurrency: AgentToolConcurrency.parallelSafe,
        parameters: importedSchemas[tool.name]!,
      );
      final registration = registry.register(descriptor, (
        invocation,
        cancellationToken,
      ) async {
        if (_disposed) {
          throw StateError('MCP server $serverId is no longer available');
        }
        final result = await client.callTool(
          tool.name,
          invocation.arguments,
          cancellationToken: cancellationToken,
        );
        if (result.isError) throw McpToolCallException(tool.name, result);
        return result.toJson();
      });
      nextRegistrations[tool.name] = registration;
    }
    for (final entry in _registrations.entries) {
      if (nextRegistrations.containsKey(entry.key)) continue;
      _unregisterIfCurrent(entry.value);
    }
    _registrations
      ..clear()
      ..addAll(nextRegistrations);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _changesSubscription?.cancel();
    for (final registration in _registrations.values) {
      _unregisterIfCurrent(registration);
    }
    _registrations.clear();
    await client.dispose();
  }

  void _unregisterIfCurrent(AgentToolRegistration registration) {
    final current = registry.registration(registration.descriptor.name);
    if (current?.registrationId == registration.registrationId) {
      registry.unregister(registration.descriptor.name);
    }
  }
}

class McpToolCallException implements Exception {
  final String toolName;
  final McpCallToolResult result;

  const McpToolCallException(this.toolName, this.result);

  @override
  String toString() =>
      'MCP tool "$toolName" reported an error: ${result.content}';
}
