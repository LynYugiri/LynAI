import 'dart:async';

import '../agent_cancellation.dart';
import 'mcp_protocol.dart';
import 'mcp_transport.dart';

enum McpClientState { idle, initializing, ready, failed, disposed }

class McpClientStatus {
  final McpClientState state;
  final String? detail;

  const McpClientStatus(this.state, [this.detail]);
}

class McpClient {
  final McpTransport transport;
  final String clientName;
  final String clientVersion;
  final Duration requestTimeout;
  final int maxToolPages;
  final StreamController<McpClientStatus> _statuses =
      StreamController.broadcast();
  final StreamController<void> _toolsChanged = StreamController.broadcast();
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  StreamSubscription<Map<String, dynamic>>? _messageSubscription;
  var _nextRequestId = 0;
  var _status = const McpClientStatus(McpClientState.idle);
  String? _protocolVersion;

  McpClient({
    required this.transport,
    this.clientName = 'LynAI',
    this.clientVersion = '4.0.0',
    this.requestTimeout = const Duration(seconds: 30),
    this.maxToolPages = 100,
  });

  Stream<McpClientStatus> get statuses => _statuses.stream;
  Stream<void> get toolsChanged => _toolsChanged.stream;
  McpClientStatus get status => _status;
  String? get protocolVersion => _protocolVersion;

  Future<void> initialize() async {
    if (_status.state != McpClientState.idle) {
      throw StateError('MCP client can only be initialized once');
    }
    _setStatus(McpClientState.initializing);
    try {
      _messageSubscription = transport.messages.listen(
        _handleMessage,
        onError: (Object error, StackTrace stackTrace) => _fail(error),
        onDone: () {
          if (_status.state != McpClientState.disposed) {
            _fail(const McpTransportException('MCP transport closed'));
          }
        },
      );
      await transport.start();
      final result = await request('initialize', {
        'protocolVersion': mcpProtocolVersion,
        'capabilities': const {},
        'clientInfo': {'name': clientName, 'version': clientVersion},
      });
      final version = result['protocolVersion'];
      if (version is! String || version.isEmpty) {
        throw const McpProtocolException(
          'initialize response lacks protocolVersion',
        );
      }
      _protocolVersion = version;
      await notify('notifications/initialized');
      _setStatus(McpClientState.ready);
    } catch (error) {
      _fail(error);
      rethrow;
    }
  }

  Future<List<McpTool>> listTools({
    AgentCancellationToken? cancellationToken,
  }) async {
    final tools = <McpTool>[];
    String? cursor;
    final seenCursors = <String>{};
    for (var page = 0; page < maxToolPages; page++) {
      final result = await request(
        'tools/list',
        cursor == null ? const {} : {'cursor': cursor},
        cancellationToken: cancellationToken,
      );
      final rawTools = result['tools'];
      if (rawTools is! List) {
        throw const McpProtocolException('tools/list result lacks tools array');
      }
      tools.addAll(
        rawTools.map((item) {
          if (item is! Map) {
            throw const McpProtocolException(
              'Invalid tool in tools/list result',
            );
          }
          return McpTool.fromJson(Map<String, dynamic>.from(item));
        }),
      );
      final nextCursor = result['nextCursor'];
      if (nextCursor == null) return List.unmodifiable(tools);
      if (nextCursor is! String ||
          nextCursor.isEmpty ||
          !seenCursors.add(nextCursor)) {
        throw const McpProtocolException(
          'Invalid or repeated tools/list cursor',
        );
      }
      cursor = nextCursor;
    }
    throw McpProtocolException('tools/list exceeded $maxToolPages pages');
  }

  Future<McpCallToolResult> callTool(
    String name,
    Map<String, dynamic> arguments, {
    AgentCancellationToken? cancellationToken,
  }) async {
    final result = await request('tools/call', {
      'name': name,
      'arguments': arguments,
    }, cancellationToken: cancellationToken);
    return McpCallToolResult.fromJson(result);
  }

  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params, {
    AgentCancellationToken? cancellationToken,
    Duration? timeout,
  }) async {
    _ensureUsable(method);
    cancellationToken?.throwIfCancellationRequested();
    final id = ++_nextRequestId;
    final completer = Completer<Map<String, dynamic>>();
    final sendCancellation = McpTransportCancellation();
    _pending[id] = completer;
    Timer? timer;
    StreamSubscription<AgentCancellationReason>? cancellationSubscription;
    var sendStarted = false;

    void cancelRequest(Object error, String reason) {
      if (_pending.remove(id) == null || completer.isCompleted) return;
      sendCancellation.cancel();
      completer.completeError(error);
      if (sendStarted) _notifyCancellation(id, reason);
    }

    final cancellation = cancellationToken;
    if (cancellation != null) {
      cancellationSubscription = cancellation.whenCancelled.asStream().listen((
        reason,
      ) {
        cancelRequest(AgentCancellationException(reason), reason.message);
      });
    }
    timer = Timer(timeout ?? requestTimeout, () {
      cancelRequest(
        TimeoutException('MCP $method timed out', timeout ?? requestTimeout),
        'Request timed out',
      );
    });
    sendStarted = true;
    unawaited(
      transport
          .send({
            'jsonrpc': '2.0',
            'id': id,
            'method': method,
            'params': params,
          }, cancellation: sendCancellation)
          .catchError((Object error, StackTrace stackTrace) {
            if (_pending.remove(id) == null || completer.isCompleted) return;
            completer.completeError(error, stackTrace);
          }),
    );
    try {
      return await completer.future;
    } finally {
      sendCancellation.cancel();
      timer.cancel();
      await cancellationSubscription?.cancel();
      _pending.remove(id);
    }
  }

  Future<void> notify(String method, [Map<String, dynamic>? params]) {
    _ensureUsable(method);
    return transport.send({
      'jsonrpc': '2.0',
      'method': method,
      'params': ?params,
    });
  }

  void _notifyCancellation(int requestId, String reason) {
    final cancellation = McpTransportCancellation();
    final timer = Timer(requestTimeout, cancellation.cancel);
    unawaited(
      transport
          .send({
            'jsonrpc': '2.0',
            'method': 'notifications/cancelled',
            'params': {'requestId': requestId, 'reason': reason},
          }, cancellation: cancellation)
          .catchError((_) {})
          .whenComplete(timer.cancel),
    );
  }

  void _handleMessage(Map<String, dynamic> message) {
    final method = message['method'];
    if (method == 'notifications/tools/list_changed') {
      _toolsChanged.add(null);
      return;
    }
    final id = message['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    final error = message['error'];
    if (error is Map) {
      completer.completeError(
        McpRpcException(
          error['code'] is int ? error['code'] as int : -32603,
          error['message'] is String
              ? error['message'] as String
              : 'Unknown MCP error',
          error['data'],
        ),
      );
      return;
    }
    final result = message['result'];
    if (result is! Map) {
      completer.completeError(
        const McpProtocolException('JSON-RPC response lacks object result'),
      );
      return;
    }
    completer.complete(Map<String, dynamic>.from(result));
  }

  void _ensureUsable(String method) {
    if (_status.state == McpClientState.disposed ||
        _status.state == McpClientState.failed) {
      throw StateError('MCP client is not usable');
    }
    if (_status.state == McpClientState.idle && method != 'initialize') {
      throw StateError('MCP client is not initialized');
    }
  }

  void _fail(Object error) {
    if (_status.state == McpClientState.disposed) return;
    _setStatus(McpClientState.failed, error.toString());
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  void _setStatus(McpClientState state, [String? detail]) {
    _status = McpClientStatus(state, detail);
    _statuses.add(_status);
  }

  Future<void> dispose() async {
    if (_status.state == McpClientState.disposed) return;
    _setStatus(McpClientState.disposed);
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const McpTransportException('MCP client disposed'),
        );
      }
    }
    _pending.clear();
    await _messageSubscription?.cancel();
    await transport.dispose();
    await _toolsChanged.close();
    await _statuses.close();
  }
}
