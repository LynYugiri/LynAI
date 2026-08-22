import 'package:file_picker/file_picker.dart' show FileType;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plugin.dart';
import '../providers/plugin_provider.dart';
import '../repositories/plugin_repository.dart';
import '../utils/file_picker_io_utils.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/plugin_icon.dart';
import '../widgets/plugin_permission_authorization_dialog.dart';
import 'plugin_creation_page.dart';
import 'plugin_studio_page.dart';

/// 插件工坊首页。
///
/// 集中展示可创作的本地插件，并在同一页面提供新建插件和导入 ZIP 入口。
class PluginStudioHomePage extends StatelessWidget {
  const PluginStudioHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PluginProvider>();
    final plugins = provider.plugins;
    final editable = plugins
        .where(
          (plugin) => !PluginRepository.builtInPluginIds.contains(plugin.id),
        )
        .toList(growable: false);
    final builtIns = plugins
        .where(
          (plugin) => PluginRepository.builtInPluginIds.contains(plugin.id),
        )
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('插件工坊'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '导入插件 ZIP',
            onPressed: provider.loading ? null : () => _importZip(context),
            icon: const Icon(Icons.archive_outlined),
          ),
          IconButton(
            tooltip: '新建插件',
            onPressed: provider.loading ? null : () => _createPlugin(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'plugin_studio_create',
        onPressed: provider.loading ? null : () => _createPlugin(context),
        icon: const Icon(Icons.add),
        label: const Text('新建插件'),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            context.read<PluginProvider>().refreshManifests(save: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            _HeroCard(
              onCreate: () => _createPlugin(context),
              onImport: () => _importZip(context),
            ),
            const SizedBox(height: 20),
            Text('我的插件', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (editable.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('还没有可编辑插件。点击“新建插件”从模板开始，或导入一个插件 ZIP。'),
                ),
              )
            else
              for (final plugin in editable) _StudioPluginCard(plugin: plugin),
            if (builtIns.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('内置插件', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final plugin in builtIns)
                _StudioPluginCard(plugin: plugin, builtIn: true),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _createPlugin(BuildContext context) async {
    final pluginId = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const PluginCreationPage()),
    );
    if (pluginId == null || !context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PluginStudioPage(pluginId: pluginId)),
    );
  }

  Future<void> _importZip(BuildContext context) async {
    final file = await pickSingleFilePayload(
      dialogTitle: '选择插件 ZIP',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (file == null || !context.mounted) return;
    try {
      final bytes = await file.readBytes();
      if (!context.mounted) return;
      final provider = context.read<PluginProvider>();
      final existingIds = provider.plugins.map((plugin) => plugin.id).toSet();
      final imported = await provider.importZipBytes(bytes);
      if (!context.mounted) return;
      final isNewInstall = !existingIds.contains(imported.id);
      if (isNewInstall) {
        await showPluginPermissionAuthorizationDialog(
          context,
          pluginId: imported.id,
        );
      }
      if (!context.mounted) return;
      showShortSnackBar(context, '插件已导入');
      if (isNewInstall) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PluginStudioPage(pluginId: imported.id),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      showErrorSnackBar(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        details: e.toString(),
      );
    }
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onCreate, required this.onImport});

  final VoidCallback onCreate;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.design_services, size: 40, color: colors.primary),
            const SizedBox(height: 12),
            Text(
              '创造你的 LynAI 能力',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '从模板创建工具、Skill 或功能页，也可以导入已有插件继续修改。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('新建插件'),
                ),
                OutlinedButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('导入 ZIP'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StudioPluginCard extends StatelessWidget {
  const _StudioPluginCard({required this.plugin, this.builtIn = false});

  final InstalledPlugin plugin;
  final bool builtIn;

  @override
  Widget build(BuildContext context) {
    final manifest = plugin.manifest;
    final color = plugin.hasError
        ? Theme.of(context).colorScheme.error
        : plugin.devState == PluginDevState.draft
        ? Colors.amber
        : plugin.devState == PluginDevState.testing
        ? Colors.blue
        : Colors.green;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
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
        subtitle: Text(
          'v${manifest.version} · ${builtIn ? "内置只读" : plugin.devState.label}\n'
          '${manifest.tools.length} 工具 · ${manifest.skills.length} Skill · ${manifest.featurePages.length} 功能页',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PluginStudioPage(pluginId: plugin.id),
          ),
        ),
      ),
    );
  }
}
