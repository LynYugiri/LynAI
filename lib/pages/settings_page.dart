import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/account_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/recycle_bin_provider.dart';
import '../providers/settings_provider.dart';
import '../services/backend_client.dart';
import '../widgets/account_header_card.dart';
import '../widgets/plugin_feature_webview.dart';
import '../widgets/text_editing_controller_host.dart';
import 'about_page.dart';
import 'admin_review_page.dart';
import 'background_page.dart';
import 'api_models_page.dart';
import 'data_management_page.dart';
import 'floating_assistant_settings_page.dart';
import 'lan_sync_page.dart';
import 'plugin_capability_management_page.dart';
import 'plugin_management_page.dart';
import 'recycle_bin_page.dart';
import 'role_management_page.dart';
import 'theme_page.dart';

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
    final pluginProvider = context.watch<PluginProvider>();
    final recycleBinProvider = context.watch<RecycleBinProvider>();
    final account = context.watch<AccountProvider>();
    final backend = context.watch<BackendClient>();
    final pluginItems = _buildPluginItems(context, pluginProvider);

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
            Icons.dns_outlined,
            '连接到服务端',
            _backendSubtitle(settings.backendUrl, backend),
            Colors.blueGrey,
            () => _showBackendDialog(context),
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
          ...pluginItems,
        ],
      ),
    );
  }

  /// 弹出后端地址配置对话框。
  Future<void> _showBackendDialog(BuildContext context) async {
    final settingsProvider = context.read<SettingsProvider>();
    final backend = context.read<BackendClient>();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => TextEditingControllerHost(
        initialTexts: [
          settingsProvider.settings.backendUrl ??
              BackendClient.defaultBackendUrl,
        ],
        builder: (ctx, controllers) {
          final controller = controllers.single;
          return AlertDialog(
            title: const Text('连接到服务端'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: '后端地址',
                    hintText: BackendClient.defaultBackendUrl,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link),
                  ),
                  keyboardType: TextInputType.url,
                  autofocus: true,
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    final warning = BackendClient.insecureHttpWarningFor(
                      value.text,
                    );
                    if (warning == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        warning,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx, '');
                },
                child: const Text('断开'),
              ),
              if (BackendClient.defaultBackendUrl.isNotEmpty)
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx, BackendClient.defaultBackendUrl);
                  },
                  child: const Text('恢复默认'),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return;
    if (!context.mounted) return;

    final url = result.isEmpty ? null : result;
    backend.configure(url ?? '');
    settingsProvider.updateBackendUrl(url);
    await context.read<ModelConfigProvider>().syncLynaiManagedProvider(backend);
  }

  String _backendSubtitle(String? savedUrl, BackendClient backend) {
    if (!backend.isConnected) return '未连接';
    return backend.usesInsecureHttp
        ? '${backend.backendUrl}（未加密，仅限隔离测试）'
        : backend.backendUrl;
  }

  /// 遍历所有已启用插件中标记了 [PluginFeaturePageDefinition.showInSettings] 的功能页，生成对应的设置项列表。
  List<Widget> _buildPluginItems(
    BuildContext context,
    PluginProvider provider,
  ) {
    final items = <Widget>[];
    for (final plugin in provider.plugins) {
      if (!plugin.enabled || plugin.hasError) continue;
      for (final page in plugin.manifest.featurePages) {
        if (!page.showInSettings) continue;
        if (!plugin.enabledFeaturePages.contains(page.id)) continue;
        items.add(
          _buildItem(
            context,
            Icons.dashboard_customize,
            page.title.isNotEmpty ? page.title : plugin.manifest.name,
            plugin.manifest.name,
            Colors.deepOrange,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(
                    title: Text(
                      page.title.isNotEmpty ? page.title : plugin.manifest.name,
                    ),
                    centerTitle: true,
                  ),
                  body: PluginFeatureWebView(plugin: plugin, page: page),
                ),
              ),
            ),
          ),
        );
      }
    }
    return items;
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
