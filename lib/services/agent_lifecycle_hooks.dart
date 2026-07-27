import 'dart:async';

import '../models/agent_runtime.dart';
import 'agent_cancellation.dart';
import 'agent_context_builder.dart';

class AgentModelRequestHookContext {
  final AgentModelTurnRequest request;
  final AgentRunCancellation cancellationToken;

  const AgentModelRequestHookContext(this.request, this.cancellationToken);
}

class AgentModelResponseHookContext {
  final AgentTurnIdentity identity;
  final String content;
  final String reasoning;
  final List<AgentToolInvocation> toolCalls;
  final AgentRunCancellation cancellationToken;

  AgentModelResponseHookContext({
    required this.identity,
    required this.content,
    required this.reasoning,
    required Iterable<AgentToolInvocation> toolCalls,
    required this.cancellationToken,
  }) : toolCalls = List.unmodifiable(toolCalls);
}

class AgentToolCallHookContext {
  final AgentTurnIdentity identity;
  final AgentToolInvocation invocation;
  final AgentRunCancellation cancellationToken;

  const AgentToolCallHookContext({
    required this.identity,
    required this.invocation,
    required this.cancellationToken,
  });
}

class AgentToolResultHookContext {
  final AgentTurnIdentity identity;
  final AgentToolInvocation invocation;
  final AgentToolResult result;
  final AgentRunCancellation cancellationToken;

  const AgentToolResultHookContext({
    required this.identity,
    required this.invocation,
    required this.result,
    required this.cancellationToken,
  });
}

class AgentCompactionHookContext {
  final AgentTurnIdentity identity;
  final AgentCompactionRequest request;

  const AgentCompactionHookContext(this.identity, this.request);
}

class AgentAfterRunHookContext {
  final AgentRunResult result;
  final AgentRunCancellation cancellationToken;

  const AgentAfterRunHookContext(this.result, this.cancellationToken);
}

typedef AgentLifecycleHook<T> = FutureOr<void> Function(T context);

class AgentLifecycleHooks {
  final Duration timeout;
  final AgentLifecycleHook<AgentModelRequestHookContext>? beforeModelRequest;
  final AgentLifecycleHook<AgentModelResponseHookContext>? afterModelResponse;
  final AgentLifecycleHook<AgentToolCallHookContext>? beforeToolCall;
  final AgentLifecycleHook<AgentToolResultHookContext>? afterToolCall;
  final AgentLifecycleHook<AgentCompactionHookContext>? beforeCompaction;
  final AgentLifecycleHook<AgentAfterRunHookContext>? afterRun;

  const AgentLifecycleHooks({
    this.timeout = const Duration(seconds: 2),
    this.beforeModelRequest,
    this.afterModelResponse,
    this.beforeToolCall,
    this.afterToolCall,
    this.beforeCompaction,
    this.afterRun,
  });
}

class AgentLifecycleHookRunner {
  final AgentLifecycleHooks hooks;

  const AgentLifecycleHookRunner(this.hooks);

  Future<void> invoke<T>(
    AgentLifecycleHook<T>? hook,
    T context,
    AgentCancellationToken cancellationToken, {
    bool cancelWithRun = true,
  }) async {
    if (hook == null) return;
    if (cancelWithRun) cancellationToken.throwIfCancellationRequested();
    try {
      final hookFuture = Future<void>.sync(() => hook(context));
      if (!cancelWithRun) {
        await hookFuture.timeout(hooks.timeout);
        return;
      }
      final cancellation = cancellationToken.whenCancelled.then<void>(
        (reason) => throw AgentCancellationException(reason),
      );
      await Future.any([hookFuture.timeout(hooks.timeout), cancellation]);
      cancellationToken.throwIfCancellationRequested();
    } on AgentCancellationException {
      rethrow;
    } catch (_) {
      // Hooks are observational and must not break the agent run.
    }
  }
}
