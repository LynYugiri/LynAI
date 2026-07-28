import '../outbound_host_resolver.dart';

typedef McpHostResolver = Future<List<String>?> Function(String host);

Future<List<String>?> resolveMcpHost(String host) => resolveOutboundHost(host);
