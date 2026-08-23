import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/account.dart';
import 'package:lynai/pages/settings_page.dart';
import 'package:lynai/providers/account_provider.dart';
import 'package:lynai/providers/recycle_bin_provider.dart';
import 'package:lynai/services/account_service.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:provider/provider.dart';

import 'support/memory_repositories.dart';

void main() {
  testWidgets('settings search filters items by title, subtitle and section', (
    tester,
  ) async {
    await _pumpSettingsPage(tester);

    expect(find.text('关于'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'BlueLM');
    await tester.pump();

    expect(find.text('本地模型'), findsOneWidget);
    expect(find.text('关于'), findsNothing);

    await tester.enterText(find.byType(TextField), 'mcp');
    await tester.pump();

    expect(find.text('MCP 服务'), findsOneWidget);
    expect(find.text('本地模型'), findsNothing);
    expect(find.text('插件能力'), findsNothing);

    await tester.enterText(find.byType(TextField), '插件');
    await tester.pump();

    expect(find.byKey(const ValueKey('settings-section-插件')), findsOneWidget);
    expect(find.text('插件配置'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '不存在的设置项');
    await tester.pump();

    expect(find.textContaining('未找到'), findsOneWidget);
    expect(find.text('MCP 服务'), findsNothing);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    expect(find.text('关于'), findsOneWidget);
    expect(find.textContaining('未找到'), findsNothing);
  });

  testWidgets('settings page groups related items under sections', (
    tester,
  ) async {
    await _pumpSettingsPage(tester);

    expect(find.text('外观'), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '插件');
    await tester.pump();

    expect(find.byKey(const ValueKey('settings-section-插件')), findsOneWidget);
    expect(find.text('插件配置'), findsOneWidget);
    expect(find.text('插件能力'), findsOneWidget);
  });
}

Future<void> _pumpSettingsPage(WidgetTester tester) async {
  final account = AccountProvider(service: _NoSessionAccountService());
  final settings = memorySettingsProvider();
  final recycleBin = RecycleBinProvider(
    repository: MemoryRecycleBinRepository(),
  );
  final backend = BackendClient()..configure('https://api.example.com');
  addTearDown(() {
    account.dispose();
    settings.dispose();
    recycleBin.dispose();
    backend.dispose();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: account),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: recycleBin),
        ChangeNotifierProvider.value(value: backend),
      ],
      child: const MaterialApp(home: SettingsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

final class _NoSessionAccountService implements AccountService {
  @override
  bool get isBackendConnected => true;

  @override
  Future<AccountUser?> getCurrentUser() async => null;

  @override
  Future<AuthSession?> loadStoredSession() async => null;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<AuthSession> register({
    required String username,
    required String password,
    String? displayName,
  }) => throw UnimplementedError();

  @override
  Future<AccountUser> updateDisplayName(String displayName) =>
      throw UnimplementedError();
}
