import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lynai/models/account.dart';
import 'package:lynai/providers/account_provider.dart';
import 'package:lynai/services/account_service.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/remote_account_service.dart';
import 'package:lynai/services/secret_store.dart';

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
      var enrollmentCalls = 0;
      final provider = AccountProvider(
        service: _MockAccountService(),
        afterAuthenticated: () async => enrollmentCalls++,
      );
      var notifyCount = 0;
      provider.addListener(() => notifyCount++);

      final success = await provider.login('13800001111', '');

      expect(success, isTrue);
      expect(provider.isLoggedIn, isTrue);
      expect(provider.user?.phone, '13800001111');
      expect(provider.user?.displayName, 'TestUser');
      expect(provider.loading, isFalse);
      expect(provider.error, isNull);
      expect(enrollmentCalls, 1);
      expect(notifyCount, greaterThanOrEqualTo(2));
    });

    test('login binds local session before background activation', () async {
      final calls = <String>[];
      final activated = Completer<void>();
      final provider = AccountProvider(
        service: _MockAccountService(),
        afterAuthenticated: () async => calls.add('enroll'),
        onSessionChanged: (user) async {
          if (user != null) calls.add('bind');
        },
        onRemoteActivation: (_) async => activated.complete(),
      );

      expect(await provider.login('13800001111', 'password'), isTrue);
      expect(calls.first, 'bind');
      await activated.future;
      expect(calls, ['bind', 'enroll']);
    });

    test('login activates dataset before publishing user', () async {
      final calls = <String>[];
      late final AccountProvider provider;
      provider = AccountProvider(
        service: _MockAccountService(),
        onDatasetActivation: (user) async {
          expect(provider.user, isNull);
          calls.add('dataset:${user?.id}');
        },
        onSessionChanged: (user) async => calls.add('session:${user?.id}'),
      );

      expect(await provider.login('13800001111', 'password'), isTrue);
      expect(calls, ['dataset:1', 'session:1']);
    });

    test('failed target activation leaves previous user unpublished', () async {
      final provider = AccountProvider(
        service: _MockAccountService(),
        onDatasetActivation: (_) async => throw StateError('bad dataset'),
      );

      expect(await provider.login('13800001111', 'password'), isFalse);
      expect(provider.user, isNull);
      expect(provider.error, contains('bad dataset'));
    });

    test(
      'backend reconfiguration awaits persistence then session teardown',
      () async {
        final backend = BackendClient()..configure('https://old.example');
        final calls = <String>[];
        final provider = AccountProvider(
          backend: backend,
          secretStore: InMemorySecretStore(),
          onDatasetActivation: (_) async => calls.add('dataset'),
          onSessionChanged: (_) async => calls.add('session'),
        );

        await provider.reconfigureBackend(
          url: 'https://new.example/api',
          persist: (url) async => calls.add('persist:$url'),
        );

        expect(calls, [
          'persist:https://new.example/api',
          'dataset',
          'session',
        ]);
        expect(backend.backendUrl, 'https://new.example/api');
        backend.dispose();
      },
    );

    test(
      'failed enrollment keeps login and still starts session callback',
      () async {
        var sessionCallbacks = 0;
        final provider = AccountProvider(
          service: _MockAccountService(),
          afterAuthenticated: () async => throw StateError('old backend'),
          onSessionChanged: (user) async {
            if (user != null) sessionCallbacks++;
          },
        );

        expect(await provider.login('13800001111', 'password'), isTrue);
        expect(provider.isLoggedIn, isTrue);
        expect(provider.error, isNull);
        expect(sessionCallbacks, 1);
      },
    );

    test('logout clears user', () async {
      final provider = AccountProvider(service: _MockAccountService());
      await provider.login('13800001111', '');
      expect(provider.isLoggedIn, isTrue);

      await provider.logout();

      expect(provider.isLoggedIn, isFalse);
      expect(provider.user, isNull);
    });

    test(
      'logout activation failure preserves authenticated publication',
      () async {
        var failLocalActivation = false;
        final provider = AccountProvider(
          service: _MockAccountService(),
          onDatasetActivation: (user) async {
            if (user == null && failLocalActivation) {
              throw StateError('local unavailable');
            }
          },
        );
        await provider.login('13800001111', '');
        failLocalActivation = true;

        await provider.logout();

        expect(provider.user, isNotNull);
        expect(provider.isLoggedIn, isTrue);
        expect(provider.loading, isFalse);
        expect(provider.error, contains('local unavailable'));
      },
    );

    test('local session restore does not wait for remote refresh', () async {
      final service = _SplitRecoveryAccountService();
      final provider = AccountProvider(service: service);

      await provider.restoreLocalSession();

      expect(provider.user?.displayName, 'Cached');
      expect(service.refreshCalls, 0);
    });

    test('refresh updates the restored user', () async {
      final service = _SplitRecoveryAccountService();
      final provider = AccountProvider(service: service);
      await provider.restoreLocalSession();

      service.refreshResult.complete(
        const AccountUser(
          id: '1',
          phone: '13800001111',
          displayName: 'Current',
          isAdmin: true,
        ),
      );
      await provider.refreshCurrentSession();

      expect(provider.user?.displayName, 'Current');
      expect(provider.user?.isAdmin, isTrue);
      expect(service.refreshCalls, 1);
    });

    test('refresh invalidation activates local before clearing user', () async {
      final service = _SplitRecoveryAccountService();
      final calls = <String>[];
      final provider = AccountProvider(
        service: service,
        onDatasetActivation: (user) async => calls.add('dataset:${user?.id}'),
        onSessionChanged: (user) async => calls.add('session:${user?.id}'),
      );
      await provider.restoreLocalSession();
      calls.clear();
      service.refreshResult.complete(null);

      await provider.refreshCurrentSession();

      expect(provider.user, isNull);
      expect(calls, ['dataset:null', 'session:null']);
    });

    test(
      'refresh invalidation failure keeps the account dataset published',
      () async {
        final service = _SplitRecoveryAccountService();
        final provider = AccountProvider(
          service: service,
          onDatasetActivation: (user) async {
            if (user == null) throw StateError('local unavailable');
          },
        );
        await provider.restoreLocalSession();
        service.refreshResult.complete(null);

        await provider.refreshCurrentSession();

        expect(provider.user?.displayName, 'Cached');
        expect(provider.isLoggedIn, isTrue);
      },
    );

    test('stale refresh cannot overwrite a new login session', () async {
      final service = _SplitRecoveryAccountService();
      final provider = AccountProvider(service: service);
      await provider.restoreLocalSession();

      final refresh = provider.refreshCurrentSession();
      await service.refreshStarted.future;
      expect(await provider.login('13900002222', 'password'), isTrue);
      service.refreshResult.complete(
        const AccountUser(id: '1', phone: '13800001111', displayName: 'Stale'),
      );
      await refresh;

      expect(provider.user?.phone, '13900002222');
      expect(provider.user?.displayName, 'Logged In');
    });

    test('dispose prevents an in-flight restore from publishing', () async {
      final service = _DelayedRestoreAccountService();
      var sessionCallbacks = 0;
      final provider = AccountProvider(
        service: service,
        onSessionChanged: (_) async => sessionCallbacks++,
      );
      var notifyCount = 0;
      provider.addListener(() => notifyCount++);

      final restore = provider.restoreLocalSession();
      await service.restoreStarted.future;
      provider.dispose();
      service.restoreResult.complete(_cachedSession());

      await restore;
      expect(notifyCount, 0);
      expect(sessionCallbacks, 0);
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

    test('logout invalidates an in-flight login', () async {
      final service = _DelayedAccountService();
      final provider = AccountProvider(service: service);

      final login = provider.login('13800001111', 'password');
      await service.loginStarted.future;
      await provider.logout();
      service.loginResult.complete(
        const AuthSession(
          user: AccountUser(
            id: 'late',
            phone: '13800001111',
            displayName: 'Late',
          ),
          token: AuthToken(accessToken: 'late-access'),
        ),
      );

      expect(await login, isFalse);
      expect(provider.user, isNull);
      expect(provider.loading, isFalse);
    });

    test('login invalidated during session callback reports failure', () async {
      final callbackStarted = Completer<void>();
      final releaseCallback = Completer<void>();
      var afterAuthenticatedCalls = 0;
      late AccountProvider provider;
      provider = AccountProvider(
        service: _MockAccountService(),
        onSessionChanged: (user) async {
          if (user == null) return;
          callbackStarted.complete();
          await releaseCallback.future;
        },
        afterAuthenticated: () async => afterAuthenticatedCalls++,
      );

      final login = provider.login('13800001111', 'password');
      await callbackStarted.future;
      await provider.logout();
      releaseCallback.complete();

      expect(await login, isFalse);
      expect(afterAuthenticatedCalls, 0);
      expect(provider.user, isNull);
    });

    test('login does not wait for remote activation', () async {
      final activationStarted = Completer<void>();
      final releaseActivation = Completer<void>();
      final provider = AccountProvider(
        service: _MockAccountService(),
        afterAuthenticated: () async {
          activationStarted.complete();
          await releaseActivation.future;
        },
      );

      expect(await provider.login('13800001111', 'password'), isTrue);
      await activationStarted.future;
      expect(provider.isLoggedIn, isTrue);
      releaseActivation.complete();
    });

    test('current session activation is single-flight', () async {
      final activationStarted = Completer<void>();
      final releaseActivation = Completer<void>();
      var activationCalls = 0;
      final provider = AccountProvider(
        service: _MockAccountService(),
        afterAuthenticated: () async {
          activationCalls++;
          activationStarted.complete();
          await releaseActivation.future;
        },
      );
      expect(await provider.login('13800001111', 'password'), isTrue);
      await activationStarted.future;

      final duplicate = provider.activateCurrentSession();
      expect(activationCalls, 1);
      releaseActivation.complete();
      await duplicate;
      expect(activationCalls, 1);
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

  group('remote account session', () {
    test('refresh persists the new token pair', () async {
      final client = BackendClient(
        client: _AccountClient((request) async {
          if (request.url.path == '/auth/login') {
            return _jsonResponse(200, _sessionJson());
          }
          if (request.url.path == '/auth/refresh') {
            return _jsonResponse(200, {
              'token': {
                'accessToken': 'refreshed-access',
                'refreshToken': 'refreshed-refresh',
              },
            });
          }
          return _jsonResponse(401, {'error': 'expired'});
        }),
      )..configure('http://localhost:8080');
      final secrets = InMemorySecretStore();
      final provider = AccountProvider(backend: client, secretStore: secrets);
      expect(await provider.login('13800001111', 'password'), isTrue);

      expect((await client.get('/protected')).statusCode, 401);

      final stored =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  RemoteAccountService.sessionKeyForScope(client.backendScope),
                )!,
              )
              as Map<String, dynamic>;
      expect(stored['user']['id'], '1');
      expect(stored, isNot(contains('token')));
      expect(
        await secrets.read(
          RemoteAccountService.accessTokenKeyForScope(client.backendScope),
        ),
        'refreshed-access',
      );
      expect(
        await secrets.read(
          RemoteAccountService.refreshTokenKeyForScope(client.backendScope),
        ),
        'refreshed-refresh',
      );
      expect(provider.isLoggedIn, isTrue);
      client.dispose();
    });

    test(
      'failed refresh clears tokens, stored session, and provider user',
      () async {
        final client = BackendClient(
          client: _AccountClient((request) async {
            if (request.url.path == '/auth/login') {
              return _jsonResponse(200, _sessionJson());
            }
            if (request.url.path == '/auth/refresh') {
              return _jsonResponse(401, {'error': 'refresh expired'});
            }
            return _jsonResponse(401, {'error': 'expired'});
          }),
        )..configure('http://localhost:8080');
        final secrets = InMemorySecretStore();
        final provider = AccountProvider(backend: client, secretStore: secrets);
        expect(await provider.login('13800001111', 'password'), isTrue);

        expect((await client.get('/protected')).statusCode, 401);

        expect(client.accessToken, isNull);
        expect(client.refreshToken, isNull);
        expect(provider.isLoggedIn, isFalse);
        expect(
          (await SharedPreferences.getInstance()).getString(
            RemoteAccountService.sessionKeyForScope(client.backendScope),
          ),
          isNull,
        );
        expect(
          await secrets.read(
            RemoteAccountService.accessTokenKeyForScope(client.backendScope),
          ),
          isNull,
        );
        expect(
          await secrets.read(
            RemoteAccountService.refreshTokenKeyForScope(client.backendScope),
          ),
          isNull,
        );
        client.dispose();
      },
    );

    test(
      'legacy SharedPreferences token pair migrates to SecretStore',
      () async {
        SharedPreferences.setMockInitialValues({
          'lynai_account_session': jsonEncode({
            'backendOrigin': 'https://example.com',
            'user': {
              'id': '1',
              'phone': '13800001111',
              'displayName': 'TestUser',
            },
            'token': {
              'accessToken': 'legacy-access',
              'refreshToken': 'legacy-refresh',
              'expiresAt': 1234,
            },
          }),
        });
        final client = BackendClient()..configure('https://example.com');
        final secrets = InMemorySecretStore();
        final service = RemoteAccountService(client, secretStore: secrets);

        final session = await service.loadStoredSession();

        expect(session?.user.displayName, 'TestUser');
        expect(session?.token.accessToken, 'legacy-access');
        expect(session?.token.refreshToken, 'legacy-refresh');
        expect(session?.token.expiresAt, 1234);
        expect(
          await secrets.read(
            RemoteAccountService.accessTokenKeyForScope(client.backendScope),
          ),
          'legacy-access',
        );
        final metadata =
            jsonDecode(
                  (await SharedPreferences.getInstance()).getString(
                    RemoteAccountService.sessionKeyForScope(
                      client.backendScope,
                    ),
                  )!,
                )
                as Map<String, dynamic>;
        expect(metadata['user']['displayName'], 'TestUser');
        expect(metadata['expiresAt'], 1234);
        expect(metadata, isNot(contains('token')));
        client.dispose();
      },
    );

    test('corrupt partial stored session is cleared', () async {
      SharedPreferences.setMockInitialValues({
        'lynai_account_session': jsonEncode({
          'backendOrigin': 'https://example.com',
          'user': {
            'id': '1',
            'phone': '13800001111',
            'displayName': 'TestUser',
          },
        }),
      });
      final client = BackendClient()..configure('https://example.com');
      final secrets = InMemorySecretStore({
        RemoteAccountService.refreshTokenSecretKey: 'orphan-refresh',
      });
      final service = RemoteAccountService(client, secretStore: secrets);

      expect(await service.loadStoredSession(), isNull);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'lynai_account_session',
        ),
        isNull,
      );
      expect(
        await secrets.read(RemoteAccountService.refreshTokenSecretKey),
        isNull,
      );
      client.dispose();
    });

    test('legacy credentials are not adopted by an unrelated origin', () async {
      SharedPreferences.setMockInitialValues({
        'lynai_account_session': jsonEncode({
          'user': {
            'id': '1',
            'phone': '13800001111',
            'displayName': 'TestUser',
          },
          'token': {
            'accessToken': 'legacy-access',
            'refreshToken': 'legacy-refresh',
          },
        }),
      });
      final client = BackendClient()..configure('https://other.example.com');
      final secrets = InMemorySecretStore();
      final service = RemoteAccountService(client, secretStore: secrets);

      expect(await service.loadStoredSession(), isNull);
      expect(client.accessToken, isNull);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'lynai_account_session',
        ),
        isNotNull,
      );
      client.dispose();
    });

    test('sessions are isolated by canonical full backend scope', () async {
      final client = BackendClient(
        client: _AccountClient((request) async {
          if (request.url.path.endsWith('/auth/login')) {
            return _jsonResponse(200, _sessionJson());
          }
          return _jsonResponse(404, {'error': 'not found'});
        }),
      )..configure('https://one.example.com/api');
      final secrets = InMemorySecretStore();
      final service = RemoteAccountService(client, secretStore: secrets);
      await service.login(username: '13800001111', password: 'password');

      client.configure('https://two.example.com');

      expect(await service.loadStoredSession(), isNull);
      expect(client.accessToken, isNull);
      expect(
        await secrets.read(
          RemoteAccountService.accessTokenKeyForScope(
            'https://one.example.com/api',
          ),
        ),
        'initial-access',
      );
      client.dispose();
    });

    test('logout prevents an in-flight remote login from persisting', () async {
      final loginResponse = Completer<http.StreamedResponse>();
      final client = BackendClient(
        client: _AccountClient((request) async {
          if (request.url.path.endsWith('/auth/login')) {
            return loginResponse.future;
          }
          return _jsonResponse(404, {'error': 'not found'});
        }),
      )..configure('https://example.com');
      final secrets = InMemorySecretStore();
      final service = RemoteAccountService(client, secretStore: secrets);

      final login = service.login(username: 'user', password: 'password');
      await service.logout();
      loginResponse.complete(_jsonResponse(200, _sessionJson()));

      await expectLater(login, throwsA(isA<AccountUnavailableException>()));
      expect(client.accessToken, isNull);
      expect(
        await secrets.read(
          RemoteAccountService.accessTokenKeyForScope(client.backendScope),
        ),
        isNull,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          RemoteAccountService.sessionKeyForScope(client.backendScope),
        ),
        isNull,
      );
      client.dispose();
    });

    test(
      'backend switch prevents an in-flight login from persisting',
      () async {
        final loginResponse = Completer<http.StreamedResponse>();
        final client = BackendClient(
          client: _AccountClient((request) async {
            if (request.url.path.endsWith('/auth/login')) {
              return loginResponse.future;
            }
            return _jsonResponse(404, {'error': 'not found'});
          }),
        )..configure('https://old.example.com');
        final oldScope = client.backendScope;
        final secrets = InMemorySecretStore();
        final service = RemoteAccountService(client, secretStore: secrets);

        final login = service.login(username: 'user', password: 'password');
        client.configure('https://new.example.com');
        loginResponse.complete(_jsonResponse(200, _sessionJson()));

        await expectLater(login, throwsA(isA<AccountUnavailableException>()));
        expect(client.accessToken, isNull);
        expect(
          await secrets.read(
            RemoteAccountService.accessTokenKeyForScope(oldScope),
          ),
          isNull,
        );
        expect(
          (await SharedPreferences.getInstance()).getString(
            RemoteAccountService.sessionKeyForScope(oldScope),
          ),
          isNull,
        );
        client.dispose();
      },
    );

    test('logout is local-first and queues transient revocation', () async {
      final revokeResponse = Completer<http.StreamedResponse>();
      final requests = <Uri>[];
      final client = BackendClient(
        client: _AccountClient((request) async {
          requests.add(request.url);
          if (request.url.path.endsWith('/auth/login')) {
            return _jsonResponse(200, _sessionJson());
          }
          if (request.url.path.endsWith('/auth/revoke')) {
            return revokeResponse.future;
          }
          return _jsonResponse(404, {'error': 'not found'});
        }),
      )..configure('https://example.com/api');
      final secrets = InMemorySecretStore();
      final service = RemoteAccountService(client, secretStore: secrets);
      await service.login(username: '13800001111', password: 'password');

      await service.logout().timeout(const Duration(seconds: 1));

      expect(client.accessToken, isNull);
      expect(client.refreshToken, isNull);
      expect(
        await secrets.read(
          RemoteAccountService.accessTokenKeyForScope(client.backendScope),
        ),
        isNull,
      );
      expect(
        await secrets.read(RemoteAccountService.pendingRevocationsSecretKey),
        contains('initial-refresh'),
      );
      expect(
        requests.where((uri) => uri.path.endsWith('/auth/revoke')),
        hasLength(1),
      );
      expect(
        requests.singleWhere((uri) => uri.path.endsWith('/auth/revoke')),
        Uri.parse('https://example.com/api/auth/revoke'),
      );

      revokeResponse.complete(_jsonResponse(503, {'error': 'unavailable'}));
      await service.retryPendingRevocations();
      expect(
        await secrets.read(RemoteAccountService.pendingRevocationsSecretKey),
        contains('initial-refresh'),
      );
      client.dispose();
    });

    test('provider logout awaits one session changed callback', () async {
      final client = BackendClient(
        client: _AccountClient((request) async {
          if (request.url.path.endsWith('/auth/login')) {
            return _jsonResponse(200, _sessionJson());
          }
          if (request.url.path.endsWith('/auth/revoke')) {
            return _jsonResponse(200, const {});
          }
          return _jsonResponse(404, {'error': 'not found'});
        }),
      )..configure('https://example.com');
      final callbackStarted = Completer<void>();
      final releaseCallback = Completer<void>();
      var logoutCallbacks = 0;
      final provider = AccountProvider(
        backend: client,
        secretStore: InMemorySecretStore(),
        onSessionChanged: (user) async {
          if (user != null) return;
          logoutCallbacks++;
          callbackStarted.complete();
          await releaseCallback.future;
        },
      );
      expect(await provider.login('13800001111', 'password'), isTrue);

      var completed = false;
      final logout = provider.logout().whenComplete(() => completed = true);
      await callbackStarted.future;

      expect(logoutCallbacks, 1);
      expect(completed, isFalse);
      expect(provider.user, isNull);
      expect(provider.loading, isFalse);

      releaseCallback.complete();
      await logout;
      expect(logoutCallbacks, 1);
      expect(completed, isTrue);
      client.dispose();
    });

    test('same origin path prefixes do not share stored sessions', () async {
      final client = BackendClient(
        client: _AccountClient((request) async {
          if (request.url.path == '/one/auth/login') {
            return _jsonResponse(200, _sessionJson());
          }
          return _jsonResponse(404, {'error': 'not found'});
        }),
      )..configure('https://example.com/one');
      final secrets = InMemorySecretStore();
      final service = RemoteAccountService(client, secretStore: secrets);
      await service.login(username: '13800001111', password: 'password');

      client.configure('https://example.com/two');

      expect(await service.loadStoredSession(), isNull);
      expect(client.accessToken, isNull);
      expect(
        await secrets.read(
          RemoteAccountService.accessTokenKeyForScope(
            'https://example.com/one',
          ),
        ),
        'initial-access',
      );
      client.dispose();
    });

    test('path-prefixed backend does not adopt origin-only storage', () async {
      final origin = 'https://example.com';
      SharedPreferences.setMockInitialValues({
        RemoteAccountService.sessionKeyForScope(origin): jsonEncode({
          'backendOrigin': origin,
          'user': {
            'id': '1',
            'phone': '13800001111',
            'displayName': 'Origin User',
          },
        }),
      });
      final client = BackendClient()..configure('$origin/api');
      final secrets = InMemorySecretStore({
        RemoteAccountService.accessTokenKeyForScope(origin): 'origin-access',
        RemoteAccountService.refreshTokenKeyForScope(origin): 'origin-refresh',
      });
      final service = RemoteAccountService(client, secretStore: secrets);

      expect(await service.loadStoredSession(), isNull);
      expect(client.accessToken, isNull);
      client.dispose();
    });

    test('account recovery refreshes user through auth me', () async {
      final scope = 'https://example.com/api';
      SharedPreferences.setMockInitialValues({
        RemoteAccountService.sessionKeyForScope(scope): jsonEncode({
          'backendBaseUrl': scope,
          'user': {
            'id': '1',
            'phone': '13800001111',
            'displayName': 'Cached',
            'isAdmin': false,
          },
        }),
      });
      final requests = <Uri>[];
      final client = BackendClient(
        client: _AccountClient((request) async {
          requests.add(request.url);
          if (request.url.path == '/api/auth/me') {
            return _jsonResponse(200, {
              'user': {
                'id': '1',
                'phone': '13800001111',
                'displayName': 'Current',
                'isAdmin': true,
              },
            });
          }
          return _jsonResponse(404, {'error': 'not found'});
        }),
      )..configure(scope);
      final secrets = InMemorySecretStore({
        RemoteAccountService.accessTokenKeyForScope(scope): 'access',
        RemoteAccountService.refreshTokenKeyForScope(scope): 'refresh',
      });
      final provider = AccountProvider(backend: client, secretStore: secrets);

      await provider.load();

      expect(requests, contains(Uri.parse('$scope/auth/me')));
      expect(provider.user?.displayName, 'Current');
      expect(provider.user?.isAdmin, isTrue);
      client.dispose();
    });

    test(
      'account recovery refreshes expired access token before auth me',
      () async {
        final scope = 'https://example.com/api';
        SharedPreferences.setMockInitialValues({
          RemoteAccountService.sessionKeyForScope(scope): jsonEncode({
            'backendBaseUrl': scope,
            'user': {
              'id': '1',
              'phone': '13800001111',
              'displayName': 'Cached',
            },
          }),
        });
        var meCalls = 0;
        final client = BackendClient(
          client: _AccountClient((request) async {
            if (request.url.path == '/api/auth/refresh') {
              return _jsonResponse(200, {
                'token': {
                  'accessToken': 'new-access',
                  'refreshToken': 'new-refresh',
                },
              });
            }
            if (request.url.path == '/api/auth/me') {
              meCalls++;
              if (request.headers['Authorization'] == 'Bearer new-access') {
                return _jsonResponse(200, {
                  'user': {
                    'id': '1',
                    'phone': '13800001111',
                    'displayName': 'Refreshed',
                    'isAdmin': true,
                  },
                });
              }
              return _jsonResponse(401, {'error': 'expired'});
            }
            return _jsonResponse(404, {'error': 'not found'});
          }),
        )..configure(scope);
        final secrets = InMemorySecretStore({
          RemoteAccountService.accessTokenKeyForScope(scope): 'old-access',
          RemoteAccountService.refreshTokenKeyForScope(scope): 'old-refresh',
        });
        final provider = AccountProvider(backend: client, secretStore: secrets);

        await provider.load();

        expect(meCalls, 2);
        expect(provider.user?.displayName, 'Refreshed');
        expect(client.accessToken, 'new-access');
        expect(provider.isLoggedIn, isTrue);
        client.dispose();
      },
    );

    test(
      'account recovery keeps cached session on auth me server error',
      () async {
        final scope = 'https://example.com';
        SharedPreferences.setMockInitialValues({
          RemoteAccountService.sessionKeyForScope(scope): jsonEncode({
            'backendBaseUrl': scope,
            'user': {
              'id': '1',
              'phone': '13800001111',
              'displayName': 'Cached',
            },
          }),
        });
        final client = BackendClient(
          client: _AccountClient(
            (_) async => _jsonResponse(503, {'error': 'unavailable'}),
          ),
        )..configure(scope);
        final secrets = InMemorySecretStore({
          RemoteAccountService.accessTokenKeyForScope(scope): 'access',
          RemoteAccountService.refreshTokenKeyForScope(scope): 'refresh',
        });
        final provider = AccountProvider(backend: client, secretStore: secrets);

        await provider.load();

        expect(provider.user?.displayName, 'Cached');
        expect(client.accessToken, 'access');
        expect(provider.isLoggedIn, isTrue);
        client.dispose();
      },
    );

    test('account recovery clears session after final auth me 401', () async {
      final scope = 'https://example.com';
      SharedPreferences.setMockInitialValues({
        RemoteAccountService.sessionKeyForScope(scope): jsonEncode({
          'backendBaseUrl': scope,
          'user': {'id': '1', 'phone': '13800001111', 'displayName': 'Cached'},
        }),
      });
      final client = BackendClient(
        client: _AccountClient((request) async {
          if (request.url.path == '/auth/refresh') {
            return _jsonResponse(200, {
              'token': {
                'accessToken': 'new-access',
                'refreshToken': 'new-refresh',
              },
            });
          }
          return _jsonResponse(401, {'error': 'unauthorized'});
        }),
      )..configure(scope);
      final secrets = InMemorySecretStore({
        RemoteAccountService.accessTokenKeyForScope(scope): 'old-access',
        RemoteAccountService.refreshTokenKeyForScope(scope): 'old-refresh',
      });
      final provider = AccountProvider(backend: client, secretStore: secrets);

      await provider.load();

      expect(provider.isLoggedIn, isFalse);
      expect(client.accessToken, isNull);
      expect(client.refreshToken, isNull);
      expect(
        (await SharedPreferences.getInstance()).getString(
          RemoteAccountService.sessionKeyForScope(scope),
        ),
        isNull,
      );
      client.dispose();
    });

    test(
      'stale invalidation cannot clear a newer credential generation',
      () async {
        const scope = 'https://example.com';
        SharedPreferences.setMockInitialValues({
          RemoteAccountService.sessionKeyForScope(scope): jsonEncode({
            'backendBaseUrl': scope,
            'user': {
              'id': '1',
              'phone': '13800001111',
              'displayName': 'Cached',
            },
          }),
        });
        final client = BackendClient(
          client: _AccountClient(
            (_) async => _jsonResponse(401, {'error': 'unauthorized'}),
          ),
        )..configure(scope);
        final secrets = _BlockingDeleteSecretStore({
          RemoteAccountService.accessTokenKeyForScope(scope): 'old-access',
        });
        var invalidations = 0;
        final service = RemoteAccountService(
          client,
          secretStore: secrets,
          onSessionInvalidated: () async => invalidations++,
        );
        await service.loadStoredSession();

        final refresh = service.refreshCurrentSession();
        await secrets.deleteStarted.future;
        client.setTokens('new-access', 'new-refresh');
        secrets.allowDelete.complete();
        await refresh;

        expect(invalidations, 0);
        expect(client.accessToken, 'new-access');
        client.dispose();
      },
    );
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

class _BlockingDeleteSecretStore implements SecretStore {
  _BlockingDeleteSecretStore(Map<String, String> values)
    : _values = Map.of(values);

  final Map<String, String> _values;
  final deleteStarted = Completer<void>();
  final allowDelete = Completer<void>();
  bool _blocked = false;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async {
    if (!_blocked) {
      _blocked = true;
      deleteStarted.complete();
      await allowDelete.future;
    }
    _values.remove(key);
  }
}

Map<String, dynamic> _sessionJson() => {
  'user': {'id': '1', 'phone': '13800001111', 'displayName': 'TestUser'},
  'token': {'accessToken': 'initial-access', 'refreshToken': 'initial-refresh'},
};

AuthSession _cachedSession() => const AuthSession(
  user: AccountUser(id: '1', phone: '13800001111', displayName: 'Cached'),
  token: AuthToken(
    accessToken: 'cached-access',
    refreshToken: 'cached-refresh',
  ),
);

http.StreamedResponse _jsonResponse(int statusCode, Map<String, dynamic> body) {
  final encoded = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream.value(encoded),
    statusCode,
    contentLength: encoded.length,
    headers: {'content-type': 'application/json'},
  );
}

class _AccountClient extends http.BaseClient {
  _AccountClient(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _send(request);
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

class _DelayedAccountService implements AccountService {
  final loginStarted = Completer<void>();
  final loginResult = Completer<AuthSession>();

  @override
  bool get isBackendConnected => true;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) {
    if (!loginStarted.isCompleted) loginStarted.complete();
    return loginResult.future;
  }

  @override
  Future<AuthSession> register({
    required String username,
    required String password,
    String? displayName,
  }) => throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<AccountUser?> getCurrentUser() async => null;

  @override
  Future<AuthSession?> loadStoredSession() async => null;
}

class _SplitRecoveryAccountService
    implements AccountService, AccountSessionRecovery {
  final refreshStarted = Completer<void>();
  final refreshResult = Completer<AccountUser?>();
  int refreshCalls = 0;

  @override
  bool get isBackendConnected => true;

  @override
  Future<AuthSession?> loadStoredSession() async => _cachedSession();

  @override
  Future<AuthSession?> restoreLocalSession() => loadStoredSession();

  @override
  Future<AccountUser?> getCurrentUser() => refreshCurrentSession();

  @override
  Future<AccountUser?> refreshCurrentSession() {
    refreshCalls++;
    if (!refreshStarted.isCompleted) refreshStarted.complete();
    return refreshResult.future;
  }

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async => AuthSession(
    user: AccountUser(id: '2', phone: username, displayName: 'Logged In'),
    token: const AuthToken(accessToken: 'new-access'),
  );

  @override
  Future<AuthSession> register({
    required String username,
    required String password,
    String? displayName,
  }) => throw UnimplementedError();

  @override
  Future<void> logout() async {}
}

class _DelayedRestoreAccountService
    implements AccountService, AccountSessionRecovery {
  final restoreStarted = Completer<void>();
  final restoreResult = Completer<AuthSession?>();

  @override
  bool get isBackendConnected => true;

  @override
  Future<AuthSession?> loadStoredSession() {
    restoreStarted.complete();
    return restoreResult.future;
  }

  @override
  Future<AccountUser?> getCurrentUser() async => null;

  @override
  Future<AuthSession?> restoreLocalSession() => loadStoredSession();

  @override
  Future<AccountUser?> refreshCurrentSession() async => null;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<AuthSession> register({
    required String username,
    required String password,
    String? displayName,
  }) => throw UnimplementedError();

  @override
  Future<void> logout() async {}
}
