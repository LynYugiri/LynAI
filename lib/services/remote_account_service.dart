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
    final origin = _client.backendOrigin;
    if (origin.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_sessionKeyForOrigin(origin));
    var accessToken = await _secretStore.read(accessTokenKeyForOrigin(origin));
    var refreshToken = await _secretStore.read(
      refreshTokenKeyForOrigin(origin),
    );
    var migratingLegacy = false;
    if ((raw == null || raw.isEmpty) &&
        accessToken == null &&
        refreshToken == null) {
      final legacyRaw = prefs.getString(_sessionKey);
      final legacyOrigin = _sessionOrigin(legacyRaw);
      final defaultOrigin = normalizedBackendOrigin(
        BackendClient.defaultBackendUrl,
      );
      if (legacyOrigin == origin ||
          (legacyOrigin == null && origin == defaultOrigin)) {
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
          origin: origin,
          generation: generation,
        );
        if (!saved) return null;
        await _clearLegacySession();
      }
      if (generation != _authGeneration || _client.backendOrigin != origin) {
        return null;
      }
      _client.setTokens(storedAccess, storedRefresh ?? '');
      return session;
    } catch (_) {
      await _clearStoredSession(origin: origin, notify: false);
      if (migratingLegacy) await _clearLegacySession();
      return null;
    }
  }

  @override
  Future<AccountUser?> getCurrentUser() async =>
      (await loadStoredSession())?.user;

  @override
  Future<AuthSession> register({
    required String username,
    required String password,
    String? displayName,
  }) async {
    final generation = ++_authGeneration;
    final origin = _client.backendOrigin;
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
    return _acceptAuthenticatedSession(resp.body, origin, generation);
  }

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final generation = ++_authGeneration;
    unawaited(retryPendingRevocations());
    final origin = _client.backendOrigin;
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
      origin,
      generation,
    );
    unawaited(retryPendingRevocations());
    return session;
  }

  Future<AuthSession> _acceptAuthenticatedSession(
    String body,
    String origin,
    int generation,
  ) async {
    final session = AuthSession.fromJson(
      Map<String, dynamic>.from(jsonDecode(body) as Map),
    );
    if (generation != _authGeneration ||
        origin.isEmpty ||
        _client.backendOrigin != origin) {
      throw const AccountUnavailableException('后端地址已变更，请重试');
    }
    _client.setTokens(
      session.token.accessToken,
      session.token.refreshToken ?? '',
    );
    final saved = await _saveSession(
      session,
      origin: origin,
      generation: generation,
    );
    if (!saved ||
        generation != _authGeneration ||
        _client.backendOrigin != origin ||
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
    final origin = _client.backendOrigin;
    final refreshToken = _client.refreshToken;
    _client.clearTokens();
    _onSessionInvalidated?.call();
    await _clearStoredSession(origin: origin, notify: false);
    if (origin.isNotEmpty && refreshToken != null && refreshToken.isNotEmpty) {
      await _enqueueRevocation(origin, refreshToken);
      unawaited(retryPendingRevocations());
    }
  }

  Future<bool> _saveSession(
    AuthSession session, {
    required String origin,
    int? generation,
  }) => _serializeCredentialStoreResult(() async {
    if ((generation != null && generation != _authGeneration) ||
        _client.backendOrigin != origin) {
      return false;
    }
    await _secretStore.write(
      accessTokenKeyForOrigin(origin),
      session.token.accessToken,
    );
    final refreshToken = session.token.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      await _secretStore.delete(refreshTokenKeyForOrigin(origin));
    } else {
      await _secretStore.write(refreshTokenKeyForOrigin(origin), refreshToken);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sessionKeyForOrigin(origin),
      jsonEncode({
        'backendOrigin': origin,
        'user': session.user.toJson(),
        if (session.token.expiresAt != null)
          'expiresAt': session.token.expiresAt,
      }),
    );
    if ((generation != null && generation != _authGeneration) ||
        _client.backendOrigin != origin) {
      await _secretStore.delete(accessTokenKeyForOrigin(origin));
      await _secretStore.delete(refreshTokenKeyForOrigin(origin));
      await prefs.remove(_sessionKeyForOrigin(origin));
      return false;
    }
    return true;
  });

  Future<void> _saveRefreshedTokens(
    String origin,
    String accessToken,
    String refreshToken,
  ) => _serializeCredentialStore(() async {
    if (_client.backendOrigin != origin ||
        _client.accessToken != accessToken ||
        _client.refreshToken != refreshToken) {
      return;
    }
    await _secretStore.write(refreshTokenKeyForOrigin(origin), refreshToken);
    await _secretStore.write(accessTokenKeyForOrigin(origin), accessToken);
  });

  Future<void> _clearSession(String origin) async {
    await _clearStoredSession(origin: origin, notify: true);
  }

  Future<void> _clearStoredSession({
    required String origin,
    required bool notify,
  }) => _serializeCredentialStore(() async {
    if (notify) _onSessionInvalidated?.call();
    if (origin.isEmpty) return;
    await _secretStore.delete(accessTokenKeyForOrigin(origin));
    await _secretStore.delete(refreshTokenKeyForOrigin(origin));
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKeyForOrigin(origin));
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
          backendUrl: item.origin,
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

  Future<void> _enqueueRevocation(String origin, String refreshToken) =>
      _serializeRevocationStore(() async {
        final pending = await _readPendingRevocations();
        final item = _PendingRevocation(origin, refreshToken);
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
            (item) => item.origin.isNotEmpty && item.refreshToken.isNotEmpty,
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

  static String accessTokenKeyForOrigin(String origin) =>
      '$accessTokenSecretKey.${Uri.encodeComponent(origin)}';

  static String refreshTokenKeyForOrigin(String origin) =>
      '$refreshTokenSecretKey.${Uri.encodeComponent(origin)}';

  static String sessionKeyForOrigin(String origin) =>
      '$_sessionKey.${Uri.encodeComponent(origin)}';

  static String _sessionKeyForOrigin(String origin) =>
      sessionKeyForOrigin(origin);

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
  const _PendingRevocation(this.origin, this.refreshToken);

  factory _PendingRevocation.fromJson(Map<String, dynamic> json) =>
      _PendingRevocation(
        normalizedBackendOrigin(json['origin'] as String? ?? ''),
        json['refreshToken'] as String? ?? '',
      );

  final String origin;
  final String refreshToken;

  Map<String, String> toJson() => {
    'origin': origin,
    'refreshToken': refreshToken,
  };

  @override
  bool operator ==(Object other) =>
      other is _PendingRevocation &&
      other.origin == origin &&
      other.refreshToken == refreshToken;

  @override
  int get hashCode => Object.hash(origin, refreshToken);
}
