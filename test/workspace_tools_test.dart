import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/providers/workspace_provider.dart';
import 'package:lynai/services/lynai_call_identity.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';
import 'package:lynai/services/tool_call_service.dart';

void main() {
  late Directory root;
  late StorageV2Service storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lynai_workspace_tools_');
    storage = StorageV2Service(rootDirectory: root);
    await StorageV2UpgradeService(storageV2: storage).ensureReady();
  });

  tearDown(() async {
    await storage.close();
    await root.delete(recursive: true);
  });

  test(
    'Agent can create, bind and read/write a workspace in a conversation',
    () async {
      final features = FeatureProvider(storageV2: storage);
      final settings = SettingsProvider(storageV2: storage);
      final conversations = ConversationProvider(storageV2: storage);
      final workspaces = WorkspaceProvider(storageV2: storage);
      await settings.loadSettings();
      await conversations.loadConversations();
      await workspaces.loadWorkspaces();
      final cid = conversations.createConversation(
        ConversationSettings(modelId: 'm1', agentEnabled: true),
      );

      final service = ToolCallService(
        features,
        conversations: conversations,
        workspaces: workspaces,
        settings: settings,
        conversationId: cid,
        permissionSnapshot: settings.settings.agentPermissionSnapshot,
        agentIdentity: LynAICallIdentity(
          type: LynAICallerType.agent,
          conversationId: cid,
        ),
      );

      Set<String> toolNames() => service
          .createRunSnapshot(agentEnabled: true, imageGenerationEnabled: false)
          .openAITools
          .map((tool) => tool['function']?['name']?.toString())
          .whereType<String>()
          .toSet();
      expect(
        toolNames(),
        containsAll({'list_workspaces', 'create_workspace', 'bind_workspace'}),
      );
      expect(toolNames(), isNot(contains('workspace_file_list')));

      final created = await service.execute(
        const ChatToolCall(
          id: 'c1',
          name: 'create_workspace',
          arguments: {
            'name': '插件项目',
            'devPluginIds': ['p-x'],
          },
        ),
        const [],
      );
      // p-x 不存在，应结构化失败而不是创建半成品工作区。
      expect(created['ok'], isFalse);
      expect(workspaces.workspaces, isEmpty);

      final createdOk = await service.execute(
        const ChatToolCall(
          id: 'c2',
          name: 'create_workspace',
          arguments: {'name': '插件项目', 'bindCurrentConversation': true},
        ),
        const [],
      );
      expect(createdOk['ok'], isTrue);
      final workspaceId = (createdOk['result'] as Map)['workspaceId'] as String;
      final bound = conversations.getConversation(cid);
      expect(bound?.workspaceId, workspaceId);
      expect(workspaces.activeWorkspaceId, workspaceId);

      expect(
        toolNames(),
        containsAll({
          'workspace_file_list',
          'workspace_file_read',
          'workspace_file_write',
        }),
      );

      final written = await service.execute(
        const ChatToolCall(
          id: 'c3',
          name: 'workspace_file_write',
          arguments: {'path': 'files/README.md', 'content': '# 项目'},
        ),
        const [],
      );
      expect(written['ok'], isTrue);
      expect(
        workspaces.activeWorkspace!.files.single.originalName,
        'README.md',
      );

      final read = await service.execute(
        const ChatToolCall(
          id: 'c4',
          name: 'workspace_file_read',
          arguments: {'path': 'files/README.md'},
        ),
        const [],
      );
      expect(read['ok'], isTrue);
      expect((read['result'] as Map)['content'], '# 项目');

      final listed = await service.execute(
        const ChatToolCall(id: 'c5', name: 'list_workspaces', arguments: {}),
        const [],
      );
      expect(listed['ok'], isTrue);
      final items = ((listed['result'] as Map)['workspaces'] as List)
          .cast<Map<String, dynamic>>();
      expect(items.single['id'], workspaceId);
      expect(items.single.containsKey('mountedFolderPath'), isFalse);
      expect(items.single['hasMountedFolder'], isFalse);
    },
  );

  test('workspace tools follow conversation permission snapshot', () async {
    final features = FeatureProvider(storageV2: storage);
    final settings = SettingsProvider(storageV2: storage);
    final conversations = ConversationProvider(storageV2: storage);
    final workspaces = WorkspaceProvider(storageV2: storage);
    await settings.loadSettings();
    await conversations.loadConversations();
    await workspaces.loadWorkspaces();
    final workspace = workspaces.createWorkspace(name: '只读项目');
    final cid = conversations.createConversation(
      ConversationSettings(modelId: 'm1', agentEnabled: true),
      workspaceId: workspace.id,
      workspaceName: workspace.name,
    );

    final service = ToolCallService(
      features,
      conversations: conversations,
      workspaces: workspaces,
      settings: settings,
      conversationId: cid,
      permissionSnapshot: AgentPermissionSnapshot(
        permissions: const [LynAIPermissions.workspaceRead],
      ),
      agentIdentity: LynAICallIdentity(
        type: LynAICallerType.agent,
        conversationId: cid,
      ),
    );
    final names = service
        .createRunSnapshot(agentEnabled: true, imageGenerationEnabled: false)
        .openAITools
        .map((tool) => tool['function']?['name']?.toString())
        .whereType<String>()
        .toSet();
    expect(names, contains('workspace_file_read'));
    expect(names, isNot(contains('workspace_file_write')));
    expect(names, isNot(contains('create_workspace')));
    expect(names, isNot(contains('bind_workspace')));
  });
}
