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
          ),
        );
      },
    );
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
