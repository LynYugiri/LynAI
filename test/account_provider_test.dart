import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lynai/models/account.dart';
import 'package:lynai/providers/account_provider.dart';
import 'package:lynai/services/account_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('AccountProvider with mock service', () {
    test('initial state is logged out', () {
      final provider = AccountProvider(service: _MockAccountService());
      expect(provider.isLoggedIn, isFalse);
      expect(provider.user, isNull);
      expect(provider.loading, isFalse);
      expect(provider.error, isNull);
    });

    test('login sets user and notifies listeners', () async {
      final provider = AccountProvider(service: _MockAccountService());
      var notifyCount = 0;
      provider.addListener(() => notifyCount++);

      final success = await provider.login('13800001111', '');

      expect(success, isTrue);
      expect(provider.isLoggedIn, isTrue);
      expect(provider.user?.phone, '13800001111');
      expect(provider.user?.displayName, 'TestUser');
      expect(provider.loading, isFalse);
      expect(provider.error, isNull);
      expect(notifyCount, greaterThanOrEqualTo(2));
    });

    test('logout clears user', () async {
      final provider = AccountProvider(service: _MockAccountService());
      await provider.login('13800001111', '');
      expect(provider.isLoggedIn, isTrue);

      await provider.logout();

      expect(provider.isLoggedIn, isFalse);
      expect(provider.user, isNull);
    });

    test('register sets user', () async {
      final provider = AccountProvider(service: _MockAccountService());
      final success = await provider.register(
        '13900002222',
        '',
        displayName: 'Alice',
      );

      expect(success, isTrue);
      expect(provider.isLoggedIn, isTrue);
      expect(provider.user?.phone, '13900002222');
      expect(provider.user?.displayName, 'Alice');
    });

    test('clearError clears error and notifies', () async {
      final provider = AccountProvider(service: _ThrowingAccountService());
      await provider.login('user', 'pass');
      expect(provider.error, isNotNull);

      provider.clearError();
      expect(provider.error, isNull);
    });

    test('login without backend returns error', () async {
      final provider = AccountProvider();
      final success = await provider.login('13800001111', '');

      expect(success, isFalse);
      expect(provider.error, contains('未连接后端'));
    });
  });

  group('AccountUser', () {
    test('fromJson tolerates missing fields', () {
      final user = AccountUser.fromJson({'id': 'u1'});
      expect(user.id, 'u1');
      expect(user.phone, '');
      expect(user.displayName, '');
      expect(user.avatarUrl, isNull);
      expect(user.email, isNull);
    });

    test('toJson round-trips', () {
      const user = AccountUser(
        id: 'u1',
        phone: '13800001111',
        displayName: 'Alice',
        email: 'alice@example.com',
      );
      final json = user.toJson();
      final restored = AccountUser.fromJson(json);
      expect(restored.id, 'u1');
      expect(restored.phone, '13800001111');
      expect(restored.displayName, 'Alice');
      expect(restored.email, 'alice@example.com');
    });
  });

  group('AuthToken', () {
    test('fromJson tolerates missing fields', () {
      final token = AuthToken.fromJson({});
      expect(token.accessToken, '');
      expect(token.refreshToken, isNull);
      expect(token.expiresAt, isNull);
    });
  });
}

/// Mock service that returns fake sessions for testing.
class _MockAccountService implements AccountService {
  @override
  bool get isBackendConnected => true;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    return AuthSession(
      user: AccountUser(id: '1', phone: username, displayName: 'TestUser'),
      token: const AuthToken(
        accessToken: 'mock-access',
        refreshToken: 'mock-refresh',
      ),
    );
  }

  @override
  Future<AuthSession> register({
    required String username,
    required String password,
    String? displayName,
  }) async {
    return AuthSession(
      user: AccountUser(
        id: '2',
        phone: username,
        displayName: displayName ?? 'TestUser',
      ),
      token: const AuthToken(
        accessToken: 'mock-access',
        refreshToken: 'mock-refresh',
      ),
    );
  }

  @override
  Future<void> logout() async {}

  @override
  Future<AccountUser?> getCurrentUser() async => null;

  @override
  Future<AuthSession?> loadStoredSession() async => null;
}

/// 总是抛异常的 service，用于测试错误路径。
class _ThrowingAccountService implements AccountService {
  @override
  bool get isBackendConnected => true;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    throw const AccountUnavailableException('测试错误');
  }

  @override
  Future<AuthSession> register({
    required String username,
    required String password,
    String? displayName,
  }) async {
    throw const AccountUnavailableException('测试错误');
  }

  @override
  Future<void> logout() async {}

  @override
  Future<AccountUser?> getCurrentUser() async => null;

  @override
  Future<AuthSession?> loadStoredSession() async => null;
}
