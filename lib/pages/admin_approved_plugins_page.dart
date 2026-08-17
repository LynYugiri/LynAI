import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plugin_market_entry.dart';
import '../services/backend_client.dart';
import '../services/remote_market_service.dart';
import '../utils/snackbar_utils.dart';

/// 管理员已上架插件管理页。
///
/// 列出市场公开目录中的已上架插件，允许管理员编辑元数据、下架或删除。
class AdminApprovedPluginsPage extends StatefulWidget {
  const AdminApprovedPluginsPage({super.key});

  @override
  State<AdminApprovedPluginsPage> createState() =>
      _AdminApprovedPluginsPageState();
}

class _AdminApprovedPluginsPageState extends State<AdminApprovedPluginsPage> {
  List<MarketPluginEntry> _plugins = const [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final backend = context.read<BackendClient>();
    if (!backend.isConnected) {
      setState(() {
        _error = '未连接后端';
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await RemoteMarketService(
        backend,
      ).listPlugins(const MarketQuery(page: 1, pageSize: 100));
      if (!mounted) return;
      setState(() {
        _plugins = result.entries;
        _hasMore = result.hasMore;
        _page = 1;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('已上架插件'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_plugins.isEmpty) {
      return const Center(child: Text('暂无已上架插件'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _plugins.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _plugins.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: TextButton.icon(
                icon: _loadingMore
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more),
                label: Text(_loadingMore ? '加载中…' : '加载更多'),
                onPressed: _loadMore,
              ),
            ),
          );
        }
        final entry = _plugins[index];
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
              child: Text(
                'v${entry.version} · ${entry.category.isEmpty ? "未分类" : entry.category}',
              ),
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (action) => _onAction(entry, action),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('编辑元数据'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'unpublish',
                  child: ListTile(
                    leading: Icon(Icons.get_app),
                    title: Text('下架'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('删除'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final backend = context.read<BackendClient>();
    if (!backend.isConnected) return;
    setState(() => _loadingMore = true);
    try {
      final result = await RemoteMarketService(
        backend,
      ).listPlugins(MarketQuery(page: _page + 1, pageSize: 100));
      if (!mounted) return;
      final seen = _plugins.map((plugin) => plugin.id).toSet();
      setState(() {
        _plugins = [
          ..._plugins,
          ...result.entries.where((plugin) => !seen.contains(plugin.id)),
        ];
        _hasMore = result.hasMore;
        _page += 1;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showErrorSnackBar(context, '加载更多失败', details: e.toString());
    }
  }

  Future<void> _onAction(MarketPluginEntry entry, String action) async {
    if (action == 'edit') {
      await _edit(entry);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action == 'unpublish' ? '下架插件？' : '删除插件？'),
        content: Text(
          action == 'unpublish'
              ? '「${entry.name}」将退回待审核状态，市场不再展示。'
              : '「${entry.name}」将从市场永久删除，此操作不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action == 'unpublish' ? '下架' : '删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final service = RemoteMarketService(context.read<BackendClient>());
      if (action == 'unpublish') {
        await service.unpublishPlugin(entry.id);
      } else {
        await service.deletePlugin(entry.id);
      }
      if (!mounted) return;
      showShortSnackBar(context, action == 'unpublish' ? '已下架' : '已删除');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, '操作失败', details: e.toString());
    }
  }

  Future<void> _edit(MarketPluginEntry entry) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (context) => _EditPluginDialog(entry: entry),
    );
    if (result == null || !mounted) return;
    try {
      await RemoteMarketService(context.read<BackendClient>()).updatePlugin(
        entry.id,
        name: result.name,
        description: result.description,
        category: result.category,
      );
      if (!mounted) return;
      showShortSnackBar(context, '已更新');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, '更新失败', details: e.toString());
    }
  }
}

class _EditResult {
  const _EditResult({
    required this.name,
    required this.description,
    required this.category,
  });

  final String name;
  final String description;
  final String category;
}

class _EditPluginDialog extends StatefulWidget {
  const _EditPluginDialog({required this.entry});

  final MarketPluginEntry entry;

  @override
  State<_EditPluginDialog> createState() => _EditPluginDialogState();
}

class _EditPluginDialogState extends State<_EditPluginDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _category;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.entry.name);
    _description = TextEditingController(text: widget.entry.description);
    _category = TextEditingController(text: widget.entry.category);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑插件元数据'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '描述'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _category,
              decoration: const InputDecoration(labelText: '分类'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('名称不能为空')));
              return;
            }
            Navigator.pop(
              context,
              _EditResult(
                name: _name.text.trim(),
                description: _description.text.trim(),
                category: _category.text.trim(),
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
