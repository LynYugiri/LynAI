import 'mcp_host_resolver_stub.dart'
    if (dart.library.io) 'mcp_host_resolver_io.dart'
    as implementation;

typedef McpHostResolver = Future<List<String>?> Function(String host);

Future<List<String>?> resolveMcpHost(String host) =>
    implementation.resolveMcpHost(host);
