import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/web_search.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('app defaults serialize new-conversation and search policy', () {
    final settings = AppSettings.defaults().copyWith(
      agentEnabledByDefault: true,
      agentGrantedPermissions: const [LynAIPermissions.networkAccess],
      webSearchRoute: WebSearchRoute.client,
      webSearchClientProvider: WebSearchClientProvider.searxng,
      searxngEndpoint: 'https://search.example/search',
      searxngAllowHttp: true,
    );

    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.agentEnabledByDefault, isTrue);
    expect(
      restored.agentGrantedPermissions,
      contains(LynAIPermissions.networkAccess),
    );
    expect(restored.webSearchRoute, WebSearchRoute.client);
    expect(restored.webSearchClientProvider, WebSearchClientProvider.searxng);
    expect(restored.searxngEndpoint, 'https://search.example/search');
    expect(restored.searxngAllowHttp, isTrue);
  });

  test(
    'conversation permissions and snapshot version are always serialized',
    () {
      final json = ConversationSettings(
        modelId: 'model',
        agentGrantedPermissions: const [],
      ).toJson();

      expect(
        json['permissionSnapshotVersion'],
        AgentPermissionSnapshot.currentVersion,
      );
      expect(json, containsPair('agentGrantedPermissions', const <String>[]));
    },
  );

  test(
    'legacy permission snapshots migrate to inherit and stay idempotent',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_conversation_permission_',
      );
      final storage = StorageV2Service(rootDirectory: root);
      try {
        await StorageV2UpgradeService(storageV2: storage).ensureReady();
        final now = DateTime.utc(2026, 7, 28).toIso8601String();
        await storage.writeDataFile('conversations.json', {
          'conversations': [
            {
              'id': 'legacy',
              'title': 'Legacy',
              'modelId': 'model',
              'settings': {
                'modelId': 'model',
                'agentGrantedPermissions': [LynAIPermissions.notesWrite],
              },
              'roleId': 'default',
              'createdAt': now,
              'updatedAt': now,
            },
            {
              'id': 'customized',
              'title': 'Customized',
              'modelId': 'model',
              'settings': {
                'modelId': 'model',
                'permissionSnapshotVersion':
                    AgentPermissionSnapshot.currentVersion,
                'agentPermissionsOverride': true,
                'agentGrantedPermissions': [LynAIPermissions.notesWrite],
              },
              'roleId': 'default',
              'createdAt': now,
              'updatedAt': now,
            },
            {
              'id': 'mirror',
              'title': 'Mirror',
              'modelId': 'model',
              'settings': {
                'modelId': 'model',
                'permissionSnapshotVersion':
                    AgentPermissionSnapshot.currentVersion,
                'agentGrantedPermissions': [
                  LynAIPermissions.networkAccess,
                  LynAIPermissions.todosRead,
                ],
              },
              'roleId': 'default',
              'createdAt': now,
              'updatedAt': now,
            },
          ],
          'messages': const [],
          'messageAttachments': const [],
        });
        final provider = ConversationProvider(storageV2: storage);
        await provider.loadConversations();
        expect(
          provider
              .getConversation('legacy')!
              .settings
              .permissionSnapshotVersion,
          0,
        );

        const defaults = [
          LynAIPermissions.todosRead,
          LynAIPermissions.networkAccess,
        ];
        expect(
          await provider.migrateLegacyPermissionSnapshots(defaults),
          isTrue,
        );

        // v0 历史数据直接转为跟随全局，列表写入当前全局镜像。
        final legacy = provider.getConversation('legacy')!.settings;
        expect(legacy.permissionSnapshotVersion,
            AgentPermissionSnapshot.currentVersion);
        expect(legacy.agentPermissionsOverride, isFalse);
        expect(legacy.agentGrantedPermissions, defaults);

        // 已显式自定义的对话保持覆盖，不动。
        final customized = provider.getConversation('customized')!.settings;
        expect(customized.agentPermissionsOverride, isTrue);
        expect(customized.agentGrantedPermissions, const [
          LynAIPermissions.notesWrite,
        ]);

        // v1 且列表与全局一致（无 override 字段的旧数据）自动转为继承。
        final mirror = provider.getConversation('mirror')!.settings;
        expect(mirror.agentPermissionsOverride, isFalse);

        // 幂等：再次迁移无变化。
        expect(
          await provider.migrateLegacyPermissionSnapshots(const [
            LynAIPermissions.deviceControl,
          ]),
          isFalse,
        );
        await provider.flushPendingSaves();
        await storage.close();

        final db = sqlite3.open('${root.path}/storage_v2/app.db');
        try {
          final rows = db.select(
            'SELECT id, settings_json FROM conversations ORDER BY id',
          );
          final byId = {
            for (final row in rows) row['id'] as String: row['settings_json'] as String,
          };
          final legacyJson =
              jsonDecode(byId['legacy']!) as Map<String, dynamic>;
          expect(
            legacyJson['permissionSnapshotVersion'],
            AgentPermissionSnapshot.currentVersion,
          );
          expect(legacyJson['agentPermissionsOverride'], isFalse);
          expect(legacyJson['agentGrantedPermissions'], defaults);
          final mirrorJson =
              jsonDecode(byId['mirror']!) as Map<String, dynamic>;
          expect(mirrorJson['agentPermissionsOverride'], isFalse);
          final customizedJson =
              jsonDecode(byId['customized']!) as Map<String, dynamic>;
          expect(customizedJson['agentPermissionsOverride'], isTrue);
        } finally {
          db.close();
        }
        provider.dispose();
      } finally {
        await storage.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );
}
