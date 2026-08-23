import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_settings.dart';
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
import 'local_model_settings_page.dart';
import 'mcp_settings_page.dart';
import 'memory_settings_page.dart';
import 'onboarding/onboarding_page.dart';
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
/// 顶部提供设置项搜索，并按「外观」「向导」「模型与接口」「插件」「数据」
/// 分组展示入口；关于、权限、悬浮窗、角色和记忆等入口保持独立展示。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) context.read<RecycleBinProvider>().load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _normalizedQuery => _searchQuery.trim().toLowerCase();

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final recycleBinProvider = context.watch<RecycleBinProvider>();
    final account = context.watch<AccountProvider>();
    final sections = _filterSections(
      _buildSections(context, settings, recycleBinProvider, account),
      _normalizedQuery,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildSearchField(),
          if (_normalizedQuery.isEmpty) const AccountHeaderCard(),
          if (_normalizedQuery.isNotEmpty && sections.isEmpty)
            _buildNoSearchResults(_normalizedQuery)
          else
            ...sections.expand((section) => _buildSection(context, section)),
        ],
      ),
    );
  }

  List<Widget> _buildSection(BuildContext context, _SettingsSection section) {
    return [
      if (section.title != null) _buildSectionHeader(section.title!),
      ...section.entries.map(
        (entry) => _buildItem(
          context,
          entry.icon,
          entry.title,
          entry.subtitle,
          entry.iconColor,
          entry.onTap,
        ),
      ),
    ];
  }

  Widget _buildSectionHeader(String title) {
    final theme = Theme.of(context);
    return Padding(
      key: ValueKey('settings-section-$title'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '搜索设置项',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除搜索',
                  icon: const Icon(Icons.clear),
                  onPressed: _clearSearch,
                ),
          filled: true,
          fillColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildNoSearchResults(String query) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            '未找到与“$query”相关的设置项',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  List<_SettingsSection> _buildSections(
    BuildContext context,
    AppSettings settings,
    RecycleBinProvider recycleBinProvider,
    AccountProvider account,
  ) {
    return [
      _SettingsSection(
        entries: [
          if (account.isLoggedIn && account.user!.isAdmin)
            _SettingsEntry(
              icon: Icons.admin_panel_settings,
              title: '审核管理',
              subtitle: '审核用户提交的插件',
              iconColor: Colors.deepOrange,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminReviewPage()),
              ),
            ),
          _SettingsEntry(
            icon: Icons.info_outline,
            title: '关于',
            subtitle: '关于 LynAI',
            iconColor: Colors.blue,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutPage()),
            ),
          ),
        ],
      ),
      _SettingsSection(
        title: '外观',
        entries: [
          _SettingsEntry(
            icon: Icons.palette,
            title: '主题',
            subtitle: '自定义主题颜色',
            iconColor: Colors.green,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ThemePage()),
            ),
          ),
          _SettingsEntry(
            icon: Icons.wallpaper,
            title: '背景',
            subtitle: settings.backgroundImagePath != null
                ? '已设置背景图片'
                : '自定义背景图片',
            iconColor: Colors.purple,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BackgroundPage()),
            ),
          ),
        ],
      ),
      _SettingsSection(
        title: '向导',
        entries: [
          _SettingsEntry(
            icon: Icons.auto_awesome,
            title: '新手向导',
            subtitle: settings.hasCompletedOnboarding
                ? '重新生成个性化初始配置'
                : '选择用途与身份，生成专属配置',
            iconColor: Colors.orange,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OnboardingPage()),
            ),
          ),
          _SettingsEntry(
            icon: Icons.explore_outlined,
            title: '功能引导',
            subtitle: '重新看一遍底部导航、快捷盘和角色/Agent 入口',
            iconColor: Colors.teal,
            onTap: () {
              final provider = context.read<SettingsProvider>();
              provider.replaceSettings(
                provider.settings.copyWith(hasCompletedGuidedTour: false),
              );
            },
          ),
        ],
      ),
      _SettingsSection(
        title: '模型与接口',
        entries: [
          _SettingsEntry(
            icon: Icons.api,
            title: 'API 模型',
            subtitle: '管理模型与接口',
            iconColor: Colors.orange,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ApiModelsPage()),
            ),
          ),
          _SettingsEntry(
            icon: Icons.smart_toy_outlined,
            title: '本地模型',
            subtitle: 'BlueLM 3B 路径、权限与初始化',
            iconColor: Colors.teal,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LocalModelSettingsPage()),
            ),
          ),
          _SettingsEntry(
            icon: Icons.travel_explore,
            title: '网页搜索',
            subtitle:
                '${settings.webSearchRoute.name} · ${settings.webSearchClientProvider.name}',
            iconColor: Colors.lightBlue,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WebSearchSettingsPage()),
            ),
          ),
          _SettingsEntry(
            icon: Icons.hub_outlined,
            title: 'MCP 服务',
            subtitle: '连接远程或桌面工具服务',
            iconColor: Colors.blueGrey,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const McpSettingsPage()),
            ),
          ),
        ],
      ),
      _SettingsSection(
        entries: [
          _SettingsEntry(
            icon: Icons.shield_outlined,
            title: '权限管理',
            subtitle: settings.agentEnabledByDefault
                ? '默认启用 · ${settings.agentGrantedPermissions.length} 项权限'
                : '默认关闭 · ${settings.agentGrantedPermissions.length} 项权限',
            iconColor: Colors.deepPurple,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PermissionManagementPage(),
              ),
            ),
          ),
          _SettingsEntry(
            icon: Icons.bubble_chart_outlined,
            title: '悬浮窗',
            subtitle: settings.floatingAssistant.enabled
                ? '已启用悬浮助手'
                : '系统悬浮聊天、Agent Plan 和屏幕翻译',
            iconColor: Colors.cyan,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const FloatingAssistantSettingsPage(),
              ),
            ),
          ),
          _SettingsEntry(
            icon: Icons.person_pin_circle_outlined,
            title: '角色管理',
            subtitle:
                '${settings.roles.length} 个角色 · ${settings.roleGroups.length} 个分组',
            iconColor: Colors.indigo,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RoleManagementPage()),
            ),
          ),
          _SettingsEntry(
            icon: Icons.psychology_outlined,
            title: '记忆管理',
            subtitle: '角色记忆开关、容量、维护提醒与条目管理',
            iconColor: Colors.deepPurple,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MemorySettingsPage()),
            ),
          ),
        ],
      ),
      _SettingsSection(
        title: '插件',
        entries: [
          _SettingsEntry(
            icon: Icons.extension,
            title: '插件配置',
            subtitle: '权限与配置',
            iconColor: Colors.deepPurple,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PluginManagementPage()),
            ),
          ),
          _SettingsEntry(
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
          _SettingsEntry(
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
      ),
      _SettingsSection(
        title: '数据',
        entries: [
          _SettingsEntry(
            icon: Icons.import_export,
            title: '数据管理',
            subtitle: '导入、导出与备份恢复',
            iconColor: Colors.teal,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DataManagementPage()),
            ),
          ),
          _SettingsEntry(
            icon: Icons.delete_sweep_outlined,
            title: '回收站',
            subtitle: '${recycleBinProvider.items.length} 个项目',
            iconColor: Colors.red,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecycleBinPage()),
            ),
          ),
          _SettingsEntry(
            icon: Icons.phonelink_lock_outlined,
            title: '局域网配对与同步',
            subtitle: '发现设备、扫码配对、同步、冲突与撤销',
            iconColor: Colors.blue,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LanSyncPage()),
            ),
          ),
        ],
      ),
    ];
  }

  List<_SettingsSection> _filterSections(
    List<_SettingsSection> sections,
    String query,
  ) {
    if (query.isEmpty) return sections;
    final filtered = <_SettingsSection>[];
    for (final section in sections) {
      final titleMatches =
          section.title?.toLowerCase().contains(query) ?? false;
      if (titleMatches) {
        filtered.add(section);
        continue;
      }
      final entries = section.entries
          .where((entry) => entry.matches(query))
          .toList(growable: false);
      if (entries.isNotEmpty) {
        filtered.add(_SettingsSection(title: section.title, entries: entries));
      }
    }
    return filtered;
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

class _SettingsEntry {
  const _SettingsEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final VoidCallback onTap;

  bool matches(String normalizedQuery) {
    return title.toLowerCase().contains(normalizedQuery) ||
        subtitle.toLowerCase().contains(normalizedQuery);
  }
}

class _SettingsSection {
  const _SettingsSection({this.title, required this.entries});

  final String? title;
  final List<_SettingsEntry> entries;
}
