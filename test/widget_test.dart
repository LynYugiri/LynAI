import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:lynai/main.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/settings_provider.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ConversationProvider()),
          ChangeNotifierProvider(create: (_) => ModelConfigProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const LynAIApp(),
      ),
    );
    // Wait for async data loading in initState
    await tester.pump();
    expect(find.byType(LynAIApp), findsOneWidget);
  });
}
