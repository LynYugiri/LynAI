import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plugin.dart';
import '../providers/plugin_provider.dart';
import '../repositories/plugin_repository.dart';
import '../utils/file_picker_io_utils.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/text_editing_controller_host.dart';
import 'plugin_file_editor_page.dart';
import 'plugin_studio_capability_editors.dart';

/// 插件工坊页面。
///
/// 以两栏布局提供插件创作入口：左侧文件树、右侧属性检查器（开发状态、元数据、
/// 能力清单、依赖、权限、恢复点）。点击文件进入全屏 [PluginFileEditorPage]
/// 编辑，避免内嵌编辑器与全屏编辑器两套体验并存。窄屏自动退化为单栏卡片布局。
class PluginStudioPage extends StatefulWidget {
  const PluginStudioPage({super.key, required this.pluginId});

  final String pluginId;

  @override
  State<PluginStudioPage> createState() => _PluginStudioPageState();
}

class _PluginStudioPageState extends State<PluginStudioPage> {
  late Future<List<PluginFileEntry>> _filesFuture;
  late Future<List<PluginRecoveryPoint>> _recoveryFuture;

  @override
  void initState() {
    super.initState();
    _filesFuture = context.read<PluginProvider>().listDeveloperFiles(
      widget.pluginId,
    );
    _recoveryFuture = context.read<PluginProvider>().listRecoveryPoints(
      widget.pluginId,
    );
  }

  void _refreshFiles() {
    setState(() {
      _filesFuture = context.read<PluginProvider>().listDeveloperFiles(
        widget.pluginId,
      );
    });
  }

  Future<void> _reloadPlugin() async {
    try {
      await context.read<PluginProvider>().refreshManifests(save: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('插件已重新加载')));
      _refreshFiles();
      setState(() {
        _recoveryFuture = context.read<PluginProvider>().listRecoveryPoints(
          widget.pluginId,
        );
      });
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          details: e.toString(),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PluginProvider>();
    final plugin = provider.pluginById(widget.pluginId);
    if (plugin == null) {
      return const Scaffold(body: Center(child: Text('插件不存在')));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('${plugin.displayName} · 插件工坊'),
        actions: [
          IconButton(
            tooltip: '保存并重新加载',
            onPressed: _reloadPlugin,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          if (!wide) {
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _fileTreeCard(plugin),
                const SizedBox(height: 12),
                ..._inspectorCards(plugin),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 300, child: _fileTreeCard(plugin)),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _inspectorCards(plugin),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---- 文件树 ----

  Widget _fileTreeCard(InstalledPlugin plugin) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('文件', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _createFile(),
                  icon: const Icon(Icons.note_add_outlined, size: 18),
                  label: const Text('新建文件'),
                ),
                TextButton.icon(
                  onPressed: () => _uploadFile(plugin),
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('上传'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 440,
              child: FutureBuilder<List<PluginFileEntry>>(
                future: _filesFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final files = snapshot.data!;
                  if (files.isEmpty) return const Text('没有文件');
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: files.length,
                    itemBuilder: (context, index) {
                      final file = files[index];
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        leading: Icon(
                          file.isDirectory
                              ? Icons.folder_outlined
                              : file.isEditable
                              ? Icons.edit_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                        ),
                        title: Text(
                          file.path,
                          style: TextStyle(
                            fontSize: 13,
                            color: file.isDefault ? Colors.grey[500] : null,
                          ),
                        ),
                        subtitle: file.isDefault
                            ? const Text(
                                '出厂版本',
                                style: TextStyle(fontSize: 11),
                              )
                            : null,
                        onTap: file.isDirectory
                            ? null
                            : () => _openFile(file),
                        onLongPress: file.isDirectory
                            ? null
                            : () => _showFileActions(file),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFile(PluginFileEntry file) async {
    try {
      final provider = context.read<PluginProvider>();
      final content = await provider.readDeveloperFile(widget.pluginId, file.path);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PluginFileEditorPage(
            pluginId: widget.pluginId,
            path: file.path,
            initialContent: content,
            readOnly: !file.isEditable,
          ),
        ),
      );
      if (!mounted) return;
      _refreshFiles();
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          details: e.toString(),
        );
      }
    }
  }

  Future<void> _createFile() async {
    final path = await showDialog<String>(
      context: context,
      builder: (context) => TextEditingControllerHost(
        initialTexts: const [''],
        builder: (context, controllers) {
          final controller = controllers.single;
          return AlertDialog(
            title: const Text('新建文件'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '文件名',
                hintText: '例如 style.css',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, controller.text.trim()),
                child: const Text('创建'),
              ),
            ],
          );
        },
      ),
    );
    if (path == null || path.isEmpty || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PluginFileEditorPage(
          pluginId: widget.pluginId,
          path: path,
          initialContent: '',
        ),
      ),
    );
    if (!mounted) return;
    _refreshFiles();
  }

  Future<void> _uploadFile(InstalledPlugin plugin) async {
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
    try {
      final bytes = await file.readBytes();
      if (!mounted) return;
      await context.read<PluginProvider>().writeFileBytes(
        widget.pluginId,
        targetPath,
        bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('文件已上传')));
      _refreshFiles();
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        details: e.toString(),
      );
    }
  }

  Future<void> _showFileActions(PluginFileEntry file) async {
    final isCore = context.read<PluginProvider>().isCoreDeveloperFile(
      widget.pluginId,
      file.path,
    );
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
      await context.read<PluginProvider>().renameFile(
        widget.pluginId,
        file.path,
        next,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文件已重命名')));
      }
      _refreshFiles();
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          details: e.toString(),
        );
      }
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
      await context.read<PluginProvider>().deleteFile(widget.pluginId, file.path);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文件已删除')));
      }
      _refreshFiles();
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          details: e.toString(),
        );
      }
    }
  }

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
      await context.read<PluginProvider>().deleteFile(widget.pluginId, file.path);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已恢复默认')));
      }
      _refreshFiles();
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          details: e.toString(),
        );
      }
    }
  }

  // ---- 属性检查器 ----

  List<Widget> _inspectorCards(InstalledPlugin plugin) {
    return [
      _StudioSection(
        title: '开发状态',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${plugin.devState.label} · ${plugin.devState.description}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<PluginDevState>(
              segments: [
                for (final state in PluginDevState.values)
                  ButtonSegment(value: state, label: Text(state.label)),
              ],
              selected: {plugin.devState},
              onSelectionChanged: PluginRepository.builtInPluginIds.contains(
                plugin.id,
              )
                  ? null
                  : (selection) {
                      final state = selection.single;
                      if (state == plugin.devState) return;
                      _runStudioAction(
                        () => context.read<PluginProvider>().setDevState(
                          plugin.id,
                          state,
                        ),
                        success: '开发状态已切换为「${state.label}」',
                      );
                    },
            ),
          ],
        ),
      ),
      _StudioSection(
        title: '能力速览',
        child: Text(
          '工具(tools) 是模型可调用的能力；函数(functions) 供插件内部或跨插件调用；'
          '命令(commands) 是命令面板选项源；Skill 是按需加载的方法论正文；'
          '功能页(featurePages) 是 WebView 界面；设置项(settings) 渲染为插件配置表单。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      _MetadataEditor(plugin: plugin, enabled: _canEditCore(plugin)),
      PluginStudioToolsEditor(plugin: plugin),
      PluginStudioFunctionsEditor(plugin: plugin),
      PluginStudioCommandsEditor(plugin: plugin),
      PluginStudioSkillsEditor(plugin: plugin),
      PluginStudioFeaturePagesEditor(plugin: plugin),
      PluginStudioSettingsEditor(plugin: plugin),
      _DependencyEditor(plugin: plugin, enabled: _canEditCore(plugin)),
      _PermissionEditor(plugin: plugin, enabled: _canEditCore(plugin)),
      _RecoveryPointsCard(
        pluginId: plugin.id,
        recoveryFuture: _recoveryFuture,
        onRestored: () {
          _refreshFiles();
          setState(() {
            _recoveryFuture = context.read<PluginProvider>().listRecoveryPoints(
              widget.pluginId,
            );
          });
        },
      ),
    ];
  }

  bool _canEditCore(InstalledPlugin plugin) {
    return context.read<PluginProvider>().canEditCore(plugin.id);
  }

  Future<void> _runStudioAction(
    Future<void> Function() action, {
    required String success,
  }) async {
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          details: e.toString(),
        );
      }
    }
  }
}

class _MetadataEditor extends StatefulWidget {
  const _MetadataEditor({required this.plugin, required this.enabled});

  final InstalledPlugin plugin;
  final bool enabled;

  @override
  State<_MetadataEditor> createState() => _MetadataEditorState();
}

class _MetadataEditorState extends State<_MetadataEditor> {
  late final TextEditingController _name;
  late final TextEditingController _version;
  late final TextEditingController _author;
  late final TextEditingController _description;

  @override
  void initState() {
    super.initState();
    final manifest = widget.plugin.manifest;
    _name = TextEditingController(text: manifest.name);
    _version = TextEditingController(text: manifest.version);
    _author = TextEditingController(text: manifest.author);
    _description = TextEditingController(text: manifest.description);
  }

  @override
  void dispose() {
    _name.dispose();
    _version.dispose();
    _author.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _StudioSection(
      title: '元数据',
      child: Column(
        children: [
          TextField(
            controller: _name,
            enabled: widget.enabled,
            decoration: const InputDecoration(labelText: '名称'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _version,
            enabled: widget.enabled,
            decoration: const InputDecoration(labelText: '版本'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _author,
            enabled: widget.enabled,
            decoration: const InputDecoration(labelText: '作者'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _description,
            enabled: widget.enabled,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '描述'),
          ),
          if (widget.enabled) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => _runSave(context),
                child: const Text('保存元数据'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _runSave(BuildContext context) async {
    try {
      await context.read<PluginProvider>().updateManifestMetadata(
        widget.plugin.id,
        name: _name.text.trim(),
        version: _version.text.trim(),
        author: _author.text.trim(),
        description: _description.text.trim(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('元数据已保存')));
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          details: e.toString(),
        );
      }
    }
  }
}

class _DependencyEditor extends StatelessWidget {
  const _DependencyEditor({required this.plugin, required this.enabled});

  final InstalledPlugin plugin;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final dependencies = plugin.manifest.dependencies;
    return _StudioSection(
      title: '依赖',
      child: Column(
        children: [
          if (dependencies.isEmpty) const Text('无依赖声明'),
          for (final entry in dependencies.entries)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(entry.key),
              subtitle: Text(entry.value),
              trailing: enabled
                  ? IconButton(
                      tooltip: '移除依赖',
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      onPressed: () => _removeDependency(context, entry.key),
                    )
                  : null,
            ),
          if (enabled) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加依赖'),
                onPressed: () => _addDependency(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addDependency(BuildContext context) async {
    final pluginId = await showDialog<String>(
      context: context,
      builder: (context) => const _DependencyDialog(),
    );
    if (pluginId == null || !context.mounted) return;
    try {
      await context.read<PluginProvider>().addDependency(
        plugin.id,
        pluginId,
        '*',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('依赖已添加')));
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          details: e.toString(),
        );
      }
    }
  }

  Future<void> _removeDependency(
    BuildContext context,
    String dependencyId,
  ) async {
    try {
      await context.read<PluginProvider>().removeDependency(
        plugin.id,
        dependencyId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('依赖已移除')));
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          details: e.toString(),
        );
      }
    }
  }
}

class _DependencyDialog extends StatefulWidget {
  const _DependencyDialog();

  @override
  State<_DependencyDialog> createState() => _DependencyDialogState();
}

class _DependencyDialogState extends State<_DependencyDialog> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final plugins = context.read<PluginProvider>().plugins;
    return AlertDialog(
      title: const Text('添加依赖'),
      content: DropdownButtonFormField<String>(
        initialValue: _selectedId,
        items: plugins
            .map(
              (plugin) => DropdownMenuItem(
                value: plugin.id,
                child: Text(plugin.displayName),
              ),
            )
            .toList(growable: false),
        onChanged: (value) => setState(() => _selectedId = value),
        decoration: const InputDecoration(labelText: '依赖插件'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selectedId == null
              ? null
              : () => Navigator.pop(context, _selectedId),
          child: const Text('添加'),
        ),
      ],
    );
  }
}

class _PermissionEditor extends StatelessWidget {
  const _PermissionEditor({required this.plugin, required this.enabled});

  final InstalledPlugin plugin;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final permissions = plugin.manifest.permissions;
    return _StudioSection(
      title: '声明权限',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (permissions.isEmpty) const Text('未声明权限'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final permission in permissions)
                InputChip(
                  label: Text(permission),
                  onDeleted: enabled
                      ? () => _removePermission(context, permission)
                      : null,
                ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加权限'),
                onPressed: () => _addPermission(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _removePermission(
    BuildContext context,
    String permission,
  ) async {
    final next = plugin.manifest.permissions.toSet()..remove(permission);
    await _savePermissions(context, next.toList(growable: false));
  }

  Future<void> _addPermission(BuildContext context) async {
    final permission = await showDialog<String>(
      context: context,
      builder: (context) => const _PermissionDialog(),
    );
    if (permission == null || !context.mounted) return;
    final next = plugin.manifest.permissions.toSet()..add(permission);
    await _savePermissions(context, next.toList(growable: false));
  }

  Future<void> _savePermissions(
    BuildContext context,
    List<String> permissions,
  ) async {
    try {
      await context.read<PluginProvider>().setManifestPermissions(
        plugin.id,
        permissions,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('权限已更新')));
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          details: e.toString(),
        );
      }
    }
  }
}

class _PermissionDialog extends StatefulWidget {
  const _PermissionDialog();

  @override
  State<_PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<_PermissionDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加权限'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '权限 ID',
          hintText: '例如 notes:read',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('添加'),
        ),
      ],
    );
  }
}

class _RecoveryPointsCard extends StatelessWidget {
  const _RecoveryPointsCard({
    required this.pluginId,
    required this.recoveryFuture,
    required this.onRestored,
  });

  final String pluginId;
  final Future<List<PluginRecoveryPoint>> recoveryFuture;
  final VoidCallback onRestored;

  @override
  Widget build(BuildContext context) {
    return _StudioSection(
      title: '恢复点',
      child: FutureBuilder<List<PluginRecoveryPoint>>(
        future: recoveryFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final points = snapshot.data!;
          return Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('立即保存恢复点'),
                  onPressed: () => _createRecoveryPoint(context),
                ),
              ),
              if (points.isEmpty) const Text('暂无恢复点'),
              for (final point in points.take(5))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restore, size: 18),
                  title: Text(point.reason),
                  subtitle: Text(
                    '${point.createdAt.toLocal()} · ${point.sizeBytes} bytes',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: TextButton(
                    onPressed: () => _restore(context, point),
                    child: const Text('恢复'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createRecoveryPoint(BuildContext context) async {
    try {
      await context.read<PluginProvider>().createRecoveryPoint(pluginId);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('恢复点已保存')));
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          details: e.toString(),
        );
      }
    }
  }

  Future<void> _restore(BuildContext context, PluginRecoveryPoint point) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复到此状态？'),
        content: Text('当前状态会自动保存为一个新恢复点，然后恢复到「${point.reason}」。'),
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
    try {
      await context.read<PluginProvider>().restoreRecoveryPoint(
        pluginId,
        point.id,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已恢复')));
      }
      onRestored();
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          details: e.toString(),
        );
      }
    }
  }
}

class _StudioSection extends StatelessWidget {
  const _StudioSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
