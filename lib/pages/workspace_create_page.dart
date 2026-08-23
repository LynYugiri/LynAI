import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_quick_action.dart';
import '../models/workspace.dart';
import '../providers/plugin_provider.dart';
import '../providers/workspace_provider.dart';
import '../utils/file_picker_io_utils.dart';

/// 新建工作区页面。
///
/// 分组收集名称、插件策略、开发插件、功能页、挂载本地文件夹与添加文件。
/// 创建成功即选中新工作区；可选在创建时导入文件。
class WorkspaceCreatePage extends StatefulWidget {
  const WorkspaceCreatePage({
    super.key,
    this.suggestedName,
    this.suggestedDevPluginId,
  });

  final String? suggestedName;
  final String? suggestedDevPluginId;

  @override
  State<WorkspaceCreatePage> createState() => _WorkspaceCreatePageState();
}

class _WorkspaceCreatePageState extends State<WorkspaceCreatePage> {
  final _nameCtrl = TextEditingController();
  var _policy = WorkspacePluginPolicyMode.followGlobal;
  final _enabledPluginIds = <String>{};
  final _devPluginIds = <String>{};
  final _featureIds = <String>{};
  String? _mountedFolderPath;
  final _files = <PickedFilePayload>[];
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.suggestedName ?? '';
    final suggested = widget.suggestedDevPluginId?.trim();
    if (suggested != null && suggested.isNotEmpty) {
      _devPluginIds.add(suggested);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pluginProvider = context.watch<PluginProvider>();
    final plugins = pluginProvider.plugins;
    final enabledPlugins = plugins
        .where((plugin) => plugin.enabled && !plugin.hasError)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: const Text('新建工作区')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: '工作区名称',
              hintText: '例如：我的插件项目',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle('启用插件'),
          SegmentedButton<WorkspacePluginPolicyMode>(
            segments: const [
              ButtonSegment(
                value: WorkspacePluginPolicyMode.followGlobal,
                label: Text('跟从全局'),
              ),
              ButtonSegment(
                value: WorkspacePluginPolicyMode.custom,
                label: Text('自定义启用'),
              ),
            ],
            selected: {_policy},
            onSelectionChanged: (selection) =>
                setState(() => _policy = selection.single),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 4),
          Text(
            _policy == WorkspacePluginPolicyMode.followGlobal
                ? '使用全局已启用的插件'
                : '只能从全局已启用的插件中收窄',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_policy == WorkspacePluginPolicyMode.custom)
            for (final plugin in enabledPlugins)
              CheckboxListTile(
                value: _enabledPluginIds.contains(plugin.id),
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    _enabledPluginIds.add(plugin.id);
                  } else {
                    _enabledPluginIds.remove(plugin.id);
                  }
                }),
                title: Text(plugin.displayName),
                subtitle: pluginProvider.dependencyError(plugin) == null
                    ? null
                    : Text(
                        pluginProvider.dependencyError(plugin)!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
          const SizedBox(height: 16),
          _sectionTitle('插件（开发）'),
          for (final plugin in plugins)
            CheckboxListTile(
              value: _devPluginIds.contains(plugin.id),
              onChanged: (checked) => setState(() {
                if (checked == true) {
                  _devPluginIds.add(plugin.id);
                } else {
                  _devPluginIds.remove(plugin.id);
                }
              }),
              title: Text(plugin.displayName),
              subtitle: Text(
                plugin.enabled
                    ? '已启用 · ${plugin.devState.label}'
                    : '未启用 · ${plugin.devState.label}',
              ),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          const SizedBox(height: 16),
          _sectionTitle('功能页'),
          for (final entry in ChatQuickAction.featurePages.entries)
            if (supportedWorkspaceFeatureIds.contains(entry.key))
              CheckboxListTile(
                value: _featureIds.contains(entry.key),
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    _featureIds.add(entry.key);
                  } else {
                    _featureIds.remove(entry.key);
                  }
                }),
                title: Text(entry.value),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
          const SizedBox(height: 16),
          _sectionTitle('文件'),
          if (!Platform.isAndroid && !Platform.isIOS && !kIsWeb) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_open),
              title: Text(_mountedFolderPath ?? '挂载本地文件夹'),
              subtitle: _mountedFolderPath == null
                  ? null
                  : Text(_mountedFolderPath!),
              trailing: _mountedFolderPath == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: '移除',
                      onPressed: () =>
                          setState(() => _mountedFolderPath = null),
                    ),
              onTap: _pickFolder,
            ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.attach_file),
            title: Text(_files.isEmpty ? '添加文件' : '已选 ${_files.length} 个文件'),
            trailing: _files.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: '清空',
                    onPressed: () => setState(_files.clear),
                  ),
            onTap: _pickFiles,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _create,
            child: Text(_saving ? '正在创建…' : '创建'),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: '选择本地文件夹');
    if (path == null || !mounted) return;
    setState(() => _mountedFolderPath = path);
  }

  Future<void> _pickFiles() async {
    final files = await pickMultipleFilePayloads(dialogTitle: '添加文件到工作区');
    if (files.isEmpty || !mounted) return;
    setState(() => _files.addAll(files));
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写工作区名称')));
      return;
    }
    final pluginProvider = context.read<PluginProvider>();
    final enabled = _enabledPluginIds
        .where((id) => pluginProvider.pluginById(id) != null)
        .where((id) {
          final plugin = pluginProvider.pluginById(id)!;
          return plugin.enabled && !plugin.hasError;
        })
        .toList();
    if (_policy == WorkspacePluginPolicyMode.custom &&
        enabled.any(
          (id) =>
              pluginProvider.dependencyError(pluginProvider.pluginById(id)!) !=
              null,
        )) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('启用插件存在未满足的依赖，请调整选择')));
      return;
    }
    final dev = _devPluginIds
        .where((id) => pluginProvider.pluginById(id) != null)
        .toList();
    setState(() => _saving = true);
    try {
      final provider = context.read<WorkspaceProvider>();
      final workspace = provider.createWorkspace(
        name: name,
        featureIds: _featureIds,
        pluginPolicyMode: _policy,
        enabledPluginIds: enabled,
        devPluginIds: dev,
        mountedFolderPath: _mountedFolderPath,
      );
      for (final file in _files) {
        await provider.importWorkspaceFile(workspace.id, file);
      }
      if (mounted) Navigator.pop(context, workspace);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('创建工作区失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
