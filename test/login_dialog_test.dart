import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/account.dart';
import 'package:lynai/providers/account_provider.dart';
import 'package:lynai/services/account_service.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/widgets/login_dialog.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('successful login closes the dialog', (tester) async {
    final account = AccountProvider(service: _TestAccountService());
    final backend = BackendClient();
    addTearDown(account.dispose);
    addTearDown(backend.dispose);

    await _pumpDialog(tester, account: account, backend: backend);
    await tester.enterText(find.byType(TextFormField).at(0), '13800001111');
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginDialog), findsNothing);
    expect(account.isLoggedIn, isTrue);
  });

  testWidgets('successful registration closes the dialog', (tester) async {
    final account = AccountProvider(service: _TestAccountService());
    final backend = BackendClient();
    addTearDown(account.dispose);
    addTearDown(backend.dispose);

    await _pumpDialog(
      tester,
      account: account,
      backend: backend,
      initialRegisterMode: true,
    );
    await tester.enterText(find.byType(TextFormField).at(0), '13800002222');
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.enterText(find.byType(TextFormField).at(2), 'password');
    await tester.tap(find.widgetWithText(FilledButton, '注册'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginDialog), findsNothing);
    expect(account.isLoggedIn, isTrue);
  });

  testWidgets('failed login keeps the dialog open', (tester) async {
    final account = AccountProvider(service: _TestAccountService(fail: true));
    final backend = BackendClient();
    addTearDown(account.dispose);
    addTearDown(backend.dispose);

    await _pumpDialog(tester, account: account, backend: backend);
    await tester.enterText(find.byType(TextFormField).at(0), '13800003333');
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.byType(LoginDialog), findsOneWidget);
    expect(find.textContaining('登录失败'), findsOneWidget);
    expect(account.isLoggedIn, isFalse);
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required AccountProvider account,
  required BackendClient backend,
  bool initialRegisterMode = false,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: account),
        ChangeNotifierProvider.value(value: backend),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    LoginDialog(initialRegisterMode: initialRegisterMode),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

class _TestAccountService implements AccountService {
  _TestAccountService({this.fail = false});

  final bool fail;

  @override
  bool get isBackendConnected => true;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async => _session(username);

  @override
  Future<AuthSession> register({
    required String username,
    required String password,
    String? displayName,
  }) async => _session(username, displayName: displayName);

  AuthSession _session(String username, {String? displayName}) {
    if (fail) throw StateError('登录失败');
    return AuthSession(
      user: AccountUser(
        id: 'user-1',
        phone: username,
        displayName: displayName ?? 'Test User',
      ),
      token: const AuthToken(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      ),
    );
  }

  @override
  Future<AccountUser?> getCurrentUser() async => null;

  @override
  Future<AuthSession?> loadStoredSession() async => null;

  @override
  Future<void> logout() async {}
}
