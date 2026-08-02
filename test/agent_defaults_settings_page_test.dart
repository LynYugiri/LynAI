import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/pages/agent_defaults_settings_page.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';
import 'package:provider/provider.dart';

import 'support/memory_repositories.dart';

void main() {
  testWidgets('conversation permissions page edits only new-chat defaults', (
    tester,
  ) async {
    final settings = memorySettingsProvider();
    await settings.replaceSettings(
      AppSettings.defaults().copyWith(
        agentEnabledByDefault: false,
        agentGrantedPermissions: const [LynAIPermissions.notesRead],
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(home: AgentDefaultsSettingsPage()),
      ),
    );

    expect(find.text('对话权限'), findsOneWidget);
    expect(find.text('新对话默认启用 Agent'), findsOneWidget);
    expect(find.text('新对话默认权限'), findsOneWidget);
    expect(find.text('读取回收站'), findsNothing);
    expect(find.text('写入回收站'), findsNothing);
    expect(find.text('恢复回收站项目'), findsNothing);

    await tester.tap(find.text('新对话默认启用 Agent'));
    await tester.pump();
    expect(settings.settings.agentEnabledByDefault, isTrue);
    expect(settings.settings.agentGrantedPermissions, const [
      LynAIPermissions.notesRead,
    ]);

    await tester.scrollUntilVisible(
      find.text('访问网络'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('访问网络'));
    await tester.pump();
    expect(settings.settings.agentEnabledByDefault, isTrue);
    expect(settings.settings.agentGrantedPermissions, const [
      LynAIPermissions.notesRead,
      LynAIPermissions.networkAccess,
    ]);
    await settings.flushPendingSaves();
  });
}
