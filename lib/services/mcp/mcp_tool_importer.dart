import '../../models/agent_runtime.dart';
import '../agent_json_schema.dart';
import '../agent_tool_name_codec.dart';
import 'mcp_protocol.dart';

final AgentToolNameCodec mcpToolNameCodec = AgentToolNameCodec();

String canonicalMcpToolName(String serverId, String toolName) =>
    mcpToolNameCodec.encode(
      source: AgentToolSource.mcp,
      namespace: serverId,
      name: toolName,
    );

class McpToolSchemaImporter {
  final AgentJsonSchemaValidator _validator;

  const McpToolSchemaImporter({
    AgentJsonSchemaValidator validator = const AgentJsonSchemaValidator(),
  }) : _validator = validator;

  Map<String, dynamic> import(McpTool tool) {
    final validation = _validator.validateSchema(tool.inputSchema);
    if (!validation.isValid) {
      throw McpToolSchemaException(tool.name, validation.issues);
    }
    return tool.inputSchema;
  }
}

class McpToolSchemaException implements Exception {
  final String toolName;
  final List<AgentJsonSchemaIssue> issues;

  McpToolSchemaException(this.toolName, Iterable<AgentJsonSchemaIssue> issues)
    : issues = List.unmodifiable(issues);

  @override
  String toString() =>
      'MCP tool "$toolName" has an incompatible input schema: '
      '${issues.join('; ')}';
}
