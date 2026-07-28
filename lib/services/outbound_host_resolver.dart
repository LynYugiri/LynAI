import 'outbound_host_resolver_stub.dart'
    if (dart.library.io) 'outbound_host_resolver_io.dart'
    as implementation;

typedef OutboundHostResolver = Future<List<String>?> Function(String host);

Future<List<String>?> resolveOutboundHost(String host) =>
    implementation.resolveOutboundHost(host);
