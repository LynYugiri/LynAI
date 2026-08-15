import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/agent_defaults.dart';
import '../providers/settings_provider.dart';
import '../services/lynai_permission_definitions.dart';

class AgentDefaultsSettingsPage extends StatelessWidget {
  const AgentDefaultsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SettingsProvider>();
    final settings = provider.settings;
    final permissions = settings.agentGrantedPermissions.toSet();
    return Scaffold(
      appBar: AppBar(title: const Text('对话权限')),
      body: ListView(
        children: [
          SwitchListTile(
            value: settings.agentEnabledByDefault,
            title: const Text('新对话默认启用 Agent'),
            subtitle: const Text('只影响之后创建的对话；历史对话保留自己的开关。'),
            onChanged: (value) => provider.updateAgentDefaults(
              enabled: value,
              permissions: settings.agentGrantedPermissions,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('单次任务最大工具轮数'),
            subtitle: Text(
              '达到上限后模型会基于已有结果强制收尾。当前：${settings.agentMaxToolRounds} 轮',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    value: settings.agentMaxToolRounds
                        .clamp(minAgentMaxToolRounds, maxAgentMaxToolRounds)
                        .toDouble(),
                    min: minAgentMaxToolRounds.toDouble(),
                    max: maxAgentMaxToolRounds.toDouble(),
                    divisions: maxAgentMaxToolRounds - minAgentMaxToolRounds,
                    label: '${settings.agentMaxToolRounds} 轮',
                    onChanged: (value) => provider.updateAgentDefaults(
                      enabled: settings.agentEnabledByDefault,
                      permissions: settings.agentGrantedPermissions,
                      maxToolRounds: value.round(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${settings.agentMaxToolRounds}',
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('全局权限'),
            subtitle: const Text('修改后对所有对话即时生效。'),
            trailing: TextButton(
              onPressed: () => provider.updateAgentDefaults(
                enabled: settings.agentEnabledByDefault,
                permissions: LynAIPermissions.defaultAgent,
                maxToolRounds: defaultAgentMaxToolRounds,
              ),
              child: const Text('恢复默认'),
            ),
          ),
          for (final definition in agentAssignablePermissionDefinitions)
            CheckboxListTile(
              value: permissions.contains(definition.id),
              title: Text(definition.title),
              subtitle: Text(definition.description),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) {
                final next = Set<String>.from(permissions);
                value == true
                    ? next.add(definition.id)
                    : next.remove(definition.id);
                provider.updateAgentDefaults(
                  enabled: settings.agentEnabledByDefault,
                  permissions: LynAIPermissions.agentAssignable
                      .where(next.contains)
                      .toList(growable: false),
                );
              },
            ),
        ],
      ),
    );
  }
}
