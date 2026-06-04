import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plugin.dart';
import '../providers/plugin_provider.dart';
import '../widgets/plugin_icon.dart';

class PluginManagementPage extends StatelessWidget {
  const PluginManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PluginProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件管理'),
        actions: [
          IconButton(
            tooltip: '刷新插件',
            onPressed: provider.loading
                ? null
                : () => _runAction(
                    context,
                    () => context.read<PluginProvider>().refreshManifests(
                      save: true,
                    ),
                    success: '插件已刷新',
                  ),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<_PluginImportAction>(
            tooltip: '导入插件',
            onSelected: (action) => _importPlugin(context, action),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _PluginImportAction.directory,
                child: ListTile(
                  leading: Icon(Icons.folder_open),
                  title: Text('导入目录'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _PluginImportAction.zip,
                child: ListTile(
                  leading: Icon(Icons.archive_outlined),
                  title: Text('导入 ZIP'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: provider.plugins.isEmpty
          ? const _EmptyPlugins()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: provider.plugins.length,
              itemBuilder: (context, index) {
                return _PluginCard(plugin: provider.plugins[index]);
              },
            ),
    );
  }

  Future<void> _importPlugin(
    BuildContext context,
    _PluginImportAction action,
  ) async {
    if (action == _PluginImportAction.directory) {
      final path = await FilePicker.getDirectoryPath(dialogTitle: '选择插件目录');
      if (path == null || !context.mounted) return;
      await _runAction(
        context,
        () => context.read<PluginProvider>().importDirectory(path),
        success: '插件已导入',
      );
      return;
    }

    final result = await FilePicker.pickFiles(
      dialogTitle: '选择插件 ZIP',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;
    await _runAction(
      context,
      () => context.read<PluginProvider>().importZip(path),
      success: '插件已导入',
    );
  }
}

class _PluginCard extends StatelessWidget {
  const _PluginCard({required this.plugin});

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
          manifest.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${manifest.version} · ${plugin.enabled ? '已启用' : '已禁用'}'),
              const SizedBox(height: 2),
              Text(
                '${manifest.tools.length} 个工具 · ${manifest.functions.length} 个函数 · ${manifest.featurePages.length} 个功能页',
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
        trailing: Switch(
          value: plugin.enabled,
          onChanged: plugin.hasError
              ? null
              : (value) => _runAction(
                  context,
                  () => context.read<PluginProvider>().setEnabled(
                    plugin.id,
                    value,
                  ),
                ),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PluginDetailPage(pluginId: plugin.id),
          ),
        ),
      ),
    );
  }
}

class PluginDetailPage extends StatelessWidget {
  const PluginDetailPage({super.key, required this.pluginId});

  final String pluginId;

  @override
  Widget build(BuildContext context) {
    final plugin = context.watch<PluginProvider>().pluginById(pluginId);
    if (plugin == null) {
      return const Scaffold(body: Center(child: Text('插件不存在')));
    }
    final manifest = plugin.manifest;
    return Scaffold(
      appBar: AppBar(title: Text(manifest.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PluginHeader(plugin: plugin),
          const SizedBox(height: 12),
          _SectionCard(
            title: '权限',
            child: manifest.permissions.isEmpty
                ? const Text('此插件未声明权限')
                : Column(
                    children: manifest.permissions.map((permission) {
                      final granted = plugin.grantedPermissions.contains(
                        permission,
                      );
                      return CheckboxListTile(
                        value: granted,
                        title: Text(_permissionLabel(permission)),
                        subtitle: Text(permission),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          final next = plugin.grantedPermissions.toSet();
                          if (value == true) {
                            next.add(permission);
                          } else {
                            next.remove(permission);
                          }
                          _runAction(
                            context,
                            () => context
                                .read<PluginProvider>()
                                .setGrantedPermissions(
                                  plugin.id,
                                  next.toList(growable: false),
                                ),
                          );
                        },
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 12),
          _DefinitionListCard(
            title: 'Tools',
            emptyText: '未提供模型工具',
            children: manifest.tools
                .map(
                  (tool) => ListTile(
                    leading: const Icon(Icons.build_outlined),
                    title: Text(tool.name),
                    subtitle: Text(
                      tool.description.isEmpty
                          ? tool.handler
                          : tool.description,
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          _DefinitionListCard(
            title: 'Functions',
            emptyText: '未声明内部函数',
            children: manifest.functions
                .map(
                  (function) => ListTile(
                    leading: const Icon(Icons.functions),
                    title: Text(function.name),
                    subtitle: Text(function.handler),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: '功能页',
            child: manifest.featurePages.isEmpty
                ? const Text('未提供 WebView 功能页')
                : Column(
                    children: manifest.featurePages.map((page) {
                      return SwitchListTile(
                        value: plugin.enabledFeaturePages.contains(page.id),
                        title: Text(page.title.isEmpty ? page.id : page.title),
                        subtitle: Text(page.entry),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) => _runAction(
                          context,
                          () => context
                              .read<PluginProvider>()
                              .setFeaturePageEnabled(plugin.id, page.id, value),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          if (manifest.settings.isNotEmpty) ...[
            const SizedBox(height: 12),
            _PluginSettingsCard(plugin: plugin),
          ],
          const SizedBox(height: 12),
          _SectionCard(
            title: '危险操作',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _runAction(
                    context,
                    () => context.read<PluginProvider>().refreshManifests(
                      save: true,
                    ),
                    success: '插件已重新加载',
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新加载插件'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => _confirmDelete(context, plugin),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除插件'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    InstalledPlugin plugin,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除插件'),
        content: Text('确定删除 ${plugin.manifest.name}？插件文件会从应用私有目录移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _runAction(
      context,
      () => context.read<PluginProvider>().deletePlugin(plugin.id),
      success: '插件已删除',
    );
    if (context.mounted) Navigator.pop(context);
  }
}

class _PluginHeader extends StatelessWidget {
  const _PluginHeader({required this.plugin});

  final InstalledPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final manifest = plugin.manifest;
    return _SectionCard(
      title: '概览',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(manifest.description.isEmpty ? '无描述' : manifest.description),
          const SizedBox(height: 12),
          _InfoRow(label: 'ID', value: manifest.id),
          _InfoRow(label: '版本', value: manifest.version),
          if (manifest.icon.isNotEmpty)
            _InfoRow(label: '图标', value: manifest.icon),
          if (manifest.author.isNotEmpty)
            _InfoRow(label: '作者', value: manifest.author),
          _InfoRow(label: '入口', value: manifest.entry),
          _InfoRow(label: '路径', value: plugin.path),
          if (plugin.loadError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                plugin.loadError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _PluginSettingsCard extends StatelessWidget {
  const _PluginSettingsCard({required this.plugin});

  final InstalledPlugin plugin;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: context.read<PluginProvider>().loadSettings(plugin.id),
      builder: (context, snapshot) {
        final values = snapshot.data ?? const <String, dynamic>{};
        return _SectionCard(
          title: '插件设置',
          child: Column(
            children: plugin.manifest.settings.map((setting) {
              final value = values[setting.key] ?? setting.defaultValue;
              return _PluginSettingTile(
                pluginId: plugin.id,
                setting: setting,
                value: value,
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _PluginSettingTile extends StatelessWidget {
  const _PluginSettingTile({
    required this.pluginId,
    required this.setting,
    required this.value,
  });

  final String pluginId;
  final PluginSettingDefinition setting;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    if (setting.type == 'boolean') {
      return SwitchListTile(
        value: value as bool? ?? false,
        title: Text(setting.title),
        subtitle: Text(setting.key),
        contentPadding: EdgeInsets.zero,
        onChanged: (next) => context.read<PluginProvider>().updateSetting(
          pluginId,
          setting.key,
          next,
        ),
      );
    }
    if (setting.type == 'select') {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(setting.title),
        subtitle: DropdownButtonFormField<String>(
          initialValue: value?.toString(),
          items: setting.options.map((option) {
            final optionValue = option['value']?.toString() ?? '';
            return DropdownMenuItem(
              value: optionValue,
              child: Text(option['label']?.toString() ?? optionValue),
            );
          }).toList(),
          onChanged: (next) => context.read<PluginProvider>().updateSetting(
            pluginId,
            setting.key,
            next,
          ),
        ),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(setting.title),
      subtitle: Text(value?.toString() ?? '未设置'),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () => _editTextSetting(context),
    );
  }

  Future<void> _editTextSetting(BuildContext context) async {
    final controller = TextEditingController(text: value?.toString() ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(setting.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: setting.key),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !context.mounted) return;
    await context.read<PluginProvider>().updateSetting(
      pluginId,
      setting.key,
      result,
    );
  }
}

class _DefinitionListCard extends StatelessWidget {
  const _DefinitionListCard({
    required this.title,
    required this.emptyText,
    required this.children,
  });

  final String title;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: title,
      child: children.isEmpty ? Text(emptyText) : Column(children: children),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

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
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

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
            width: 64,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _EmptyPlugins extends StatelessWidget {
  const _EmptyPlugins();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension, size: 56, color: Colors.grey[500]),
            const SizedBox(height: 16),
            Text('暂无插件', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              '通过右上角按钮导入包含 plugin.json 的插件目录或 ZIP。',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

String _permissionLabel(String permission) {
  return switch (permission) {
    'notes:read' => '读取笔记',
    'notes:write' => '修改笔记',
    'todos:read' => '读取待办',
    'todos:write' => '修改待办',
    'schedules:read' => '读取日程',
    'schedules:write' => '修改日程',
    'model:chat' => '调用模型',
    'storage:read' => '读取插件存储',
    'storage:write' => '写入插件存储',
    'webview:bridge' => '使用 WebView Bridge',
    'native:location' => '获取位置',
    'native:open_app' => '打开应用',
    _ => permission,
  };
}

Future<void> _runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (!context.mounted || success == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(success)));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('操作失败: $e')));
  }
}

enum _PluginImportAction { directory, zip }
