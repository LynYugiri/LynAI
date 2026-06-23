import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:lynai/main.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/recycle_bin_provider.dart';
import 'package:lynai/providers/roleplay_provider.dart';
import 'package:lynai/providers/settings_provider.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ConversationProvider()),
          ChangeNotifierProvider(create: (_) => FeatureProvider()),
          ChangeNotifierProvider(create: (_) => ModelConfigProvider()),
          ChangeNotifierProvider(create: (_) => PluginProvider()),
          ChangeNotifierProvider(create: (_) => RecycleBinProvider()),
          ChangeNotifierProvider(create: (_) => RoleplayProvider()),
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
  });
}
