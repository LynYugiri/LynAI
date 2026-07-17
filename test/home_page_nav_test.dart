import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lynai/pages/home_page.dart';
import 'package:lynai/providers/account_provider.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/recycle_bin_provider.dart';
import 'package:lynai/providers/roleplay_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/providers/sync_provider.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/secret_store.dart';

void main() {
  Widget buildHome({AppTab initialTab = AppTab.chat}) {
    return MultiProvider(
      providers: [
        Provider<SecretStore>(create: (_) => InMemorySecretStore()),
        ChangeNotifierProvider(create: (_) => BackendClient()),
        ChangeNotifierProvider(create: (_) => ConversationProvider()),
        ChangeNotifierProvider(create: (_) => FeatureProvider()),
        ChangeNotifierProvider(create: (_) => ModelConfigProvider()),
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
        ChangeNotifierProvider(create: (_) => RecycleBinProvider()),
        ChangeNotifierProvider(create: (_) => RoleplayProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(home: HomePage(initialTab: initialTab)),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders all five tab labels', (tester) async {
    await tester.pumpWidget(buildHome());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final navBar = find.byType(NavigationBar);
    for (final label in ['功能', '插件市场', '对话', '社区', '设置']) {
      expect(
        find.descendant(of: navBar, matching: find.text(label)),
        findsOneWidget,
      );
    }
  });

  testWidgets('default tab is chat', (tester) async {
    await tester.pumpWidget(buildHome());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, AppTab.chat.index);
  });

  testWidgets('tapping market tab switches selectedIndex', (tester) async {
    await tester.pumpWidget(buildHome());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final navBar = find.byType(NavigationBar);
    await tester.tap(find.descendant(of: navBar, matching: find.text('插件市场')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, AppTab.market.index);
  });

  testWidgets('tapping settings tab switches selectedIndex', (tester) async {
    await tester.pumpWidget(buildHome());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final navBar = find.byType(NavigationBar);
    await tester.tap(find.descendant(of: navBar, matching: find.text('设置')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, AppTab.settings.index);
  });

  testWidgets('new placeholder pages are mounted in the stack', (tester) async {
    await tester.pumpWidget(buildHome());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // IndexedStack 会 mount 所有 children，但 find.byType 对非 active index
    // 的 child 存在 quirk（可能跳过 Offstage/Visibility 包裹的子树）。
    // 用 tester.allWidgets 直接遍历 element 树更可靠。
    final marketWidgets = tester.allWidgets
        .where((w) => w.runtimeType.toString() == 'PluginMarketPage')
        .toList();
    final communityWidgets = tester.allWidgets
        .where((w) => w.runtimeType.toString() == 'CommunityPage')
        .toList();

    expect(marketWidgets.length, 1);
    expect(communityWidgets.length, 1);
  });

  testWidgets('initialTab feature is respected', (tester) async {
    await tester.pumpWidget(buildHome(initialTab: AppTab.feature));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, AppTab.feature.index);
  });

  test('AppTab order and indices are stable', () {
    expect(AppTab.values, [
      AppTab.feature,
      AppTab.market,
      AppTab.chat,
      AppTab.community,
      AppTab.settings,
    ]);
    expect(AppTab.feature.index, 0);
    expect(AppTab.market.index, 1);
    expect(AppTab.chat.index, 2);
    expect(AppTab.community.index, 3);
    expect(AppTab.settings.index, 4);
  });
}
