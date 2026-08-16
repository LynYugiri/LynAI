import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plugin_market_entry.dart';
import '../services/backend_client.dart';
import '../services/remote_market_service.dart';

/// 我的提交页面。
///
/// 列出当前用户提交到市场的插件及其审核状态（待审核/已通过/已驳回）。
class MySubmissionsPage extends StatefulWidget {
  const MySubmissionsPage({super.key});

  @override
  State<MySubmissionsPage> createState() => _MySubmissionsPageState();
}

class _MySubmissionsPageState extends State<MySubmissionsPage> {
  List<MarketPluginEntry>? _submissions;
  bool _loading = false;
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
      final service = RemoteMarketService(backend);
      final entries = await service.mySubmissions();
      if (!mounted) return;
      setState(() {
        _submissions = entries;
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
        title: const Text('我的提交'),
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
    final subs = _submissions;
    if (subs == null || subs.isEmpty) {
      return const Center(child: Text('还没有提交过插件'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: subs.length,
      itemBuilder: (context, index) {
        final entry = subs[index];
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
                  Text('v${entry.version} · ${entry.author}'),
                  const SizedBox(height: 4),
                  Text(
                    _statusLabel(entry),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (entry.reviewNote != null && entry.reviewNote!.isNotEmpty)
                    Text(
                      '原因：${entry.reviewNote!}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (action) => _onAction(entry, action),
              itemBuilder: (context) => [
                if (entry.status == 'approved')
                  const PopupMenuItem(
                    value: 'unpublish',
                    child: ListTile(
                      leading: Icon(Icons.get_app),
                      title: Text('下架'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                const PopupMenuItem(
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

  Future<void> _onAction(MarketPluginEntry entry, String action) async {
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(action == 'unpublish' ? '已下架' : '已删除')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  String _statusLabel(MarketPluginEntry entry) {
    switch (entry.status) {
      case 'approved':
        return '已上架';
      case 'rejected':
        return '已驳回';
      case 'pending':
      default:
        return '待审核';
    }
  }
}
