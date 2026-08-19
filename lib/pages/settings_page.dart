import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/account_provider.dart';
import '../providers/recycle_bin_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/account_header_card.dart';
import 'about_page.dart';
import 'admin_review_page.dart';
import 'background_page.dart';
import 'api_models_page.dart';
import 'data_management_page.dart';
import 'floating_assistant_settings_page.dart';
import 'lan_sync_page.dart';
import 'mcp_settings_page.dart';
import 'plugin_capability_management_page.dart';
import 'permission_management_page.dart';
import 'plugin_management_page.dart';
import 'plugin_studio_home_page.dart';
import 'recycle_bin_page.dart';
import 'role_management_page.dart';
import 'theme_page.dart';
import 'web_search_settings_page.dart';

/// 设置页面。
///
/// 以列表形式展示关于、背景、模型与接口、角色管理、主题、数据管理、
/// 插件管理入口，并遍历已启用插件的功能页生成设置项。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) context.read<RecycleBinProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final recycleBinProvider = context.watch<RecycleBinProvider>();
    final account = context.watch<AccountProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const AccountHeaderCard(),
          if (account.isLoggedIn && account.user!.isAdmin)
            _buildItem(
              context,
              Icons.admin_panel_settings,
              '审核管理',
              '审核用户提交的插件',
              Colors.deepOrange,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminReviewPage()),
              ),
            ),
          _buildItem(
            context,
            Icons.info_outline,
            '关于',
            '关于 LynAI',
            Colors.blue,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutPage()),
            ),
          ),
          _buildItem(
            context,
            Icons.wallpaper,
            '背景',
            settings.backgroundImagePath != null ? '已设置背景图片' : '自定义背景图片',
            Colors.purple,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BackgroundPage()),
            ),
          ),
          _buildItem(
            context,
            Icons.api,
            '模型与接口',
            '管理模型与接口',
            Colors.orange,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ApiModelsPage()),
            ),
          ),
          _buildItem(
            context,
            Icons.travel_explore,
            '网页搜索',
            '${settings.webSearchRoute.name} · ${settings.webSearchClientProvider.name}',
            Colors.lightBlue,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WebSearchSettingsPage()),
            ),
          ),
          _buildItem(
            context,
            Icons.shield_outlined,
            '权限管理',
            settings.agentEnabledByDefault
                ? '默认启用 · ${settings.agentGrantedPermissions.length} 项权限'
                : '默认关闭 · ${settings.agentGrantedPermissions.length} 项权限',
            Colors.deepPurple,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PermissionManagementPage(),
              ),
            ),
          ),
          _buildItem(
            context,
            Icons.bubble_chart_outlined,
            '悬浮窗',
            settings.floatingAssistant.enabled
                ? '已启用悬浮助手'
                : '系统悬浮聊天、Agent Plan 和屏幕翻译',
            Colors.cyan,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const FloatingAssistantSettingsPage(),
              ),
            ),
          ),
          _buildItem(
            context,
            Icons.person_pin_circle_outlined,
            '角色管理',
            '${settings.roles.length} 个角色 · ${settings.roleGroups.length} 个分组',
            Colors.indigo,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RoleManagementPage()),
            ),
          ),
          _buildItem(
            context,
            Icons.palette,
            '主题',
            '自定义主题颜色',
            Colors.green,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ThemePage()),
            ),
          ),
          _buildItem(
            context,
            Icons.import_export,
            '数据管理',
            '导入、导出与备份恢复',
            Colors.teal,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DataManagementPage()),
            ),
          ),
          _buildItem(
            context,
            Icons.phonelink_lock_outlined,
            '局域网配对与同步',
            '发现设备、扫码配对、同步、冲突与撤销',
            Colors.blue,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LanSyncPage()),
            ),
          ),
          _buildItem(
            context,
            Icons.delete_sweep_outlined,
            '回收站',
            '${recycleBinProvider.items.length} 个项目',
            Colors.red,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecycleBinPage()),
            ),
          ),
          _buildItem(
            context,
            Icons.design_services_outlined,
            '插件工坊',
            '新建、编辑、恢复和发布插件',
            Colors.purple,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PluginStudioHomePage()),
            ),
          ),
          _buildItem(
            context,
            Icons.extension,
            '插件',
            '权限与配置',
            Colors.deepPurple,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PluginManagementPage()),
            ),
          ),
          _buildItem(
            context,
            Icons.auto_awesome_motion,
            '插件能力',
            '集中管理 Tools、Functions、Skills',
            Colors.deepOrange,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PluginCapabilityManagementPage(),
              ),
            ),
          ),
          _buildItem(
            context,
            Icons.hub_outlined,
            'MCP 服务',
            '连接远程或桌面工具服务',
            Colors.blueGrey,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const McpSettingsPage()),
            ),
          ),
        ],
      ),
    );
  }

  // 构建统一的设置项卡片：圆形图标、标题、副标题和右侧箭头。
  Widget _buildItem(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: iconColor.withValues(alpha: 0.1),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
