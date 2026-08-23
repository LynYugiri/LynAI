import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/workspace_provider.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';

void main() {
  late Directory root;
  late StorageV2Service storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lynai_workspace_provider_');
    storage = StorageV2Service(rootDirectory: root);
    await StorageV2UpgradeService(storageV2: storage).ensureReady();
  });

  tearDown(() async {
    await storage.close();
    await root.delete(recursive: true);
  });

  test('workspace CRUD and active state persist', () async {
    final provider = WorkspaceProvider(storageV2: storage);
    await provider.loadWorkspaces();
    expect(provider.workspaces, isEmpty);

    final workspace = provider.createWorkspace(
      name: ' 项目A ',
      featureIds: ['notes', 'knowledge'],
      devPluginIds: ['plugin-notes'],
    );
    expect(workspace.name, '项目A');
    expect(provider.activeWorkspaceId, workspace.id);
    provider.addDevPlugin(workspace.id, 'plugin-notes');
    provider.addDevPlugin(workspace.id, 'plugin-web');
    await provider.flushPendingSaves();

    provider.exitWorkspace();
    expect(provider.activeWorkspaceId, isNull);
    expect(provider.lastWorkspaceId, workspace.id);
    await provider.flushPendingSaves();

    final reloaded = WorkspaceProvider(storageV2: storage);
    await reloaded.loadWorkspaces();
    expect(reloaded.workspaces, hasLength(1));
    expect(reloaded.workspaces.single.name, '项目A');
    expect(reloaded.workspaces.single.devPluginIds, [
      'plugin-notes',
      'plugin-web',
    ]);
    expect(reloaded.activeWorkspaceId, isNull);
    expect(reloaded.lastWorkspaceId, workspace.id);

    reloaded.selectWorkspace(workspace.id);
    expect(reloaded.activeWorkspaceId, workspace.id);
    await reloaded.flushPendingSaves();

    final third = WorkspaceProvider(storageV2: storage);
    await third.loadWorkspaces();
    expect(third.activeWorkspaceId, workspace.id);
  });

  test('bind conversation moves it into workspace history scope', () async {
    final workspaces = WorkspaceProvider(storageV2: storage);
    await workspaces.loadWorkspaces();
    final workspace = workspaces.createWorkspace(name: '项目B');
    await workspaces.flushPendingSaves();

    final conversations = ConversationProvider(storageV2: storage);
    await conversations.loadConversations();
    final convId = conversations.createConversation(
      ConversationSettings(modelId: 'm1'),
      roleId: 'default',
    );
    expect(
      conversations
          .searchConversationsInScope('', workspaceOnly: true)
          .map((item) => item.conversation.id),
      isEmpty,
    );

    final result = conversations.bindConversationToWorkspace(
      convId,
      workspace.id,
      workspace.name,
    );
    expect(result, 'ok');
    expect(
      conversations
          .searchConversationsInScope(
            '',
            workspaceOnly: true,
            workspaceId: workspace.id,
          )
          .single
          .conversation
          .id,
      convId,
    );
    expect(
      conversations
          .searchConversationsInScope('', workspaceOnly: false)
          .map((item) => item.conversation.id),
      isEmpty,
    );

    expect(
      conversations.bindConversationToWorkspace(
        convId,
        'other-workspace',
        '其他',
      ),
      'already_bound',
    );
    expect(
      conversations.bindConversationToWorkspace(
        convId,
        workspace.id,
        workspace.name,
      ),
      'ok',
    );

    conversations.detachWorkspaceFromConversations(workspace.id);
    expect(
      conversations.searchConversationsInScope('', workspaceOnly: true),
      isEmpty,
    );
  });
}
