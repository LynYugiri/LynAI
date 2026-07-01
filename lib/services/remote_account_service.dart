import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import 'account_service.dart';
import 'backend_client.dart';

/// 连接真实后端的 [AccountService] 实现。
///
/// 通过 [BackendClient] 发送 HTTP 请求到 Go 后端 `/auth/*` 端点。
/// 登录方式为手机号和密码。access token 过期时
/// [BackendClient] 自动用 refresh token 刷新。
class RemoteAccountService implements AccountService {
  static const _sessionKey = 'lynai_account_session';

  final BackendClient _client;

  /// 创建远端账号服务实例。
  RemoteAccountService(this._client);

  @override
  bool get isBackendConnected => true;

  @override
  Future<AuthSession?> loadStoredSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = Map<String, dynamic>.from(
        jsonDecode(raw) as Map? ?? const {},
      );
      final session = AuthSession.fromJson(json);
      _client.setTokens(
        session.token.accessToken,
        session.token.refreshToken ?? '',
      );
      return session;
    } catch (_) {
      await prefs.remove(_sessionKey);
      return null;
    }
  }

  @override
  Future<AccountUser?> getCurrentUser() async {
    final session = await loadStoredSession();
    return session?.user;
  }

  @override
  Future<AuthSession> register({
    required String username,
    required String password,
    String? displayName,
  }) async {
    final body = <String, dynamic>{
      'phone': username,
      'password': password,
      if (displayName != null && displayName.isNotEmpty)
        'displayName': displayName,
    };

    final resp = await _client.post('/auth/register', body: body);
    if (resp.statusCode != 200) {
      final msg = _extractError(resp.body) ?? '注册失败';
      throw AccountUnavailableException(msg);
    }
    final session = AuthSession.fromJson(
      Map<String, dynamic>.from(jsonDecode(resp.body) as Map),
    );
    _client.setTokens(
      session.token.accessToken,
      session.token.refreshToken ?? '',
    );
    await _saveSession(session);
    return session;
  }

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final resp = await _client.post(
      '/auth/login',
      body: {'phone': username, 'password': password},
    );
    if (resp.statusCode != 200) {
      final msg = _extractError(resp.body) ?? '登录失败';
      throw AccountUnavailableException(msg);
    }
    final session = AuthSession.fromJson(
      Map<String, dynamic>.from(jsonDecode(resp.body) as Map),
    );
    _client.setTokens(
      session.token.accessToken,
      session.token.refreshToken ?? '',
    );
    await _saveSession(session);
    return session;
  }

  @override
  Future<void> logout() async {
    try {
      await _client.post('/auth/logout');
    } catch (_) {
      // 登出失败不阻塞本地清理
    }
    _client.clearTokens();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  Future<void> _saveSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sessionKey,
      jsonEncode({
        'user': session.user.toJson(),
        'token': session.token.toJson(),
      }),
    );
  }

  String? _extractError(String body) {
    try {
      final json = jsonDecode(body) as Map?;
      return json?['error'] as String?;
    } catch (_) {
      return null;
    }
  }
}
