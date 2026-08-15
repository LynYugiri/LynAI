import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/agent_persistence.dart';
import '../models/agent_runtime.dart';
import '../repositories/mcp_repository.dart';
import '../services/agent_tool_registry.dart';
import '../services/mcp/mcp_client.dart';
import '../services/mcp/mcp_connection_factory.dart';
import '../services/mcp/mcp_protocol.dart';
import '../services/mcp/mcp_tool_importer.dart';
import '../services/dataset_runtime_barrier.dart';

enum McpServerStatus { disconnected, connecting, connected, failed }

class McpServerState {
  McpServerState({
    required this.server,
    required this.preferences,
    this.status = McpServerStatus.disconnected,
    this.tools = const [],
    this.error,
  });

  AgentMcpServerRecord server;
  McpServerPreferences preferences;
  McpServerStatus status;
  List<McpTool> tools;
  String? error;
}

class McpProvider extends ChangeNotifier {
  McpProvider({
    required McpRepository repository,
    required McpConnectionFactory connectionFactory,
    required this.toolRegistry,
    DatasetRuntimeBarrier? datasetBarrier,
  }) : _repository = repository,
       _connectionFactory = connectionFactory,
       _datasetBarrier = datasetBarrier;

  final McpRepository _repository;
  final McpConnectionFactory _connectionFactory;
  final AgentToolRegistry toolRegistry;
  final DatasetRuntimeBarrier? _datasetBarrier;
  final List<McpServerState> _servers = [];
  final Map<String, _McpConnection> _connections = {};
  final Map<String, int> _connectionGenerations = {};
  static const _schemaImporter = McpToolSchemaImporter();
  bool _loading = false;
  String? _loadError;

  List<McpServerState> get servers => List.unmodifiable(_servers);
  bool get loading => _loading;
  String? get loadError => _loadError;
  bool get supportsStdio => _connectionFactory.supportsStdio;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final disconnects = <Future<void>>[];
      for (final serverId in {
        ..._servers.map((state) => state.server.id),
        ..._connections.keys,
      }) {
        _connectionGenerations[serverId] =
            (_connectionGenerations[serverId] ?? 0) + 1;
        final connection = _connections.remove(serverId);
        if (connection != null) {
          disconnects.add(_disposeConnection(connection));
        }
      }
      await Future.wait(disconnects);
      final records = await _repository.loadServers();
      final states = <McpServerState>[];
      for (final record in records) {
        states.add(
          McpServerState(
            server: record,
            preferences: await _repository.loadPreferences(record.id),
          ),
        );
      }
      _servers
        ..clear()
        ..addAll(states);
      for (final state in states.where((state) => state.server.enabled)) {
        unawaited(connect(state.server.id));
      }
    } catch (error) {
      await disconnectAll();
      _servers.clear();
      _loadError = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> saveServer({
    required AgentMcpServerRecord server,
    required McpServerPreferences preferences,
    required Map<String, String> credentials,
  }) async {
    final existing = _state(server.id);
    final removedNames = existing == null
        ? const <String>[]
        : existing.server.environmentNames.where(
            (name) => !server.environmentNames.contains(name),
          );
    await disconnect(server.id);
    await _repository.saveServer(server);
    await _repository.savePreferences(server.id, preferences);
    await _repository.saveCredentials(server.id, credentials, removedNames);
    final next = McpServerState(server: server, preferences: preferences);
    if (existing == null) {
      _servers.add(next);
      _servers.sort((a, b) => a.server.name.compareTo(b.server.name));
    } else {
      _servers[_servers.indexOf(existing)] = next;
    }
    notifyListeners();
    if (server.enabled) await connect(server.id);
  }

  Future<void> setServerEnabled(String serverId, bool enabled) async {
    final state = _requireState(serverId);
    if (!enabled) await disconnect(serverId);
    final now = DateTime.now();
    final server = AgentMcpServerRecord(
      id: state.server.id,
      name: state.server.name,
      transport: state.server.transport,
      enabled: enabled,
      command: state.server.command,
      url: state.server.url,
      arguments: state.server.arguments,
      environmentNames: state.server.environmentNames,
      createdAt: state.server.createdAt,
      updatedAt: now,
    );
    await _repository.saveServer(server);
    state.server = server;
    notifyListeners();
    if (enabled) {
      await connect(serverId);
    }
  }

  Future<void> setToolEnabled(
    String serverId,
    String toolName,
    bool enabled,
  ) async {
    final state = _requireState(serverId);
    final tools = Map<String, bool>.of(state.preferences.enabledTools)
      ..[toolName] = enabled;
    state.preferences = McpServerPreferences(
      allowHttp: state.preferences.allowHttp,
      allowPrivateNetwork: state.preferences.allowPrivateNetwork,
      enabledTools: tools,
      credentialTargets: state.preferences.credentialTargets,
    );
    await _repository.savePreferences(serverId, state.preferences);
    state.error = _syncRegistrations(state, _connections[serverId]);
    notifyListeners();
  }

  bool isToolEnabled(String serverId, String toolName) =>
      _state(serverId)?.preferences.enabledTools[toolName] != false;

  Future<void> deleteServer(String serverId) async {
    final state = _requireState(serverId);
    await disconnect(serverId);
    await _repository.deleteServer(serverId);
    _servers.remove(state);
    notifyListeners();
  }

  Future<void> connect(String serverId) async {
    await _datasetBarrier?.waitUntilOpen();
    final state = _requireState(serverId);
    if (_connections.containsKey(serverId) ||
        state.status == McpServerStatus.connecting) {
      return;
    }
    state
      ..status = McpServerStatus.connecting
      ..error = null;
    notifyListeners();
    final generation = _connectionGenerations[serverId] ?? 0;
    McpClient? client;
    _McpConnection? connection;
    try {
      final credentials = await _repository.loadCredentials(
        serverId,
        state.server.environmentNames,
      );
      final resolvedCredentials = {
        for (final entry in credentials.entries)
          state.preferences.credentialTargets[entry.key] ?? entry.key:
              entry.value,
      };
      client = await _connectionFactory.create(
        state.server,
        state.preferences,
        resolvedCredentials,
      );
      if (!_isCurrent(serverId, state, generation)) {
        await client.dispose();
        return;
      }
      connection = _McpConnection(client, generation);
      _connections[serverId] = connection;
      connection.statusSubscription = client.statuses.listen((status) {
        if (status.state != McpClientState.failed) return;
        unawaited(
          _failConnection(
            serverId,
            state,
            connection!,
            status.detail ?? 'MCP connection failed',
          ),
        );
      });
      connection.toolsSubscription = client.toolsChanged.listen((_) {
        unawaited(_refreshTools(serverId, state, connection!));
      });
      await client.initialize();
      if (!_ownsConnection(serverId, state, connection)) return;
      if (!await _refreshTools(serverId, state, connection)) return;
      state.status = McpServerStatus.connected;
    } catch (error) {
      if (connection != null && _ownsConnection(serverId, state, connection)) {
        await _failConnection(serverId, state, connection, error.toString());
      } else {
        await client?.dispose();
      }
    }
    if (_isCurrent(serverId, state, generation)) notifyListeners();
  }

  Future<bool> testConnection(String serverId) async {
    await disconnect(serverId);
    await connect(serverId);
    return _requireState(serverId).status == McpServerStatus.connected;
  }

  Future<void> disconnect(String serverId) async {
    _connectionGenerations[serverId] =
        (_connectionGenerations[serverId] ?? 0) + 1;
    final state = _state(serverId);
    final connection = _connections.remove(serverId);
    if (connection != null) {
      await _disposeConnection(connection);
    }
    if (state != null) {
      state
        ..status = McpServerStatus.disconnected
        ..error = null;
      notifyListeners();
    }
  }

  Future<void> disconnectAll() async {
    final serverIds = {
      ..._servers.map((state) => state.server.id),
      ..._connections.keys,
    };
    for (final serverId in serverIds) {
      await disconnect(serverId);
    }
  }

  Future<void> quiesceForDatasetSwitch() => disconnectAll();

  Future<bool> _refreshTools(
    String serverId,
    McpServerState state,
    _McpConnection connection,
  ) async {
    try {
      final tools = await connection.client.listTools();
      if (!_ownsConnection(serverId, state, connection)) return false;
      state.tools = tools;
      state.error = _syncRegistrations(state, connection);
      state.status = McpServerStatus.connected;
      notifyListeners();
      return true;
    } catch (error) {
      if (_ownsConnection(serverId, state, connection)) {
        await _failConnection(serverId, state, connection, error.toString());
      }
      return false;
    }
  }

  bool _isCurrent(String serverId, McpServerState state, int generation) =>
      _state(serverId) == state &&
      (_connectionGenerations[serverId] ?? 0) == generation;

  bool _ownsConnection(
    String serverId,
    McpServerState state,
    _McpConnection connection,
  ) =>
      _isCurrent(serverId, state, connection.generation) &&
      identical(_connections[serverId], connection);

  Future<void> _failConnection(
    String serverId,
    McpServerState state,
    _McpConnection connection,
    String error,
  ) async {
    if (!_ownsConnection(serverId, state, connection)) return;
    _connections.remove(serverId);
    await _disposeConnection(connection);
    if (!_isCurrent(serverId, state, connection.generation)) return;
    state
      ..status = McpServerStatus.failed
      ..error = error;
    notifyListeners();
  }

  Future<void> _disposeConnection(_McpConnection connection) async {
    await connection.statusSubscription?.cancel();
    await connection.toolsSubscription?.cancel();
    for (final registration in connection.registrations.values) {
      _unregisterIfCurrent(registration);
    }
    connection.registrations.clear();
    await connection.client.dispose();
  }

  String? _syncRegistrations(McpServerState state, _McpConnection? connection) {
    if (connection == null) return null;
    final next = <String, AgentToolRegistration>{};
    final errors = <String>[];
    for (final tool in state.tools) {
      if (!isToolEnabled(state.server.id, tool.name)) continue;
      Map<String, dynamic> parameters;
      try {
        parameters = _schemaImporter.import(tool);
      } on McpToolSchemaException catch (error) {
        errors.add(error.toString());
        continue;
      }
      final registeredName = canonicalMcpToolName(state.server.id, tool.name);
      final owned = connection.registrations[tool.name];
      final existing = toolRegistry.registration(registeredName);
      if (existing != null &&
          (owned == null || existing.registrationId != owned.registrationId)) {
        errors.add('工具名称冲突: $registeredName');
        continue;
      }
      next[tool.name] = toolRegistry.register(
        AgentToolDescriptor(
          name: registeredName,
          description: tool.description,
          source: AgentToolSource.mcp,
          sideEffect: AgentToolSideEffect.external,
          concurrency: AgentToolConcurrency.parallelSafe,
          parameters: parameters,
        ),
        (invocation, cancellationToken) async {
          final result = await connection.client.callTool(
            tool.name,
            invocation.arguments,
            cancellationToken: cancellationToken,
          );
          if (result.isError) {
            throw StateError('MCP tool ${tool.name} failed: ${result.content}');
          }
          return result.toJson();
        },
      );
    }
    for (final entry in connection.registrations.entries) {
      if (!next.containsKey(entry.key)) _unregisterIfCurrent(entry.value);
    }
    connection.registrations
      ..clear()
      ..addAll(next);
    return errors.isEmpty ? null : errors.join('\n');
  }

  void _unregisterIfCurrent(AgentToolRegistration registration) {
    if (toolRegistry
            .registration(registration.descriptor.name)
            ?.registrationId ==
        registration.registrationId) {
      toolRegistry.unregister(registration.descriptor.name);
    }
  }

  McpServerState? _state(String id) {
    for (final state in _servers) {
      if (state.server.id == id) return state;
    }
    return null;
  }

  McpServerState _requireState(String id) =>
      _state(id) ?? (throw ArgumentError.value(id, 'id', 'unknown MCP server'));

  @override
  void dispose() {
    unawaited(disconnectAll());
    super.dispose();
  }
}

class _McpConnection {
  _McpConnection(this.client, this.generation);

  final McpClient client;
  final int generation;
  final Map<String, AgentToolRegistration> registrations = {};
  StreamSubscription<McpClientStatus>? statusSubscription;
  StreamSubscription<void>? toolsSubscription;
}
