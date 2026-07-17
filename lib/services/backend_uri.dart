/// Canonicalizes a backend base URI while preserving its optional path prefix.
String normalizeBackendUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '';
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return '';
  final defaultPort =
      (scheme == 'http' && uri.port == 80) ||
      (scheme == 'https' && uri.port == 443);
  var path = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (path == '/') path = '';
  return Uri(
    scheme: scheme,
    host: uri.host.toLowerCase(),
    port: defaultPort
        ? null
        : uri.hasPort
        ? uri.port
        : null,
    path: path,
  ).toString().replaceFirst(RegExp(r'/$'), '');
}

/// Returns only the canonical scheme, host, and effective non-default port.
String normalizedBackendOrigin(String value) {
  final normalized = normalizeBackendUri(value);
  if (normalized.isEmpty) return '';
  final uri = Uri.parse(normalized);
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  ).toString().replaceFirst(RegExp(r'/$'), '');
}

bool isInsecureHttpBackend(String value) {
  final normalized = normalizeBackendUri(value);
  return normalized.isNotEmpty && Uri.parse(normalized).scheme == 'http';
}

String? insecureHttpBackendWarning(String value) => isInsecureHttpBackend(value)
    ? '当前后端使用未加密 HTTP，仅可用于隔离测试；登录凭证和同步数据可能被网络中的其他设备读取，请勿用于生产或真实账号。'
    : null;
