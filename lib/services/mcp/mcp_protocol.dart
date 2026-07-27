import 'dart:convert';

const mcpProtocolVersion = '2025-06-18';

class McpProtocolException implements Exception {
  final String message;

  const McpProtocolException(this.message);

  @override
  String toString() => 'McpProtocolException: $message';
}

class McpRpcException implements Exception {
  final int code;
  final String message;
  final Object? data;

  const McpRpcException(this.code, this.message, [this.data]);

  @override
  String toString() => 'McpRpcException($code): $message';
}

Map<String, dynamic> decodeMcpMessage(List<int> bytes, int maxMessageBytes) {
  if (bytes.length > maxMessageBytes) {
    throw McpProtocolException('MCP message exceeds $maxMessageBytes bytes');
  }
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map) {
    throw const McpProtocolException('MCP message must be a JSON object');
  }
  final message = Map<String, dynamic>.from(decoded);
  if (message['jsonrpc'] != '2.0') {
    throw const McpProtocolException('MCP message must use JSON-RPC 2.0');
  }
  return message;
}

List<int> encodeMcpMessage(Map<String, dynamic> message, int maxMessageBytes) {
  final bytes = utf8.encode(jsonEncode(message));
  if (bytes.length > maxMessageBytes) {
    throw McpProtocolException('MCP message exceeds $maxMessageBytes bytes');
  }
  return bytes;
}

class McpTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  McpTool({
    required this.name,
    required this.description,
    required Map<String, dynamic> inputSchema,
  }) : inputSchema = Map.unmodifiable(inputSchema) {
    if (name.trim().isEmpty) {
      throw const McpProtocolException('MCP tool name must not be empty');
    }
  }

  factory McpTool.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final schema = json['inputSchema'];
    if (name is! String || schema is! Map) {
      throw const McpProtocolException('Invalid MCP tool descriptor');
    }
    return McpTool(
      name: name,
      description: json['description'] is String
          ? json['description'] as String
          : '',
      inputSchema: Map<String, dynamic>.from(schema),
    );
  }
}

class McpCallToolResult {
  final List<Object?> content;
  final Object? structuredContent;
  final bool isError;

  McpCallToolResult({
    required Iterable<Object?> content,
    this.structuredContent,
    required this.isError,
  }) : content = List.unmodifiable(content);

  factory McpCallToolResult.fromJson(Map<String, dynamic> json) {
    final content = json['content'];
    if (content is! List) {
      throw const McpProtocolException(
        'tools/call result content must be an array',
      );
    }
    return McpCallToolResult(
      content: content,
      structuredContent: json['structuredContent'],
      isError: json['isError'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'content': content,
    if (structuredContent != null) 'structuredContent': structuredContent,
    'isError': isError,
  };
}
