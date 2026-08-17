import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plugin.dart';
import '../providers/plugin_provider.dart';
import '../repositories/plugin_repository.dart';
import '../services/code_syntax_service.dart';
import '../utils/file_picker_io_utils.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/text_editing_controller_host.dart';
import 'plugin_file_editor_page.dart' show PluginCodeEditingController;

/// 插件工坊页面。
///
/// 以三栏布局提供插件创作入口：左侧文件树、中间代码编辑器、右侧属性检查器。
/// 窄屏自动退化为单栏卡片布局。
class PluginStudioPage extends StatefulWidget {
  const PluginStudioPage({super.key, required this.pluginId});

  final String pluginId;

  @override
  State<PluginStudioPage> createState() => _PluginStudioPageState();
}

class _PluginStudioPageState extends State<PluginStudioPage> {
  String? _selectedPath;
  PluginCodeEditingController? _controller;
  String _savedContent = '';

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

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  bool get _dirty => _controller != null && _controller!.text != _savedContent;

  Future<void> _selectFile(String path) async {
    if (_dirty && !await _confirmDiscard()) return;
    if (!mounted) return;
    final provider = context.read<PluginProvider>();
    try {
      final content = await provider.readDeveloperFile(widget.pluginId, path);
      if (!mounted) return;
      _controller?.dispose();
      _controller = PluginCodeEditingController(
        text: content,
        language: fileTypeFromPath(path),
      );
      _savedContent = content;
      setState(() => _selectedPath = path);
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
      setState(() {
        _filesFuture = context.read<PluginProvider>().listDeveloperFiles(
          widget.pluginId,
        );
      });
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        details: e.toString(),
      );
    }
  }

  Future<void> _saveFile() async {
    final controller = _controller;
    final path = _selectedPath;
    if (controller == null || path == null) return;
    try {
      await context.read<PluginProvider>().writeEditableFile(
        widget.pluginId,
        path,
        controller.text,
      );
      _savedContent = controller.text;
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文件已保存')));
        _filesFuture = context.read<PluginProvider>().listDeveloperFiles(
          widget.pluginId,
        );
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

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存修改？'),
        content: const Text('当前文件还有未保存修改，切换文件会丢失这些内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    return result == true;
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
            tooltip: '保存文件',
            onPressed:
                _selectedPath == null ||
                    !provider.isEditableFile(widget.pluginId, _selectedPath!)
                ? null
                : _saveFile,
            icon: const Icon(Icons.save),
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
                _StudioSection(title: '文件', child: _buildFileTree(plugin)),
                const SizedBox(height: 12),
                _StudioSection(title: '编辑器', child: _buildEditorPane(plugin)),
                const SizedBox(height: 12),
                _StudioSection(title: '属性', child: _buildInspector(plugin)),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 250,
                child: _StudioSection(
                  title: '文件',
                  child: _buildFileTree(plugin),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _StudioSection(
                  title: '编辑器',
                  child: _buildEditorPane(plugin),
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 320,
                child: _StudioSection(
                  title: '属性',
                  child: _buildInspector(plugin),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFileTree(InstalledPlugin plugin) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('上传文件'),
            onPressed: () => _uploadFile(plugin),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 420,
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
                  final selected = file.path == _selectedPath;
                  final editable = file.isEditable;
                  return ListTile(
                    dense: true,
                    selected: selected,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(
                      file.isDirectory
                          ? Icons.folder_outlined
                          : editable
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
                        ? const Text('出厂版本', style: TextStyle(fontSize: 11))
                        : null,
                    onTap: file.isDirectory
                        ? null
                        : () => _selectFile(file.path),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEditorPane(InstalledPlugin plugin) {
    if (_selectedPath == null) {
      return const Center(child: Text('从左侧选择一个文件开始编辑'));
    }
    final readOnly = !context.read<PluginProvider>().isEditableFile(
      widget.pluginId,
      _selectedPath!,
    );
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(_selectedPath!)),
            if (_dirty)
              TextButton(onPressed: _saveFile, child: const Text('保存')),
          ],
        ),
        const Divider(height: 1),
        SizedBox(
          height: 560,
          child: TextField(
            controller: controller,
            readOnly: readOnly,
            expands: true,
            maxLines: null,
            minLines: null,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            cursorColor: const Color(0xFF61AFEF),
            style: const TextStyle(
              fontFamily: codeFontFamily,
              fontSize: 14,
              height: 1.45,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInspector(InstalledPlugin plugin) {
    final canEditCore = context.read<PluginProvider>().canEditCore(
      widget.pluginId,
    );
    return ListView(
      shrinkWrap: true,
      children: [
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
                onSelectionChanged:
                    PluginRepository.builtInPluginIds.contains(plugin.id)
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
        const SizedBox(height: 8),
        _MetadataEditor(plugin: plugin, enabled: canEditCore),
        const SizedBox(height: 8),
        _DependencyEditor(plugin: plugin, enabled: canEditCore),
        const SizedBox(height: 8),
        _PermissionEditor(plugin: plugin, enabled: canEditCore),
        const SizedBox(height: 8),
        _RecoveryPointsCard(
          pluginId: plugin.id,
          recoveryFuture: _recoveryFuture,
          onRestored: () {
            _controller?.dispose();
            _controller = null;
            _selectedPath = null;
            setState(() {
              _filesFuture = context.read<PluginProvider>().listDeveloperFiles(
                widget.pluginId,
              );
              _recoveryFuture = context
                  .read<PluginProvider>()
                  .listRecoveryPoints(widget.pluginId);
            });
          },
        ),
      ],
    );
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
