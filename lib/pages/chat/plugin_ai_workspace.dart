import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/conversation.dart';
import '../../models/model_config.dart';
import '../../providers/conversation_provider.dart';
import '../../providers/model_config_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/lynai_permission_definitions.dart';
import '../agent_defaults_settings_page.dart';
import '../chat_page.dart';

/// 打开（或复用）绑定指定插件的对话并让 AI 开始修改。
///
/// 这是插件工坊与主聊天之间的共享桥接：复用现有 `ChatPage` 与
/// `AgentLoopRuntime`，不在工坊内重建 Agent 循环。
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
  final settings = ConversationSettings(
    modelId: model.id,
    modelName: model.name,
    thinking: true,
    systemPrompt: settingsProvider.settings.systemPrompt,
    agentEnabled: true,
  );
  final conversationId = conversations.ensurePluginConversation(
    pluginId: pluginId,
    pluginName: pluginName,
    settings: settings,
  );
  // 复用已有工作区对话时，也确保它使用支持工具调用的模型并开启 Agent。
  conversations.updateConversationSettings(conversationId, settings);

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
