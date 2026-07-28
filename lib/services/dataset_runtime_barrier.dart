import 'dart:async';

import '../models/agent_runtime.dart';

/// Blocks new dataset-bound work while a physical dataset is being replaced.
final class DatasetRuntimeBarrier {
  bool _open = true;
  int _generation = 0;
  int _nextWorkId = 0;
  Completer<void>? _opened;
  final Map<int, _DatasetWork> _work = {};

  int get generation => _generation;
  bool get isOpen => _open;

  bool isCurrent(int generation) => _open && generation == _generation;

  Future<void> waitUntilOpen() =>
      _open ? Future.value() : (_opened ??= Completer<void>()).future;

  Future<T> run<T>(Future<T> Function(int generation) action) async {
    await waitUntilOpen();
    final generation = _generation;
    final id = _nextWorkId++;
    final done = Completer<void>();
    _work[id] = _DatasetWork(done.future);
    try {
      if (!isCurrent(generation)) {
        throw StateError('Physical dataset changed before work started');
      }
      final result = await action(generation);
      if (!isCurrent(generation)) {
        throw StateError('Physical dataset changed while work was running');
      }
      return result;
    } finally {
      _work.remove(id);
      done.complete();
    }
  }

  Future<T> runExisting<T>(Future<T> Function(int generation) action) async {
    if (!_open) {
      throw StateError('Physical dataset switch is in progress');
    }
    final generation = _generation;
    final id = _nextWorkId++;
    final done = Completer<void>();
    _work[id] = _DatasetWork(done.future);
    try {
      final result = await action(generation);
      if (!isCurrent(generation)) {
        throw StateError('Physical dataset changed while work was running');
      }
      return result;
    } finally {
      _work.remove(id);
      done.complete();
    }
  }

  void trackAgentRun(AgentRunHandle run) {
    if (!_open) {
      run.cancel();
      return;
    }
    final id = _nextWorkId++;
    final done = run.result.then<void>((_) {});
    _work[id] = _DatasetWork(done, cancel: run.cancel);
    unawaited(done.whenComplete(() => _work.remove(id)));
  }

  Future<void> quiesce() async {
    if (!_open) {
      await Future.wait(_work.values.map((work) => work.done));
      return;
    }
    _open = false;
    _opened = Completer<void>();
    final work = _work.values.toList(growable: false);
    for (final item in work) {
      item.cancel?.call();
    }
    await Future.wait(work.map((item) => item.done));
  }

  void reopen() {
    _generation++;
    _open = true;
    final opened = _opened;
    _opened = null;
    if (opened != null && !opened.isCompleted) opened.complete();
  }
}

final class _DatasetWork {
  const _DatasetWork(this.done, {this.cancel});

  final Future<void> done;
  final void Function()? cancel;
}
