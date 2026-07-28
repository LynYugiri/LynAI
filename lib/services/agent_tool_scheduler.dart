import 'dart:async';
import 'dart:collection';

import '../models/agent_runtime.dart';
import 'agent_cancellation.dart';
import 'agent_json_schema.dart';
import 'agent_tool_registry.dart';
import 'lynai_permission_definitions.dart';

class AgentToolScheduler {
  final int maxConcurrency;
  final AgentJsonSchemaValidator _schemaValidator;

  AgentToolScheduler({
    this.maxConcurrency = 4,
    AgentJsonSchemaValidator schemaValidator = const AgentJsonSchemaValidator(),
  }) : _schemaValidator = schemaValidator {
    if (maxConcurrency < 1) {
      throw ArgumentError.value(
        maxConcurrency,
        'maxConcurrency',
        'must be positive',
      );
    }
  }

  Future<List<AgentToolResult>> execute(
    AgentToolSnapshot snapshot,
    Iterable<AgentToolInvocation> invocations, {
    AgentCancellationToken? cancellationToken,
  }) {
    final source = cancellationToken == null ? AgentCancellationSource() : null;
    final future = executeCaptured(
      snapshot: snapshot,
      invocations: invocations,
      turnIdentity: const AgentTurnIdentity(
        runId: 'legacy',
        turnId: 'legacy',
        turnIndex: 0,
      ),
      permissionSnapshot: AgentPermissionSnapshot(permissions: const []),
      cancellationToken: cancellationToken ?? source!.token,
      authorizer: (registration, context) => true,
      errorSanitizer: (error) => error.toString(),
    );
    return source == null ? future : future.whenComplete(source.dispose);
  }

  Future<List<AgentToolResult>> executeCaptured({
    required AgentToolSnapshot snapshot,
    required Iterable<AgentToolInvocation> invocations,
    required AgentTurnIdentity turnIdentity,
    required AgentPermissionSnapshot permissionSnapshot,
    required AgentCancellationToken cancellationToken,
    required AgentToolAuthorizer authorizer,
    required AgentToolErrorSanitizer errorSanitizer,
    String? conversationId,
    DateTime? deadline,
  }) async {
    final calls = invocations.toList(growable: false);
    if (calls.isEmpty) return const [];
    final results = List<AgentToolResult?>.filled(calls.length, null);
    final pending = Queue<int>.from(
      List.generate(calls.length, (index) => index),
    );
    final activeKeys = <String>{};
    final keys = <int, String?>{};
    final completions = _AsyncQueue<_Completion>();
    var active = 0;
    var exclusiveActive = false;

    String? deriveKey(int index, AgentToolRegistration registration) {
      if (registration.descriptor.concurrency != AgentToolConcurrency.keyed) {
        return null;
      }
      if (keys.containsKey(index)) return keys[index];
      final invocation = calls[index];
      final identity = AgentToolExecutionIdentity(
        runId: turnIdentity.runId,
        turnId: turnIdentity.turnId,
        turnIndex: turnIdentity.turnIndex,
        invocationId: invocation.id,
        toolName: invocation.name,
        conversationId: conversationId,
      );
      final value = registration.concurrencyKeyResolver!(invocation, identity);
      final key = value.trim();
      if (key.isEmpty) {
        throw StateError('Concurrency key resolver returned an empty key');
      }
      keys[index] = key;
      return key;
    }

    void start(int index, AgentToolRegistration registration, String? key) {
      final invocation = calls[index];
      final concurrency = registration.descriptor.concurrency;
      active++;
      if (concurrency == AgentToolConcurrency.exclusive) exclusiveActive = true;
      if (key != null) activeKeys.add(key);
      unawaited(
        _executeOne(
          snapshot: snapshot,
          registration: registration,
          invocation: invocation,
          turnIdentity: turnIdentity,
          permissionSnapshot: permissionSnapshot,
          cancellationToken: cancellationToken,
          authorizer: authorizer,
          errorSanitizer: errorSanitizer,
          conversationId: conversationId,
          batchDeadline: deadline,
        ).then(
          (result) => completions.add(
            _Completion(
              index: index,
              result: result,
              concurrency: concurrency,
              key: key,
            ),
          ),
        ),
      );
    }

    while (pending.isNotEmpty || active > 0) {
      if (cancellationToken.isCancellationRequested) {
        while (pending.isNotEmpty) {
          final index = pending.removeFirst();
          final call = calls[index];
          results[index] = AgentToolResult.cancelled(
            invocationId: call.id,
            toolName: call.name,
            message: cancellationToken.reason?.message ?? 'Operation cancelled',
          );
        }
      }
      var started = false;
      while (active < maxConcurrency &&
          !exclusiveActive &&
          pending.isNotEmpty) {
        final index = pending.first;
        final invocation = calls[index];
        final registration = snapshot[invocation.name];
        if (registration == null) {
          pending.removeFirst();
          results[index] = AgentToolResult.failure(
            invocationId: invocation.id,
            toolName: invocation.name,
            code: 'tool_not_found',
            message: 'Tool is not present in the captured snapshot',
          );
          continue;
        }
        final concurrency = registration.descriptor.concurrency;
        if (concurrency == AgentToolConcurrency.exclusive && active > 0) break;
        String? key;
        try {
          key = deriveKey(index, registration);
        } catch (error) {
          pending.removeFirst();
          results[index] = AgentToolResult.failure(
            invocationId: invocation.id,
            toolName: invocation.name,
            code: 'concurrency_key_failed',
            message: errorSanitizer(error),
          );
          continue;
        }
        if (key != null && activeKeys.contains(key)) {
          final candidate = _firstRunnableIndex(
            pending,
            calls,
            snapshot,
            activeKeys,
            deriveKey,
          );
          if (candidate == null) break;
          pending.remove(candidate);
          final candidateInvocation = calls[candidate];
          final candidateRegistration = snapshot[candidateInvocation.name];
          if (candidateRegistration == null) {
            results[candidate] = AgentToolResult.failure(
              invocationId: candidateInvocation.id,
              toolName: candidateInvocation.name,
              code: 'tool_not_found',
              message: 'Tool is not present in the captured snapshot',
            );
            continue;
          }
          start(candidate, candidateRegistration, keys[candidate]);
          started = true;
          continue;
        }
        pending.removeFirst();
        start(index, registration, key);
        started = true;
        if (concurrency == AgentToolConcurrency.exclusive) break;
      }
      if (active == 0) {
        if (!started && pending.isNotEmpty) continue;
        break;
      }
      final completion = await completions.removeFirst();
      results[completion.index] = completion.result;
      active--;
      if (completion.concurrency == AgentToolConcurrency.exclusive) {
        exclusiveActive = false;
      }
      if (completion.key != null) activeKeys.remove(completion.key);
    }
    return results.cast<AgentToolResult>();
  }

  int? _firstRunnableIndex(
    Queue<int> pending,
    List<AgentToolInvocation> calls,
    AgentToolSnapshot snapshot,
    Set<String> activeKeys,
    String? Function(int, AgentToolRegistration) deriveKey,
  ) {
    for (final index in pending) {
      final registration = snapshot[calls[index].name];
      if (registration == null) return index;
      final concurrency = registration.descriptor.concurrency;
      if (concurrency == AgentToolConcurrency.exclusive) return null;
      if (concurrency == AgentToolConcurrency.parallelSafe) return index;
      try {
        final key = deriveKey(index, registration);
        if (key == null || !activeKeys.contains(key)) return index;
      } catch (_) {
        return index;
      }
    }
    return null;
  }

  Future<AgentToolResult> _executeOne({
    required AgentToolSnapshot snapshot,
    required AgentToolRegistration registration,
    required AgentToolInvocation invocation,
    required AgentTurnIdentity turnIdentity,
    required AgentPermissionSnapshot permissionSnapshot,
    required AgentCancellationToken cancellationToken,
    required AgentToolAuthorizer authorizer,
    required AgentToolErrorSanitizer errorSanitizer,
    required String? conversationId,
    required DateTime? batchDeadline,
  }) async {
    final now = DateTime.now();
    final toolDeadline = now.add(registration.spec.semantics.timeout);
    final deadline =
        batchDeadline != null && batchDeadline.isBefore(toolDeadline)
        ? batchDeadline
        : toolDeadline;
    final identity = AgentToolExecutionIdentity(
      runId: turnIdentity.runId,
      turnId: turnIdentity.turnId,
      turnIndex: turnIdentity.turnIndex,
      invocationId: invocation.id,
      toolName: invocation.name,
      conversationId: conversationId,
    );
    final context = AgentToolExecutionContext(
      identity: identity,
      permissionSnapshot: permissionSnapshot,
      cancellationToken: cancellationToken,
      snapshot: snapshot,
      deadline: deadline,
    );
    try {
      cancellationToken.throwIfCancellationRequested();
      if (!deadline.isAfter(DateTime.now())) {
        return _deadlineResult(invocation);
      }
      final validation = _schemaValidator.validate(
        invocation.arguments,
        registration.descriptor.parameters,
      );
      if (!validation.isValid) {
        return AgentToolResult.failure(
          invocationId: invocation.id,
          toolName: invocation.name,
          code: 'invalid_arguments',
          message: validation.issues.join('; '),
        );
      }
      cancellationToken.throwIfCancellationRequested();
      if (!await authorizer(registration, context)) {
        return AgentToolResult.failure(
          invocationId: invocation.id,
          toolName: invocation.name,
          code: 'permission_denied',
          message: 'Tool execution is not authorized',
        );
      }
      cancellationToken.throwIfCancellationRequested();
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) return _deadlineResult(invocation);
      final handler = registration
          .handler(invocation, context)
          .then(
            _HandlerOutcome.value,
            onError: (Object error, StackTrace stackTrace) =>
                _HandlerOutcome.error(error),
          );
      final cancellation = cancellationToken.whenCancelled.then(
        _HandlerOutcome.cancelled,
      );
      final timeoutCompleter = Completer<_HandlerOutcome>();
      final timeoutTimer = Timer(
        remaining,
        () => timeoutCompleter.complete(_HandlerOutcome.timedOut()),
      );
      late final _HandlerOutcome outcome;
      try {
        outcome = await Future.any([
          handler,
          cancellation,
          timeoutCompleter.future,
        ]);
      } finally {
        timeoutTimer.cancel();
      }
      if (outcome.cancellation != null) {
        return AgentToolResult.cancelled(
          invocationId: invocation.id,
          toolName: invocation.name,
          message: outcome.cancellation!.message,
        );
      }
      if (outcome.timedOut) return _deadlineResult(invocation);
      if (outcome.error != null) {
        return AgentToolResult.failure(
          invocationId: invocation.id,
          toolName: invocation.name,
          code: 'tool_execution_failed',
          message: errorSanitizer(outcome.error!),
        );
      }
      final value = switch (registration.spec.semantics.resultPolicy) {
        AgentToolResultPolicy.returnValue => outcome.value,
        AgentToolResultPolicy.redactValue => const {'redacted': true},
        AgentToolResultPolicy.discardValue => null,
      };
      return AgentToolResult.success(
        invocationId: invocation.id,
        toolName: invocation.name,
        value: value,
      );
    } on AgentCancellationException catch (error) {
      return AgentToolResult.cancelled(
        invocationId: invocation.id,
        toolName: invocation.name,
        message: error.reason.message,
      );
    } catch (error) {
      return AgentToolResult.failure(
        invocationId: invocation.id,
        toolName: invocation.name,
        code: 'tool_execution_failed',
        message: errorSanitizer(error),
      );
    }
  }

  AgentToolResult _deadlineResult(AgentToolInvocation invocation) =>
      AgentToolResult.failure(
        invocationId: invocation.id,
        toolName: invocation.name,
        code: 'deadline_exceeded',
        message: 'Tool execution deadline exceeded',
      );
}

class _HandlerOutcome {
  final Object? value;
  final Object? error;
  final AgentCancellationReason? cancellation;
  final bool timedOut;

  const _HandlerOutcome._({
    this.value,
    this.error,
    this.cancellation,
    this.timedOut = false,
  });

  factory _HandlerOutcome.value(Object? value) =>
      _HandlerOutcome._(value: value);
  factory _HandlerOutcome.error(Object error) =>
      _HandlerOutcome._(error: error);
  factory _HandlerOutcome.cancelled(AgentCancellationReason reason) =>
      _HandlerOutcome._(cancellation: reason);
  factory _HandlerOutcome.timedOut() => const _HandlerOutcome._(timedOut: true);
}

class _Completion {
  final int index;
  final AgentToolResult result;
  final AgentToolConcurrency concurrency;
  final String? key;

  const _Completion({
    required this.index,
    required this.result,
    required this.concurrency,
    required this.key,
  });
}

class _AsyncQueue<T> {
  final Queue<T> _values = Queue();
  final Queue<Completer<T>> _waiters = Queue();

  void add(T value) {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete(value);
    } else {
      _values.addLast(value);
    }
  }

  Future<T> removeFirst() {
    if (_values.isNotEmpty) return Future.value(_values.removeFirst());
    final waiter = Completer<T>();
    _waiters.addLast(waiter);
    return waiter.future;
  }
}
