import '../models/agent_runtime.dart';
import 'agent_cancellation.dart';
import 'agent_tool_registry.dart';
import 'agent_tool_scheduler.dart';
import 'lynai_permission_definitions.dart';

abstract interface class AgentToolResultProcessor {
  Future<List<AgentToolResult>> process(
    List<AgentToolResult> results, {
    required AgentCancellationToken cancellationToken,
  });
}

class AgentToolExecutionRequest {
  final AgentToolSnapshot snapshot;
  final List<AgentToolInvocation> invocations;
  final AgentTurnIdentity turnIdentity;
  final AgentPermissionSnapshot permissionSnapshot;
  final AgentCancellationToken cancellationToken;
  final String? conversationId;
  final DateTime? deadline;

  AgentToolExecutionRequest({
    required this.snapshot,
    required Iterable<AgentToolInvocation> invocations,
    required this.turnIdentity,
    required this.permissionSnapshot,
    required this.cancellationToken,
    this.conversationId,
    this.deadline,
  }) : invocations = List.unmodifiable(invocations);
}

class AgentToolExecutionService {
  final AgentToolScheduler scheduler;
  final AgentToolAuthorizer _authorizer;
  final AgentToolErrorSanitizer _errorSanitizer;

  AgentToolExecutionService({
    AgentToolScheduler? scheduler,
    AgentToolAuthorizer? authorizer,
    AgentToolErrorSanitizer? errorSanitizer,
  }) : scheduler = scheduler ?? AgentToolScheduler(),
       _authorizer = authorizer ?? _authorizePermissions,
       _errorSanitizer = errorSanitizer ?? _sanitizeError;

  Future<List<AgentToolResult>> execute(
    AgentToolExecutionRequest request,
  ) async {
    return scheduler.executeCaptured(
      snapshot: request.snapshot,
      invocations: request.invocations,
      turnIdentity: request.turnIdentity,
      permissionSnapshot: request.permissionSnapshot,
      cancellationToken: request.cancellationToken,
      conversationId: request.conversationId,
      deadline: request.deadline,
      authorizer: _authorizer,
      errorSanitizer: _errorSanitizer,
    );
  }

  AgentToolCompatibilityExecutor capturedExecutor({
    required AgentToolSnapshot snapshot,
    required AgentPermissionSnapshot permissionSnapshot,
    String? conversationId,
    DateTime? deadline,
  }) {
    return (invocations, identity, cancellationToken) {
      if (cancellationToken is! AgentCancellationToken) {
        throw ArgumentError.value(
          cancellationToken,
          'cancellationToken',
          'must expose cancellation completion',
        );
      }
      return execute(
        AgentToolExecutionRequest(
          snapshot: snapshot,
          invocations: invocations,
          turnIdentity: identity,
          permissionSnapshot: permissionSnapshot,
          cancellationToken: cancellationToken,
          conversationId: conversationId,
          deadline: deadline,
        ),
      );
    };
  }

  static bool _authorizePermissions(
    AgentToolRegistration registration,
    AgentToolExecutionContext context,
  ) => registration.spec.permissionRequirements.allows(
    context.permissionSnapshot.permissions,
  );

  static String _sanitizeError(Object error) => 'Tool execution failed';
}
