import '../../models/mcp_config.dart';
import 'mcp_process.dart';
import 'mcp_transport.dart';
import 'mcp_transport_secrets.dart';

McpTransport createMcpStdioTransport({
  required McpServerConfig config,
  required McpStdioEnvironment environment,
  McpProcessStarter? processStarter,
}) => _UnsupportedMcpStdioTransport();

class _UnsupportedMcpStdioTransport implements McpTransport {
  static const _error = McpTransportException(
    'MCP stdio is only supported on Linux, macOS, and Windows',
  );

  @override
  Stream<Map<String, dynamic>> get messages => const Stream.empty();

  @override
  Stream<McpTransportStatus> get statuses => const Stream.empty();

  @override
  McpTransportStatus get status => const McpTransportStatus(
    McpTransportState.failed,
    'Unsupported platform',
  );

  @override
  Future<void> start() => Future.error(_error);

  @override
  Future<void> send(
    Map<String, dynamic> message, {
    McpTransportCancellation? cancellation,
  }) => Future.error(_error);

  @override
  Future<void> dispose() async {}
}
