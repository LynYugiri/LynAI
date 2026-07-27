import 'dart:async';

import '../models/agent_runtime.dart';

class AgentCancellationReason {
  final String code;
  final String message;
  final Object? cause;

  const AgentCancellationReason({
    required this.code,
    required this.message,
    this.cause,
  });

  static const requested = AgentCancellationReason(
    code: 'cancelled',
    message: 'Operation cancelled',
  );

  @override
  String toString() => '$code: $message';
}

class AgentCancellationException implements Exception {
  final AgentCancellationReason reason;

  const AgentCancellationException(this.reason);

  @override
  String toString() => 'AgentCancellationException(${reason.toString()})';
}

class AgentCancellationToken implements AgentRunCancellation {
  final Future<AgentCancellationReason> _cancelled;
  final AgentCancellationReason? Function() _reason;

  const AgentCancellationToken._(this._cancelled, this._reason);

  @override
  bool get isCancellationRequested => _reason() != null;

  AgentCancellationReason? get reason => _reason();

  Future<AgentCancellationReason> get whenCancelled => _cancelled;

  @override
  void throwIfCancellationRequested() {
    final cancellation = reason;
    if (cancellation != null) {
      throw AgentCancellationException(cancellation);
    }
  }
}

class AgentCancellationSource {
  final Completer<AgentCancellationReason> _completer = Completer();
  late final AgentCancellationToken token = AgentCancellationToken._(
    _completer.future,
    () => _reason,
  );
  AgentCancellationReason? _reason;
  bool _disposed = false;

  AgentCancellationSource({AgentCancellationToken? parent}) {
    if (parent == null) return;
    final parentReason = parent.reason;
    if (parentReason != null) {
      cancel(parentReason);
      return;
    }
    parent.whenCancelled.then((reason) {
      if (!_disposed) cancel(reason);
    });
  }

  bool cancel([
    AgentCancellationReason reason = AgentCancellationReason.requested,
  ]) {
    if (_reason != null) return false;
    _reason = reason;
    _completer.complete(reason);
    return true;
  }

  AgentCancellationSource createChild() {
    return AgentCancellationSource(parent: token);
  }

  void dispose() {
    _disposed = true;
  }
}
