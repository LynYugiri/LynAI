import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:lynai/main.dart';
import 'package:lynai/providers/account_provider.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/recycle_bin_provider.dart';
import 'package:lynai/providers/roleplay_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/providers/sync_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/calendar_platform_bridge.dart';
import 'package:lynai/services/calendar_platform_projection_coordinator.dart';
import 'package:lynai/services/device_identity_service.dart';
import 'package:lynai/services/secret_store.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final conversations = _CountingConversationProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SecretStore>(create: (_) => InMemorySecretStore()),
          Provider(
            create: (ctx) =>
                DeviceIdentityService(secretStore: ctx.read<SecretStore>()),
          ),
          ChangeNotifierProvider(create: (_) => BackendClient()),
          ChangeNotifierProvider<ConversationProvider>(
            create: (_) => conversations,
          ),
          ChangeNotifierProvider(create: (_) => FeatureProvider()),
          ChangeNotifierProvider(create: (_) => CalendarProvider()),
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
          ChangeNotifierProvider(create: (_) => TaskProvider()),
          Provider(create: (_) => const CalendarPlatformBridge()),
          Provider(
            create: (ctx) {
              final coordinator = CalendarPlatformProjectionCoordinator(
                tasks: ctx.read<TaskProvider>(),
                calendar: ctx.read<CalendarProvider>(),
                bridge: ctx.read<CalendarPlatformBridge>(),
              );
              coordinator.attach();
              return coordinator;
            },
            dispose: (_, coordinator) => coordinator.dispose(),
          ),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const LynAIApp(),
      ),
    );

    await tester.pump();

    expect(find.byType(LynAIApp), findsOneWidget);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.supportedLocales, const [
      Locale('zh', 'CN'),
      Locale('en', 'US'),
    ]);
    expect(
      app.localizationsDelegates,
      contains(GlobalMaterialLocalizations.delegate),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(conversations.flushCount, 1);
    conversations.completeFlush();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _CountingConversationProvider extends ConversationProvider {
  final Completer<void> _flush = Completer<void>();
  int flushCount = 0;

  @override
  Future<void> flushPendingSaves() {
    flushCount++;
    return _flush.future;
  }

  void completeFlush() => _flush.complete();
}
