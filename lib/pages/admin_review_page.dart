import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plugin_market_entry.dart';
import '../services/backend_client.dart';
import '../services/remote_market_service.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/text_editing_controller_host.dart';

/// 管理员审核页面。
///
/// 列出后端 `pending` 状态的插件提交，允许管理员批准上架或驳回。
/// 仅管理员可见——设置页根据 `AccountUser.isAdmin` 决定是否显示入口。
class AdminReviewPage extends StatefulWidget {
  const AdminReviewPage({super.key});

  @override
  State<AdminReviewPage> createState() => _AdminReviewPageState();
}

class _AdminReviewPageState extends State<AdminReviewPage> {
  List<MarketPluginEntry> _pending = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
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
      final entries = await service.pendingPlugins();
      if (!mounted) return;
      setState(() {
        _pending = entries;
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
        title: const Text('审核管理'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPending,
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
            Text(_error!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadPending, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_pending.isEmpty) {
      return const Center(child: Text('暂无待审核插件'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _pending.length,
      itemBuilder: (context, index) {
        final entry = _pending[index];
        return _PendingPluginCard(
          entry: entry,
          onApprove: () => _approve(entry),
          onReject: () => _reject(entry),
        );
      },
    );
  }

  Future<void> _approve(MarketPluginEntry entry) async {
    final backend = context.read<BackendClient>();
    try {
      await RemoteMarketService(backend).approvePlugin(entry.id);
      if (!mounted) return;
      showShortSnackBar(context, '${entry.name} 已批准');
      _loadPending();
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, '批准失败', details: e.toString());
    }
  }

  Future<void> _reject(MarketPluginEntry entry) async {
    final backend = context.read<BackendClient>();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => TextEditingControllerHost(
        initialTexts: const [''],
        builder: (ctx, controllers) {
          final controller = controllers.single;
          return AlertDialog(
            title: Text('驳回 ${entry.name}'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '驳回理由（可选）',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('确认驳回'),
              ),
            ],
          );
        },
      ),
    );
    if (reason == null || !mounted) return;
    try {
      await RemoteMarketService(
        backend,
      ).rejectPlugin(entry.id, reason: reason.isEmpty ? null : reason);
      if (!mounted) return;
      showShortSnackBar(context, '${entry.name} 已驳回');
      _loadPending();
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, '驳回失败', details: e.toString());
    }
  }
}

/// 待审核插件卡片。
class _PendingPluginCard extends StatelessWidget {
  const _PendingPluginCard({
    required this.entry,
    required this.onApprove,
    required this.onReject,
  });

  final MarketPluginEntry entry;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.extension)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'v${entry.version} · ${entry.author.isNotEmpty ? entry.author : "未知作者"}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(entry.description.isEmpty ? '暂无描述' : entry.description),
            if (entry.permissions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: entry.permissions
                    .map(
                      (p) => Chip(
                        label: Text(p),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check),
                  label: const Text('批准'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close),
                  label: const Text('驳回'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
