import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_settings.dart';
import '../providers/account_provider.dart';
import '../providers/recycle_bin_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/account_header_card.dart';
import '../widgets/settings_entry.dart';
import 'about_page.dart';
import 'admin_review_page.dart';
import 'api_models_page.dart';
import 'appearance_settings_page.dart';
import 'data_settings_page.dart';
import 'floating_assistant_settings_page.dart';
import 'memory_settings_page.dart';
import 'model_catalog_settings_page.dart';
import 'permission_management_page.dart';
import 'plugin_settings_page.dart';
import 'role_management_page.dart';
import 'wizard_settings_page.dart';

/// 设置页面。
///
/// 顶部提供设置项搜索；相关入口收纳到「外观」「向导」「模型与接口」
/// 「插件」「数据」子页面，其余设置入口保持独立展示。
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
    final account = context.watch<AccountProvider>();
    final query = _normalizedQuery;
    final entries = _buildEntries(context, settings, account);
    final visibleEntries = query.isEmpty
        ? entries
        : entries.where((entry) => entry.matches(query)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildSearchField(),
          if (query.isEmpty) const AccountHeaderCard(),
          if (query.isNotEmpty && visibleEntries.isEmpty)
            _buildNoSearchResults(query)
          else
            for (final entry in visibleEntries) SettingsItemCard(entry: entry),
        ],
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

  List<SettingsEntry> _buildEntries(
    BuildContext context,
    AppSettings settings,
    AccountProvider account,
  ) {
    return [
      if (account.isLoggedIn && account.user!.isAdmin)
        SettingsEntry(
          icon: Icons.admin_panel_settings,
          title: '审核管理',
          subtitle: '审核用户提交的插件',
          iconColor: Colors.deepOrange,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminReviewPage()),
          ),
        ),
      SettingsEntry(
        icon: Icons.info_outline,
        title: '关于',
        subtitle: '关于 LynAI',
        iconColor: Colors.blue,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AboutPage()),
        ),
      ),
      SettingsEntry(
        icon: Icons.palette_outlined,
        title: '外观',
        subtitle: '主题与背景图',
        iconColor: Colors.green,
        searchTerms: const ['主题', '背景', '背景图', '背景图片'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AppearanceSettingsPage()),
        ),
      ),
      SettingsEntry(
        icon: Icons.auto_awesome,
        title: '向导',
        subtitle: '新手向导与功能引导',
        iconColor: Colors.orange,
        searchTerms: const ['新手向导', '功能引导'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WizardSettingsPage()),
        ),
      ),
      SettingsEntry(
        icon: Icons.api,
        title: '模型与接口',
        subtitle: '管理模型与接口',
        iconColor: Colors.orange,
        searchTerms: const [
          'Chat',
          'OCR',
          '语音转文字',
          '图片生成',
          '本地模型',
          'BlueLM',
          '网页搜索',
          'MCP 服务',
        ],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ApiModelsPage()),
        ),
      ),
      SettingsEntry(
        icon: Icons.travel_explore,
        title: '模型目录',
        subtitle: '从 models.dev 补全上下文、输出上限与能力',
        iconColor: Colors.teal,
        searchTerms: const [
          'models.dev',
          '模型目录',
          '上下文窗口',
          'context window',
          '输出上限',
          '思考强度',
          '参数补全',
        ],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ModelCatalogSettingsPage(),
          ),
        ),
      ),
      SettingsEntry(
        icon: Icons.shield_outlined,
        title: '权限管理',
        subtitle: settings.agentEnabledByDefault
            ? '默认启用 · ${settings.agentGrantedPermissions.length} 项权限'
            : '默认关闭 · ${settings.agentGrantedPermissions.length} 项权限',
        iconColor: Colors.deepPurple,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PermissionManagementPage()),
        ),
      ),
      SettingsEntry(
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
      SettingsEntry(
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
      SettingsEntry(
        icon: Icons.psychology_outlined,
        title: '记忆管理',
        subtitle: '角色记忆开关、容量、维护提醒与条目管理',
        iconColor: Colors.deepPurple,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MemorySettingsPage()),
        ),
      ),
      SettingsEntry(
        icon: Icons.extension,
        title: '插件',
        subtitle: '插件配置、插件能力与插件工坊',
        iconColor: Colors.deepPurple,
        searchTerms: const ['插件配置', '插件能力', '插件工坊'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PluginSettingsPage()),
        ),
      ),
      SettingsEntry(
        icon: Icons.storage_outlined,
        title: '数据',
        subtitle: '数据管理、回收站与局域网同步',
        iconColor: Colors.teal,
        searchTerms: const ['数据管理', '回收站', '局域网配对与同步'],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DataSettingsPage()),
        ),
      ),
    ];
  }
}
