import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/agent_persistence.dart';
import '../../models/mcp_config.dart';
import '../../repositories/mcp_repository.dart';
import 'mcp_client.dart';
import 'mcp_http_transport.dart';
import 'mcp_stdio_transport.dart';
import 'mcp_transport_secrets.dart';

abstract interface class McpConnectionFactory {
  bool get supportsStdio;

  Future<McpClient> create(
    AgentMcpServerRecord server,
    McpServerPreferences preferences,
    Map<String, String> credentials,
  );
}

class DefaultMcpConnectionFactory implements McpConnectionFactory {
  const DefaultMcpConnectionFactory();

  @override
  bool get supportsStdio =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  @override
  Future<McpClient> create(
    AgentMcpServerRecord server,
    McpServerPreferences preferences,
    Map<String, String> credentials,
  ) async {
    switch (server.transport) {
      case 'http':
      case 'streamableHttp':
        final config = McpServerConfig.streamableHttp(
          id: server.id,
          displayName: server.name,
          endpoint: Uri.parse(server.url!),
          allowHttp: preferences.allowHttp,
          allowPrivateNetwork: preferences.allowPrivateNetwork,
        );
        return McpClient(
          transport: McpHttpTransport(
            config: config,
            credentials: McpHttpCredentials(headers: credentials),
            client: http.Client(),
            closeClient: true,
          ),
          requestTimeout: config.requestTimeout,
        );
      case 'stdio':
        if (!supportsStdio) {
          throw UnsupportedError(
            'MCP stdio is only available on Linux, macOS, and Windows',
          );
        }
        final config = McpServerConfig.stdio(
          id: server.id,
          displayName: server.name,
          command: server.command!,
          arguments: server.arguments,
        );
        return McpClient(
          transport: createMcpStdioTransport(
            config: config,
            environment: McpStdioEnvironment(variables: credentials),
          ),
          requestTimeout: config.requestTimeout,
        );
      default:
        throw ArgumentError.value(
          server.transport,
          'server.transport',
          'unsupported MCP transport',
        );
    }
  }
}
