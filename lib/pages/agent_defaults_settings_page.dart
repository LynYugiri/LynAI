import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
      appBar: AppBar(title: const Text('新对话 Agent 默认值')),
      body: ListView(
        children: [
          SwitchListTile(
            value: settings.agentEnabledByDefault,
            title: const Text('新对话默认启用 Agent'),
            subtitle: const Text('只影响之后创建的对话；历史对话保留自己的快照。'),
            onChanged: (value) => provider.updateAgentDefaults(
              enabled: value,
              permissions: settings.agentGrantedPermissions,
            ),
          ),
          const Divider(height: 1),
          for (final definition in lynaiPermissionDefinitions)
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
