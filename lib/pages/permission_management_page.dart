import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plugin.dart';
import '../providers/plugin_provider.dart';
import '../services/lynai_permission_definitions.dart';
import '../widgets/plugin_icon.dart';
import 'agent_defaults_settings_page.dart';
import 'plugin_management_page.dart' show PluginDetailPage;

/// 权限管理页面。
///
/// 统一管理对话/Agent 的全局权限与每个插件的授权状态。插件授权状态按敏感
/// 权限（需授权）与免授权权限（自动授予）分别统计。
class PermissionManagementPage extends StatelessWidget {
  const PermissionManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final plugins = context.watch<PluginProvider>().plugins;
    return Scaffold(
      appBar: AppBar(title: const Text('权限管理')),
      body: ListView(
        children: [
          const _SectionHeader('对话与 Agent'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.smart_toy_outlined),
              ),
              title: const Text('对话权限'),
              subtitle: const Text('新对话默认权限与 Agent 能力'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AgentDefaultsSettingsPage(),
                ),
              ),
            ),
          ),
          const _SectionHeader('插件'),
          if (plugins.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('暂无已安装插件')),
          for (final plugin in plugins)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                leading: PluginIcon(
                  pluginPath: plugin.path,
                  iconPath: plugin.manifest.icon,
                  size: 28,
                ),
                title: Text(plugin.displayName),
                subtitle: Text(_permissionSummary(context, plugin)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PluginDetailPage(pluginId: plugin.id),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _permissionSummary(BuildContext context, InstalledPlugin plugin) {
    if (plugin.needsReview) return '需完成本机审查';
    final listable = context.read<PluginProvider>().listablePermissionIds(
      plugin,
    );
    final sensitive = listable
        .where((p) => !isAutoGrantedPluginPermission(p))
        .toList(growable: false);
    if (sensitive.isEmpty) return '无需授权';
    final granted = sensitive.where(plugin.grantedPermissions.contains).length;
    if (granted == sensitive.length) return '已授权全部 $granted 项';
    if (granted == 0) return '未授权（$sensitive.length 项待授权）';
    return '已授权 $granted / ${sensitive.length} 项';
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
