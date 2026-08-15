import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_persistence.dart';
import 'package:lynai/providers/mcp_provider.dart';
import 'package:lynai/repositories/mcp_repository.dart';
import 'package:lynai/services/agent_tool_registry.dart';
import 'package:lynai/services/mcp/mcp_client.dart';
import 'package:lynai/services/mcp/mcp_connection_factory.dart';
import 'package:lynai/services/mcp/mcp_tool_importer.dart';
import 'package:lynai/services/mcp/mcp_transport.dart';

void main() {
  test(
    'loads, connects, registers tools, and persists tool controls',
    () async {
      final now = DateTime(2026, 7, 27);
      final repository = _MemoryMcpRepository([
        AgentMcpServerRecord(
          id: 'weather',
          name: 'Weather',
          transport: 'http',
          url: 'https://mcp.example.test',
          environmentNames: const ['MCP_HEADER_1'],
          enabled: false,
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      repository.credentials['weather'] = const {
        'MCP_HEADER_1': 'Bearer secret',
      };
      repository.preferences['weather'] = const McpServerPreferences(
        credentialTargets: {'MCP_HEADER_1': 'Authorization'},
      );
      final factory = _FakeConnectionFactory();
      final registry = AgentToolRegistry();
      final provider = McpProvider(
        repository: repository,
        connectionFactory: factory,
        toolRegistry: registry,
      );

      await provider.load();
      expect(provider.servers.single.status, McpServerStatus.disconnected);

      await provider.connect('weather');
      final registeredName = canonicalMcpToolName('weather', 'forecast');
      expect(provider.servers.single.status, McpServerStatus.connected);
      expect(provider.servers.single.tools.single.name, 'forecast');
      expect(factory.lastCredentials, {'Authorization': 'Bearer secret'});
      expect(registry.registration(registeredName), isNotNull);

      await provider.setToolEnabled('weather', 'forecast', false);
      expect(registry.registration(registeredName), isNull);
      expect(
        repository.preferences['weather']!.enabledTools['forecast'],
        isFalse,
      );

      await provider.setToolEnabled('weather', 'forecast', true);
      expect(registry.registration(registeredName), isNotNull);
      await provider.disconnect('weather');
      expect(registry.registration(registeredName), isNull);
      expect(provider.servers.single.tools.single.name, 'forecast');
    },
  );

  test('save stores only credential references in the server row', () async {
    final repository = _MemoryMcpRepository([]);
    final provider = McpProvider(
      repository: repository,
      connectionFactory: _FakeConnectionFactory(),
      toolRegistry: AgentToolRegistry(),
    );
    final now = DateTime(2026, 7, 27);

    await provider.saveServer(
      server: AgentMcpServerRecord(
        id: 'local',
        name: 'Local',
        transport: 'stdio',
        command: 'mcp-server',
        environmentNames: const ['API_KEY'],
        enabled: false,
        createdAt: now,
        updatedAt: now,
      ),
      preferences: const McpServerPreferences(),
      credentials: const {'API_KEY': 'top-secret'},
    );

    expect(repository.servers.single.environmentNames, ['API_KEY']);
    expect(repository.servers.single.command, isNot(contains('top-secret')));
    expect(repository.credentials['local'], {'API_KEY': 'top-secret'});
  });

  test('disable during blocked initialize disposes the stale client', () async {
    final repository = _MemoryMcpRepository([_server(enabled: true)]);
    final transport = _BlockedInitializeTransport();
    final provider = McpProvider(
      repository: repository,
      connectionFactory: _QueueConnectionFactory([transport]),
      toolRegistry: AgentToolRegistry(),
    );

    await provider.load();
    await transport.initializeSent.future;
    await provider.setServerEnabled('weather', false);

    expect(transport.disposed, isTrue);
    expect(provider.servers.single.status, McpServerStatus.disconnected);
    expect(provider.servers.single.server.enabled, isFalse);
  });

  test(
    'edit during blocked initialize cannot publish the stale client',
    () async {
      final repository = _MemoryMcpRepository([_server(enabled: true)]);
      final staleTransport = _BlockedInitializeTransport();
      final replacementTransport = _ToolTransport();
      final provider = McpProvider(
        repository: repository,
        connectionFactory: _QueueConnectionFactory([
          staleTransport,
          replacementTransport,
        ]),
        toolRegistry: AgentToolRegistry(),
      );

      await provider.load();
      await staleTransport.initializeSent.future;
      final edited = _server(enabled: true, name: 'Edited Weather');
      await provider.saveServer(
        server: edited,
        preferences: const McpServerPreferences(),
        credentials: const {},
      );

      expect(staleTransport.disposed, isTrue);
      expect(provider.servers.single.server.name, 'Edited Weather');
      expect(provider.servers.single.status, McpServerStatus.connected);
      expect(provider.servers.single.tools.single.name, 'forecast');
    },
  );

  test(
    'load invalidates a blocked initialize before replacing state',
    () async {
      final repository = _MemoryMcpRepository([_server(enabled: true)]);
      final staleTransport = _BlockedInitializeTransport();
      final replacementTransport = _ToolTransport();
      final provider = McpProvider(
        repository: repository,
        connectionFactory: _QueueConnectionFactory([
          staleTransport,
          replacementTransport,
        ]),
        toolRegistry: AgentToolRegistry(),
      );

      await provider.load();
      await staleTransport.initializeSent.future;
      await provider.load();
      await _waitUntil(
        () => provider.servers.single.status == McpServerStatus.connected,
      );

      expect(staleTransport.disposed, isTrue);
      expect(provider.servers.single.tools.single.name, 'forecast');
    },
  );

  test('terminal failure cleans up tools and permits reconnect', () async {
    final repository = _MemoryMcpRepository([_server(enabled: false)]);
    final failedTransport = _ToolTransport();
    final replacementTransport = _ToolTransport();
    final registry = AgentToolRegistry();
    final provider = McpProvider(
      repository: repository,
      connectionFactory: _QueueConnectionFactory([
        failedTransport,
        replacementTransport,
      ]),
      toolRegistry: registry,
    );

    await provider.load();
    await provider.connect('weather');
    final registeredName = canonicalMcpToolName('weather', 'forecast');
    expect(registry.registration(registeredName), isNotNull);

    failedTransport.fail(StateError('connection lost'));
    await _waitUntil(
      () => provider.servers.single.status == McpServerStatus.failed,
    );
    expect(failedTransport.disposed, isTrue);
    expect(registry.registration(registeredName), isNull);

    await provider.connect('weather');
    expect(provider.servers.single.status, McpServerStatus.connected);
    expect(registry.registration(registeredName), isNotNull);
  });

  test('target load failure clears old MCP publication and state', () async {
    final repository = _MemoryMcpRepository([_server(enabled: false)]);
    final registry = AgentToolRegistry();
    final provider = McpProvider(
      repository: repository,
      connectionFactory: _QueueConnectionFactory([_ToolTransport()]),
      toolRegistry: registry,
    );
    await provider.load();
    await provider.connect('weather');
    final name = canonicalMcpToolName('weather', 'forecast');
    expect(registry.registration(name), isNotNull);

    repository.loadError = StateError('target dataset unreadable');
    await provider.load();

    expect(registry.registration(name), isNull);
    expect(provider.servers, isEmpty);
    expect(provider.loadError, contains('target dataset unreadable'));
  });

  test(
    'keeps incompatible tools visible but explicitly unregistered',
    () async {
      final repository = _MemoryMcpRepository([_server(enabled: false)]);
      final transport = _ToolTransport(
        inputSchema: {
          'type': 'object',
          'properties': <String, dynamic>{},
          r'$schema': 'https://json-schema.org/draft/2020-12/schema',
        },
      );
      final registry = AgentToolRegistry();
      final provider = McpProvider(
        repository: repository,
        connectionFactory: _QueueConnectionFactory([transport]),
        toolRegistry: registry,
      );

      await provider.load();
      await provider.connect('weather');

      expect(provider.servers.single.status, McpServerStatus.connected);
      expect(provider.servers.single.tools.single.name, 'forecast');
      expect(provider.servers.single.error, contains(r'$schema'));
      expect(
        registry.registration(canonicalMcpToolName('weather', 'forecast')),
        isNull,
      );
    },
  );
}

AgentMcpServerRecord _server({bool enabled = false, String name = 'Weather'}) {
  final now = DateTime(2026, 7, 27);
  return AgentMcpServerRecord(
    id: 'weather',
    name: name,
    transport: 'http',
    url: 'https://mcp.example.test',
    enabled: enabled,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('condition was not reached');
}

class _MemoryMcpRepository implements McpRepository {
  _MemoryMcpRepository(List<AgentMcpServerRecord> initial)
    : servers = List.of(initial);

  final List<AgentMcpServerRecord> servers;
  final Map<String, McpServerPreferences> preferences = {};
  final Map<String, Map<String, String>> credentials = {};
  Object? loadError;

  @override
  Future<List<AgentMcpServerRecord>> loadServers() async {
    final error = loadError;
    if (error != null) throw error;
    return List.of(servers);
  }

  @override
  Future<void> saveServer(AgentMcpServerRecord server) async {
    final index = servers.indexWhere((item) => item.id == server.id);
    if (index < 0) {
      servers.add(server);
    } else {
      servers[index] = server;
    }
  }

  @override
  Future<void> deleteServer(String serverId) async {
    servers.removeWhere((item) => item.id == serverId);
    preferences.remove(serverId);
    credentials.remove(serverId);
  }

  @override
  Future<McpServerPreferences> loadPreferences(String serverId) async =>
      preferences[serverId] ?? const McpServerPreferences();

  @override
  Future<void> savePreferences(
    String serverId,
    McpServerPreferences value,
  ) async {
    preferences[serverId] = value;
  }

  @override
  Future<Map<String, String>> loadCredentials(
    String serverId,
    Iterable<String> names,
  ) async {
    final result = <String, String>{};
    for (final name in names) {
      final value = credentials[serverId]?[name];
      if (value != null) result[name] = value;
    }
    return result;
  }

  @override
  Future<void> saveCredentials(
    String serverId,
    Map<String, String> values,
    Iterable<String> removedNames,
  ) async {
    final stored = credentials.putIfAbsent(serverId, () => {});
    stored.addAll(values);
    for (final name in removedNames) {
      stored.remove(name);
    }
  }
}

class _FakeConnectionFactory implements McpConnectionFactory {
  Map<String, String>? lastCredentials;

  @override
  bool get supportsStdio => false;

  @override
  Future<McpClient> create(
    AgentMcpServerRecord server,
    McpServerPreferences preferences,
    Map<String, String> credentials,
  ) async {
    lastCredentials = credentials;
    return McpClient(transport: _ToolTransport());
  }
}

class _QueueConnectionFactory implements McpConnectionFactory {
  _QueueConnectionFactory(this.transports);

  final List<McpTransport> transports;

  @override
  bool get supportsStdio => false;

  @override
  Future<McpClient> create(
    AgentMcpServerRecord server,
    McpServerPreferences preferences,
    Map<String, String> credentials,
  ) async => McpClient(transport: transports.removeAt(0));
}

class _BlockedInitializeTransport implements McpTransport {
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final initializeSent = Completer<void>();
  bool disposed = false;

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

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
    if (message['method'] == 'initialize' && !initializeSent.isCompleted) {
      initializeSent.complete();
    }
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await _messages.close();
  }
}

class _ToolTransport implements McpTransport {
  _ToolTransport({
    this.inputSchema = const {
      'type': 'object',
      'properties': <String, dynamic>{},
    },
  });

  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final Map<String, dynamic> inputSchema;
  bool disposed = false;

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

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
    if (id is! int) return;
    final result = switch (message['method']) {
      'initialize' => {'protocolVersion': '2025-06-18'},
      'tools/list' => {
        'tools': [
          {
            'name': 'forecast',
            'description': 'Weather forecast',
            'inputSchema': inputSchema,
          },
        ],
      },
      _ => {
        'content': [
          {'type': 'text', 'text': 'ok'},
        ],
        'isError': false,
      },
    };
    scheduleMicrotask(
      () => _messages.add({'jsonrpc': '2.0', 'id': id, 'result': result}),
    );
  }

  void fail(Object error) => _messages.addError(error);

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await _messages.close();
  }
}
