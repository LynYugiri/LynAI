class McpHttpCredentials {
  final Map<String, String> headers;

  McpHttpCredentials({Map<String, String> headers = const {}})
    : headers = Map.unmodifiable(headers);
}

class McpStdioEnvironment {
  final Map<String, String> variables;

  McpStdioEnvironment({required Map<String, String> variables})
    : variables = Map.unmodifiable(variables);
}
