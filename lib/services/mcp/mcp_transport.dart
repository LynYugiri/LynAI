import 'dart:async';

enum McpTransportState {
  idle,
  connecting,
  connected,
  degraded,
  failed,
  disposed,
}

class McpTransportStatus {
  final McpTransportState state;
  final String? detail;

  const McpTransportStatus(this.state, [this.detail]);
}

abstract interface class McpTransport {
  Stream<Map<String, dynamic>> get messages;
  Stream<McpTransportStatus> get statuses;
  McpTransportStatus get status;

  Future<void> start();
  Future<void> send(
    Map<String, dynamic> message, {
    McpTransportCancellation? cancellation,
  });
  Future<void> dispose();
}

class McpTransportCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const McpTransportSendCancelledException();
  }
}

class McpTransportSendCancelledException implements Exception {
  const McpTransportSendCancelledException();

  @override
  String toString() => 'MCP transport send cancelled';
}

class McpTransportException implements Exception {
  final String message;

  const McpTransportException(this.message);

  @override
  String toString() => 'McpTransportException: $message';
}
