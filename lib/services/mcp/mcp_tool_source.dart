import 'dart:async';

import '../../models/agent_runtime.dart';
import '../agent_tool_registry.dart';
import 'mcp_client.dart';
import 'mcp_protocol.dart';

class McpToolSource {
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
    final nextRegistrations = <String, AgentToolRegistration>{};
    for (final tool in tools) {
      final registeredName = _registeredName(tool.name);
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
        parameters: _compatibleSchema(tool.inputSchema),
      );
      final registration = registry.register(descriptor, (
        invocation,
        cancellationToken,
      ) async {
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

  String _registeredName(String toolName) {
    final safeServer = _encodeName(serverId);
    final safeTool = _encodeName(toolName);
    return 'mcp_${safeServer}_$safeTool';
  }

  Map<String, dynamic> _compatibleSchema(Map<String, dynamic> schema) {
    final copy = _sanitizeSchema(schema);
    copy.putIfAbsent('type', () => 'object');
    copy.putIfAbsent('properties', () => <String, dynamic>{});
    return copy;
  }

  String _encodeName(String value) {
    final buffer = StringBuffer();
    for (final codeUnit in value.codeUnits) {
      final isAlphaNumeric =
          (codeUnit >= 48 && codeUnit <= 57) ||
          (codeUnit >= 65 && codeUnit <= 90) ||
          (codeUnit >= 97 && codeUnit <= 122) ||
          codeUnit == 45 ||
          codeUnit == 95;
      if (isAlphaNumeric) {
        buffer.writeCharCode(codeUnit);
      } else {
        buffer
          ..write('_')
          ..write(codeUnit.toRadixString(16))
          ..write('_');
      }
    }
    return buffer.toString();
  }

  Map<String, dynamic> _sanitizeSchema(Map<String, dynamic> schema) {
    const supported = {
      'type',
      'properties',
      'required',
      'additionalProperties',
      'items',
      'enum',
      'const',
      'minimum',
      'maximum',
      'exclusiveMinimum',
      'exclusiveMaximum',
      'minLength',
      'maxLength',
      'pattern',
      'minItems',
      'maxItems',
      'uniqueItems',
      'minProperties',
      'maxProperties',
      'anyOf',
      'oneOf',
      'allOf',
      'not',
      'description',
      'title',
      'default',
    };
    final sanitized = <String, dynamic>{};
    for (final entry in schema.entries) {
      if (!supported.contains(entry.key)) continue;
      final value = entry.value;
      if (entry.key == 'properties' && value is Map) {
        sanitized[entry.key] = value.map(
          (key, property) => MapEntry(
            key.toString(),
            property is Map
                ? _sanitizeSchema(Map<String, dynamic>.from(property))
                : property,
          ),
        );
      } else if ((entry.key == 'items' ||
              entry.key == 'additionalProperties' ||
              entry.key == 'not') &&
          value is Map) {
        sanitized[entry.key] = _sanitizeSchema(
          Map<String, dynamic>.from(value),
        );
      } else if ((entry.key == 'anyOf' ||
              entry.key == 'oneOf' ||
              entry.key == 'allOf') &&
          value is List) {
        sanitized[entry.key] = value
            .map(
              (item) => item is Map
                  ? _sanitizeSchema(Map<String, dynamic>.from(item))
                  : item,
            )
            .toList();
      } else {
        sanitized[entry.key] = value;
      }
    }
    return sanitized;
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
