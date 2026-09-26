import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/conversation.dart';
import '../../models/model_config.dart';
import '../../providers/conversation_provider.dart';
import '../../providers/model_config_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/lynai_permission_definitions.dart';
import '../agent_defaults_settings_page.dart';
import '../chat_page.dart';

/// 为插件工坊的 AI 协作新建一个工作区、挂入该插件并打开绑定后的对话。
///
/// 这是插件工坊与主聊天之间的共享桥接：复用现有 `ChatPage` 与
/// `AgentLoopRuntime`，不在工坊内重建 Agent 循环。每次调用都会创建新的
/// 工作区与会话，历史自动归入「工作区对话历史」。
Future<bool> openPluginAiConversation(
  BuildContext context, {
  required String pluginId,
  required String pluginName,
  String? prompt,
}) async {
  final settingsProvider = context.read<SettingsProvider>();
  final granted = settingsProvider.settings.agentGrantedPermissions.toSet();
  if (!granted.contains(LynAIPermissions.pluginsFilesWrite)) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('需要先在「对话权限」中开启“修改插件文件”，AI 才能编辑插件草稿。'),
        // 带 action 的 SnackBar 在 Flutter 3.35+ 默认 persist: true（永不自动
        // 消失），这里显式关掉并给一段读完提示的时长。
        duration: const Duration(seconds: 6),
        persist: false,
        action: SnackBarAction(
          label: '去开启',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AgentDefaultsSettingsPage(),
            ),
          ),
        ),
      ),
    );
    return false;
  }

  final modelProvider = context.read<ModelConfigProvider>();
  final chatModels = modelProvider.enabledModelsByCategory(
    ModelConfig.categoryChat,
  );
  ModelConfig? model;
  for (final item in chatModels) {
    if (item.supportsNativeTools) {
      model = item;
      break;
    }
  }
  if (model == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('没有支持工具调用的聊天模型，无法让 AI 修改插件。')));
    return false;
  }

  final conversations = context.read<ConversationProvider>();
  final workspaces = context.read<WorkspaceProvider>();
  final displayName = pluginName.trim().isEmpty ? pluginId : pluginName.trim();
  final workspaceName = _uniqueWorkspaceName(
    workspaces,
    '$displayName · AI 协作',
  );
  final workspace = workspaces.createWorkspace(
    name: workspaceName,
    devPluginIds: [pluginId],
  );
  final settings = ConversationSettings(
    modelId: model.id,
    modelName: model.name,
    thinking: true,
    systemPrompt: settingsProvider.settings.systemPrompt,
    agentEnabled: true,
  );
  final conversationId = conversations.createConversation(
    settings,
    workspaceId: workspace.id,
    workspaceName: workspace.name,
  );
  conversations.updateConversationTitle(conversationId, '插件 · $displayName');
  conversations.setPluginWorkspace(conversationId, pluginId);

  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChatPage(
        conversationId: conversationId,
        initialPrompt: prompt == null || prompt.trim().isEmpty
            ? '请先查看当前插件文件和 manifest，说明你准备怎么改，然后直接修改草稿文件。'
            : prompt.trim(),
        autoSendInitialPrompt: true,
      ),
    ),
  );
  return true;
}

String _uniqueWorkspaceName(WorkspaceProvider provider, String base) {
  if (!provider.workspaces.any((workspace) => workspace.name == base)) {
    return base;
  }
  var suffix = 2;
  while (provider.workspaces.any(
    (workspace) => workspace.name == '$base $suffix',
  )) {
    suffix++;
  }
  return '$base $suffix';
}
