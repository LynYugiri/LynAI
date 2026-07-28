import 'agent_runtime.dart';
import '../services/lynai_permission_definitions.dart';

enum AgentToolCallStatus { pending, running, completed, failed, cancelled }

class AgentRunRecord {
  const AgentRunRecord({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.conversationId,
    this.completedAt,
    this.errorCode,
    this.errorMessage,
  });

  final String id;
  final String? conversationId;
  final AgentRunStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final String? errorCode;
  final String? errorMessage;
}

class AgentTurnRecord {
  const AgentTurnRecord({
    required this.id,
    required this.runId,
    required this.index,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.errorCode,
    this.errorMessage,
  });

  final String id;
  final String runId;
  final int index;
  final AgentTurnStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final String? errorCode;
  final String? errorMessage;
}

class AgentItemRecord {
  const AgentItemRecord({
    required this.id,
    required this.turnId,
    required this.index,
    required this.kind,
    required this.status,
    required this.payload,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.errorCode,
    this.errorMessage,
  });

  final String id;
  final String turnId;
  final int index;
  final AgentItemKind kind;
  final AgentItemStatus status;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final String? errorCode;
  final String? errorMessage;
}

class AgentToolCallRecord {
  const AgentToolCallRecord({
    required this.id,
    required this.itemId,
    required this.toolName,
    required this.arguments,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.result,
    this.completedAt,
    this.errorCode,
    this.errorMessage,
  });

  final String id;
  final String itemId;
  final String toolName;
  final Map<String, dynamic> arguments;
  final AgentToolCallStatus status;
  final Object? result;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final String? errorCode;
  final String? errorMessage;
}

class AgentSnapshotRecord {
  const AgentSnapshotRecord({
    required this.id,
    required this.runId,
    required this.kind,
    required this.data,
    required this.createdAt,
    this.turnId,
  });

  final String id;
  final String runId;
  final String? turnId;
  final String kind;
  final Map<String, dynamic> data;
  final DateTime createdAt;
}

class AgentRunCreation {
  const AgentRunCreation({required this.run, required this.permissionPolicy});

  final AgentRunRecord run;
  final AgentPermissionSnapshot permissionPolicy;
}

class AgentMcpServerRecord {
  const AgentMcpServerRecord({
    required this.id,
    required this.name,
    required this.transport,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    this.command,
    this.url,
    this.arguments = const [],
    this.environmentNames = const [],
  });

  final String id;
  final String name;
  final String transport;
  final String? command;
  final String? url;
  final List<String> arguments;
  final List<String> environmentNames;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class AgentRestartReconciliation {
  const AgentRestartReconciliation({
    required this.runIds,
    required this.turnCount,
    required this.itemCount,
    required this.toolCallCount,
  });

  final List<String> runIds;
  final int turnCount;
  final int itemCount;
  final int toolCallCount;

  bool get changed => runIds.isNotEmpty;
}
