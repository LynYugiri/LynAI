import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import 'account_service.dart';
import 'backend_client.dart';
import 'backend_uri.dart';
import 'secret_store.dart';

/// Connects account operations and protected session storage to the backend.
class RemoteAccountService implements AccountService {
  static const _sessionKey = 'lynai_account_session';
  static const accessTokenSecretKey = 'account.access_token';
  static const refreshTokenSecretKey = 'account.refresh_token';
  static const pendingRevocationsSecretKey = 'account.pending_revocations';

  RemoteAccountService(
    this._client, {
    required SecretStore secretStore,
    void Function()? onSessionInvalidated,
  }) : _secretStore = secretStore,
       _onSessionInvalidated = onSessionInvalidated {
    _client.onTokensRefreshed = _saveRefreshedTokens;
    _client.onSessionCleared = _clearSession;
  }

  final BackendClient _client;
  final SecretStore _secretStore;
  final void Function()? _onSessionInvalidated;
  Future<void> _credentialStoreTail = Future.value();
  Future<void> _revocationStoreTail = Future.value();
  Future<void>? _revocationRetry;
  int _authGeneration = 0;

  @override
  bool get isBackendConnected => true;

  @override
  Future<AuthSession?> loadStoredSession() async {
    final generation = _authGeneration;
    unawaited(retryPendingRevocations());
    final scope = _client.backendScope;
    if (scope.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_sessionKeyForScope(scope));
    var accessToken = await _secretStore.read(accessTokenKeyForScope(scope));
    var refreshToken = await _secretStore.read(refreshTokenKeyForScope(scope));
    var migratingLegacy = false;
    if ((raw == null || raw.isEmpty) &&
        accessToken == null &&
        refreshToken == null &&
        scope == _client.backendOrigin) {
      final legacyRaw = prefs.getString(_sessionKey);
      final legacyOrigin = _sessionOrigin(legacyRaw);
      if (legacyOrigin == scope) {
        raw = legacyRaw;
        accessToken = await _secretStore.read(accessTokenSecretKey);
        refreshToken = await _secretStore.read(refreshTokenSecretKey);
        migratingLegacy =
            (raw != null && raw.isNotEmpty) ||
            accessToken != null ||
            refreshToken != null;
      }
    }
    if ((raw == null || raw.isEmpty) &&
        accessToken == null &&
        refreshToken == null) {
      return null;
    }
    try {
      final json = Map<String, dynamic>.from(
        jsonDecode(raw ?? '') as Map? ?? const {},
      );
      final legacyToken = Map<String, dynamic>.from(
        json['token'] as Map? ?? const {},
      );
      final storedAccess = accessToken ?? legacyToken['accessToken'] as String?;
      final storedRefresh =
          refreshToken ?? legacyToken['refreshToken'] as String?;
      if (storedAccess == null || storedAccess.isEmpty) {
        throw const FormatException('missing access token');
      }
      final user = AccountUser.fromJson(
        Map<String, dynamic>.from(json['user'] as Map? ?? const {}),
      );
      if (user.id.isEmpty) throw const FormatException('missing account user');
      final session = AuthSession(
        user: user,
        token: AuthToken(
          accessToken: storedAccess,
          refreshToken: storedRefresh,
          expiresAt:
              json['expiresAt'] as int? ?? legacyToken['expiresAt'] as int?,
        ),
      );
      if (legacyToken.isNotEmpty || migratingLegacy) {
        final saved = await _saveSession(
          session,
          scope: scope,
          generation: generation,
        );
        if (!saved) return null;
        await _clearLegacySession();
      }
      if (generation != _authGeneration || _client.backendScope != scope) {
        return null;
      }
      _client.setTokens(storedAccess, storedRefresh ?? '');
      return session;
    } catch (_) {
      await _clearStoredSession(scope: scope, notify: false);
      if (migratingLegacy) await _clearLegacySession();
      return null;
    }
  }

  @override
  Future<AccountUser?> getCurrentUser() async {
    final session = await loadStoredSession();
    if (session == null) return null;
    final scope = _client.backendScope;
    final accessToken = _client.accessToken;
    try {
      final response = await _client.get('/auth/me');
      if (response.statusCode == 200) {
        final decoded = Map<String, dynamic>.from(
          jsonDecode(response.body) as Map,
        );
        final userJson = Map<String, dynamic>.from(
          decoded['user'] as Map? ?? decoded,
        );
        final user = AccountUser.fromJson(userJson);
        if (user.id.isEmpty) return session.user;
        final refreshedSession = AuthSession(
          user: user,
          token: AuthToken(
            accessToken: _client.accessToken ?? session.token.accessToken,
            refreshToken: _client.refreshToken,
            expiresAt: session.token.expiresAt,
          ),
        );
        await _saveSession(refreshedSession, scope: scope);
        return user;
      }
      if (response.statusCode == 401 &&
          (_client.accessToken == null ||
              _client.refreshToken == null ||
              _client.accessToken != accessToken)) {
        await _invalidateSession(scope);
        return null;
      }
    } catch (_) {
      // A cached session remains usable when account refresh is unavailable.
    }
    return session.user;
  }

  @override
  Future<AuthSession> register({
    required String username,
    required String password,
    String? displayName,
  }) async {
    final generation = ++_authGeneration;
    final scope = _client.backendScope;
    final resp = await _client.post(
      '/auth/register',
      body: {
        'phone': username,
        'password': password,
        if (displayName != null && displayName.isNotEmpty)
          'displayName': displayName,
      },
    );
    if (resp.statusCode != 200) {
      throw AccountUnavailableException(
        BackendClient.extractErrorMessage(resp.body) ?? '注册失败',
      );
    }
    return _acceptAuthenticatedSession(resp.body, scope, generation);
  }

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final generation = ++_authGeneration;
    unawaited(retryPendingRevocations());
    final scope = _client.backendScope;
    final resp = await _client.post(
      '/auth/login',
      body: {'phone': username, 'password': password},
    );
    if (resp.statusCode != 200) {
      throw AccountUnavailableException(
        BackendClient.extractErrorMessage(resp.body) ?? '登录失败',
      );
    }
    final session = await _acceptAuthenticatedSession(
      resp.body,
      scope,
      generation,
    );
    unawaited(retryPendingRevocations());
    return session;
  }

  Future<AuthSession> _acceptAuthenticatedSession(
    String body,
    String scope,
    int generation,
  ) async {
    final session = AuthSession.fromJson(
      Map<String, dynamic>.from(jsonDecode(body) as Map),
    );
    if (generation != _authGeneration ||
        scope.isEmpty ||
        _client.backendScope != scope) {
      throw const AccountUnavailableException('后端地址已变更，请重试');
    }
    _client.setTokens(
      session.token.accessToken,
      session.token.refreshToken ?? '',
    );
    final saved = await _saveSession(
      session,
      scope: scope,
      generation: generation,
    );
    if (!saved ||
        generation != _authGeneration ||
        _client.backendScope != scope ||
        _client.accessToken != session.token.accessToken) {
      if (_client.accessToken == session.token.accessToken) {
        _client.clearTokens();
      }
      throw const AccountUnavailableException('后端地址已变更，请重试');
    }
    return session;
  }

  @override
  Future<void> logout() async {
    _authGeneration++;
    final scope = _client.backendScope;
    final refreshToken = _client.refreshToken;
    _client.clearTokens();
    _onSessionInvalidated?.call();
    await _clearStoredSession(scope: scope, notify: false);
    if (scope.isNotEmpty && refreshToken != null && refreshToken.isNotEmpty) {
      await _enqueueRevocation(scope, refreshToken);
      unawaited(retryPendingRevocations());
    }
  }

  Future<bool> _saveSession(
    AuthSession session, {
    required String scope,
    int? generation,
  }) => _serializeCredentialStoreResult(() async {
    if ((generation != null && generation != _authGeneration) ||
        _client.backendScope != scope) {
      return false;
    }
    await _secretStore.write(
      accessTokenKeyForScope(scope),
      session.token.accessToken,
    );
    final refreshToken = session.token.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      await _secretStore.delete(refreshTokenKeyForScope(scope));
    } else {
      await _secretStore.write(refreshTokenKeyForScope(scope), refreshToken);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sessionKeyForScope(scope),
      jsonEncode({
        'backendBaseUrl': scope,
        'user': session.user.toJson(),
        if (session.token.expiresAt != null)
          'expiresAt': session.token.expiresAt,
      }),
    );
    if ((generation != null && generation != _authGeneration) ||
        _client.backendScope != scope) {
      await _secretStore.delete(accessTokenKeyForScope(scope));
      await _secretStore.delete(refreshTokenKeyForScope(scope));
      await prefs.remove(_sessionKeyForScope(scope));
      return false;
    }
    return true;
  });

  Future<void> _saveRefreshedTokens(
    String scope,
    String accessToken,
    String refreshToken,
  ) => _serializeCredentialStore(() async {
    if (_client.backendScope != scope ||
        _client.accessToken != accessToken ||
        _client.refreshToken != refreshToken) {
      return;
    }
    await _secretStore.write(refreshTokenKeyForScope(scope), refreshToken);
    await _secretStore.write(accessTokenKeyForScope(scope), accessToken);
  });

  Future<void> _clearSession(String scope) async {
    await _clearStoredSession(scope: scope, notify: true);
  }

  Future<void> _invalidateSession(String scope) async {
    _client.clearTokens();
    await _clearStoredSession(scope: scope, notify: true);
  }

  Future<void> _clearStoredSession({
    required String scope,
    required bool notify,
  }) => _serializeCredentialStore(() async {
    if (notify) _onSessionInvalidated?.call();
    if (scope.isEmpty) return;
    await _secretStore.delete(accessTokenKeyForScope(scope));
    await _secretStore.delete(refreshTokenKeyForScope(scope));
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKeyForScope(scope));
  });

  /// Retries revocations retained exclusively in protected storage.
  Future<void> retryPendingRevocations() {
    return _revocationRetry ??=
        _serializeRevocationStore(_retryPendingRevocations).whenComplete(() {
          _revocationRetry = null;
        });
  }

  Future<void> _retryPendingRevocations() async {
    final pending = await _readPendingRevocations();
    if (pending.isEmpty) return;
    final remaining = <_PendingRevocation>[];
    for (final item in pending) {
      try {
        final response = await _client.revokeRefreshToken(
          backendUrl: item.backendBaseUrl,
          refreshToken: item.refreshToken,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          if (!BackendClient.isCredentialRejectionStatus(response.statusCode)) {
            remaining.add(item);
          }
        }
      } catch (_) {
        remaining.add(item);
      }
    }
    await _writePendingRevocations(remaining);
  }

  Future<void> _enqueueRevocation(String backendBaseUrl, String refreshToken) =>
      _serializeRevocationStore(() async {
        final pending = await _readPendingRevocations();
        final item = _PendingRevocation(backendBaseUrl, refreshToken);
        if (!pending.contains(item)) pending.add(item);
        await _writePendingRevocations(pending);
      });

  Future<List<_PendingRevocation>> _readPendingRevocations() async {
    final raw = await _secretStore.read(pendingRevocationsSecretKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map(
            (item) => _PendingRevocation.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .where(
            (item) =>
                item.backendBaseUrl.isNotEmpty && item.refreshToken.isNotEmpty,
          )
          .toList();
    } catch (_) {
      await _secretStore.delete(pendingRevocationsSecretKey);
      return [];
    }
  }

  Future<void> _writePendingRevocations(
    List<_PendingRevocation> pending,
  ) async {
    if (pending.isEmpty) {
      await _secretStore.delete(pendingRevocationsSecretKey);
      return;
    }
    await _secretStore.write(
      pendingRevocationsSecretKey,
      jsonEncode(pending.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _clearLegacySession() => _serializeCredentialStore(() async {
    await _secretStore.delete(accessTokenSecretKey);
    await _secretStore.delete(refreshTokenSecretKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  });

  Future<void> _serializeCredentialStore(Future<void> Function() operation) {
    final result = _credentialStoreTail.then(
      (_) => operation(),
      onError: (_) => operation(),
    );
    _credentialStoreTail = result.catchError((_) {});
    return result;
  }

  Future<T> _serializeCredentialStoreResult<T>(Future<T> Function() operation) {
    final result = _credentialStoreTail.then(
      (_) => operation(),
      onError: (_) => operation(),
    );
    _credentialStoreTail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _serializeRevocationStore(Future<void> Function() operation) {
    final result = _revocationStoreTail.then(
      (_) => operation(),
      onError: (_) => operation(),
    );
    _revocationStoreTail = result.catchError((_) {});
    return result;
  }

  static String accessTokenKeyForScope(String scope) =>
      '$accessTokenSecretKey.${Uri.encodeComponent(scope)}';

  static String refreshTokenKeyForScope(String scope) =>
      '$refreshTokenSecretKey.${Uri.encodeComponent(scope)}';

  static String sessionKeyForScope(String scope) =>
      '$_sessionKey.${Uri.encodeComponent(scope)}';

  static String _sessionKeyForScope(String scope) => sessionKeyForScope(scope);

  static String? _sessionOrigin(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final value = decoded['backendOrigin'] as String?;
      if (value == null || value.isEmpty) return null;
      final origin = normalizedBackendOrigin(value);
      return origin.isEmpty ? null : origin;
    } catch (_) {
      return null;
    }
  }
}

class _PendingRevocation {
  const _PendingRevocation(this.backendBaseUrl, this.refreshToken);

  factory _PendingRevocation.fromJson(Map<String, dynamic> json) =>
      _PendingRevocation(
        normalizeBackendUri(
          json['backendBaseUrl'] as String? ?? json['origin'] as String? ?? '',
        ),
        json['refreshToken'] as String? ?? '',
      );

  final String backendBaseUrl;
  final String refreshToken;

  Map<String, String> toJson() => {
    'backendBaseUrl': backendBaseUrl,
    'refreshToken': refreshToken,
  };

  @override
  bool operator ==(Object other) =>
      other is _PendingRevocation &&
      other.backendBaseUrl == backendBaseUrl &&
      other.refreshToken == refreshToken;

  @override
  int get hashCode => Object.hash(backendBaseUrl, refreshToken);
}
