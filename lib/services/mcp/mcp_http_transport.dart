import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../models/mcp_config.dart';
import '../outbound_http_client_factory.dart';
import '../outbound_network_policy.dart';
import 'mcp_host_resolver.dart';
import 'mcp_protocol.dart';
import 'mcp_transport.dart';
import 'mcp_transport_secrets.dart';

typedef McpHttpClientFactory = http.Client Function(List<String>? addresses);

http.Client _defaultOutboundClientFactory(List<String>? addresses) =>
    createOutboundHttpClient(addresses ?? const []);

class McpHttpTransport implements McpTransport {
  final McpServerConfig config;
  final McpHttpCredentials credentials;
  final http.Client? _client;
  final bool _closeClient;
  final McpHttpClientFactory _clientFactory;
  final McpHostResolver _hostResolver;
  final Set<http.Client> _activeClients = {};
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
    http.Client? client,
    bool closeClient = false,
    McpHttpClientFactory clientFactory = _defaultOutboundClientFactory,
    McpHostResolver hostResolver = resolveMcpHost,
  }) : _client = client,
       _closeClient = closeClient,
       _clientFactory = clientFactory,
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
  Future<void> send(
    Map<String, dynamic> message, {
    McpTransportCancellation? cancellation,
  }) async {
    if (_disposed) {
      throw const McpTransportException('HTTP transport is disposed');
    }
    cancellation?.throwIfCancelled();
    final body = encodeMcpMessage(message, config.maxMessageBytes);
    final result = await _sendWithRedirects(
      'POST',
      config.endpoint!,
      body: body,
      cancellation: cancellation,
    );
    try {
      final response = result.response;
      _captureSession(response);
      if (response.statusCode == 202 || response.statusCode == 204) {
        await _drain(response.stream, cancellation: cancellation);
        _startSseIfAvailable();
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorBody = await _readBounded(
          response.stream,
          config.maxResponseBytes,
          cancellation: cancellation,
        );
        throw McpTransportException(
          'MCP HTTP request failed with ${response.statusCode}: ${utf8.decode(errorBody, allowMalformed: true)}',
        );
      }
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.contains('text/event-stream')) {
        await _readSse(
          response.stream,
          maxTotalBytes: config.maxResponseBytes,
          cancellation: cancellation,
        );
      } else {
        final bytes = await _readBounded(
          response.stream,
          config.maxResponseBytes,
          cancellation: cancellation,
        );
        if (bytes.isNotEmpty) {
          _messages.add(decodeMcpMessage(bytes, config.maxMessageBytes));
        }
      }
      _startSseIfAvailable();
    } finally {
      _releaseClient(result.client);
    }
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
      final result = await _sendWithRedirects('GET', config.endpoint!);
      try {
        final response = result.response;
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
        final contentType =
            response.headers['content-type']?.toLowerCase() ?? '';
        if (!contentType.contains('text/event-stream')) {
          await response.stream.drain<void>();
          _setStatus(
            McpTransportState.degraded,
            'SSE notification response has the wrong content type',
          );
          return;
        }
        await _readSse(response.stream);
      } finally {
        _releaseClient(result.client);
      }
    } catch (error, stackTrace) {
      if (_disposed) return;
      _setStatus(McpTransportState.degraded, error.toString());
      _messages.addError(error, stackTrace);
    }
  }

  Future<_McpHttpResult> _sendWithRedirects(
    String method,
    Uri initialUri, {
    List<int>? body,
    McpTransportCancellation? cancellation,
  }) async {
    var uri = initialUri;
    var includeSensitiveHeaders = true;
    for (var redirect = 0; redirect <= 3; redirect++) {
      cancellation?.throwIfCancelled();
      final addresses = await _validateUri(uri);
      cancellation?.throwIfCancelled();
      if (_disposed && method != 'DELETE') {
        throw const McpTransportException('HTTP transport is disposed');
      }
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
      final client = _client ?? _clientFactory(addresses);
      _activeClients.add(client);
      late final http.StreamedResponse response;
      try {
        response = await _sendRequest(
          client,
          request,
          cancellation: cancellation,
          closeOnCancel: !identical(client, _client),
        );
      } catch (_) {
        _releaseClient(client);
        rethrow;
      }
      if (!_isRedirect(response.statusCode)) {
        return _McpHttpResult(response: response, client: client);
      }
      final location = response.headers['location'];
      try {
        await _drain(response.stream, cancellation: cancellation);
      } finally {
        _releaseClient(client);
      }
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

  Future<List<String>?> _validateUri(Uri uri) async {
    if (uri.userInfo.isNotEmpty) {
      throw const McpTransportException(
        'MCP endpoint must not contain URL credentials',
      );
    }
    if (uri.scheme != 'https' && !(config.allowHttp && uri.scheme == 'http')) {
      throw const McpTransportException('MCP endpoint must use HTTPS');
    }
    if (!config.allowPrivateNetwork && isPrivateNetworkHost(uri.host)) {
      throw const McpTransportException('MCP private endpoint is not allowed');
    }
    final addresses = await _hostResolver(uri.host);
    if (addresses != null && addresses.isEmpty) {
      throw const McpTransportException('MCP endpoint did not resolve');
    }
    if (!config.allowPrivateNetwork &&
        (addresses?.any(isNonPublicAddress) ?? false)) {
      throw const McpTransportException(
        'MCP endpoint resolves to a non-public address',
      );
    }
    return addresses;
  }

  void _releaseClient(http.Client client) {
    _activeClients.remove(client);
    if (!identical(client, _client)) client.close();
  }

  Future<http.StreamedResponse> _sendRequest(
    http.Client client,
    http.BaseRequest request, {
    required McpTransportCancellation? cancellation,
    required bool closeOnCancel,
  }) async {
    final send = client.send(request).timeout(config.requestTimeout);
    if (cancellation == null) return send;
    cancellation.throwIfCancelled();
    return Future.any([
      send,
      cancellation.whenCancelled.then<http.StreamedResponse>((_) {
        if (closeOnCancel) client.close();
        throw const McpTransportSendCancelledException();
      }),
    ]);
  }

  Future<void> _readSse(
    Stream<List<int>> stream, {
    int? maxTotalBytes,
    McpTransportCancellation? cancellation,
  }) async {
    final buffer = BytesBuilder(copy: false);
    var total = 0;
    await _consume(stream, cancellation, (chunk) {
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
    });
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

  Future<List<int>> _readBounded(
    Stream<List<int>> stream,
    int limit, {
    McpTransportCancellation? cancellation,
  }) async {
    final bytes = BytesBuilder(copy: false);
    var total = 0;
    await _consume(stream, cancellation, (chunk) {
      total += chunk.length;
      if (total > limit) {
        throw McpTransportException('MCP HTTP response exceeds $limit bytes');
      }
      bytes.add(chunk);
    });
    return bytes.takeBytes();
  }

  Future<void> _drain(
    Stream<List<int>> stream, {
    McpTransportCancellation? cancellation,
  }) => _consume(stream, cancellation, (_) {});

  Future<void> _consume(
    Stream<List<int>> stream,
    McpTransportCancellation? cancellation,
    void Function(List<int>) onData,
  ) {
    cancellation?.throwIfCancelled();
    final completer = Completer<void>();
    StreamSubscription<List<int>>? subscription;
    subscription = stream.listen(
      (chunk) {
        if (completer.isCompleted) return;
        try {
          onData(chunk);
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
          unawaited(subscription?.cancel());
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );
    if (cancellation != null) {
      cancellation.whenCancelled.then((_) {
        if (completer.isCompleted) return;
        completer.completeError(const McpTransportSendCancelledException());
        unawaited(subscription?.cancel());
      });
    }
    return completer.future;
  }

  void _setStatus(McpTransportState state, [String? detail]) {
    _status = McpTransportStatus(state, detail);
    _statuses.add(_status);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final client in _activeClients.toList(growable: false)) {
      client.close();
    }
    _activeClients.clear();
    if (_sessionId != null) {
      try {
        final result = await _sendWithRedirects('DELETE', config.endpoint!);
        try {
          await result.response.stream.drain<void>();
        } finally {
          _releaseClient(result.client);
        }
      } catch (_) {}
    }
    if (_closeClient) _client?.close();
    _setStatus(McpTransportState.disposed);
    await _messages.close();
    await _statuses.close();
  }
}

class _McpHttpResult {
  const _McpHttpResult({required this.response, required this.client});

  final http.StreamedResponse response;
  final http.Client client;
}

bool _isRedirect(int status) =>
    status == 301 ||
    status == 302 ||
    status == 303 ||
    status == 307 ||
    status == 308;
