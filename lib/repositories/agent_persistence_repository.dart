import '../models/agent_persistence.dart';
import '../models/agent_runtime.dart';
import '../services/storage_v2_service.dart';
import '../services/lynai_permission_definitions.dart';

class AgentPersistenceRepository {
  AgentPersistenceRepository(this._storage);

  final StorageV2Service _storage;

  Future<void> createRun(
    AgentRunRecord run, {
    AgentPermissionSnapshot? permissionPolicy,
    String? parentRunId,
  }) async {
    if (run.status != AgentRunStatus.queued) {
      throw ArgumentError('New Agent runs must be queued');
    }
    final database = await _storage.storageDatabase();
    final inherited = parentRunId == null
        ? null
        : await database.loadAgentPermissionSnapshot(parentRunId);
    await database.insertAgentRun(
      AgentRunCreation(
        run: run,
        permissionPolicy:
            inherited ??
            permissionPolicy ??
            AgentPermissionSnapshot(permissions: LynAIPermissions.defaultAgent),
      ),
    );
  }

  Future<void> createTurn(AgentTurnRecord turn) async {
    if (turn.status != AgentTurnStatus.pending) {
      throw ArgumentError('New Agent turns must be pending');
    }
    await (await _storage.storageDatabase()).insertAgentTurn(turn);
  }

  Future<void> createItem(AgentItemRecord item) async {
    if (item.status != AgentItemStatus.pending) {
      throw ArgumentError('New Agent items must be pending');
    }
    await (await _storage.storageDatabase()).insertAgentItem(item);
  }

  Future<void> createToolCall(AgentToolCallRecord call) async {
    if (call.status != AgentToolCallStatus.pending) {
      throw ArgumentError('New Agent tool calls must be pending');
    }
    await (await _storage.storageDatabase()).insertAgentToolCall(call);
  }

  Future<void> saveSnapshot(AgentSnapshotRecord snapshot) async {
    if (snapshot.kind == 'permission_policy') {
      throw ArgumentError('permission_policy is insert-only at run creation');
    }
    await (await _storage.storageDatabase()).insertAgentSnapshot(snapshot);
  }

  Future<bool> transitionRun(
    String id, {
    required AgentRunStatus from,
    required AgentRunStatus to,
    required DateTime at,
    String? errorCode,
    String? errorMessage,
  }) {
    _requireTransition(_runTransitions, from, to);
    return _transition(
      table: 'runs',
      id: id,
      from: from.name,
      to: to.name,
      at: at,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  Future<bool> transitionTurn(
    String id, {
    required AgentTurnStatus from,
    required AgentTurnStatus to,
    required DateTime at,
    String? errorCode,
    String? errorMessage,
  }) {
    _requireTransition(_turnTransitions, from, to);
    return _transition(
      table: 'turns',
      id: id,
      from: from.name,
      to: to.name,
      at: at,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  Future<bool> transitionItem(
    String id, {
    required AgentItemStatus from,
    required AgentItemStatus to,
    required DateTime at,
    String? errorCode,
    String? errorMessage,
  }) {
    _requireTransition(_itemTransitions, from, to);
    return _transition(
      table: 'items',
      id: id,
      from: from.name,
      to: to.name,
      at: at,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  Future<bool> transitionToolCall(
    String id, {
    required AgentToolCallStatus from,
    required AgentToolCallStatus to,
    required DateTime at,
    Object? result,
    String? errorCode,
    String? errorMessage,
  }) {
    _requireTransition(_toolCallTransitions, from, to);
    return _transition(
      table: 'tool_calls',
      id: id,
      from: from.name,
      to: to.name,
      at: at,
      result: result,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  Future<void> saveMcpServer(AgentMcpServerRecord server) async {
    _validateMcpServer(server);
    await (await _storage.storageDatabase()).upsertAgentMcpServer(server);
  }

  Future<List<AgentMcpServerRecord>> loadMcpServers() async {
    return (await _storage.storageDatabase()).loadAgentMcpServers();
  }

  Future<void> deleteMcpServer(String id) async {
    await (await _storage.storageDatabase()).deleteAgentMcpServer(id);
  }

  Future<AgentRestartReconciliation> reconcileAfterRestart({DateTime? at}) {
    return _storage.storageDatabase().then(
      (database) => database.reconcileAgentRestart(at ?? DateTime.now()),
    );
  }

  Future<bool> _transition({
    required String table,
    required String id,
    required String from,
    required String to,
    required DateTime at,
    Object? result,
    String? errorCode,
    String? errorMessage,
  }) async {
    return (await _storage.storageDatabase()).compareAndSetAgentStatus(
      table: table,
      id: id,
      expectedStatus: from,
      nextStatus: to,
      updatedAt: at,
      result: result,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  static void _requireTransition<T>(Map<T, Set<T>> transitions, T from, T to) {
    if (!(transitions[from]?.contains(to) ?? false)) {
      throw StateError('Invalid Agent status transition: $from -> $to');
    }
  }

  static void _validateMcpServer(AgentMcpServerRecord server) {
    if (server.id.trim().isEmpty || server.name.trim().isEmpty) {
      throw ArgumentError('MCP server id and name must not be empty');
    }
    final uri = server.url == null ? null : Uri.tryParse(server.url!);
    if (uri != null &&
        (uri.userInfo.isNotEmpty ||
            uri.query.isNotEmpty ||
            uri.fragment.isNotEmpty)) {
      throw ArgumentError(
        'MCP server URLs must not contain credentials, queries, or fragments',
      );
    }
    for (final name in server.environmentNames) {
      if (!_environmentName.hasMatch(name)) {
        throw ArgumentError.value(name, 'environmentNames', 'invalid name');
      }
    }
    for (final value in [
      server.command,
      server.url,
      ...server.arguments,
      ...server.environmentNames,
    ].whereType<String>()) {
      if (_secretAssignment.hasMatch(value)) {
        throw ArgumentError('MCP rows must not contain secret values');
      }
    }
    if (server.arguments.any(_secretArgument.hasMatch)) {
      throw ArgumentError('MCP arguments must reference secrets indirectly');
    }
  }

  static final _environmentName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
  static final _secretAssignment = RegExp(
    r'(api[_-]?key|token|secret|password|authorization)\s*[:=]',
    caseSensitive: false,
  );
  static final _secretArgument = RegExp(
    r'(^|[-_])(api[_-]?key|token|secret|password|authorization)($|[-_=])',
    caseSensitive: false,
  );

  static const _runTransitions = <AgentRunStatus, Set<AgentRunStatus>>{
    AgentRunStatus.queued: {
      AgentRunStatus.running,
      AgentRunStatus.failed,
      AgentRunStatus.cancelled,
    },
    AgentRunStatus.running: {
      AgentRunStatus.completed,
      AgentRunStatus.failed,
      AgentRunStatus.cancelled,
    },
  };
  static const _turnTransitions = <AgentTurnStatus, Set<AgentTurnStatus>>{
    AgentTurnStatus.pending: {
      AgentTurnStatus.running,
      AgentTurnStatus.failed,
      AgentTurnStatus.cancelled,
    },
    AgentTurnStatus.running: {
      AgentTurnStatus.completed,
      AgentTurnStatus.failed,
      AgentTurnStatus.cancelled,
    },
  };
  static const _itemTransitions = <AgentItemStatus, Set<AgentItemStatus>>{
    AgentItemStatus.pending: {
      AgentItemStatus.running,
      AgentItemStatus.failed,
      AgentItemStatus.cancelled,
    },
    AgentItemStatus.running: {
      AgentItemStatus.completed,
      AgentItemStatus.failed,
      AgentItemStatus.cancelled,
    },
  };
  static const _toolCallTransitions =
      <AgentToolCallStatus, Set<AgentToolCallStatus>>{
        AgentToolCallStatus.pending: {
          AgentToolCallStatus.running,
          AgentToolCallStatus.failed,
          AgentToolCallStatus.cancelled,
        },
        AgentToolCallStatus.running: {
          AgentToolCallStatus.completed,
          AgentToolCallStatus.failed,
          AgentToolCallStatus.cancelled,
        },
      };
}
