import 'package:flutter/material.dart';

import '../models/plugin_market_entry.dart';
import '../services/market_service.dart';

/// 社区发帖时的插件选择页。
///
/// 只列出已上架（后端已审核通过）的插件；选中后把完整市场条目返回给
/// 编辑器，帖子只持久化插件 id 并携带后端返回的展示快照。
class CommunityPluginPickerPage extends StatefulWidget {
  const CommunityPluginPickerPage({super.key, required this.marketService});

  final MarketService marketService;

  @override
  State<CommunityPluginPickerPage> createState() =>
      _CommunityPluginPickerPageState();
}

class _CommunityPluginPickerPageState extends State<CommunityPluginPickerPage> {
  final TextEditingController _searchController = TextEditingController();
  List<MarketPluginEntry> _entries = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (!widget.marketService.isBackendConnected) {
      setState(() {
        _loading = false;
        _error = '尚未连接后端';
      });
      return;
    }
    if (more && (!_hasMore || _loadingMore || _loading)) return;
    setState(() {
      more ? _loadingMore = true : _loading = true;
      _error = null;
    });
    try {
      final page = more ? _page + 1 : 1;
      final result = await widget.marketService.listPlugins(
        MarketQuery(query: _searchController.text.trim(), page: page),
      );
      if (!mounted) return;
      setState(() {
        if (more) {
          final byId = {for (final item in _entries) item.id: item};
          for (final item in result.entries) {
            byId[item.id] = item;
          }
          _entries = byId.values.toList(growable: false);
        } else {
          _entries = result.entries;
        }
        _page = page;
        _hasMore = result.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('分享插件'), centerTitle: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: '搜索已上架插件',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(child: Text(_error!)),
          Center(
            child: TextButton(onPressed: _load, child: const Text('重试')),
          ),
        ],
      );
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('没有找到可分享的插件'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: _entries.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _entries.length) {
          return Center(
            child: OutlinedButton(
              onPressed: _loadingMore ? null : () => _load(more: true),
              child: Text(_loadingMore ? '加载中…' : '加载更多'),
            ),
          );
        }
        final entry = _entries[index];
        return _PluginTile(
          entry: entry,
          onTap: () => Navigator.pop(context, entry),
        );
      },
    );
  }
}

class _PluginTile extends StatelessWidget {
  const _PluginTile({required this.entry, required this.onTap});

  final MarketPluginEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.extension)),
        title: Text(
          entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.description.isEmpty ? '暂无描述' : entry.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text('v${entry.version}'),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
