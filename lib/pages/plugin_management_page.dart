import 'dart:convert';

import 'package:file_picker/file_picker.dart' show FileType;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plugin.dart';
import '../models/plugin_config_schema.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../repositories/plugin_repository.dart';
import '../services/lynai_permission_definitions.dart';
import 'plugin_creation_page.dart';
import 'plugin_file_editor_page.dart';
import 'plugin_studio_page.dart';
import '../utils/file_picker_io_utils.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/model_config_picker.dart';
import '../widgets/plugin_icon.dart';
import '../widgets/text_editing_controller_host.dart';

/// 插件管理页面。
///
/// 展示已安装的插件列表和未安装的内置插件，支持启用/禁用、导入 ZIP 等操作。
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
          IconButton(
            tooltip: '新建插件',
            onPressed: provider.loading ? null : () => _createPlugin(context),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: '导入 ZIP 插件',
            onPressed: provider.loading
                ? null
                : () => _importPluginZip(context),
            icon: const Icon(Icons.archive_outlined),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          const _BuiltInPluginsSection(),
          SliverToBoxAdapter(
            child: provider.plugins.isEmpty
                ? const _EmptyPlugins()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: provider.plugins.length,
                    itemBuilder: (context, index) {
                      return _PluginCard(plugin: provider.plugins[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 打开文件选择器选取 ZIP 文件后，调用 [PluginProvider.importZip] 导入插件。
  Future<void> _importPluginZip(BuildContext context) async {
    final file = await pickSingleFilePayload(
      dialogTitle: '选择插件 ZIP',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (file == null || !context.mounted) return;
    await _runAction(
      context,
      () async =>
          context.read<PluginProvider>().importZipBytes(await file.readBytes()),
      success: '插件已导入',
    );
  }

  /// 打开新建插件向导，创建成功后进入插件详情页继续编辑。
  Future<void> _createPlugin(BuildContext context) async {
    final pluginId = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const PluginCreationPage()),
    );
    if (pluginId == null || !context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PluginDetailPage(pluginId: pluginId)),
    );
  }
}

/// 插件列表卡片。
///
/// 展示插件图标、名称、版本、工具数、功能页数及启用开关。
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
    final canDelete = context.select<PluginProvider, bool>(
      (provider) => provider.canDeletePlugin(plugin.id),
    );
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
          plugin.displayName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${manifest.version} · ${plugin.enabled ? '已启用' : '已禁用'}'),
              if (plugin.needsReview)
                Text(
                  '来自其他设备，需本机审查',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 2),
              Text(
                '${manifest.tools.length} 个工具 · ${manifest.functions.length} 个函数 · ${manifest.skills.length} 个 Skill · ${manifest.featurePages.length} 个功能页',
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: plugin.enabled,
              onChanged: plugin.hasError || plugin.needsReview
                  ? null
                  : (value) => _runAction(
                      context,
                      () => context.read<PluginProvider>().setEnabled(
                        plugin.id,
                        value,
                      ),
                    ),
            ),
            if (canDelete)
              IconButton(
                tooltip: '删除插件',
                color: Theme.of(context).colorScheme.error,
                onPressed: () => _confirmDeletePlugin(context, plugin),
                icon: const Icon(Icons.delete_outline),
              ),
          ],
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

/// 插件详情页面。
///
/// 展示插件的权限、工具、函数、功能页、配置文件与文件管理等完整信息。
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
    final provider = context.read<PluginProvider>();
    final dependencyPermissions =
        provider
            .dependencyCallerPermissions(plugin)
            .difference(manifest.permissions.toSet())
            .toList()
          ..sort();
    final canDelete = context.select<PluginProvider, bool>(
      (provider) => provider.canDeletePlugin(plugin.id),
    );
    return Scaffold(
      appBar: AppBar(title: Text(plugin.displayName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PluginHeader(plugin: plugin),
          const SizedBox(height: 12),
          _PluginDevStateCard(plugin: plugin),
          const SizedBox(height: 12),
          _SectionCard(
            title: '插件工坊',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('提供文件树、代码编辑器、元数据/依赖/权限编辑和恢复点。'),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.design_services_outlined),
                  label: const Text('打开插件工坊'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PluginStudioPage(pluginId: plugin.id),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (plugin.needsReview) ...[
            const SizedBox(height: 12),
            _SectionCard(
              title: '安全审查',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('此第三方插件由其他设备恢复。权限与所有能力均已清除，完成本机审查后才可启用。'),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => _runAction(
                      context,
                      () => context.read<PluginProvider>().markReviewed(
                        plugin.id,
                      ),
                      success: '已记录本机审查，插件仍保持禁用',
                    ),
                    child: const Text('完成本机审查'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _SectionCard(
            title: '权限',
            child: manifest.permissions.isEmpty && dependencyPermissions.isEmpty
                ? const Text('此插件未声明权限')
                : Column(
                    children: [
                      for (final permission in manifest.permissions)
                        if (isAutoGrantedPluginPermission(permission))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.check_circle_outline,
                              size: 18,
                            ),
                            title: Text(_permissionLabel(permission)),
                            subtitle: Text('$permission · 已自动授予'),
                          ),
                      for (final permission in manifest.permissions)
                        if (!isAutoGrantedPluginPermission(permission))
                          CheckboxListTile(
                            value: plugin.grantedPermissions.contains(
                              permission,
                            ),
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
                          ),
                      for (final permission in dependencyPermissions)
                        if (isAutoGrantedPluginPermission(permission))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.check_circle_outline,
                              size: 18,
                            ),
                            title: Text(_permissionLabel(permission)),
                            subtitle: Text('$permission · 依赖函数要求 · 已自动授予'),
                          ),
                      for (final permission in dependencyPermissions)
                        if (!isAutoGrantedPluginPermission(permission))
                          CheckboxListTile(
                            value: plugin.grantedPermissions.contains(
                              permission,
                            ),
                            title: Text(_permissionLabel(permission)),
                            subtitle: Text('$permission · 依赖函数要求'),
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
                          ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Tools',
            child: manifest.tools.isEmpty
                ? const Text('未提供模型工具')
                : Column(
                    children: manifest.tools.map((tool) {
                      return SwitchListTile(
                        value: plugin.enabledTools.contains(tool.name),
                        title: Text(tool.name),
                        subtitle: Text(
                          tool.description.isEmpty
                              ? tool.handler
                              : tool.description,
                        ),
                        secondary: const Icon(Icons.build_outlined),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) => _runAction(
                          context,
                          () => context.read<PluginProvider>().setToolEnabled(
                            plugin.id,
                            tool.name,
                            value,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Functions',
            child: manifest.functions.isEmpty
                ? const Text('未声明内部函数')
                : Column(
                    children: manifest.functions.map((function) {
                      return SwitchListTile(
                        value: plugin.enabledFunctions.contains(function.name),
                        title: Text(function.name),
                        subtitle: Text(function.handler),
                        secondary: const Icon(Icons.functions),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) => _runAction(
                          context,
                          () =>
                              context.read<PluginProvider>().setFunctionEnabled(
                                plugin.id,
                                function.name,
                                value,
                              ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Skills',
            child: manifest.skills.isEmpty
                ? const Text('未声明 Skill')
                : Column(
                    children: manifest.skills.map((skill) {
                      final title = skill.title.isEmpty
                          ? skill.name
                          : skill.title;
                      return SwitchListTile(
                        value: plugin.enabledSkills.contains(skill.name),
                        title: Text(title),
                        subtitle: Text(
                          skill.description.isEmpty
                              ? 'skills/${skill.name}.md'
                              : skill.description,
                        ),
                        secondary: const Icon(Icons.auto_awesome_motion),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) => _runAction(
                          context,
                          () => context.read<PluginProvider>().setSkillEnabled(
                            plugin.id,
                            skill.name,
                            value,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
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
          _PluginConfigCard(plugin: plugin),
          const SizedBox(height: 12),
          _PluginFilesCard(plugin: plugin),
          const SizedBox(height: 12),
          _SectionCard(
            title: '危险操作',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _renameDisplayName(context, plugin),
                  icon: const Icon(Icons.drive_file_rename_outline),
                  label: const Text('修改显示名'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _runAction(
                    context,
                    () => context.read<PluginProvider>().createSnapshot(
                      plugin.id,
                    ),
                    success: '快照已创建',
                  ),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('创建快照'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _exportPlugin(context, plugin),
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('导出插件 ZIP'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _confirmResetDefaults(context, plugin),
                  icon: const Icon(Icons.restore_page_outlined),
                  label: const Text('重置为默认'),
                ),
                if (plugin.isSnapshot) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _editSnapshotIdentity(context, plugin),
                    icon: const Icon(Icons.badge_outlined),
                    label: const Text('修改快照 ID/Name'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _confirmRestoreSnapshot(context, plugin),
                    icon: const Icon(Icons.restore_outlined),
                    label: const Text('恢复到原插件'),
                  ),
                ],
                const SizedBox(height: 8),
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
                if (canDelete) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () => _confirmDeletePlugin(
                      context,
                      plugin,
                      popAfterDelete: true,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(plugin.isSnapshot ? '删除快照' : '删除插件'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _renameDisplayName(
    BuildContext context,
    InstalledPlugin plugin,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => TextEditingControllerHost(
        initialTexts: [plugin.displayName],
        builder: (context, controllers) {
          final controller = controllers.single;
          return AlertDialog(
            title: const Text('修改显示名'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '显示名',
                border: OutlineInputBorder(),
              ),
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
          );
        },
      ),
    );
    if (result == null || !context.mounted) return;
    await _runAction(
      context,
      () => context.read<PluginProvider>().renameDisplayName(plugin.id, result),
      success: '显示名已更新',
    );
  }

  Future<void> _editSnapshotIdentity(
    BuildContext context,
    InstalledPlugin plugin,
  ) async {
    String? error;
    final result = await showDialog<({String id, String name})>(
      context: context,
      builder: (context) => TextEditingControllerHost(
        initialTexts: [plugin.id, plugin.manifest.name],
        builder: (context, controllers) {
          final idController = controllers[0];
          final nameController = controllers[1];
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('修改快照 ID/Name'),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: idController,
                      decoration: InputDecoration(
                        labelText: '插件 ID',
                        border: const OutlineInputBorder(),
                        errorText: error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: '插件 name',
                        border: OutlineInputBorder(),
                      ),
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
                    final id = idController.text.trim();
                    final name = nameController.text.trim();
                    if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(id)) {
                      setDialogState(() => error = 'ID 只能包含字母、数字、下划线、点和横线');
                      return;
                    }
                    if (name.isEmpty) {
                      setDialogState(() => error = 'Name 不能为空');
                      return;
                    }
                    Navigator.pop(context, (id: id, name: name));
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (result == null || !context.mounted) return;
    await _runAction(
      context,
      () => context.read<PluginProvider>().updateSnapshotIdentity(
        plugin.id,
        result.id,
        result.name,
      ),
      success: '快照身份已更新',
    );
  }

  Future<void> _exportPlugin(
    BuildContext context,
    InstalledPlugin plugin,
  ) async {
    await _runAction(context, () async {
      final bytes = await context.read<PluginProvider>().buildPluginZipBytes(
        plugin.id,
      );
      await saveBytesWithPicker(
        dialogTitle: '导出插件 ZIP',
        fileName: '${_safeFileName(plugin.displayName)}.zip',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        bytes: bytes,
      );
    }, success: '插件已导出');
  }

  Future<void> _confirmResetDefaults(
    BuildContext context,
    InstalledPlugin plugin,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置为默认'),
        content: Text('将删除 ${plugin.displayName} 的所有用户自定义文件，并回退到出厂默认。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _runAction(
      context,
      () => context.read<PluginProvider>().resetPluginDefaults(plugin.id),
      success: '已重置为默认',
    );
  }

  Future<void> _confirmRestoreSnapshot(
    BuildContext context,
    InstalledPlugin plugin,
  ) async {
    final sourceId = plugin.manifest.snapshotOf;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复到原插件'),
        content: Text('将用此快照覆盖原插件 $sourceId 的文件。快照不会删除，原插件名称和当前状态会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _runAction(
      context,
      () => context.read<PluginProvider>().restoreSnapshotToSource(plugin.id),
      success: '已恢复到原插件',
    );
  }

  String _safeFileName(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
    return cleaned.isEmpty ? 'plugin' : cleaned;
  }
}

Future<void> _confirmDeletePlugin(
  BuildContext context,
  InstalledPlugin plugin, {
  bool popAfterDelete = false,
}) async {
  final canDelete = context.read<PluginProvider>().canDeletePlugin(plugin.id);
  if (!canDelete) {
    showErrorSnackBar(context, '内置插件不可删除');
    return;
  }
  final title = plugin.isSnapshot ? '删除快照' : '删除插件';
  final message = plugin.isSnapshot
      ? '确定删除快照“${plugin.displayName}”吗？原插件不会受影响。'
      : '确定删除插件“${plugin.displayName}”吗？插件文件、设置和私有存储会一并移除。';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await context.read<PluginProvider>().deletePlugin(plugin.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$title已完成')));
    if (popAfterDelete && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  } catch (e) {
    if (!context.mounted) return;
    showErrorSnackBar(context, '删除失败', details: e.toString());
  }
}

/// 插件概览区域。
/// 插件开发状态切换卡片。
///
/// 内置插件固定为已定型；用户自建插件可在草稿/测试中/已定型之间切换。
class _PluginDevStateCard extends StatelessWidget {
  const _PluginDevStateCard({required this.plugin});

  final InstalledPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final builtIn = PluginRepository.builtInPluginIds.contains(plugin.id);
    return _SectionCard(
      title: '开发状态',
      child: builtIn
          ? ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline, size: 18),
              title: const Text('已定型 · 内置插件'),
              subtitle: const Text('内置插件核心文件只读，仅可编辑声明的 overlay 文件。'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<PluginDevState>(
                  segments: [
                    for (final state in PluginDevState.values)
                      ButtonSegment(value: state, label: Text(state.label)),
                  ],
                  selected: {plugin.devState},
                  onSelectionChanged: (selection) {
                    final state = selection.single;
                    if (state == plugin.devState) return;
                    _runAction(
                      context,
                      () => context.read<PluginProvider>().setDevState(
                        plugin.id,
                        state,
                      ),
                      success: '开发状态已切换为「${state.label}」',
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  plugin.devState.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}

/// 插件详情头部。
///
/// 以 [_SectionCard] 包裹，展示插件描述及 ID、版本、图标等基本信息。
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

/// 插件权限与功能页设置卡片。
///
/// 展示权限列表及可启用的功能页列表，并为每个功能页提供显示位置选项。
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

/// 单个设置项行。
///
/// 用于展示插件配置 schema 中的字符串、数字、布尔等基础类型字段。
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
    final result = await showDialog<String>(
      context: context,
      builder: (context) => TextEditingControllerHost(
        initialTexts: [value?.toString() ?? ''],
        builder: (context, controllers) {
          final controller = controllers.single;
          return AlertDialog(
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
          );
        },
      ),
    );
    if (result == null || !context.mounted) return;
    await context.read<PluginProvider>().updateSetting(
      pluginId,
      setting.key,
      result,
    );
  }
}

/// 插件配置文件卡片。
///
/// 展示由 manifest 声明的可编辑配置项，支持字符串、数字、布尔、枚举
/// 和模型选择器等多种类型。
class _PluginConfigCard extends StatefulWidget {
  const _PluginConfigCard({required this.plugin});

  final InstalledPlugin plugin;

  @override
  State<_PluginConfigCard> createState() => _PluginConfigCardState();
}

class _PluginConfigCardState extends State<_PluginConfigCard> {
  Map<String, dynamic>? _values;
  PluginConfigSchema? _schema;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PluginConfigCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plugin.id != widget.plugin.id) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final provider = context.read<PluginProvider>();
      final raw = await provider.loadConfig(widget.plugin.id);
      final schema = await provider.loadConfigSchema(widget.plugin.id);
      if (!mounted) return;
      setState(() {
        _schema = schema;
        _values = schema?.applyDefaults(raw) ?? raw;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _values = <String, dynamic>{};
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '配置文件',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.plugin.manifest.config.path),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (_schema == null)
                  _rawJsonEditor()
                else
                  _schemaForm(_schema!, _values ?? <String, dynamic>{}),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _saving || _error != null ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('保存配置'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _schemaForm(PluginConfigSchema schema, Map<String, dynamic> values) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (schema.description.isNotEmpty) Text(schema.description),
        for (final field in schema.fields) _fieldTile(field, values[field.key]),
      ],
    );
  }

  Widget _fieldTile(PluginConfigFieldDefinition field, Object? value) {
    final description = field.description.isEmpty
        ? field.key
        : field.description;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.titleOrKey(field.key),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          if (field.type == PluginConfigFieldType.boolean)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: value as bool? ?? false,
              title: Text(description),
              onChanged: (next) => _setValue(field.key, next),
            )
          else if (field.type == PluginConfigFieldType.select)
            DropdownButtonFormField<Object?>(
              initialValue: value,
              decoration: InputDecoration(
                labelText: description,
                border: const OutlineInputBorder(),
              ),
              items: field.options
                  .map(
                    (option) => DropdownMenuItem<Object?>(
                      value: option.value,
                      child: Text(option.label),
                    ),
                  )
                  .toList(),
              onChanged: (next) => _setValue(field.key, next),
            )
          else if (field.type == PluginConfigFieldType.multiSelect)
            _multiSelectField(field, value)
          else if (field.type == PluginConfigFieldType.model)
            ModelConfigPicker(
              title: field.titleOrKey(field.key),
              category: field.modelCategory,
              capabilities: field.modelCapabilities,
              allowClear: field.allowClear,
              value: _modelValue(field, value),
              onChanged: (next) => _setValue(
                field.key,
                field.modelStore == PluginModelStoreMode.id
                    ? next?.modelId
                    : next?.toJson(),
              ),
            )
          else if (field.type == PluginConfigFieldType.object ||
              field.type == PluginConfigFieldType.array)
            _jsonValueField(field, value)
          else
            TextFormField(
              key: ValueKey('${widget.plugin.id}-${field.key}-${value ?? ''}'),
              initialValue: value?.toString() ?? '',
              minLines: field.type == PluginConfigFieldType.text ? 3 : 1,
              maxLines: field.type == PluginConfigFieldType.text ? 8 : 1,
              keyboardType:
                  field.type == PluginConfigFieldType.number ||
                      field.type == PluginConfigFieldType.integer
                  ? TextInputType.number
                  : TextInputType.text,
              decoration: InputDecoration(
                hintText: field.placeholder,
                helperText: description,
                border: const OutlineInputBorder(),
              ),
              onChanged: (text) =>
                  _setValue(field.key, _coerceText(field, text)),
            ),
        ],
      ),
    );
  }

  Widget _multiSelectField(PluginConfigFieldDefinition field, Object? value) {
    final selected = value is List ? value.toSet() : <Object?>{};
    return Column(
      children: field.options.map((option) {
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: selected.contains(option.value),
          title: Text(option.label),
          onChanged: (checked) {
            final next = selected.toSet();
            if (checked == true) {
              next.add(option.value);
            } else {
              next.remove(option.value);
            }
            _setValue(field.key, next.toList());
          },
        );
      }).toList(),
    );
  }

  Widget _jsonValueField(PluginConfigFieldDefinition field, Object? value) {
    return OutlinedButton.icon(
      onPressed: () => _editJsonValue(field, value),
      icon: const Icon(Icons.data_object),
      label: Text('编辑 ${field.titleOrKey(field.key)} JSON'),
    );
  }

  Widget _rawJsonEditor() {
    return OutlinedButton.icon(
      onPressed: () => _editRawJson(_values ?? <String, dynamic>{}),
      icon: const Icon(Icons.edit_outlined),
      label: const Text('编辑原始 JSON'),
    );
  }

  Object? _coerceText(PluginConfigFieldDefinition field, String text) {
    if (text.isEmpty && !field.required) return null;
    if (field.type == PluginConfigFieldType.integer) return int.tryParse(text);
    if (field.type == PluginConfigFieldType.number) return num.tryParse(text);
    return text;
  }

  ModelSelectionValue? _modelValue(
    PluginConfigFieldDefinition field,
    Object? value,
  ) {
    if (field.modelStore == PluginModelStoreMode.id) {
      final id = value as String?;
      return id == null || id.isEmpty
          ? null
          : ModelSelectionValue(
              modelId: id,
              modelName: null,
              category: field.modelCategory,
            );
    }
    if (value is! Map) return null;
    final id = value['modelId'] as String?;
    if (id == null || id.isEmpty) return null;
    return ModelSelectionValue(
      modelId: id,
      modelName: value['modelName'] as String?,
      category: value['category'] as String? ?? field.modelCategory,
    );
  }

  void _setValue(String key, Object? value) {
    setState(() {
      final next = Map<String, dynamic>.from(_values ?? const {});
      if (value == null) {
        next.remove(key);
      } else {
        next[key] = value;
      }
      _values = next;
    });
  }

  Future<void> _editJsonValue(
    PluginConfigFieldDefinition field,
    Object? value,
  ) async {
    final result = await _showJsonDialog(
      field.titleOrKey(field.key),
      value ?? {},
    );
    if (result != null) _setValue(field.key, result);
  }

  Future<void> _editRawJson(Map<String, dynamic> value) async {
    final result = await _showJsonDialog('原始配置 JSON', value);
    if (result is Map && mounted) {
      setState(() => _values = Map<String, dynamic>.from(result));
    }
  }

  Future<Object?> _showJsonDialog(String title, Object value) async {
    String? error;
    final result = await showDialog<Object?>(
      context: context,
      builder: (context) => TextEditingControllerHost(
        initialTexts: [const JsonEncoder.withIndent('  ').convert(value)],
        builder: (context, controllers) {
          final controller = controllers.single;
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 560,
                child: TextField(
                  controller: controller,
                  maxLines: 16,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    errorText: error,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    try {
                      Navigator.pop(context, jsonDecode(controller.text));
                    } catch (e) {
                      setDialogState(() => error = 'JSON 格式错误');
                    }
                  },
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        },
      ),
    );
    return result;
  }

  Future<void> _save() async {
    final values = Map<String, dynamic>.from(_values ?? const {});
    final schema = _schema;
    if (schema != null) {
      final errors = schema.validateValues(
        values,
        models: context.read<ModelConfigProvider>().models,
      );
      if (errors.isNotEmpty) {
        _showMessage(errors.map((error) => error.message).join('\n'));
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await context.read<PluginProvider>().saveConfig(widget.plugin.id, values);
      if (mounted) _showMessage('配置已保存');
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          details: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 插件文件管理卡片。
///
/// 展示插件工作目录下的文件列表，支持新建/编辑/删除/重命名文件，
/// 以及将文件恢复为内置默认版本。
class _PluginFilesCard extends StatefulWidget {
  const _PluginFilesCard({required this.plugin});

  final InstalledPlugin plugin;

  @override
  State<_PluginFilesCard> createState() => _PluginFilesCardState();
}

class _PluginFilesCardState extends State<_PluginFilesCard> {
  late Future<List<PluginFileEntry>> _future;
  var _seenRenderVersion = 0;

  @override
  void initState() {
    super.initState();
    _seenRenderVersion = context.read<PluginProvider>().renderVersion(
      widget.plugin.id,
    );
    _future = context.read<PluginProvider>().listDeveloperFiles(
      widget.plugin.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final renderVersion = context.watch<PluginProvider>().renderVersion(
      widget.plugin.id,
    );
    if (renderVersion != _seenRenderVersion) {
      _seenRenderVersion = renderVersion;
      _future = context.read<PluginProvider>().listDeveloperFiles(
        widget.plugin.id,
      );
    }
    return _SectionCard(
      title: '插件文件',
      child: FutureBuilder<List<PluginFileEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final files = snapshot.data!;
          if (files.isEmpty) return const Text('没有文件');
          final hasFilesWrite = widget.plugin.grantedPermissions.contains(
            'files:write',
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...files.map((file) {
                final trailing = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (file.hasDefault && !file.isDefault)
                      IconButton(
                        tooltip: '恢复默认',
                        icon: const Icon(Icons.restore, size: 18),
                        onPressed: () => _restoreDefault(file),
                      ),
                    Icon(
                      file.isEditable
                          ? Icons.edit_outlined
                          : Icons.visibility_outlined,
                    ),
                  ],
                );
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    file.isDirectory
                        ? Icons.folder_outlined
                        : Icons.insert_drive_file_outlined,
                    color: file.isDefault ? Colors.grey[600] : null,
                  ),
                  title: Text(
                    file.path,
                    style: TextStyle(
                      color: file.isDefault ? Colors.grey[500] : null,
                    ),
                  ),
                  subtitle: Text(
                    file.isDirectory
                        ? '目录'
                        : file.isDefault
                        ? '出厂版本'
                        : '${file.type} · ${file.size} bytes',
                  ),
                  trailing: trailing,
                  onTap: file.isDirectory ? null : () => _openFile(file),
                  onLongPress: file.isDirectory
                      ? null
                      : () => _showFileActions(file),
                );
              }),
              if (hasFilesWrite)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加文件'),
                    onPressed: _showAddFileMenu,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openFile(PluginFileEntry file) async {
    try {
      final provider = context.read<PluginProvider>();
      final content = await provider.readDeveloperFile(
        widget.plugin.id,
        file.path,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PluginFileEditorPage(
            pluginId: widget.plugin.id,
            path: file.path,
            initialContent: content,
            readOnly: !file.isEditable,
          ),
        ),
      );
      if (!mounted) return;
      setState(() => _future = provider.listDeveloperFiles(widget.plugin.id));
    } catch (e) {
      if (mounted) {
        _showError(e);
      }
    }
  }

  bool _isCoreFile(PluginFileEntry file) {
    return context.read<PluginProvider>().isCoreDeveloperFile(
      widget.plugin.id,
      file.path,
    );
  }

  Future<void> _showFileActions(PluginFileEntry file) async {
    final isCore = _isCoreFile(file);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (file.isEditable && !file.isDefault && !isCore)
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('重命名'),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
            if (file.hasDefault && !file.isDefault)
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('恢复默认'),
                onTap: () => Navigator.pop(context, 'restore'),
              ),
            if (file.isEditable && !file.isDefault && !isCore)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  '删除',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'rename':
        await _renameFile(file);
      case 'restore':
        await _restoreDefault(file);
      case 'delete':
        await _deleteFile(file);
    }
  }

  Future<void> _renameFile(PluginFileEntry file) async {
    final next = await showDialog<String>(
      context: context,
      builder: (context) => TextEditingControllerHost(
        initialTexts: [file.path],
        builder: (context, controllers) {
          final controller = controllers.single;
          return AlertDialog(
            title: const Text('重命名文件'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '新路径',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('重命名'),
              ),
            ],
          );
        },
      ),
    );
    if (next == null || next.isEmpty || !mounted) return;
    try {
      final provider = context.read<PluginProvider>();
      await provider.renameFile(widget.plugin.id, file.path, next);
      setState(() => _future = provider.listDeveloperFiles(widget.plugin.id));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文件已重命名')));
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _deleteFile(PluginFileEntry file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定删除 "${file.path}"？'),
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
    if (confirmed != true || !mounted) return;
    try {
      final provider = context.read<PluginProvider>();
      await provider.deleteFile(widget.plugin.id, file.path);
      setState(() => _future = provider.listDeveloperFiles(widget.plugin.id));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文件已删除')));
      }
    } catch (e) {
      _showError(e);
    }
  }

  /// 弹出确认对话框后将指定插件文件恢复为出厂默认版本。
  Future<void> _restoreDefault(PluginFileEntry file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认'),
        content: Text('将 "${file.path}" 恢复为出厂默认版本，当前修改将被丢弃。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复默认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final provider = context.read<PluginProvider>();
      await provider.deleteFile(widget.plugin.id, file.path);
      setState(() => _future = provider.listDeveloperFiles(widget.plugin.id));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已恢复默认')));
      }
    } catch (e) {
      if (mounted) {
        _showError(e);
      }
    }
  }

  Future<void> _showAddFileMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('新文件'),
              onTap: () => Navigator.pop(context, 'new'),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('上传文件'),
              onTap: () => Navigator.pop(context, 'upload'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'new') {
      await _createFile();
    } else if (action == 'upload') {
      await _uploadFile();
    }
  }

  /// 输入路径后打开独立编辑页，保存时才创建文件。
  Future<void> _createFile() async {
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => TextEditingControllerHost(
        initialTexts: const [''],
        builder: (context, controllers) {
          final nameController = controllers.single;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('新建文件'),
                content: SizedBox(
                  width: 480,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: '文件名',
                          hintText: '例如 style.css',
                          border: const OutlineInputBorder(),
                          errorText: error,
                        ),
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
                      final name = nameController.text.trim();
                      if (name.isEmpty) {
                        setDialogState(() => error = '文件名不能为空');
                        return;
                      }
                      Navigator.pop(context, name);
                    },
                    child: const Text('创建'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
    final resultPath = result;
    if (resultPath == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PluginFileEditorPage(
          pluginId: widget.plugin.id,
          path: resultPath,
          initialContent: '',
        ),
      ),
    );
    if (!mounted) return;
    setState(
      () => _future = context.read<PluginProvider>().listDeveloperFiles(
        widget.plugin.id,
      ),
    );
  }

  Future<void> _uploadFile() async {
    final file = await pickSingleFilePayload();
    if (file == null || !mounted) return;
    final targetPath = await showDialog<String>(
      context: context,
      builder: (context) => TextEditingControllerHost(
        initialTexts: [file.name],
        builder: (context, controllers) {
          final controller = controllers.single;
          return AlertDialog(
            title: const Text('上传文件'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '目标路径',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('上传'),
              ),
            ],
          );
        },
      ),
    );
    if (targetPath == null || targetPath.isEmpty || !mounted) return;
    final provider = context.read<PluginProvider>();
    final pluginId = widget.plugin.id;
    try {
      final bytes = await file.readBytes();
      await provider.writeFileBytes(pluginId, targetPath, bytes);
      setState(() => _future = provider.listFiles(pluginId));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文件已上传')));
      }
    } catch (e) {
      _showError(e);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    showErrorSnackBar(
      context,
      e.toString().replaceFirst('Exception: ', ''),
      details: e.toString(),
    );
  }
}

/// 分区卡片外壳。
///
/// 为插件详情页中的各个分区（概览、设置、配置、文件等）提供统一的
/// 带标题的卡片容器。
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

/// 键值信息行。
///
/// 以标签-内容布局展示插件元数据，如 ID、版本、作者等。
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

/// 空插件列表提示。
///
/// 在没有任何已安装插件时展示引导文案。
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
              '通过右上角「+」新建插件草稿，或「ZIP」导入包含 plugin.json 的插件包。',
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
    'notes:propose' => '提出笔记修改建议',
    'notes:write' => '修改笔记',
    'todos:read' => '读取待办',
    'todos:write' => '修改待办',
    'schedules:read' => '读取日程',
    'schedules:write' => '修改日程',
    'model:chat' => '调用模型',
    'model:ocr' => '调用 OCR 模型',
    'model:recognizeFile' => '调用文件识别模型',
    'model:generateImage' => '调用图片生成模型',
    'storage:read' => '读取插件存储',
    'storage:write' => '写入插件存储',
    'webview:bridge' => '使用 WebView Bridge',
    'native:location' => '获取位置',
    'native:open_app' => '打开应用',
    'files:write' => '插件文件读写',
    'network:access' => '网络访问',
    'network:public' => '访问公开网络',
    _ => permission,
  };
}

/// 展示尚未安装的内置插件列表，并为每个插件提供一键安装按钮。
class _BuiltInPluginsSection extends StatelessWidget {
  const _BuiltInPluginsSection();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PluginProvider>();
    final builtInIds = PluginRepository.builtInPluginIds;
    final uninstalled = builtInIds
        .where((id) => !provider.pluginExistsSync(id))
        .toList();

    if (uninstalled.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('内置插件', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('内置插件来自应用自身，安全可信。'),
                const SizedBox(height: 12),
                ...uninstalled.map(
                  (id) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      child: Icon(Icons.download, size: 20),
                    ),
                    title: Text(_builtInName(id)),
                    trailing: FilledButton.tonalIcon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('安装'),
                      onPressed: provider.loading
                          ? null
                          : () => _installBuiltIn(context, provider, id),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 将内置插件的内部标识符映射为用户可见的中文名称。
  String _builtInName(String id) {
    return switch (id) {
      'status-dashboard' => '状态',
      'weather-query' => '天气查询',
      _ => id,
    };
  }

  /// 调用 [PluginProvider.importBuiltIn] 将指定内置插件安装到用户插件目录。
  Future<void> _installBuiltIn(
    BuildContext context,
    PluginProvider provider,
    String id,
  ) async {
    try {
      final plugin = await provider.installTrustedBuiltIn(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${plugin.manifest.name} 已安装')));
    } catch (e) {
      if (!context.mounted) return;
      showErrorSnackBar(context, '安装失败', details: e.toString());
    }
  }
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
    showErrorSnackBar(context, '操作失败', details: e.toString());
  }
}
