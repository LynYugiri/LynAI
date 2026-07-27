import 'dart:async';
import 'dart:collection';

import '../models/agent_runtime.dart';
import 'agent_cancellation.dart';
import 'agent_json_schema.dart';
import 'agent_tool_registry.dart';

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
  }) async {
    final calls = invocations.toList(growable: false);
    if (calls.isEmpty) return const [];
    final token = cancellationToken;
    final results = List<AgentToolResult?>.filled(calls.length, null);
    final pending = Queue<int>.from(
      List.generate(calls.length, (index) => index),
    );
    final activeKeys = <String>{};
    final completions = _AsyncQueue<_Completion>();
    var active = 0;
    var exclusiveActive = false;

    void start(int index, AgentToolRegistration registration) {
      final invocation = calls[index];
      final descriptor = registration.descriptor;
      final key = descriptor.concurrency == AgentToolConcurrency.keyed
          ? invocation.concurrencyKey
          : null;
      active++;
      if (descriptor.concurrency == AgentToolConcurrency.exclusive) {
        exclusiveActive = true;
      }
      if (key != null) activeKeys.add(key);
      unawaited(
        _executeOne(registration, invocation, token).then((result) {
          completions.add(
            _Completion(
              index: index,
              result: result,
              concurrency: descriptor.concurrency,
              key: key,
            ),
          );
        }),
      );
    }

    while (pending.isNotEmpty || active > 0) {
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
            message: 'Tool "${invocation.name}" is not present in the snapshot',
          );
          continue;
        }
        final descriptor = registration.descriptor;
        if (descriptor.concurrency == AgentToolConcurrency.exclusive) {
          if (active > 0) break;
          pending.removeFirst();
          start(index, registration);
          started = true;
          break;
        }
        if (descriptor.concurrency == AgentToolConcurrency.keyed) {
          final key = invocation.concurrencyKey;
          if (key == null || key.trim().isEmpty) {
            pending.removeFirst();
            results[index] = AgentToolResult.failure(
              invocationId: invocation.id,
              toolName: invocation.name,
              code: 'missing_concurrency_key',
              message:
                  'Keyed tool "${invocation.name}" requires a concurrency key',
            );
            continue;
          }
          if (activeKeys.contains(key)) {
            final candidate = _firstRunnableKeyedIndex(
              pending,
              calls,
              snapshot,
              activeKeys,
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
                message:
                    'Tool "${candidateInvocation.name}" is not present in the snapshot',
              );
              continue;
            }
            start(candidate, candidateRegistration);
            started = true;
            continue;
          }
        }
        pending.removeFirst();
        start(index, registration);
        started = true;
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

  int? _firstRunnableKeyedIndex(
    Queue<int> pending,
    List<AgentToolInvocation> calls,
    AgentToolSnapshot snapshot,
    Set<String> activeKeys,
  ) {
    for (final index in pending) {
      final registration = snapshot[calls[index].name];
      if (registration == null) return index;
      final concurrency = registration.descriptor.concurrency;
      if (concurrency == AgentToolConcurrency.exclusive) return null;
      if (concurrency == AgentToolConcurrency.parallelSafe) return index;
      final key = calls[index].concurrencyKey;
      if (key == null || !activeKeys.contains(key)) return index;
    }
    return null;
  }

  Future<AgentToolResult> _executeOne(
    AgentToolRegistration registration,
    AgentToolInvocation invocation,
    AgentCancellationToken? cancellationToken,
  ) async {
    try {
      cancellationToken?.throwIfCancellationRequested();
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
      final token = cancellationToken ?? AgentCancellationSource().token;
      final value = await registration.handler(invocation, token);
      token.throwIfCancellationRequested();
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
        message: error.toString(),
      );
    }
  }
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
