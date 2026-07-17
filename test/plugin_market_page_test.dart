import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lynai/models/plugin_market_entry.dart';
import 'package:lynai/pages/plugin_market_page.dart';
import 'package:lynai/providers/account_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/sync_provider.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/secret_store.dart';

void main() {
  Widget buildPage() {
    return MultiProvider(
      providers: [
        Provider<SecretStore>(create: (_) => InMemorySecretStore()),
        ChangeNotifierProvider(create: (_) => BackendClient()),
        ChangeNotifierProvider(create: (_) => PluginProvider()),
        ChangeNotifierProvider(
          create: (ctx) => AccountProvider(
            backend: ctx.read<BackendClient>(),
            secretStore: ctx.read<SecretStore>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (ctx) => SyncProvider(backend: ctx.read<BackendClient>()),
        ),
      ],
      child: const MaterialApp(home: PluginMarketPage()),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders market and installed tabs', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('市场'), findsWidgets);
    expect(find.text('已安装'), findsWidgets);
  });

  testWidgets('market tab shows empty state when backend not connected', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('尚未连接后端'), findsOneWidget);
    expect(find.text('从 ZIP 导入'), findsOneWidget);
  });

  testWidgets('installed tab shows empty state when no plugins installed', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // 切到「已安装」tab
    await tester.tap(find.text('已安装'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('还没有已安装的插件'), findsOneWidget);
  });

  test('MarketPluginEntry fromJson tolerates missing fields', () {
    final entry = MarketPluginEntry.fromJson({'id': 'test', 'name': 'Test'});
    expect(entry.id, 'test');
    expect(entry.name, 'Test');
    expect(entry.version, '0.0.0');
    expect(entry.author, '');
    expect(entry.permissions, isEmpty);
    expect(entry.screenshots, isEmpty);
  });

  test('MarketQuery isDefault is true for empty query', () {
    const query = MarketQuery();
    expect(query.isDefault, isTrue);
  });

  test('MarketQuery isDefault is false with category', () {
    const query = MarketQuery(category: 'tools');
    expect(query.isDefault, isFalse);
  });
}
