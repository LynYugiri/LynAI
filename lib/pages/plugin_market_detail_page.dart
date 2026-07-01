import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plugin_market_entry.dart';
import '../providers/plugin_provider.dart';
import '../services/market_service.dart';
import '../utils/snackbar_utils.dart';

/// 插件市场详情页。
///
/// 展示单个 [MarketPluginEntry] 的完整信息：截图、描述、权限清单、版本。
/// 提供安装按钮，点击后通过 [MarketService] 下载 ZIP 字节并交给
/// [PluginProvider.importZipBytes] 完成本地安装。
///
class PluginMarketDetailPage extends StatefulWidget {
  const PluginMarketDetailPage({
    super.key,
    required this.entry,
    required this.marketService,
  });

  final MarketPluginEntry entry;
  final MarketService marketService;

  @override
  State<PluginMarketDetailPage> createState() => _PluginMarketDetailPageState();
}

class _PluginMarketDetailPageState extends State<PluginMarketDetailPage> {
  bool _installing = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(entry.name), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(entry: entry),
          const SizedBox(height: 16),
          if (entry.screenshots.isNotEmpty) ...[
            _ScreenshotCarousel(screenshots: entry.screenshots),
            const SizedBox(height: 16),
          ],
          _Section(
            title: '描述',
            child: Text(entry.description.isEmpty ? '暂无描述' : entry.description),
          ),
          const SizedBox(height: 12),
          _Section(
            title: '权限',
            child: entry.permissions.isEmpty
                ? const Text('此插件未声明权限')
                : Column(
                    children: entry.permissions
                        .map(
                          (p) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.lock_outline, size: 20),
                            title: Text(p),
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: '版本',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tag, size: 20),
              title: Text('v${entry.version}'),
              subtitle: entry.author.isNotEmpty
                  ? Text('作者: ${entry.author}')
                  : null,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _installing ? null : _install,
            icon: _installing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            label: Text(_installing ? '安装中…' : '安装'),
          ),
          if (!widget.marketService.isBackendConnected) ...[
            const SizedBox(height: 12),
            Text(
              '尚未连接后端，安装功能不可用。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _install() async {
    setState(() => _installing = true);
    try {
      final bytes = await widget.marketService.downloadPlugin(widget.entry.id);
      if (!mounted) return;
      await context.read<PluginProvider>().importZipBytes(bytes);
      if (!mounted) return;
      showShortSnackBar(context, '${widget.entry.name} 已安装');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, '安装失败', details: e.toString());
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }
}

/// 详情页头部：图标 + 名称 + 作者。
class _Header extends StatelessWidget {
  const _Header({required this.entry});

  final MarketPluginEntry entry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(radius: 28, child: Icon(Icons.extension, size: 32)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (entry.author.isNotEmpty) Text('作者: ${entry.author}'),
              if (entry.category.isNotEmpty)
                Text(
                  entry.category,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 截图轮播（占位实现，后端就绪后加载远端图片）。
class _ScreenshotCarousel extends StatelessWidget {
  const _ScreenshotCarousel({required this.screenshots});

  final List<String> screenshots;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: screenshots.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return Container(
            width: 240,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: Icon(Icons.image_outlined, size: 48)),
          );
        },
      ),
    );
  }
}

/// 小节容器。
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
