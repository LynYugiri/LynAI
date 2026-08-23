import 'package:flutter/material.dart';
import '../widgets/settings_entry.dart';
import 'plugin_capability_management_page.dart';
import 'plugin_management_page.dart';
import 'plugin_studio_home_page.dart';

/// 插件设置页。
///
/// 收纳插件配置、插件能力与插件工坊三个入口。
class PluginSettingsPage extends StatelessWidget {
  const PluginSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSubpage(
      title: '插件',
      entries: [
        SettingsEntry(
          icon: Icons.extension,
          title: '插件配置',
          subtitle: '权限与配置',
          iconColor: Colors.deepPurple,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PluginManagementPage()),
          ),
        ),
        SettingsEntry(
          icon: Icons.auto_awesome_motion,
          title: '插件能力',
          subtitle: '集中管理 Tools、Functions、Skills',
          iconColor: Colors.deepOrange,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PluginCapabilityManagementPage(),
            ),
          ),
        ),
        SettingsEntry(
          icon: Icons.design_services_outlined,
          title: '插件工坊',
          subtitle: '新建、编辑、恢复和发布插件',
          iconColor: Colors.purple,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PluginStudioHomePage()),
          ),
        ),
      ],
    );
  }
}
