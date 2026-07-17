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
import 'package:lynai/services/market_service.dart';

void main() {
  Widget buildPage({MarketService? marketService}) {
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
      child: MaterialApp(home: PluginMarketPage(marketService: marketService)),
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

  testWidgets('loads next market page and removes duplicate IDs', (
    tester,
  ) async {
    final service = _PagedMarketService();
    await tester.pumpWidget(buildPage(marketService: service));
    await tester.pumpAndSettle();

    expect(find.text('Plugin A'), findsOneWidget);
    expect(find.text('加载更多'), findsOneWidget);

    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();

    expect(service.pages, [1, 2]);
    expect(find.text('Plugin A'), findsOneWidget);
    expect(find.text('Plugin B'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
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

class _PagedMarketService implements MarketService {
  final pages = <int>[];

  @override
  bool get isBackendConnected => true;

  @override
  Future<MarketQueryResult> listPlugins(MarketQuery query) async {
    pages.add(query.page);
    if (query.page == 1) {
      return MarketQueryResult(
        entries: [_entry('a', 'Plugin A')],
        hasMore: true,
      );
    }
    return MarketQueryResult(
      entries: [_entry('a', 'Plugin A'), _entry('b', 'Plugin B')],
      hasMore: false,
    );
  }

  MarketPluginEntry _entry(String id, String name) => MarketPluginEntry(
    id: id,
    name: name,
    author: '',
    description: '',
    version: '1.0.0',
    downloadUrl: '/download',
  );

  @override
  Future<List<int>> downloadPlugin(String id) => throw UnimplementedError();

  @override
  Future<MarketPluginEntry> getPluginDetail(String id) =>
      throw UnimplementedError();

  @override
  Future<List<MarketPluginEntry>> getInstalledUpdates() async => const [];
}
