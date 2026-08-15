import 'dart:collection';

enum AgentRunStatus { queued, running, completed, failed, cancelled }

enum AgentTurnStatus { pending, running, completed, failed, cancelled }

enum AgentItemStatus { pending, running, completed, failed, cancelled }

enum AgentItemKind { message, reasoning, toolCall, toolResult }

enum AgentToolSource { builtIn, plugin, runtime, mcp }

enum AgentToolSideEffect { none, read, write, external }

enum AgentToolConcurrency { parallelSafe, exclusive, keyed }

enum AgentToolOperation {
  observe,
  read,
  create,
  update,
  delete,
  execute,
  network,
}

enum AgentToolRisk { low, elevated, high }

enum AgentToolResultPolicy { returnValue, redactValue, discardValue }

enum AgentToolPermissionMode { all, any }

class AgentToolPermissionRequirements {
  final List<String> permissions;
  final AgentToolPermissionMode mode;

  AgentToolPermissionRequirements({
    Iterable<String> permissions = const [],
    this.mode = AgentToolPermissionMode.all,
  }) : permissions = List.unmodifiable(
         permissions
             .map((item) => item.trim())
             .where((item) => item.isNotEmpty),
       );

  bool allows(Iterable<String> grantedPermissions) {
    if (permissions.isEmpty) return true;
    final granted = grantedPermissions.toSet();
    return switch (mode) {
      AgentToolPermissionMode.all => permissions.every(granted.contains),
      AgentToolPermissionMode.any => permissions.any(granted.contains),
    };
  }
}

class AgentToolSemantics {
  final AgentToolOperation operation;
  final AgentToolRisk risk;
  final AgentToolResultPolicy resultPolicy;
  final Duration timeout;

  const AgentToolSemantics({
    this.operation = AgentToolOperation.observe,
    this.risk = AgentToolRisk.low,
    this.resultPolicy = AgentToolResultPolicy.returnValue,
    this.timeout = const Duration(seconds: 30),
  });
}

class AgentToolDescriptor {
  final String name;
  final String description;
  final AgentToolSource source;
  final AgentToolSideEffect sideEffect;
  final AgentToolConcurrency concurrency;
  final Map<String, dynamic> parameters;

  AgentToolDescriptor({
    required this.name,
    required this.description,
    required this.source,
    required this.sideEffect,
    required this.concurrency,
    Map<String, dynamic> parameters = const {
      'type': 'object',
      'properties': <String, dynamic>{},
      'additionalProperties': false,
    },
  }) : parameters = _immutableJsonMap(parameters) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
  }
}

class AgentToolInvocation {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String? concurrencyKey;

  AgentToolInvocation({
    required this.id,
    required this.name,
    Map<String, dynamic> arguments = const {},
    this.concurrencyKey,
  }) : arguments = _immutableJsonMap(arguments) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
  }
}

class AgentToolExecutionIdentity {
  final String runId;
  final String turnId;
  final int turnIndex;
  final String invocationId;
  final String toolName;
  final String? conversationId;

  const AgentToolExecutionIdentity({
    required this.runId,
    required this.turnId,
    required this.turnIndex,
    required this.invocationId,
    required this.toolName,
    this.conversationId,
  });
}

enum AgentToolResultStatus { success, failure, cancelled }

class AgentToolResult {
  final String invocationId;
  final String toolName;
  final AgentToolResultStatus status;
  final Object? value;
  final String? errorCode;
  final String? errorMessage;

  const AgentToolResult._({
    required this.invocationId,
    required this.toolName,
    required this.status,
    this.value,
    this.errorCode,
    this.errorMessage,
  });

  factory AgentToolResult.success({
    required String invocationId,
    required String toolName,
    Object? value,
  }) => AgentToolResult._(
    invocationId: invocationId,
    toolName: toolName,
    status: AgentToolResultStatus.success,
    value: _immutableJsonValue(value),
  );

  factory AgentToolResult.failure({
    required String invocationId,
    required String toolName,
    required String code,
    required String message,
    Object? value,
  }) => AgentToolResult._(
    invocationId: invocationId,
    toolName: toolName,
    status: AgentToolResultStatus.failure,
    value: _immutableJsonValue(value),
    errorCode: code,
    errorMessage: message,
  );

  factory AgentToolResult.cancelled({
    required String invocationId,
    required String toolName,
    required String message,
  }) => AgentToolResult._(
    invocationId: invocationId,
    toolName: toolName,
    status: AgentToolResultStatus.cancelled,
    errorCode: 'cancelled',
    errorMessage: message,
  );

  bool get isSuccess => status == AgentToolResultStatus.success;
}

sealed class AgentModelStreamEvent {
  const AgentModelStreamEvent();
}

final class AgentModelTextDelta extends AgentModelStreamEvent {
  final String text;

  const AgentModelTextDelta(this.text);
}

final class AgentModelReasoningDelta extends AgentModelStreamEvent {
  final String text;

  const AgentModelReasoningDelta(this.text);
}

final class AgentModelToolCalls extends AgentModelStreamEvent {
  final List<AgentToolInvocation> calls;

  AgentModelToolCalls(Iterable<AgentToolInvocation> calls)
    : calls = List.unmodifiable(calls);
}

final class AgentModelStreamCompleted extends AgentModelStreamEvent {
  const AgentModelStreamCompleted();
}

final class AgentModelStreamFailure extends AgentModelStreamEvent {
  final Object error;
  final StackTrace stackTrace;

  const AgentModelStreamFailure(this.error, this.stackTrace);
}

typedef AgentModelTurnStream =
    Stream<AgentModelStreamEvent> Function(AgentModelTurnRequest request);

typedef AgentToolCompatibilityExecutor =
    Future<List<AgentToolResult>> Function(
      List<AgentToolInvocation> invocations,
      AgentTurnIdentity identity,
      AgentRunCancellation cancellationToken,
    );

abstract interface class AgentRunCancellation {
  bool get isCancellationRequested;
  void throwIfCancellationRequested();
}

class AgentTurnIdentity {
  final String runId;
  final String turnId;
  final int turnIndex;

  const AgentTurnIdentity({
    required this.runId,
    required this.turnId,
    required this.turnIndex,
  });
}

class AgentModelTurnRequest {
  final AgentTurnIdentity identity;
  final List<Map<String, dynamic>> messages;
  final bool forceFinalResponse;

  AgentModelTurnRequest({
    required this.identity,
    required Iterable<Map<String, dynamic>> messages,
    required this.forceFinalResponse,
  }) : messages = List.unmodifiable(
         messages.map((message) => _immutableJsonMap(message)),
       );
}

enum AgentRunEventKind {
  runStarted,
  turnStarted,
  textDelta,
  reasoningDelta,
  toolCalls,
  toolStarted,
  toolCompleted,
  turnCompleted,
  runCompleted,
  runFailed,
  runCancelled,
}

class AgentRunEvent {
  final AgentRunEventKind kind;
  final String runId;
  final String? turnId;
  final int? turnIndex;
  final String? itemId;
  final String? text;
  final List<AgentToolInvocation> toolCalls;
  final AgentToolInvocation? toolCall;
  final Object? error;

  AgentRunEvent({
    required this.kind,
    required this.runId,
    this.turnId,
    this.turnIndex,
    this.itemId,
    this.text,
    Iterable<AgentToolInvocation> toolCalls = const [],
    this.toolCall,
    this.error,
  }) : toolCalls = List.unmodifiable(toolCalls);
}

class AgentRunResult {
  final String runId;
  final AgentRunStatus status;
  final String content;
  final String partialContent;
  final String? reasoning;
  final int toolRounds;
  final bool toolRoundLimitReached;
  final List<Map<String, dynamic>> messages;
  final Object? error;

  AgentRunResult({
    required this.runId,
    required this.status,
    required this.content,
    required this.partialContent,
    required this.reasoning,
    required this.toolRounds,
    this.toolRoundLimitReached = false,
    required Iterable<Map<String, dynamic>> messages,
    this.error,
  }) : messages = List.unmodifiable(
         messages.map((message) => _immutableJsonMap(message)),
       );

  bool get isCancelled => status == AgentRunStatus.cancelled;
  bool get isSuccess => status == AgentRunStatus.completed;
}

abstract interface class AgentRunHandle {
  String get id;
  Stream<AgentRunEvent> get events;
  Future<AgentRunResult> get result;
  bool get isCancelled;
  void cancel();
}

Map<String, dynamic> _immutableJsonMap(Map<String, dynamic> value) {
  return Map.unmodifiable(
    value.map((key, item) => MapEntry(key, _immutableJsonValue(item))),
  );
}

Object? _immutableJsonValue(Object? value) {
  if (value is Map) {
    return UnmodifiableMapView(
      value.map(
        (key, item) => MapEntry(key.toString(), _immutableJsonValue(item)),
      ),
    );
  }
  if (value is List) {
    return List.unmodifiable(value.map(_immutableJsonValue));
  }
  return value;
}
