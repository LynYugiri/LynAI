import 'outbound_host_resolver.dart';

enum OutboundNetworkRejection {
  credentialsInUrl,
  unsupportedScheme,
  privateHost,
  unresolvedHost,
  nonPublicAddress,
}

class OutboundConnectionTarget {
  const OutboundConnectionTarget({required this.uri, this.address});

  final Uri uri;
  final String? address;
}

class OutboundNetworkPolicyException implements Exception {
  const OutboundNetworkPolicyException(this.rejection);

  final OutboundNetworkRejection rejection;

  @override
  String toString() => 'Outbound network request rejected: ${rejection.name}';
}

/// Validates outbound HTTP destinations immediately before connecting.
///
/// HTTPS and public DNS are required by default. Callers may explicitly allow
/// HTTP or private networks only for trusted, user-owned configuration.
class OutboundNetworkPolicy {
  const OutboundNetworkPolicy({
    this.allowedHttpOrigins = const {},
    this.allowPrivateNetwork = false,
    this.hostResolver = resolveOutboundHost,
  });

  final Set<String> allowedHttpOrigins;
  final bool allowPrivateNetwork;
  final OutboundHostResolver hostResolver;

  Future<OutboundConnectionTarget> resolve(Uri uri) async {
    if (uri.userInfo.isNotEmpty) {
      throw const OutboundNetworkPolicyException(
        OutboundNetworkRejection.credentialsInUrl,
      );
    }
    if (uri.host.isEmpty ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                allowedHttpOrigins.contains(outboundOrigin(uri))))) {
      throw const OutboundNetworkPolicyException(
        OutboundNetworkRejection.unsupportedScheme,
      );
    }
    if (!allowPrivateNetwork && isClearlyNonPublicHost(uri.host)) {
      throw const OutboundNetworkPolicyException(
        OutboundNetworkRejection.privateHost,
      );
    }
    final addresses = await hostResolver(uri.host);
    if (addresses == null || addresses.isEmpty) {
      throw const OutboundNetworkPolicyException(
        OutboundNetworkRejection.unresolvedHost,
      );
    }
    if (!allowPrivateNetwork && addresses.any(isNonPublicAddress)) {
      throw const OutboundNetworkPolicyException(
        OutboundNetworkRejection.nonPublicAddress,
      );
    }
    return OutboundConnectionTarget(uri: uri, address: addresses.first);
  }

  Future<void> validate(Uri uri) async {
    await resolve(uri);
  }
}

String outboundOrigin(Uri uri) {
  final defaultPort = uri.scheme == 'https' ? 443 : 80;
  final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';
  return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}$port';
}

bool isClearlyNonPublicHost(String host) {
  final value = host.toLowerCase();
  if (value == 'localhost' ||
      value.endsWith('.localhost') ||
      value.endsWith('.local')) {
    return true;
  }
  return isNonPublicAddress(value);
}

/// Preserves the legacy MCP literal-host check while sharing DNS classification.
bool isPrivateNetworkHost(String host) {
  final value = host.toLowerCase();
  if (value == 'localhost' ||
      value == '::1' ||
      value.startsWith('fc') ||
      value.startsWith('fd') ||
      value.startsWith('fe8') ||
      value.startsWith('fe9') ||
      value.startsWith('fea') ||
      value.startsWith('feb') ||
      value.endsWith('.local')) {
    return true;
  }
  final ipv4 = _parseIpv4(value);
  if (ipv4 == null) return false;
  final first = ipv4[0];
  final second = ipv4[1];
  return first == 10 ||
      first == 127 ||
      (first == 169 && second == 254) ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168);
}

bool isNonPublicAddress(String value) {
  final ipv4 = _parseIpv4(value);
  if (ipv4 != null) {
    final first = ipv4[0];
    final second = ipv4[1];
    final third = ipv4[2];
    return first == 0 ||
        first == 10 ||
        first == 127 ||
        (first == 100 && second >= 64 && second <= 127) ||
        (first == 169 && second == 254) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 0 && third == 0) ||
        (first == 192 && second == 0 && third == 2) ||
        (first == 192 && second == 168) ||
        (first == 198 && (second == 18 || second == 19)) ||
        (first == 198 && second == 51 && third == 100) ||
        (first == 203 && second == 0 && third == 113) ||
        first >= 224;
  }
  final normalized = value.toLowerCase();
  if (!normalized.contains(':')) return false;
  if (normalized == '::' || normalized == '::1') return true;
  if (normalized.startsWith('::ffff:')) {
    return isNonPublicAddress(normalized.substring(7));
  }
  final firstGroup = int.tryParse(normalized.split(':').first, radix: 16);
  if (firstGroup == null) return true;
  return (firstGroup & 0xfe00) == 0xfc00 ||
      (firstGroup & 0xffc0) == 0xfe80 ||
      (firstGroup & 0xff00) == 0xff00 ||
      normalized.startsWith('2001:db8:');
}

List<int>? _parseIpv4(String value) {
  final parts = value.split('.');
  if (parts.length != 4) return null;
  final bytes = <int>[];
  for (final part in parts) {
    final byte = int.tryParse(part);
    if (byte == null || byte < 0 || byte > 255) return null;
    bytes.add(byte);
  }
  return bytes;
}
