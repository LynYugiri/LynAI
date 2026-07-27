import '../../models/mcp_config.dart';
import 'mcp_process.dart';
import 'mcp_stdio_transport_stub.dart'
    if (dart.library.io) 'mcp_stdio_transport_io.dart'
    as implementation;
import 'mcp_transport.dart';
import 'mcp_transport_secrets.dart';

McpTransport createMcpStdioTransport({
  required McpServerConfig config,
  required McpStdioEnvironment environment,
  McpProcessStarter? processStarter,
}) {
  return implementation.createMcpStdioTransport(
    config: config,
    environment: environment,
    processStarter: processStarter,
  );
}
