import 'dart:async';

import 'package:uuid/uuid.dart';

import '../models/agent_runtime.dart';
import 'agent_cancellation.dart';
import 'agent_context_builder.dart';
import 'agent_lifecycle_hooks.dart';
import 'agent_persistence_lifecycle.dart';
import 'agent_protocol_codec.dart';
import 'agent_tool_execution_service.dart';
import 'dataset_runtime_barrier.dart';

class AgentLoopRuntime {
  static const _uuid = Uuid();

  const AgentLoopRuntime({
    this.codec = const AgentProtocolCodec(),
    this.contextBuilder = const AgentContextBuilder(),
    this.cleanupTimeout = const Duration(seconds: 2),
  });

  final AgentProtocolCodec codec;
  final AgentContextBuilder contextBuilder;
  final Duration cleanupTimeout;

  AgentRunHandle start({
    required Iterable<Map<String, dynamic>> messages,
    required AgentModelTurnStream model,
    required AgentToolCompatibilityExecutor executeTools,
    required int maxToolRounds,
    String? runId,
    AgentRunPersistenceLifecycle? persistence,
    AgentToolResultProcessor? toolResultProcessor,
    AgentRunPersistenceMetadata persistenceMetadata =
        const AgentRunPersistenceMetadata(),
    AgentContextCompactor? compactContext,
    AgentLifecycleHooks hooks = const AgentLifecycleHooks(),
    bool Function(Object error)? isContextOverflow,
    AgentCancellationToken? parentCancellationToken,
    DatasetRuntimeBarrier? datasetBarrier,
    String finalTurnInstruction = '工具调用已达到上限。不要再调用工具，请基于已有文本和工具结果直接给出最终回复。',
  }) {
    final handle = _AgentRunHandle(
      runId ?? _uuid.v4(),
      parentCancellationToken: parentCancellationToken,
    );
    datasetBarrier?.trackAgentRun(handle);
    unawaited(
      Future<void>.microtask(
        () => _run(
          handle,
          messages: messages,
          model: model,
          executeTools: executeTools,
          maxToolRounds: maxToolRounds,
          persistence: persistence,
          toolResultProcessor: toolResultProcessor,
          persistenceMetadata: persistenceMetadata,
          compactContext: compactContext,
          hooks: hooks,
          isContextOverflow: isContextOverflow,
          finalTurnInstruction: finalTurnInstruction,
        ),
      ),
    );
    return handle;
  }

  Future<void> _run(
    _AgentRunHandle handle, {
    required Iterable<Map<String, dynamic>> messages,
    required AgentModelTurnStream model,
    required AgentToolCompatibilityExecutor executeTools,
    required int maxToolRounds,
    required AgentRunPersistenceLifecycle? persistence,
    required AgentToolResultProcessor? toolResultProcessor,
    required AgentRunPersistenceMetadata persistenceMetadata,
    required AgentContextCompactor? compactContext,
    required AgentLifecycleHooks hooks,
    required bool Function(Object error)? isContextOverflow,
    required String finalTurnInstruction,
  }) async {
    final working = messages
        .map((message) => Map<String, dynamic>.from(message))
        .toList();
    var latestContent = '';
    final partialContent = _TurnTextAccumulator();
    final allReasoning = _TurnTextAccumulator();
    var toolRounds = 0;
    var overflowRetried = false;
    final hookRunner = AgentLifecycleHookRunner(hooks);
    AgentRunResult? result;
    try {
      await persistence?.startRun(handle.id, persistenceMetadata);
      handle.token.throwIfCancellationRequested();
      handle.emit(
        AgentRunEvent(kind: AgentRunEventKind.runStarted, runId: handle.id),
      );
      for (var turnIndex = 0; ; turnIndex++) {
        handle.token.throwIfCancellationRequested();
        final identity = AgentTurnIdentity(
          runId: handle.id,
          turnId: _uuid.v4(),
          turnIndex: turnIndex,
        );
        final forceFinal = toolRounds == maxToolRounds;
        if (forceFinal) {
          working.add({'role': 'system', 'content': finalTurnInstruction});
        }
        await persistence?.startTurn(identity);
        handle.emit(
          AgentRunEvent(
            kind: AgentRunEventKind.turnStarted,
            runId: handle.id,
            turnId: identity.turnId,
            turnIndex: turnIndex,
          ),
        );
        Future<AgentContextBuildResult> buildContext(bool forceCompaction) {
          return contextBuilder.build(
            messages: working,
            cancellationToken: handle.token,
            forceCompaction: forceCompaction,
            compact: compactContext == null
                ? null
                : (request) async {
                    await hookRunner.invoke(
                      hooks.beforeCompaction,
                      AgentCompactionHookContext(identity, request),
                      handle.token,
                    );
                    return compactContext(request);
                  },
          );
        }

        var context = await buildContext(false);
        late _TurnResult turn;
        final turnProgress = _TurnProgress(
          content: partialContent,
          reasoning: allReasoning,
        );
        while (true) {
          final request = AgentModelTurnRequest(
            identity: identity,
            messages: context.messages,
            forceFinalResponse: forceFinal,
          );
          await hookRunner.invoke(
            hooks.beforeModelRequest,
            AgentModelRequestHookContext(request, handle.token),
            handle.token,
          );
          try {
            turn = await _consumeTurn(
              handle,
              identity,
              model(request),
              turnProgress,
            );
            break;
          } catch (error) {
            final overflow =
                isContextOverflow?.call(error) ??
                _defaultContextOverflow(error);
            if (!overflow || overflowRetried) rethrow;
            overflowRetried = true;
            context = await buildContext(true);
          }
        }
        handle.token.throwIfCancellationRequested();
        _validateToolCalls(turn.toolCalls);
        await persistence?.recordAssistantResponse(
          identity,
          content: turn.content,
          reasoning: turn.reasoning,
          toolCalls: turn.toolCalls,
        );
        await hookRunner.invoke(
          hooks.afterModelResponse,
          AgentModelResponseHookContext(
            identity: identity,
            content: turn.content,
            reasoning: turn.reasoning,
            toolCalls: turn.toolCalls,
            cancellationToken: handle.token,
          ),
          handle.token,
        );
        latestContent = turn.content;
        handle.emit(
          AgentRunEvent(
            kind: AgentRunEventKind.turnCompleted,
            runId: handle.id,
            turnId: identity.turnId,
            turnIndex: turnIndex,
          ),
        );
        if (turn.toolCalls.isEmpty || forceFinal) {
          await persistence?.completeTurn(identity);
          result = AgentRunResult(
            runId: handle.id,
            status: AgentRunStatus.completed,
            content: latestContent,
            partialContent: partialContent.value,
            reasoning: allReasoning.isEmpty ? null : allReasoning.value,
            toolRounds: toolRounds,
            toolRoundLimitReached: forceFinal && turn.toolCalls.isNotEmpty,
            messages: working,
          );
          break;
        }
        handle.emit(
          AgentRunEvent(
            kind: AgentRunEventKind.toolCalls,
            runId: handle.id,
            turnId: identity.turnId,
            turnIndex: turnIndex,
            toolCalls: turn.toolCalls,
          ),
        );
        working.add(
          codec.assistantToolCallMessage(turn.content, turn.toolCalls),
        );
        for (final call in turn.toolCalls) {
          await hookRunner.invoke(
            hooks.beforeToolCall,
            AgentToolCallHookContext(
              identity: identity,
              invocation: call,
              cancellationToken: handle.token,
            ),
            handle.token,
          );
          handle.emit(
            AgentRunEvent(
              kind: AgentRunEventKind.toolStarted,
              runId: handle.id,
              turnId: identity.turnId,
              turnIndex: turnIndex,
              itemId: call.id,
              toolCall: call,
            ),
          );
        }
        handle.token.throwIfCancellationRequested();
        await persistence?.startToolCalls(identity, turn.toolCalls);
        handle.token.throwIfCancellationRequested();
        var results = await _executeTools(
          handle,
          () => executeTools(turn.toolCalls, identity, handle.token),
        );
        handle.token.throwIfCancellationRequested();
        _validateToolResults(turn.toolCalls, results);
        if (toolResultProcessor != null) {
          results = await toolResultProcessor.process(
            results,
            cancellationToken: handle.token,
          );
          handle.token.throwIfCancellationRequested();
          _validateToolResults(turn.toolCalls, results);
        }
        for (final result in results) {
          await persistence?.completeToolCall(identity, result);
          working.add(codec.toolResultMessage(result));
          final invocation = turn.toolCalls.firstWhere(
            (call) => call.id == result.invocationId,
          );
          await hookRunner.invoke(
            hooks.afterToolCall,
            AgentToolResultHookContext(
              identity: identity,
              invocation: invocation,
              result: result,
              cancellationToken: handle.token,
            ),
            handle.token,
          );
          handle.emit(
            AgentRunEvent(
              kind: AgentRunEventKind.toolCompleted,
              runId: handle.id,
              turnId: identity.turnId,
              turnIndex: identity.turnIndex,
              itemId: result.invocationId,
              toolCall: invocation,
            ),
          );
        }
        await persistence?.completeTurn(identity);
        toolRounds++;
      }
    } on AgentCancellationException catch (error) {
      result = AgentRunResult(
        runId: handle.id,
        status: AgentRunStatus.cancelled,
        content: latestContent,
        partialContent: partialContent.value,
        reasoning: allReasoning.isEmpty ? null : allReasoning.value,
        toolRounds: toolRounds,
        messages: working,
        error: error,
      );
    } catch (error) {
      result = AgentRunResult(
        runId: handle.id,
        status: AgentRunStatus.failed,
        content: latestContent,
        partialContent: partialContent.value,
        reasoning: allReasoning.isEmpty ? null : allReasoning.value,
        toolRounds: toolRounds,
        messages: working,
        error: error,
      );
    }
    var completed = result;
    if (persistence != null) {
      try {
        await persistence
            .completeRun(handle.id, completed)
            .timeout(cleanupTimeout);
      } catch (error) {
        if (completed.status == AgentRunStatus.completed) {
          completed = AgentRunResult(
            runId: handle.id,
            status: AgentRunStatus.failed,
            content: completed.content,
            partialContent: completed.partialContent,
            reasoning: completed.reasoning,
            toolRounds: completed.toolRounds,
            messages: completed.messages,
            error: error,
          );
        }
      }
    }
    await hookRunner.invoke(
      hooks.afterRun,
      AgentAfterRunHookContext(completed, handle.token),
      handle.token,
      cancelWithRun: false,
    );
    handle.complete(completed);
  }

  Future<_TurnResult> _consumeTurn(
    _AgentRunHandle handle,
    AgentTurnIdentity identity,
    Stream<AgentModelStreamEvent> stream,
    _TurnProgress progress,
  ) async {
    var content = '';
    var reasoning = '';
    var calls = const <AgentToolInvocation>[];
    final done = Completer<void>();
    late final StreamSubscription<AgentModelStreamEvent> subscription;
    subscription = stream.listen(
      (event) {
        if (handle.isCancelled || done.isCompleted) return;
        switch (event) {
          case AgentModelTextDelta():
            content += event.text;
            progress.content.add(identity.turnIndex, event.text);
            handle.emit(
              AgentRunEvent(
                kind: AgentRunEventKind.textDelta,
                runId: handle.id,
                turnId: identity.turnId,
                turnIndex: identity.turnIndex,
                text: event.text,
              ),
            );
          case AgentModelReasoningDelta():
            reasoning += event.text;
            progress.reasoning.add(identity.turnIndex, event.text);
            handle.emit(
              AgentRunEvent(
                kind: AgentRunEventKind.reasoningDelta,
                runId: handle.id,
                turnId: identity.turnId,
                turnIndex: identity.turnIndex,
                text: event.text,
              ),
            );
          case AgentModelToolCalls():
            calls = event.calls;
          case AgentModelStreamCompleted():
            done.complete();
          case AgentModelStreamFailure():
            done.completeError(event.error, event.stackTrace);
        }
      },
      onError: done.completeError,
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    final cancellation = handle.token.whenCancelled.then<void>((reason) {
      if (!done.isCompleted) {
        done.completeError(AgentCancellationException(reason));
      }
    });
    try {
      await Future.any([done.future, cancellation]);
      handle.token.throwIfCancellationRequested();
      return _TurnResult(content, reasoning, calls);
    } finally {
      try {
        await subscription.cancel().timeout(cleanupTimeout);
      } on TimeoutException {
        // A broken upstream stream must not prevent the run from terminating.
      }
    }
  }

  Future<List<AgentToolResult>> _executeTools(
    _AgentRunHandle handle,
    Future<List<AgentToolResult>> Function() execute,
  ) async {
    final cancellation = handle.token.whenCancelled.then<List<AgentToolResult>>(
      (reason) => throw AgentCancellationException(reason),
    );
    return Future.any([execute(), cancellation]);
  }

  void _validateToolResults(
    List<AgentToolInvocation> calls,
    List<AgentToolResult> results,
  ) {
    final expected = calls.map((call) => call.id).toSet();
    final actual = results.map((result) => result.invocationId).toList();
    if (actual.length != actual.toSet().length ||
        actual.length != expected.length ||
        !actual.every(expected.contains)) {
      throw StateError('Tool executor returned uncorrelated terminal results');
    }
  }

  void _validateToolCalls(List<AgentToolInvocation> calls) {
    final ids = <String>{};
    for (final call in calls) {
      if (call.id.isEmpty || call.id != call.id.trim() || !ids.add(call.id)) {
        throw FormatException('Invalid or duplicate tool invocation id');
      }
    }
  }

  bool _defaultContextOverflow(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('context_length_exceeded') ||
        message.contains('context length') ||
        message.contains('context window') ||
        message.contains('maximum context') ||
        message.contains('too many tokens');
  }
}

class _AgentRunHandle implements AgentRunHandle {
  _AgentRunHandle(this.id, {AgentCancellationToken? parentCancellationToken})
    : _cancellation = AgentCancellationSource(parent: parentCancellationToken);

  @override
  final String id;
  final AgentCancellationSource _cancellation;
  final StreamController<AgentRunEvent> _events = StreamController.broadcast(
    sync: true,
  );
  final Completer<AgentRunResult> _result = Completer();

  AgentCancellationToken get token => _cancellation.token;

  @override
  Stream<AgentRunEvent> get events => _events.stream;

  @override
  Future<AgentRunResult> get result => _result.future;

  @override
  bool get isCancelled => token.isCancellationRequested;

  @override
  void cancel() {
    _cancellation.cancel();
  }

  void emit(AgentRunEvent event) {
    if (!_events.isClosed && !isCancelled) _events.add(event);
  }

  void complete(AgentRunResult result) {
    if (_result.isCompleted) return;
    final kind = switch (result.status) {
      AgentRunStatus.completed => AgentRunEventKind.runCompleted,
      AgentRunStatus.cancelled => AgentRunEventKind.runCancelled,
      _ => AgentRunEventKind.runFailed,
    };
    if (!_events.isClosed) {
      _events.add(AgentRunEvent(kind: kind, runId: id, error: result.error));
      unawaited(_events.close());
    }
    _result.complete(result);
    _cancellation.dispose();
  }
}

class _TurnResult {
  final String content;
  final String reasoning;
  final List<AgentToolInvocation> toolCalls;

  const _TurnResult(this.content, this.reasoning, this.toolCalls);
}

class _TurnProgress {
  const _TurnProgress({required this.content, required this.reasoning});

  final _TurnTextAccumulator content;
  final _TurnTextAccumulator reasoning;
}

class _TurnTextAccumulator {
  final StringBuffer _buffer = StringBuffer();
  int? _lastTurnIndex;

  bool get isEmpty => _buffer.isEmpty;
  String get value => _buffer.toString();

  void add(int turnIndex, String text) {
    if (text.isEmpty) return;
    if (_buffer.isNotEmpty && _lastTurnIndex != turnIndex) {
      _buffer.write('\n\n');
    }
    _buffer.write(text);
    _lastTurnIndex = turnIndex;
  }
}
