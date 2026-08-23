import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/account.dart';
import 'package:lynai/pages/api_models_page.dart';
import 'package:lynai/pages/appearance_settings_page.dart';
import 'package:lynai/pages/data_settings_page.dart';
import 'package:lynai/pages/plugin_settings_page.dart';
import 'package:lynai/pages/settings_page.dart';
import 'package:lynai/pages/wizard_settings_page.dart';
import 'package:lynai/providers/account_provider.dart';
import 'package:lynai/providers/recycle_bin_provider.dart';
import 'package:lynai/services/account_service.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:provider/provider.dart';

import 'support/memory_repositories.dart';

void main() {
  testWidgets('settings search also matches items nested in subpages', (
    tester,
  ) async {
    await _pumpSettingsPage(tester);

    expect(find.text('关于'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'BlueLM');
    await tester.pump();

    expect(find.text('模型与接口'), findsOneWidget);
    expect(find.text('关于'), findsNothing);
    expect(find.text('本地模型'), findsNothing);

    await tester.enterText(find.byType(TextField), '插件配置');
    await tester.pump();

    expect(_cardText('插件'), findsOneWidget);
    expect(_cardText('插件配置'), findsNothing);

    await tester.enterText(find.byType(TextField), '回收站');
    await tester.pump();

    expect(find.text('数据'), findsOneWidget);
    expect(_cardText('回收站'), findsNothing);

    await tester.enterText(find.byType(TextField), '不存在的设置项');
    await tester.pump();

    expect(find.textContaining('未找到'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    expect(find.text('关于'), findsOneWidget);
    expect(find.textContaining('未找到'), findsNothing);
  });

  testWidgets('settings page only keeps consolidated top-level entries', (
    tester,
  ) async {
    await _pumpSettingsPage(tester);

    await tester.enterText(find.byType(TextField), '主题');
    await tester.pump();
    expect(find.text('外观'), findsOneWidget);
    expect(_cardText('主题'), findsNothing);

    await tester.enterText(find.byType(TextField), 'MCP 服务');
    await tester.pump();
    expect(find.text('模型与接口'), findsOneWidget);
    expect(_cardText('MCP 服务'), findsNothing);
  });

  testWidgets('appearance page shows theme and background entries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => memorySettingsProvider(),
          child: const AppearanceSettingsPage(),
        ),
      ),
    );

    expect(find.text('主题'), findsOneWidget);
    expect(find.text('背景'), findsOneWidget);
  });

  testWidgets('wizard page shows onboarding and guided tour entries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => memorySettingsProvider(),
          child: const WizardSettingsPage(),
        ),
      ),
    );

    expect(find.text('新手向导'), findsOneWidget);
    expect(find.text('功能引导'), findsOneWidget);
  });

  testWidgets('plugin page shows plugin configuration entries', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PluginSettingsPage()));

    expect(find.text('插件配置'), findsOneWidget);
    expect(find.text('插件能力'), findsOneWidget);
    expect(find.text('插件工坊'), findsOneWidget);
  });

  testWidgets('data page shows data management entries', (tester) async {
    final recycleBin = RecycleBinProvider(
      repository: MemoryRecycleBinRepository(),
    );
    addTearDown(recycleBin.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: recycleBin,
        child: const MaterialApp(home: DataSettingsPage()),
      ),
    );

    expect(find.text('数据管理'), findsOneWidget);
    expect(find.text('回收站'), findsOneWidget);
    expect(find.text('局域网配对与同步'), findsOneWidget);
  });

  testWidgets('model page keeps four categories and gains related entries', (
    tester,
  ) async {
    final models = memoryModelConfigProvider();
    addTearDown(models.dispose);
    final settings = memorySettingsProvider();
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: models),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: const MaterialApp(home: ApiModelsPage()),
      ),
    );
    await tester.pump();

    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('OCR'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();

    expect(find.text('本地模型'), findsOneWidget);
    expect(find.text('网页搜索'), findsOneWidget);
    expect(find.text('MCP 服务'), findsOneWidget);
  });
}

Finder _cardText(String text) {
  return find.descendant(of: find.byType(Card), matching: find.text(text));
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
