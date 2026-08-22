import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/conversation_plugin_artifact.dart';
import '../models/plugin.dart';
import '../providers/plugin_provider.dart';

/// 对话中由 AI 创建的插件草稿卡片。
///
/// 卡片只负责展示和动作回调，插件实时状态从 [PluginProvider] 读取，因此
/// 用户在插件工坊中的修改会立即反映到这里。插件被删除时降级为删除提示。
class PluginDraftCard extends StatelessWidget {
  const PluginDraftCard({
    super.key,
    required this.artifact,
    required this.onOpenStudio,
    this.onContinueEdit,
    this.onDismiss,
  });

  final ConversationPluginArtifact artifact;
  final VoidCallback onOpenStudio;
  final VoidCallback? onContinueEdit;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final plugin = context.watch<PluginProvider>().pluginById(
      artifact.pluginId,
    );
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.extension_outlined,
                        color: scheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          plugin?.displayName ?? artifact.pluginId,
                          style: Theme.of(context).textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    tooltip: '从对话移除',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onDismiss,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (plugin == null)
              Text(
                '插件已不在本地，可保留对话记录或从对话移除。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.outline),
              )
            else
              _PluginSummary(plugin: plugin),
            if (artifact.writtenFiles.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final file in artifact.writtenFiles.take(5))
                    Chip(
                      label: Text(file),
                      labelStyle: const TextStyle(fontSize: 11),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  if (artifact.writtenFiles.length > 5)
                    Text(
                      '等 ${artifact.writtenFiles.length} 个文件',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.design_services_outlined, size: 18),
                  label: const Text('打开插件工坊'),
                  onPressed: plugin == null ? null : onOpenStudio,
                ),
                if (onContinueEdit != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('继续完善'),
                    onPressed: plugin == null ? null : onContinueEdit,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PluginSummary extends StatelessWidget {
  const _PluginSummary({required this.plugin});

  final InstalledPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final manifest = plugin.manifest;
    final capabilities = <String>[
      if (manifest.tools.isNotEmpty) '工具 ${manifest.tools.length}',
      if (manifest.functions.isNotEmpty) '函数 ${manifest.functions.length}',
      if (manifest.skills.isNotEmpty) 'Skill ${manifest.skills.length}',
      if (manifest.featurePages.isNotEmpty)
        '功能页 ${manifest.featurePages.length}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${plugin.id} · v${manifest.version} · ${plugin.devState.label}'
          '${plugin.enabled ? ' · 已启用' : ' · 未启用'}',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (capabilities.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            capabilities.join(' · '),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        if (plugin.hasError) ...[
          const SizedBox(height: 4),
          Text(
            '加载错误：${plugin.loadError}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
      ],
    );
  }
}
