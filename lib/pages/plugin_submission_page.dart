import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/plugin_provider.dart';
import '../services/backend_client.dart';
import '../services/remote_market_service.dart';
import '../utils/snackbar_utils.dart';

/// 插件提交页面。
///
/// 从本地已安装插件中选择一个，构建 ZIP 上传到后端市场。
/// 上传后插件进入 `pending` 状态，等待管理员审核。
class PluginSubmissionPage extends StatefulWidget {
  const PluginSubmissionPage({super.key});

  @override
  State<PluginSubmissionPage> createState() => _PluginSubmissionPageState();
}

class _PluginSubmissionPageState extends State<PluginSubmissionPage> {
  String? _selectedPluginId;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PluginProvider>();
    final plugins = provider.plugins;

    return Scaffold(
      appBar: AppBar(title: const Text('提交插件'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '从已安装插件中选择一个提交到市场。提交后需要管理员审核通过才能上架。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (plugins.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('没有已安装的插件'),
                subtitle: Text('先安装或开发一个插件后再提交。'),
              ),
            )
          else
            RadioGroup<String>(
              groupValue: _selectedPluginId,
              onChanged: (value) {
                setState(() => _selectedPluginId = value);
              },
              child: Column(
                children: plugins
                    .map(
                      (plugin) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Radio<String>(value: plugin.id),
                          title: Text(plugin.displayName),
                          subtitle: Text(
                            'v${plugin.manifest.version} · '
                            '${plugin.manifest.author.isNotEmpty ? plugin.manifest.author : "未知作者"}',
                          ),
                          onTap: () {
                            setState(() => _selectedPluginId = plugin.id);
                          },
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          const SizedBox(height: 24),
          if (_selectedPluginId != null) ...[
            _PluginPreviewCard(
              plugin: plugins.firstWhere((p) => p.id == _selectedPluginId),
            ),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            onPressed: _selectedPluginId == null || _submitting
                ? null
                : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload),
            label: Text(_submitting ? '提交中…' : '提交到市场'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_selectedPluginId == null) return;
    setState(() => _submitting = true);
    try {
      final provider = context.read<PluginProvider>();
      final backend = context.read<BackendClient>();

      final zipBytes = await provider.buildPluginZipBytes(_selectedPluginId!);
      final service = RemoteMarketService(backend);
      final entry = await service.submitPlugin(zipBytes);

      if (!mounted) return;
      showShortSnackBar(context, '${entry.name} v${entry.version} 已提交，等待审核');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, '提交失败', details: e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

/// 插件预览卡片，展示即将提交的插件信息。
class _PluginPreviewCard extends StatelessWidget {
  const _PluginPreviewCard({required this.plugin});

  final dynamic plugin;

  @override
  Widget build(BuildContext context) {
    final manifest = plugin.manifest;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('提交预览', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _Row(label: 'ID', value: manifest.id),
            _Row(label: '名称', value: manifest.name),
            _Row(label: '版本', value: 'v${manifest.version}'),
            _Row(
              label: '作者',
              value: manifest.author.isNotEmpty ? manifest.author : '未设置',
            ),
            _Row(
              label: '描述',
              value: manifest.description.isNotEmpty
                  ? manifest.description
                  : '暂无',
            ),
            if (manifest.permissions.isNotEmpty)
              _Row(label: '权限', value: manifest.permissions.join(', ')),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
