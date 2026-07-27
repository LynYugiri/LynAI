import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../models/mcp_config.dart';
import 'mcp_host_resolver.dart';
import 'mcp_protocol.dart';
import 'mcp_transport.dart';
import 'mcp_transport_secrets.dart';

class McpHttpTransport implements McpTransport {
  final McpServerConfig config;
  final McpHttpCredentials credentials;
  final http.Client _client;
  final bool _closeClient;
  final McpHostResolver _hostResolver;
  final StreamController<Map<String, dynamic>> _messages =
      StreamController.broadcast();
  final StreamController<McpTransportStatus> _statuses =
      StreamController.broadcast();
  McpTransportStatus _status = const McpTransportStatus(McpTransportState.idle);
  String? _sessionId;
  Future<void>? _sseTask;
  bool _disposed = false;

  McpHttpTransport({
    required this.config,
    required this.credentials,
    required http.Client client,
    bool closeClient = false,
    McpHostResolver hostResolver = resolveMcpHost,
  }) : _client = client,
       _closeClient = closeClient,
       _hostResolver = hostResolver {
    if (config.transport != McpTransportKind.streamableHttp) {
      throw ArgumentError('HTTP transport requires a streamable HTTP config');
    }
  }

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  @override
  Stream<McpTransportStatus> get statuses => _statuses.stream;

  @override
  McpTransportStatus get status => _status;

  @override
  Future<void> start() async {
    if (_status.state != McpTransportState.idle) return;
    _setStatus(McpTransportState.connected);
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (_disposed) {
      throw const McpTransportException('HTTP transport is disposed');
    }
    final body = encodeMcpMessage(message, config.maxMessageBytes);
    final response = await _sendWithRedirects(
      'POST',
      config.endpoint!,
      body: body,
    );
    _captureSession(response);
    if (response.statusCode == 202 || response.statusCode == 204) {
      await response.stream.drain<void>();
      _startSseIfAvailable();
      return;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBody = await _readBounded(
        response.stream,
        config.maxResponseBytes,
      );
      throw McpTransportException(
        'MCP HTTP request failed with ${response.statusCode}: ${utf8.decode(errorBody, allowMalformed: true)}',
      );
    }
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.contains('text/event-stream')) {
      await _readSse(response.stream, maxTotalBytes: config.maxResponseBytes);
    } else {
      final bytes = await _readBounded(
        response.stream,
        config.maxResponseBytes,
      );
      if (bytes.isNotEmpty) {
        _messages.add(decodeMcpMessage(bytes, config.maxMessageBytes));
      }
    }
    _startSseIfAvailable();
  }

  void _captureSession(http.StreamedResponse response) {
    final session = response.headers['mcp-session-id'];
    if (session != null && session.isNotEmpty) _sessionId = session;
  }

  void _startSseIfAvailable() {
    if (!config.enableSseNotifications ||
        _sessionId == null ||
        _sseTask != null ||
        _disposed) {
      return;
    }
    _sseTask = _listenForNotifications();
  }

  Future<void> _listenForNotifications() async {
    try {
      final response = await _sendWithRedirects('GET', config.endpoint!);
      if (response.statusCode == 405 || response.statusCode == 404) {
        await response.stream.drain<void>();
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.drain<void>();
        _setStatus(
          McpTransportState.degraded,
          'SSE notifications returned ${response.statusCode}',
        );
        return;
      }
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (!contentType.contains('text/event-stream')) {
        await response.stream.drain<void>();
        _setStatus(
          McpTransportState.degraded,
          'SSE notification response has the wrong content type',
        );
        return;
      }
      await _readSse(response.stream);
    } catch (error, stackTrace) {
      if (_disposed) return;
      _setStatus(McpTransportState.degraded, error.toString());
      _messages.addError(error, stackTrace);
    }
  }

  Future<http.StreamedResponse> _sendWithRedirects(
    String method,
    Uri initialUri, {
    List<int>? body,
  }) async {
    var uri = initialUri;
    var includeSensitiveHeaders = true;
    for (var redirect = 0; redirect <= 3; redirect++) {
      await _validateUri(uri);
      final request = http.Request(method, uri)
        ..followRedirects = false
        ..headers['Accept'] = 'application/json, text/event-stream'
        ..headers['MCP-Protocol-Version'] = mcpProtocolVersion;
      if (includeSensitiveHeaders) {
        if (_sessionId != null) request.headers['MCP-Session-Id'] = _sessionId!;
        request.headers.addAll(credentials.headers);
      }
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.bodyBytes = body;
      }
      final response = await _client
          .send(request)
          .timeout(config.requestTimeout);
      if (!_isRedirect(response.statusCode)) return response;
      final location = response.headers['location'];
      await response.stream.drain<void>();
      if (location == null || redirect == 3) {
        throw const McpTransportException(
          'MCP HTTP redirect is invalid or exceeds the limit',
        );
      }
      if (method == 'POST' &&
          response.statusCode != 307 &&
          response.statusCode != 308) {
        throw McpTransportException(
          'MCP POST redirect must preserve the method (${response.statusCode})',
        );
      }
      uri = uri.resolve(location);
      includeSensitiveHeaders = false;
    }
    throw const McpTransportException('MCP HTTP redirect exceeds the limit');
  }

  /// Revalidates DNS immediately before each request and redirect. The current
  /// http.Client API cannot pin the validated address, so a DNS TOCTOU window
  /// remains between this lookup and the client's socket connection.
  Future<void> _validateUri(Uri uri) async {
    if (uri.userInfo.isNotEmpty) {
      throw const McpTransportException(
        'MCP endpoint must not contain URL credentials',
      );
    }
    if (uri.scheme != 'https' && !(config.allowHttp && uri.scheme == 'http')) {
      throw const McpTransportException('MCP endpoint must use HTTPS');
    }
    if (!config.allowPrivateNetwork) {
      if (_privateHost(uri.host)) {
        throw const McpTransportException(
          'MCP private endpoint is not allowed',
        );
      }
      final addresses = await _hostResolver(uri.host);
      if (addresses != null && addresses.isEmpty) {
        throw const McpTransportException('MCP endpoint did not resolve');
      }
      if (addresses?.any(_nonPublicAddress) ?? false) {
        throw const McpTransportException(
          'MCP endpoint resolves to a non-public address',
        );
      }
    }
  }

  Future<void> _readSse(Stream<List<int>> stream, {int? maxTotalBytes}) async {
    final buffer = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in stream) {
      total += chunk.length;
      if (maxTotalBytes != null && total > maxTotalBytes) {
        throw McpTransportException(
          'MCP HTTP response exceeds $maxTotalBytes bytes',
        );
      }
      buffer.add(chunk);
      var bytes = buffer.takeBytes();
      var boundary = _eventBoundary(bytes);
      while (boundary >= 0) {
        final event = Uint8List.sublistView(bytes, 0, boundary);
        _emitSseEvent(event);
        final separatorLength = bytes[boundary] == 13 ? 4 : 2;
        bytes = Uint8List.sublistView(bytes, boundary + separatorLength);
        boundary = _eventBoundary(bytes);
      }
      if (bytes.length > config.maxMessageBytes) {
        throw McpTransportException(
          'MCP SSE event exceeds ${config.maxMessageBytes} bytes',
        );
      }
      buffer.add(bytes);
    }
    final remaining = buffer.takeBytes();
    if (remaining.isNotEmpty) _emitSseEvent(remaining);
  }

  void _emitSseEvent(List<int> bytes) {
    if (_disposed) return;
    final lines = utf8.decode(bytes).split(RegExp(r'\r?\n'));
    final data = lines
        .where((line) => line.startsWith('data:'))
        .map((line) => line.substring(5).trimLeft())
        .join('\n');
    if (data.isEmpty) return;
    _messages.add(decodeMcpMessage(utf8.encode(data), config.maxMessageBytes));
  }

  int _eventBoundary(Uint8List bytes) {
    for (var index = 0; index < bytes.length - 1; index++) {
      if (bytes[index] == 10 && bytes[index + 1] == 10) return index;
      if (index < bytes.length - 3 &&
          bytes[index] == 13 &&
          bytes[index + 1] == 10 &&
          bytes[index + 2] == 13 &&
          bytes[index + 3] == 10) {
        return index;
      }
    }
    return -1;
  }

  Future<List<int>> _readBounded(Stream<List<int>> stream, int limit) async {
    final bytes = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in stream) {
      total += chunk.length;
      if (total > limit) {
        throw McpTransportException('MCP HTTP response exceeds $limit bytes');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  void _setStatus(McpTransportState state, [String? detail]) {
    _status = McpTransportStatus(state, detail);
    _statuses.add(_status);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_sessionId != null) {
      try {
        final response = await _sendWithRedirects('DELETE', config.endpoint!);
        await response.stream.drain<void>();
      } catch (_) {}
    }
    if (_closeClient) _client.close();
    _setStatus(McpTransportState.disposed);
    await _messages.close();
    await _statuses.close();
  }
}

bool _isRedirect(int status) =>
    status == 301 ||
    status == 302 ||
    status == 303 ||
    status == 307 ||
    status == 308;

bool _privateHost(String host) {
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
  final parts = value.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((part) => part == null)) return false;
  final first = parts[0]!;
  final second = parts[1]!;
  return first == 10 ||
      first == 127 ||
      (first == 169 && second == 254) ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168);
}

bool _nonPublicAddress(String value) {
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
  if (!normalized.contains(':')) return true;
  if (normalized == '::' || normalized == '::1') return true;
  if (normalized.startsWith('::ffff:')) {
    return _nonPublicAddress(normalized.substring(7));
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
