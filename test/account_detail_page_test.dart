import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/account.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/onboarding/onboarding_input.dart';
import 'package:lynai/pages/account_detail_page.dart';
import 'package:lynai/pages/onboarding/onboarding_page.dart';
import 'package:lynai/providers/account_provider.dart';
import 'package:lynai/services/account_service.dart';
import 'package:lynai/widgets/account_header_card.dart';
import 'package:provider/provider.dart';

import 'support/memory_repositories.dart';

void main() {
  testWidgets('clicking the logged-in account card opens account details', (
    tester,
  ) async {
    final account = AccountProvider(service: _FakeAccountService());
    await account.restoreLocalSession();
    addTearDown(account.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: account,
        child: const MaterialApp(home: Scaffold(body: AccountHeaderCard())),
      ),
    );

    expect(find.text('退出登录'), findsNothing);
    await tester.tap(find.text('Old Name'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountDetailPage), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('账号详情'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'Old Name');
  });

  testWidgets(
    'account details saves a new username and logs out at the bottom',
    (tester) async {
      final service = _FakeAccountService();
      final account = AccountProvider(service: service);
      await account.restoreLocalSession();
      addTearDown(account.dispose);
      final models = memoryModelConfigProvider();
      addTearDown(models.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: account),
            ChangeNotifierProvider.value(value: models),
          ],
          child: const MaterialApp(home: AccountDetailPage()),
        ),
      );

      await tester.enterText(find.byType(TextField), 'New Name');
      await tester.tap(find.text('保存用户名'));
      await tester.pumpAndSettle();

      expect(service.updatedNames, ['New Name']);
      expect(account.user?.displayName, 'New Name');
      expect(find.text('用户名已更新'), findsOneWidget);

      await tester.tap(find.text('退出登录'));
      await tester.pumpAndSettle();

      expect(account.user, isNull);
      expect(find.text('未登录'), findsOneWidget);
    },
  );

  testWidgets('onboarding name question prefills the logged-in username', (
    tester,
  ) async {
    final account = AccountProvider(service: _FakeAccountService());
    await account.restoreLocalSession();
    addTearDown(account.dispose);
    final settings = memorySettingsProvider();
    addTearDown(settings.dispose);
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(
        onboardingInputJson: jsonEncode(
          OnboardingInput(
            userName: '旧名字',
            purposes: const ['chat'],
            updatedAt: DateTime.now(),
          ).toJson(),
        ),
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: account),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: const MaterialApp(home: OnboardingPage()),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, 'Old Name');
  });
}

final class _FakeAccountService implements AccountService {
  final List<String> updatedNames = [];

  @override
  bool get isBackendConnected => true;

  @override
  Future<AuthSession?> loadStoredSession() async => AuthSession(
    user: const AccountUser(
      id: 'user-1',
      phone: '13800001111',
      displayName: 'Old Name',
    ),
    token: const AuthToken(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    ),
  );

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

  @override
  Future<AccountUser> updateDisplayName(String displayName) async {
    updatedNames.add(displayName);
    return AccountUser(
      id: 'user-1',
      phone: '13800001111',
      displayName: displayName,
    );
  }

  @override
  Future<AccountUser?> getCurrentUser() async => null;
}
