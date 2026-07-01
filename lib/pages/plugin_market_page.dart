import 'package:file_picker/file_picker.dart' show FileType;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plugin.dart';
import '../models/plugin_market_entry.dart';
import '../providers/account_provider.dart';
import '../providers/plugin_provider.dart';
import '../services/backend_client.dart';
import '../services/local_market_service.dart';
import '../services/market_service.dart';
import '../services/remote_market_service.dart';
import '../utils/file_picker_io_utils.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/plugin_icon.dart';
import 'plugin_management_page.dart' show PluginDetailPage;
import 'plugin_market_detail_page.dart';
import 'plugin_submission_page.dart';
import 'my_submissions_page.dart';

/// 插件市场页面。
///
/// 两个分段：
/// - **市场**：从 [MarketService] 浏览远端插件目录，查看详情，下载安装。
/// - **已安装**：列出本地已安装插件，支持卸载和跳转到权限/配置详情。
///
/// 当前阶段后端尚未连接，[MarketService] 使用 [LocalMarketService] 桩实现，
/// 市场分段显示空态文案与「从 ZIP 导入」入口；已安装分段直接读取
/// [PluginProvider.plugins]，用户可在此卸载本地插件。
class PluginMarketPage extends StatefulWidget {
  const PluginMarketPage({super.key});

  @override
  State<PluginMarketPage> createState() => _PluginMarketPageState();
}

class _PluginMarketPageState extends State<PluginMarketPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 根据后端连接状态返回对应的 MarketService。
  MarketService _marketService(BuildContext context) {
    final backend = context.read<BackendClient>();
    if (backend.isConnected) {
      return RemoteMarketService(backend);
    }
    return const LocalMarketService();
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountProvider>();
    final backend = context.watch<BackendClient>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('插件市场'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '市场'),
            Tab(text: '已安装'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MarketTab(
            marketService: _marketService(context),
            searchController: _searchController,
          ),
          const _InstalledTab(),
        ],
      ),
      floatingActionButton: backend.isConnected && account.isLoggedIn
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'my_submissions',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MySubmissionsPage(),
                    ),
                  ),
                  child: const Icon(Icons.list_alt),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  heroTag: 'submit_plugin',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PluginSubmissionPage(),
                    ),
                  ),
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('提交插件'),
                ),
              ],
            )
          : null,
    );
  }
}

/// 市场分段：远端插件目录浏览。
class _MarketTab extends StatefulWidget {
  const _MarketTab({
    required this.marketService,
    required this.searchController,
  });

  final MarketService marketService;
  final TextEditingController searchController;

  @override
  State<_MarketTab> createState() => _MarketTabState();
}

class _MarketTabState extends State<_MarketTab> {
  List<MarketPluginEntry> _entries = const [];
  bool _loading = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void didUpdateWidget(covariant _MarketTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.marketService.isBackendConnected !=
        widget.marketService.isBackendConnected) {
      _loadEntries();
    }
  }

  Future<void> _loadEntries() async {
    if (!widget.marketService.isBackendConnected) {
      setState(() {
        _entries = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.marketService.listPlugins(
        MarketQuery(query: _query),
      );
      if (!mounted) return;
      setState(() {
        _entries = result.entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.marketService.isBackendConnected) {
      return _MarketEmptyState(
        searchController: widget.searchController,
        onImportZip: _importZip,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: widget.searchController,
            decoration: const InputDecoration(
              hintText: '搜索插件',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (value) {
              _query = value.trim();
              _loadEntries();
            },
          ),
        ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Expanded(child: Center(child: Text(_error!)))
        else if (_entries.isEmpty)
          const Expanded(child: Center(child: Text('没有找到插件')))
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final entry = _entries[index];
                return _MarketPluginCard(
                  entry: entry,
                  marketService: widget.marketService,
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _importZip() async {
    final file = await pickSingleFilePayload(
      dialogTitle: '选择插件 ZIP',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (file == null || !mounted) return;
    try {
      await context.read<PluginProvider>().importZipBytes(
        await file.readBytes(),
      );
      if (!mounted) return;
      showShortSnackBar(context, '插件已导入');
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, '导入失败', details: e.toString());
    }
  }
}

/// 市场未连接后端时的空态。
class _MarketEmptyState extends StatelessWidget {
  const _MarketEmptyState({
    required this.searchController,
    required this.onImportZip,
  });

  final TextEditingController searchController;
  final Future<void> Function() onImportZip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.store_outlined,
              size: 72,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text('尚未连接后端', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '连接 LynAI 后端后，可在此浏览、安装和更新插件。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: onImportZip,
              icon: const Icon(Icons.archive_outlined),
              label: const Text('从 ZIP 导入'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 市场插件卡片。
class _MarketPluginCard extends StatelessWidget {
  const _MarketPluginCard({required this.entry, required this.marketService});

  final MarketPluginEntry entry;
  final MarketService marketService;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.extension)),
        title: Text(
          entry.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.author.isNotEmpty)
                Text('作者: ${entry.author}')
              else
                const Text('作者: 未知'),
              const SizedBox(height: 2),
              Text(
                entry.description.isEmpty ? '暂无描述' : entry.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text('v${entry.version}'),
            ],
          ),
        ),
        trailing: FilledButton(
          onPressed: () => _openDetail(context),
          child: const Text('详情'),
        ),
        onTap: () => _openDetail(context),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PluginMarketDetailPage(entry: entry, marketService: marketService),
      ),
    );
  }
}

/// 已安装分段：列出本地插件，支持卸载和跳转权限/配置。
class _InstalledTab extends StatelessWidget {
  const _InstalledTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PluginProvider>();
    final plugins = provider.plugins;

    if (plugins.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.extension_off_outlined,
                size: 64,
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              const Text('还没有已安装的插件'),
              const SizedBox(height: 8),
              Text(
                '从市场安装或从 ZIP 导入插件后会显示在这里。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: plugins.length,
      itemBuilder: (context, index) {
        final plugin = plugins[index];
        return _InstalledPluginCard(plugin: plugin);
      },
    );
  }
}

/// 已安装插件卡片。
class _InstalledPluginCard extends StatelessWidget {
  const _InstalledPluginCard({required this.plugin});

  final InstalledPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final manifest = plugin.manifest;
    final color = plugin.hasError
        ? Colors.red
        : plugin.enabled
        ? Colors.green
        : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: PluginIcon(
            pluginPath: plugin.path,
            iconPath: manifest.icon,
            color: color,
          ),
        ),
        title: Text(
          plugin.displayName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('v${manifest.version} · ${plugin.enabled ? "已启用" : "已禁用"}'),
              const SizedBox(height: 2),
              Text(
                '${manifest.tools.length} 个工具 · ${manifest.functions.length} 个函数 · ${manifest.skills.length} 个 Skill · ${manifest.featurePages.length} 个功能页',
              ),
              if (plugin.loadError != null) ...[
                const SizedBox(height: 4),
                Text(
                  plugin.loadError!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleAction(context, value),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'config',
              child: ListTile(
                leading: Icon(Icons.settings_outlined),
                title: Text('权限与配置'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'uninstall',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('卸载'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, String action) async {
    switch (action) {
      case 'config':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PluginDetailPage(pluginId: plugin.id),
          ),
        );
      case 'uninstall':
        await _confirmUninstall(context);
    }
  }

  Future<void> _confirmUninstall(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('卸载插件'),
        content: Text('确定卸载 ${plugin.displayName}？插件文件会从应用私有目录移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<PluginProvider>().uninstall(plugin.id);
      if (!context.mounted) return;
      showShortSnackBar(context, '插件已卸载');
    } catch (e) {
      if (!context.mounted) return;
      showErrorSnackBar(context, '卸载失败', details: e.toString());
    }
  }
}
