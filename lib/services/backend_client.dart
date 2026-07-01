import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
  String _backendUrl = '';
  String? _accessToken;
  String? _refreshToken;

  /// 正在进行的 refresh 操作。并发 401 用它去重——多个请求同时
  /// 401 只发起一次 refresh，等它完成后统一重试。
  Completer<bool>? _refreshCompleter;

  /// 当前后端根 URL（如 `https://api.lynai.com`），空字符串表示未连接。
  String get backendUrl => _backendUrl;

  /// 当前 access 令牌。
  String? get accessToken => _accessToken;

  /// 当前 refresh 令牌。
  String? get refreshToken => _refreshToken;

  /// 是否已连接后端。
  bool get isConnected => _backendUrl.isNotEmpty;

  /// 设置后端地址。传入空字符串表示断开连接。
  void configure(String url) {
    final normalized = url.trim();
    if (normalized == _backendUrl) return;
    _backendUrl = normalized;
    _accessToken = null;
    _refreshToken = null;
    _refreshCompleter = null;
    notifyListeners();
  }

  /// 设置双令牌（登录/注册/刷新成功后调用）。
  void setTokens(String accessToken, String refreshToken) {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  /// 清除令牌（登出时调用）。
  void clearTokens() {
    _accessToken = null;
    _refreshToken = null;
  }

  /// 发送 GET 请求，自动附加鉴权头。
  /// 遇到 401 时自动刷新并重试一次。
  Future<http.Response> get(String path, {Map<String, String>? headers}) {
    return _request(
      () =>
          http.get(Uri.parse('$_backendUrl$path'), headers: _withAuth(headers)),
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
      () => http.post(
        Uri.parse('$_backendUrl$path'),
        headers: _withAuth(h),
        body: body is Map || body is List ? jsonEncode(body) : body,
      ),
    );
  }

  /// 发送原始 POST 请求，不修改 Content-Type，不 JSON 编码 body。
  /// 用于 octet-stream 等非 JSON 端点。
  Future<http.Response> postRaw(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _request(
      () => http.post(
        Uri.parse('$_backendUrl$path'),
        headers: _withAuth(headers),
        body: body,
      ),
    );
  }

  /// 创建 multipart 请求，自动附加鉴权头。
  /// multipart 请求不自动重试（流式上传难以重放）。
  http.MultipartRequest multipartRequest(String method, String path) {
    final req = http.MultipartRequest(method, Uri.parse('$_backendUrl$path'));
    if (_accessToken != null) {
      req.headers['Authorization'] = 'Bearer $_accessToken';
    }
    return req;
  }

  /// 主动刷新 access token，供无法直接复用 [get]/[post] 的流式请求使用。
  Future<bool> refreshAccessToken() => _tryRefresh();

  /// 执行一个 HTTP 请求，401 时自动刷新 token 并重试一次。
  Future<http.Response> _request(Future<http.Response> Function() send) async {
    final resp = await send();
    if (resp.statusCode != 401) return resp;

    // 401 — 尝试刷新 token
    final refreshed = await _tryRefresh();
    if (!refreshed) return resp;

    // 刷新成功，重试原请求
    return send();
  }

  /// 尝试用 refresh token 获取新的 access token。
  /// 并发调用通过 [_refreshCompleter] 去重。
  /// 返回 true 表示刷新成功，false 表示失败（refresh token 也过期）。
  Future<bool> _tryRefresh() async {
    if (_refreshToken == null) return false;

    // 如果已经有 refresh 在进行中，等它完成
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<bool>();
    try {
      final resp = await http.post(
        Uri.parse('$_backendUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': _refreshToken}),
      );

      if (resp.statusCode == 200) {
        final json = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
        final token = Map<String, dynamic>.from(
          json['token'] as Map? ?? const {},
        );
        final newAccess = token['accessToken'] as String? ?? '';
        final newRefresh = token['refreshToken'] as String? ?? '';
        if (newAccess.isNotEmpty && newRefresh.isNotEmpty) {
          _accessToken = newAccess;
          _refreshToken = newRefresh;
          _refreshCompleter!.complete(true);
          return true;
        }
      }

      // Refresh failed — clear tokens, user needs to re-login
      _accessToken = null;
      _refreshToken = null;
      _refreshCompleter!.complete(false);
      return false;
    } catch (e) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  Map<String, String> _withAuth(Map<String, String>? headers) {
    final h = Map<String, String>.from(headers ?? {});
    if (_accessToken != null) {
      h['Authorization'] = 'Bearer $_accessToken';
    }
    return h;
  }
}
