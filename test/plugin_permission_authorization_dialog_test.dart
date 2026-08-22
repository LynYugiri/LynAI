import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lynai/models/plugin.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';
import 'package:lynai/widgets/plugin_permission_authorization_dialog.dart';

void main() {
  testWidgets('install permission dialog preselects all and supports 全选', (
    tester,
  ) async {
    final plugin = InstalledPlugin(
      manifest: PluginManifest.fromJson(const {
        'id': 'sample',
        'name': 'Sample',
        'entry': 'main.lua',
        'permissions': [
          LynAIPermissions.networkPublic,
          LynAIPermissions.notesRead,
          LynAIPermissions.networkAccess,
        ],
      }),
      path: '/tmp/sample',
      enabled: false,
      grantedPermissions: const [],
      enabledFeaturePages: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PluginPermissionAuthorizationDialog(
          plugin: plugin,
          sensitivePermissions: const [
            LynAIPermissions.notesRead,
            LynAIPermissions.networkAccess,
          ],
          autoGrantedPermissions: const [LynAIPermissions.networkPublic],
        ),
      ),
    );

    expect(find.text('授权「Sample」权限'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    final selectAll = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, '全选'),
    );
    expect(selectAll.value, isTrue);
    expect(find.text('已选 2/2 项'), findsOneWidget);
    expect(find.text('允许所选（2）'), findsOneWidget);
    expect(find.text('自动授予：访问公开网络'), findsOneWidget);

    // 先取消全选，保存按钮应禁用；再重新全选后恢复。
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(find.text('已选 0/2 项'), findsOneWidget);
    final disabledSave = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '允许所选（0）'),
    );
    expect(disabledSave.onPressed, isNull);

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    expect(find.text('已选 2/2 项'), findsOneWidget);
    final enabledSave = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '允许所选（2）'),
    );
    expect(enabledSave.onPressed, isNotNull);
  });
}
