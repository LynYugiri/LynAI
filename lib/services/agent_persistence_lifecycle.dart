import 'package:uuid/uuid.dart';

import '../models/agent_persistence.dart';
import '../models/agent_runtime.dart';
import '../repositories/agent_persistence_repository.dart';
import 'agent_tool_execution_service.dart';
import 'lynai_permission_definitions.dart';

class AgentRunPersistenceMetadata {
  const AgentRunPersistenceMetadata({
    this.conversationId,
    this.parentRunId,
    this.parentTurnId,
    this.parentToolCallId,
    this.permissionPolicy,
  });

  final String? conversationId;
  final String? parentRunId;
  final String? parentTurnId;
  final String? parentToolCallId;
  final AgentPermissionSnapshot? permissionPolicy;
}

abstract interface class AgentRunPersistenceLifecycle {
  AgentToolResultProcessor get toolResultProcessor;

  Future<void> startRun(String runId, AgentRunPersistenceMetadata metadata);

  Future<void> startTurn(AgentTurnIdentity identity);

  Future<void> recordAssistantResponse(
    AgentTurnIdentity identity, {
    required String content,
    required String reasoning,
    required List<AgentToolInvocation> toolCalls,
  });

  Future<void> startToolCalls(
    AgentTurnIdentity identity,
    List<AgentToolInvocation> toolCalls,
  );

  Future<void> completeToolCall(
    AgentTurnIdentity identity,
    AgentToolResult result,
  );

  Future<void> completeTurn(AgentTurnIdentity identity);

  Future<void> completeRun(String runId, AgentRunResult result);
}

class RepositoryAgentRunPersistenceLifecycle
    implements AgentRunPersistenceLifecycle {
  RepositoryAgentRunPersistenceLifecycle(
    this._repository, {
    required this.toolResultProcessor,
  });

  static const _uuid = Uuid();

  final AgentPersistenceRepository _repository;
  @override
  final AgentToolResultProcessor toolResultProcessor;
  final Map<String, _PersistedRunState> _runs = {};

  @override
  Future<void> startRun(
    String runId,
    AgentRunPersistenceMetadata metadata,
  ) async {
    final now = DateTime.now();
    await _repository.createRun(
      AgentRunRecord(
        id: runId,
        conversationId: metadata.conversationId,
        status: AgentRunStatus.queued,
        createdAt: now,
        updatedAt: now,
      ),
      permissionPolicy: metadata.permissionPolicy,
      parentRunId: metadata.parentRunId,
    );
    final state = _PersistedRunState();
    _runs[runId] = state;
    final parentData = <String, dynamic>{
      if (metadata.parentRunId != null) 'runId': metadata.parentRunId,
      if (metadata.parentTurnId != null) 'turnId': metadata.parentTurnId,
      if (metadata.parentToolCallId != null)
        'toolCallId': metadata.parentToolCallId,
    };
    if (parentData.isNotEmpty) {
      await _repository.saveSnapshot(
        AgentSnapshotRecord(
          id: _uuid.v4(),
          runId: runId,
          kind: 'parent_run',
          data: parentData,
          createdAt: now,
        ),
      );
    }
    await _requireCas(
      _repository.transitionRun(
        runId,
        from: AgentRunStatus.queued,
        to: AgentRunStatus.running,
        at: DateTime.now(),
      ),
      'run $runId queued -> running',
    );
    state.runStatus = AgentRunStatus.running;
  }

  @override
  Future<void> startTurn(AgentTurnIdentity identity) async {
    final state = _state(identity.runId);
    final now = DateTime.now();
    await _repository.createTurn(
      AgentTurnRecord(
        id: identity.turnId,
        runId: identity.runId,
        index: identity.turnIndex,
        status: AgentTurnStatus.pending,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _requireCas(
      _repository.transitionTurn(
        identity.turnId,
        from: AgentTurnStatus.pending,
        to: AgentTurnStatus.running,
        at: DateTime.now(),
      ),
      'turn ${identity.turnId} pending -> running',
    );
    state.turns[identity.turnId] = _PersistedTurnState();
  }

  @override
  Future<void> recordAssistantResponse(
    AgentTurnIdentity identity, {
    required String content,
    required String reasoning,
    required List<AgentToolInvocation> toolCalls,
  }) async {
    final turn = _turn(identity);
    var itemIndex = 0;
    if (reasoning.isNotEmpty) {
      await _createCompletedItem(
        turn,
        turnId: identity.turnId,
        index: itemIndex++,
        kind: AgentItemKind.reasoning,
        payload: {'text': reasoning},
      );
    }
    if (content.isNotEmpty || toolCalls.isEmpty) {
      await _createCompletedItem(
        turn,
        turnId: identity.turnId,
        index: itemIndex++,
        kind: AgentItemKind.message,
        payload: {'role': 'assistant', 'content': content},
      );
    }
    for (final invocation in toolCalls) {
      final now = DateTime.now();
      final itemId = _uuid.v4();
      final recordId = _uuid.v4();
      await _repository.createItem(
        AgentItemRecord(
          id: itemId,
          turnId: identity.turnId,
          index: itemIndex++,
          kind: AgentItemKind.toolCall,
          status: AgentItemStatus.pending,
          payload: {
            'invocationId': invocation.id,
            'name': invocation.name,
            'arguments': invocation.arguments,
          },
          createdAt: now,
          updatedAt: now,
        ),
      );
      turn.items[itemId] = AgentItemStatus.pending;
      await _repository.createToolCall(
        AgentToolCallRecord(
          id: recordId,
          itemId: itemId,
          toolName: invocation.name,
          arguments: invocation.arguments,
          status: AgentToolCallStatus.pending,
          createdAt: now,
          updatedAt: now,
        ),
      );
      turn.toolCalls[invocation.id] = _PersistedToolCallState(
        recordId: recordId,
        itemId: itemId,
      );
    }
  }

  @override
  Future<void> startToolCalls(
    AgentTurnIdentity identity,
    List<AgentToolInvocation> toolCalls,
  ) async {
    final turn = _turn(identity);
    for (final invocation in toolCalls) {
      final call = turn.toolCalls[invocation.id];
      if (call == null) {
        throw StateError('Tool call ${invocation.id} was not persisted');
      }
      await _requireCas(
        _repository.transitionItem(
          call.itemId,
          from: AgentItemStatus.pending,
          to: AgentItemStatus.running,
          at: DateTime.now(),
        ),
        'tool item ${call.itemId} pending -> running',
      );
      turn.items[call.itemId] = AgentItemStatus.running;
      await _requireCas(
        _repository.transitionToolCall(
          call.recordId,
          from: AgentToolCallStatus.pending,
          to: AgentToolCallStatus.running,
          at: DateTime.now(),
        ),
        'tool call ${call.recordId} pending -> running',
      );
      call.status = AgentToolCallStatus.running;
    }
  }

  @override
  Future<void> completeToolCall(
    AgentTurnIdentity identity,
    AgentToolResult result,
  ) async {
    final turn = _turn(identity);
    final call = turn.toolCalls[result.invocationId];
    if (call == null) {
      throw StateError('Unknown tool result ${result.invocationId}');
    }
    final status = switch (result.status) {
      AgentToolResultStatus.success => AgentToolCallStatus.completed,
      AgentToolResultStatus.failure => AgentToolCallStatus.failed,
      AgentToolResultStatus.cancelled => AgentToolCallStatus.cancelled,
    };
    await _requireCas(
      _repository.transitionToolCall(
        call.recordId,
        from: AgentToolCallStatus.running,
        to: status,
        at: DateTime.now(),
        result: _toolResultPayload(result),
        errorCode: result.errorCode,
        errorMessage: result.errorMessage,
      ),
      'tool call ${call.recordId} running -> ${status.name}',
    );
    call.status = status;
    final itemStatus = switch (result.status) {
      AgentToolResultStatus.success => AgentItemStatus.completed,
      AgentToolResultStatus.failure => AgentItemStatus.failed,
      AgentToolResultStatus.cancelled => AgentItemStatus.cancelled,
    };
    await _requireCas(
      _repository.transitionItem(
        call.itemId,
        from: AgentItemStatus.running,
        to: itemStatus,
        at: DateTime.now(),
        errorCode: result.errorCode,
        errorMessage: result.errorMessage,
      ),
      'tool item ${call.itemId} running -> ${itemStatus.name}',
    );
    turn.items[call.itemId] = itemStatus;
    await _createCompletedItem(
      turn,
      turnId: identity.turnId,
      index: turn.items.length,
      kind: AgentItemKind.toolResult,
      payload: _toolResultPayload(result),
    );
  }

  @override
  Future<void> completeTurn(AgentTurnIdentity identity) async {
    final turn = _turn(identity);
    await _requireCas(
      _repository.transitionTurn(
        identity.turnId,
        from: AgentTurnStatus.running,
        to: AgentTurnStatus.completed,
        at: DateTime.now(),
      ),
      'turn ${identity.turnId} running -> completed',
    );
    turn.status = AgentTurnStatus.completed;
  }

  @override
  Future<void> completeRun(String runId, AgentRunResult result) async {
    final state = _state(runId);
    final turnStatus = switch (result.status) {
      AgentRunStatus.completed => AgentTurnStatus.completed,
      AgentRunStatus.cancelled => AgentTurnStatus.cancelled,
      _ => AgentTurnStatus.failed,
    };
    final itemStatus = switch (result.status) {
      AgentRunStatus.completed => AgentItemStatus.failed,
      AgentRunStatus.cancelled => AgentItemStatus.cancelled,
      _ => AgentItemStatus.failed,
    };
    final callStatus = switch (result.status) {
      AgentRunStatus.completed => AgentToolCallStatus.failed,
      AgentRunStatus.cancelled => AgentToolCallStatus.cancelled,
      _ => AgentToolCallStatus.failed,
    };
    final errorCode = result.toolRoundLimitReached
        ? 'tool_round_limit_reached'
        : result.status == AgentRunStatus.cancelled
        ? 'cancelled'
        : result.status == AgentRunStatus.failed
        ? 'run_failed'
        : null;
    final errorMessage = result.error?.toString();
    for (final entry in state.turns.entries) {
      final turn = entry.value;
      for (final call in turn.toolCalls.values) {
        if (call.status == AgentToolCallStatus.pending ||
            call.status == AgentToolCallStatus.running) {
          await _requireCas(
            _repository.transitionToolCall(
              call.recordId,
              from: call.status,
              to: callStatus,
              at: DateTime.now(),
              errorCode: errorCode,
              errorMessage: errorMessage,
            ),
            'tool call ${call.recordId} ${call.status.name} -> ${callStatus.name}',
          );
          call.status = callStatus;
        }
      }
      for (final item in turn.items.entries.toList()) {
        if (item.value == AgentItemStatus.pending ||
            item.value == AgentItemStatus.running) {
          await _requireCas(
            _repository.transitionItem(
              item.key,
              from: item.value,
              to: itemStatus,
              at: DateTime.now(),
              errorCode: errorCode,
              errorMessage: errorMessage,
            ),
            'item ${item.key} ${item.value.name} -> ${itemStatus.name}',
          );
          turn.items[item.key] = itemStatus;
        }
      }
      if (turn.status == AgentTurnStatus.running) {
        await _requireCas(
          _repository.transitionTurn(
            entry.key,
            from: AgentTurnStatus.running,
            to: turnStatus,
            at: DateTime.now(),
            errorCode: errorCode,
            errorMessage: errorMessage,
          ),
          'turn ${entry.key} running -> ${turnStatus.name}',
        );
        turn.status = turnStatus;
      }
    }
    await _requireCas(
      _repository.transitionRun(
        runId,
        from: state.runStatus,
        to: result.status,
        at: DateTime.now(),
        errorCode: errorCode,
        errorMessage: errorMessage,
      ),
      'run $runId ${state.runStatus.name} -> ${result.status.name}',
    );
    state.runStatus = result.status;
    _runs.remove(runId);
  }

  Future<void> _createCompletedItem(
    _PersistedTurnState turn, {
    required String turnId,
    required int index,
    required AgentItemKind kind,
    required Map<String, dynamic> payload,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    await _repository.createItem(
      AgentItemRecord(
        id: id,
        turnId: turnId,
        index: index,
        kind: kind,
        status: AgentItemStatus.pending,
        payload: payload,
        createdAt: now,
        updatedAt: now,
      ),
    );
    turn.items[id] = AgentItemStatus.pending;
    await _requireCas(
      _repository.transitionItem(
        id,
        from: AgentItemStatus.pending,
        to: AgentItemStatus.running,
        at: DateTime.now(),
      ),
      'item $id pending -> running',
    );
    turn.items[id] = AgentItemStatus.running;
    await _requireCas(
      _repository.transitionItem(
        id,
        from: AgentItemStatus.running,
        to: AgentItemStatus.completed,
        at: DateTime.now(),
      ),
      'item $id running -> completed',
    );
    turn.items[id] = AgentItemStatus.completed;
  }

  _PersistedRunState _state(String runId) {
    final state = _runs[runId];
    if (state == null) throw StateError('Run $runId was not persisted');
    return state;
  }

  _PersistedTurnState _turn(AgentTurnIdentity identity) {
    final turn = _state(identity.runId).turns[identity.turnId];
    if (turn == null) {
      throw StateError('Turn ${identity.turnId} was not persisted');
    }
    return turn;
  }

  Future<void> _requireCas(Future<bool> transition, String description) async {
    if (!await transition) {
      throw StateError('Agent persistence CAS failed: $description');
    }
  }

  Map<String, dynamic> _toolResultPayload(AgentToolResult result) => {
    'invocationId': result.invocationId,
    'toolName': result.toolName,
    'status': result.status.name,
    if (result.value != null) 'value': result.value,
    if (result.errorCode != null) 'errorCode': result.errorCode,
    if (result.errorMessage != null) 'errorMessage': result.errorMessage,
  };
}

class _PersistedRunState {
  AgentRunStatus runStatus = AgentRunStatus.queued;
  final Map<String, _PersistedTurnState> turns = {};
}

class _PersistedTurnState {
  AgentTurnStatus status = AgentTurnStatus.running;
  final Map<String, AgentItemStatus> items = {};
  final Map<String, _PersistedToolCallState> toolCalls = {};
}

class _PersistedToolCallState {
  _PersistedToolCallState({required this.recordId, required this.itemId});

  final String recordId;
  final String itemId;
  AgentToolCallStatus status = AgentToolCallStatus.pending;
}
