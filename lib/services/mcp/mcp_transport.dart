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
  Future<void> send(Map<String, dynamic> message);
  Future<void> dispose();
}

class McpTransportException implements Exception {
  final String message;

  const McpTransportException(this.message);

  @override
  String toString() => 'McpTransportException: $message';
}
