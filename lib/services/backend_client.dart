import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'backend_uri.dart';

/// 后端连接配置与 HTTP 客户端。
///
/// 持有当前后端地址、access token 和 refresh token。所有需要鉴权的
/// 请求通过 [get] / [post] 发送，遇到 401 时自动用 refresh token 刷新
/// access token 并重试一次。refresh token 有效期 30 天，活跃用户不会
/// 被强制重新登录。
///
/// 当 [backendUrl] 为空时，调用方应显示「未连接后端」提示。
///
/// 这是一个 [ChangeNotifier]：当后端地址变化时通知依赖方。
class BackendClient extends ChangeNotifier {
  static const defaultBackendUrl = String.fromEnvironment(
    'LYNAI_BACKEND_URL',
    defaultValue: '',
  );
  static const defaultRequestTimeout = Duration(seconds: 30);

  /// 创建后端客户端。
  ///
  /// [client] 注入后其所有权转移给本实例，并在 [close] 或 [dispose] 时关闭。
  BackendClient({
    http.Client? client,
    this.requestTimeout = defaultRequestTimeout,
  }) : _httpClient = client ?? http.Client();

  final http.Client _httpClient;

  /// 普通、刷新和 multipart 请求使用的默认超时时间。
  final Duration requestTimeout;

  bool _closed = false;

  String _backendUrl = '';
  String? _accessToken;
  String? _refreshToken;
  int _configurationGeneration = 0;
  int _credentialGeneration = 0;

  /// 正在进行的 refresh 操作。并发 401 用它去重——多个请求同时
  /// 401 只发起一次 refresh，等它完成后统一重试。
  Completer<bool>? _refreshCompleter;

  /// refresh 成功后持久化新令牌。账号服务连接后设置此回调。
  Future<void> Function(
    String backendScope,
    String accessToken,
    String refreshToken,
  )?
  onTokensRefreshed;

  /// refresh 失败后清除持久化会话。账号服务连接后设置此回调。
  Future<void> Function(String backendScope)? onSessionCleared;

  /// 当前后端根 URL（如 `https://api.lynai.com`），空字符串表示未连接。
  String get backendUrl => _backendUrl;

  /// 当前 access 令牌。
  String? get accessToken => _accessToken;

  /// 当前 refresh 令牌。
  String? get refreshToken => _refreshToken;

  /// 是否已连接后端。
  bool get isConnected => _backendUrl.isNotEmpty;

  /// Canonical origin retained for source and same-origin comparisons.
  String get backendOrigin => normalizedBackendOrigin(_backendUrl);

  /// Canonical full base URL used to scope credentials and account state.
  String get backendScope => normalizeBackendUri(_backendUrl);

  /// Whether the configured backend transports credentials over plain HTTP.
  bool get usesInsecureHttp => isInsecureHttpBackend(_backendUrl);

  /// User-facing warning for a plain HTTP backend, otherwise null.
  String? get insecureHttpWarning => insecureHttpBackendWarning(_backendUrl);

  static String normalizeUrl(String value) => normalizeBackendUri(value);

  static String normalizeOrigin(String value) => normalizedBackendOrigin(value);

  static bool isInsecureHttp(String value) => isInsecureHttpBackend(value);

  static String? insecureHttpWarningFor(String value) =>
      insecureHttpBackendWarning(value);

  /// Whether a revocation endpoint has definitively consumed or rejected a token.
  static bool isCredentialRejectionStatus(int statusCode) =>
      statusCode == 400 || statusCode == 401 || statusCode == 403;

  /// Whether refresh definitively rejected the refresh credential.
  ///
  /// Keep this decision centralized so structured backend error codes can be
  /// added here later without spreading refresh invalidation policy.
  static bool isRefreshCredentialRejection(http.Response response) =>
      response.statusCode == 401;

  /// 从后端错误响应中提取可展示的错误消息。
  ///
  /// 兼容普通业务接口的 `{"error":"..."}`，也兼容 relay/OpenAI 风格的
  /// `{"error":{"message":"...","type":"..."}}`，避免各调用方重复解析。
  static String? extractErrorMessage(String body) {
    try {
      return extractErrorMessageFromDecoded(jsonDecode(body));
    } catch (_) {
      return null;
    }
  }

  /// 从已解码的 JSON 对象中提取可展示的错误消息。
  static String? extractErrorMessageFromDecoded(Object? decoded) {
    if (decoded is! Map) return null;
    final error = decoded['error'];
    if (error is String) {
      final text = error.trim();
      return text.isEmpty ? null : text;
    }
    if (error is Map) {
      return _firstNonEmpty([error['message'], error['error'], error['type']]);
    }
    return _firstNonEmpty([decoded['message']]);
  }

  static String? _firstNonEmpty(Iterable<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  /// 设置后端地址。传入空字符串表示断开连接。
  void configure(String url) {
    final normalized = url.trim().isEmpty ? '' : normalizeBackendUri(url);
    if (url.trim().isNotEmpty && normalized.isEmpty) {
      throw ArgumentError.value(url, 'url', 'invalid HTTP(S) backend URL');
    }
    if (normalized == _backendUrl) return;
    final scopeChanged = normalized != backendScope;
    _backendUrl = normalized;
    _configurationGeneration++;
    if (scopeChanged) {
      _credentialGeneration++;
      _accessToken = null;
      _refreshToken = null;
    }
    _refreshCompleter = null;
    notifyListeners();
  }

  /// 设置双令牌（登录/注册/刷新成功后调用）。
  void setTokens(String accessToken, String refreshToken) {
    _credentialGeneration++;
    _accessToken = accessToken;
    _refreshToken = refreshToken.isEmpty ? null : refreshToken;
  }

  /// 清除令牌（登出时调用）。
  void clearTokens() {
    _credentialGeneration++;
    _accessToken = null;
    _refreshToken = null;
  }

  /// 发送 GET 请求，自动附加鉴权头。
  /// 遇到 401 时自动刷新并重试一次。
  Future<http.Response> get(String path, {Map<String, String>? headers}) {
    return _request(
      () => _httpClient.get(
        Uri.parse('$_backendUrl$path'),
        headers: _withAuth(headers),
      ),
    );
  }

  /// Sends an authenticated GET and buffers at most [maxBytes] response bytes.
  Future<http.Response> getBounded(
    String path, {
    required int maxBytes,
    Map<String, String>? headers,
  }) async {
    if (maxBytes < 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    final response = await sendAuthenticatedStreamed(
      () =>
          http.Request('GET', Uri.parse('$_backendUrl$path'))
            ..headers.addAll(headers ?? const {}),
      maxResponseBytes: maxBytes,
    );
    final bytes = await _readBoundedResponse(response, maxBytes);
    return http.Response.bytes(
      bytes,
      response.statusCode,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
      request: response.request,
    );
  }

  /// 发送 POST 请求（JSON body），自动附加鉴权头。
  /// 遇到 401 时自动刷新并重试一次。
  Future<http.Response> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) {
    final h = Map<String, String>.from(headers ?? {});
    h['Content-Type'] = 'application/json';
    return _request(
      () => _httpClient.post(
        Uri.parse('$_backendUrl$path'),
        headers: _withAuth(h),
        body: body is Map || body is List ? jsonEncode(body) : body,
      ),
    );
  }

  /// Sends a replay-safe JSON PUT request and retries once after token refresh.
  Future<http.Response> put(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) => _jsonRequest('PUT', path, headers: headers, body: body);

  /// Sends a replay-safe JSON PATCH request and retries once after token refresh.
  Future<http.Response> patch(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) => _jsonRequest('PATCH', path, headers: headers, body: body);

  /// Sends a replay-safe JSON DELETE request and retries once after token refresh.
  Future<http.Response> delete(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) => _jsonRequest('DELETE', path, headers: headers, body: body);

  Future<http.Response> _jsonRequest(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) {
    final requestHeaders = Map<String, String>.from(headers ?? const {});
    requestHeaders['Content-Type'] = 'application/json';
    final encoded = body is Map || body is List ? jsonEncode(body) : body;
    return _request(
      () => _httpClient
          .send(
            http.Request(method, Uri.parse('$_backendUrl$path'))
              ..headers.addAll(_withAuth(requestHeaders))
              ..body = encoded?.toString() ?? '',
          )
          .then(http.Response.fromStream),
    );
  }

  /// Uploads replayable in-memory multipart data with automatic token refresh.
  Future<http.Response> multipartUpload(
    String path, {
    String method = 'POST',
    Map<String, String> fields = const {},
    List<BackendMultipartFile> files = const [],
    Duration? timeout,
  }) async {
    final streamed = await sendAuthenticatedStreamed(() {
      final request = http.MultipartRequest(
        method,
        Uri.parse('$_backendUrl$path'),
      )..fields.addAll(fields);
      for (final file in files) {
        request.files.add(file.toHttpFile());
      }
      return request;
    }, timeout: timeout);
    return http.Response.fromStream(streamed);
  }

  /// 发送原始 POST 请求，不修改 Content-Type，不 JSON 编码 body。
  /// 用于 octet-stream 等非 JSON 端点。
  Future<http.Response> postRaw(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) {
    return _request(
      () => _httpClient.post(
        Uri.parse('$_backendUrl$path'),
        headers: _withAuth(headers),
        body: body,
      ),
      timeout: timeout,
    );
  }

  /// Sends exact JSON body bytes without re-encoding them.
  Future<http.Response> postJsonBytes(
    String path, {
    Map<String, String>? headers,
    required List<int> bodyBytes,
  }) {
    final requestHeaders = Map<String, String>.from(headers ?? {});
    requestHeaders['Content-Type'] = 'application/json';
    return _request(
      () => _httpClient.post(
        Uri.parse('$_backendUrl$path'),
        headers: _withAuth(requestHeaders),
        body: bodyBytes,
      ),
    );
  }

  /// Sends stable in-memory bytes and rebuilds headers for every replay.
  ///
  /// [buildHeaders] is invoked before the initial request and again after a
  /// successful token refresh, allowing token-bound signatures to be rebuilt.
  Future<http.Response> postReplayableBytes(
    String path, {
    required Future<Map<String, String>> Function() buildHeaders,
    required List<int> bodyBytes,
    Duration? timeout,
  }) {
    final replayableBody = Uint8List.fromList(bodyBytes);
    return _request(() async {
      final headers = await buildHeaders();
      return _httpClient.post(
        Uri.parse('$_backendUrl$path'),
        headers: _withAuth(headers),
        body: replayableBody,
      );
    }, timeout: timeout);
  }

  /// 创建 multipart 请求，自动附加鉴权头。
  /// 旧调用方仍可使用；需要 401 刷新重放时使用 [sendAuthenticatedStreamed]。
  http.MultipartRequest multipartRequest(String method, String path) {
    final req = _BackendMultipartRequest(
      method,
      Uri.parse('$_backendUrl$path'),
      _httpClient,
      requestTimeout,
    );
    if (_accessToken != null) {
      req.headers['Authorization'] = 'Bearer $_accessToken';
    }
    return req;
  }

  /// 主动刷新 access token，供无法直接复用 [get]/[post] 的流式请求使用。
  Future<bool> refreshAccessToken() => _tryRefresh();

  /// Sends a replayable authenticated streamed or multipart request.
  ///
  /// [buildRequest] must create a fresh request and fresh body stream on every
  /// invocation. A 401 response is drained, the access token is refreshed once,
  /// and the request is rebuilt before retrying.
  Future<http.StreamedResponse> sendAuthenticatedStreamed(
    http.BaseRequest Function() buildRequest, {
    Duration? timeout,
    int? maxResponseBytes,
  }) async {
    Future<http.StreamedResponse> send() {
      final request = buildRequest();
      final token = _accessToken;
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      return _httpClient.send(request).timeout(timeout ?? requestTimeout);
    }

    final requestAccessToken = _accessToken;
    var response = await send();
    if (response.statusCode != 401) return response;

    final responseBytes = maxResponseBytes == null
        ? await response.stream.toBytes()
        : await _readBoundedResponse(response, maxResponseBytes);
    if (requestAccessToken != _accessToken && _accessToken != null) {
      return send();
    }
    if (!await _tryRefresh()) {
      return http.StreamedResponse(
        Stream.value(responseBytes),
        response.statusCode,
        contentLength: responseBytes.length,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    }
    return send();
  }

  static Future<List<int>> _readBoundedResponse(
    http.StreamedResponse response,
    int maxBytes,
  ) async {
    final contentLength = response.contentLength;
    if (contentLength != null && contentLength > maxBytes) {
      throw BackendResponseTooLargeException(maxBytes);
    }
    final bytes = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in response.stream) {
      total += chunk.length;
      if (total > maxBytes) {
        throw BackendResponseTooLargeException(maxBytes);
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  /// 执行一个 HTTP 请求，401 时自动刷新 token 并重试一次。
  Future<http.Response> _request(
    Future<http.Response> Function() send, {
    Duration? timeout,
  }) async {
    final requestAccessToken = _accessToken;
    final resp = await _send(send, timeout);
    if (resp.statusCode != 401) return resp;

    // 另一个并发请求已刷新令牌时，直接用新令牌重试。
    if (requestAccessToken != _accessToken && _accessToken != null) {
      return _send(send, timeout);
    }

    final refreshed = await _tryRefresh();
    if (!refreshed) return resp;

    return _send(send, timeout);
  }

  Future<http.Response> _send(
    Future<http.Response> Function() send,
    Duration? timeout,
  ) {
    return send().timeout(timeout ?? requestTimeout);
  }

  /// 尝试用 refresh token 获取新的 access token。
  /// 并发调用通过 [_refreshCompleter] 去重。
  /// 返回 true 表示刷新成功，false 表示失败（refresh token 也过期）。
  Future<bool> _tryRefresh() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null || _backendUrl.isEmpty) return false;

    // 如果已经有 refresh 在进行中，等它完成
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    final completer = Completer<bool>();
    _refreshCompleter = completer;
    final backendUrl = _backendUrl;
    final scope = normalizeBackendUri(backendUrl);
    final configurationGeneration = _configurationGeneration;
    final credentialGeneration = _credentialGeneration;
    var refreshed = false;
    var definitiveRejection = false;
    try {
      final resp = await _httpClient
          .post(
            Uri.parse('$backendUrl/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(requestTimeout);

      if (resp.statusCode == 200) {
        final json = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
        final token = Map<String, dynamic>.from(
          json['token'] as Map? ?? const {},
        );
        final newAccess = token['accessToken'] as String? ?? '';
        final newRefresh = token['refreshToken'] as String? ?? '';
        if (newAccess.isNotEmpty && newRefresh.isNotEmpty) {
          if (configurationGeneration != _configurationGeneration ||
              credentialGeneration != _credentialGeneration ||
              backendUrl != _backendUrl ||
              refreshToken != _refreshToken) {
            return false;
          }
          _accessToken = newAccess;
          _refreshToken = newRefresh;
          _credentialGeneration++;
          await onTokensRefreshed?.call(scope, newAccess, newRefresh);
          refreshed = true;
        }
      } else if (isRefreshCredentialRejection(resp)) {
        definitiveRejection = true;
      }
    } catch (_) {
      refreshed = false;
    } finally {
      if (!refreshed &&
          definitiveRejection &&
          configurationGeneration == _configurationGeneration &&
          credentialGeneration == _credentialGeneration &&
          backendUrl == _backendUrl &&
          refreshToken == _refreshToken) {
        _accessToken = null;
        _refreshToken = null;
        _credentialGeneration++;
        try {
          await onSessionCleared?.call(scope);
        } catch (_) {
          // 内存会话已经清除，持久化清理失败不应阻塞等待 refresh 的请求。
        }
      }
      completer.complete(refreshed);
      if (identical(_refreshCompleter, completer)) {
        _refreshCompleter = null;
      }
    }
    return refreshed;
  }

  /// Revokes a refresh token without attaching the current account's access token.
  Future<http.Response> revokeRefreshToken({
    required String backendUrl,
    required String refreshToken,
  }) {
    final normalized = normalizeBackendUri(backendUrl);
    if (normalized.isEmpty) {
      throw ArgumentError.value(backendUrl, 'backendUrl');
    }
    return _httpClient
        .post(
          Uri.parse('$normalized/auth/revoke'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': refreshToken}),
        )
        .timeout(requestTimeout);
  }

  Map<String, String> _withAuth(Map<String, String>? headers) {
    final h = Map<String, String>.from(headers ?? {});
    if (_accessToken != null) {
      h['Authorization'] = 'Bearer $_accessToken';
    }
    return h;
  }

  /// 关闭持有的 HTTP client。可重复调用。
  void close() {
    if (_closed) return;
    _closed = true;
    _httpClient.close();
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}

class BackendResponseTooLargeException implements Exception {
  const BackendResponseTooLargeException(this.maxBytes);

  final int maxBytes;

  @override
  String toString() => 'Backend response exceeds $maxBytes bytes';
}

class BackendMultipartFile {
  const BackendMultipartFile({
    required this.field,
    required this.bytes,
    required this.filename,
    this.contentType,
  });

  final String field;
  final List<int> bytes;
  final String filename;
  final String? contentType;

  http.MultipartFile toHttpFile() {
    final parts = contentType?.split('/');
    return http.MultipartFile.fromBytes(
      field,
      bytes,
      filename: filename,
      contentType: parts?.length == 2 ? MediaType(parts![0], parts[1]) : null,
    );
  }
}

class _BackendMultipartRequest extends http.MultipartRequest {
  _BackendMultipartRequest(
    super.method,
    super.url,
    this._client,
    this._timeout,
  );

  final http.Client _client;
  final Duration _timeout;

  @override
  Future<http.StreamedResponse> send() {
    return _client.send(this).timeout(_timeout);
  }
}
