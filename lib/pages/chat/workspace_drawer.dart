import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chat_quick_action.dart';
import '../../models/plugin.dart';
import '../../models/workspace.dart';
import '../../pages/plugin_file_editor_page.dart';
import '../../pages/workspace_create_page.dart';
import '../../pages/workspace_file_editor_page.dart';
import '../../providers/plugin_provider.dart';
import '../../providers/workspace_provider.dart';
import '../../services/workspace_file_service.dart';
import '../../utils/file_picker_io_utils.dart';
import '../../utils/snackbar_utils.dart';

/// 工作区抽屉：VSCode 风格文件树。
///
/// 未选择工作区时展示工作区列表，点名称即选中；选中后展示挂载目录、
/// 添加文件、功能页与开发插件。点文件关闭抽屉并打开全屏编辑器。
class WorkspaceDrawer extends StatefulWidget {
  const WorkspaceDrawer({super.key, required this.onOpenFeature});

  final ValueChanged<String> onOpenFeature;

  @override
  State<WorkspaceDrawer> createState() => _WorkspaceDrawerState();
}

class _WorkspaceDrawerState extends State<WorkspaceDrawer> {
  final _expandedPlugins = <String>{};
  final _mountedExpanded = <String>{};
  final _mountedCwd = <String, String>{};

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkspaceProvider>();
    final workspace = provider.activeWorkspace;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 8,
            bottom: 12,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
          ),
          child: Row(
            children: [
              const Icon(Icons.folder_copy_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: workspace == null
                    ? Text('工作区', style: Theme.of(context).textTheme.titleLarge)
                    : _workspaceSwitcher(provider, workspace),
              ),
              IconButton(
                tooltip: '新建工作区',
                icon: const Icon(Icons.add),
                onPressed: _createWorkspace,
              ),
              if (workspace != null)
                IconButton(
                  tooltip: '退出工作区',
                  icon: const Icon(Icons.logout),
                  onPressed: () =>
                      context.read<WorkspaceProvider>().exitWorkspace(),
                ),
            ],
          ),
        ),
        Expanded(
          child: workspace == null
              ? _workspaceList(provider)
              : _workspaceTree(context, provider, workspace),
        ),
      ],
    );
  }

  Widget _workspaceSwitcher(WorkspaceProvider provider, Workspace current) {
    return PopupMenuButton<String>(
      tooltip: '切换工作区',
      onSelected: provider.selectWorkspace,
      itemBuilder: (context) => [
        for (final item in provider.workspaces)
          PopupMenuItem(
            value: item.id,
            child: Row(
              children: [
                Icon(
                  item.id == current.id ? Icons.check : Icons.folder_outlined,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(item.name)),
              ],
            ),
          ),
      ],
      child: Row(
        children: [
          Flexible(
            child: Text(
              '✓ ${current.name} ▾',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _workspaceList(WorkspaceProvider provider) {
    if (provider.workspaces.isEmpty) {
      return const Center(child: Text('暂无工作区，点右上角 + 新建'));
    }
    return ListView(
      children: [
        for (final workspace in provider.workspaces)
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(workspace.name),
            subtitle: Text(
              [
                if (workspace.devPluginIds.isNotEmpty)
                  '${workspace.devPluginIds.length} 个插件',
                if (workspace.files.isNotEmpty) '${workspace.files.length} 个文件',
                if (workspace.mountedFolderPath != null) '已挂载文件夹',
              ].join(' · '),
            ),
            onTap: () => provider.selectWorkspace(workspace.id),
          ),
      ],
    );
  }

  Widget _workspaceTree(
    BuildContext context,
    WorkspaceProvider provider,
    Workspace workspace,
  ) {
    final pluginProvider = context.watch<PluginProvider>();
    final plugins = workspace.devPluginIds
        .map(pluginProvider.pluginById)
        .whereType<InstalledPlugin>()
        .toList(growable: false);
    return ListView(
      children: [
        if (workspace.mountedFolderPath != null)
          _mountedFolderTile(provider, workspace),
        _addedFilesSection(provider, workspace),
        if (workspace.featureIds.isNotEmpty) ...[
          _sectionLabel('功能页'),
          for (final featureId in workspace.featureIds)
            ListTile(
              dense: true,
              leading: const Icon(Icons.widgets_outlined, size: 18),
              title: Text(ChatQuickAction.featurePages[featureId] ?? featureId),
              onTap: () {
                Navigator.pop(context);
                widget.onOpenFeature(featureId);
              },
            ),
        ],
        if (plugins.isNotEmpty) ...[
          _sectionLabel('插件（开发）'),
          for (final plugin in plugins)
            _pluginFolderTile(pluginProvider, plugin),
        ],
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.outline,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// FutureBuilder 的加载中/错误占位。
  ///
  /// 返回 null 表示已有数据，由调用方继续渲染各自的列表。
  Widget? _snapshotPlaceholder<T>(
    BuildContext context,
    AsyncSnapshot<List<T>> snapshot,
  ) {
    if (snapshot.hasError) {
      return ListTile(
        dense: true,
        title: Text(
          snapshot.error.toString().replaceFirst('Exception: ', ''),
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
      );
    }
    if (!snapshot.hasData) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return null;
  }

  Widget _mountedFolderTile(WorkspaceProvider provider, Workspace workspace) {
    final root = workspace.mountedFolderPath!;
    final expanded = _mountedExpanded.contains(root);
    final cwd = _mountedCwd[workspace.id] ?? '';
    return ExpansionTile(
      key: ValueKey('workspace-mounted-$root'),
      leading: const Icon(Icons.folder),
      title: const Text('挂载本地文件夹'),
      subtitle: Text(root, maxLines: 1, overflow: TextOverflow.ellipsis),
      initiallyExpanded: expanded,
      onExpansionChanged: (value) => setState(() {
        if (value) {
          _mountedExpanded.add(root);
        } else {
          _mountedExpanded.remove(root);
        }
      }),
      children: [
        if (cwd.isNotEmpty)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 24),
            leading: const Icon(Icons.arrow_upward, size: 18),
            title: Text('上一级（$cwd）', overflow: TextOverflow.ellipsis),
            onTap: () => setState(() {
              _mountedCwd[workspace.id] = _parentRelative(cwd);
            }),
          ),
        FutureBuilder<List<WorkspaceFileEntry>>(
          key: ValueKey('workspace-mounted-list-${workspace.id}-$cwd'),
          future: provider.listMountedDirectory(workspace, cwd),
          builder: (context, snapshot) {
            final placeholder = _snapshotPlaceholder(context, snapshot);
            if (placeholder != null) return placeholder;
            final entries = snapshot.data!;
            if (entries.isEmpty) {
              return const ListTile(dense: true, title: Text('空目录'));
            }
            return Column(
              children: [
                for (final entry in entries)
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 32),
                    leading: Icon(
                      entry.isDirectory
                          ? Icons.folder
                          : Icons.description_outlined,
                      size: 18,
                    ),
                    title: Text(entry.name),
                    onTap: entry.isDirectory
                        ? () => setState(() {
                            _mountedCwd[workspace.id] = entry.path;
                          })
                        : () => _openMountedFile(provider, workspace, entry),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  static String _parentRelative(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    if (index <= 0) return '';
    return normalized.substring(0, index);
  }

  Widget _addedFilesSection(WorkspaceProvider provider, Workspace workspace) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('文件'),
        for (final ref in workspace.files)
          ListTile(
            dense: true,
            leading: const Icon(Icons.description_outlined, size: 18),
            title: Text(ref.originalName),
            subtitle: Text(ref.mimeType),
            onTap: () => _openAddedFile(provider, workspace, ref),
          ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.note_add_outlined, size: 18),
          title: const Text('添加文件'),
          onTap: () => _addFiles(provider, workspace),
        ),
      ],
    );
  }

  Widget _pluginFolderTile(
    PluginProvider pluginProvider,
    InstalledPlugin plugin,
  ) {
    final expanded = _expandedPlugins.contains(plugin.id);
    return ExpansionTile(
      key: ValueKey('workspace-plugin-${plugin.id}'),
      leading: const Icon(Icons.extension_outlined),
      title: Text(plugin.displayName),
      subtitle: Text(plugin.devState.label),
      initiallyExpanded: expanded,
      onExpansionChanged: (value) => setState(() {
        if (value) {
          _expandedPlugins.add(plugin.id);
        } else {
          _expandedPlugins.remove(plugin.id);
        }
      }),
      children: [
        FutureBuilder<List<PluginFileEntry>>(
          future: pluginProvider.listDeveloperFiles(plugin.id),
          builder: (context, snapshot) {
            final placeholder = _snapshotPlaceholder(context, snapshot);
            if (placeholder != null) return placeholder;
            final entries = snapshot.data!;
            return Column(
              children: [
                for (final entry in entries)
                  if (!entry.isDirectory)
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 32),
                      leading: Icon(
                        entry.isEditable ? Icons.code : Icons.lock_outline,
                        size: 18,
                      ),
                      title: Text(entry.path),
                      onTap: () =>
                          _openPluginFile(pluginProvider, plugin, entry),
                    ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _openMountedFile(
    WorkspaceProvider provider,
    Workspace workspace,
    WorkspaceFileEntry entry,
  ) async {
    try {
      final content = await provider.readMountedFile(workspace, entry.path);
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop();
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => WorkspaceFileEditorPage(
            workspace: workspace,
            kind: WorkspaceFileKind.mounted,
            relativePath: entry.path,
            initialContent: content,
          ),
        ),
      );
    } catch (e) {
      if (mounted) showErrorSnackBar(context, '$e');
    }
  }

  Future<void> _openAddedFile(
    WorkspaceProvider provider,
    Workspace workspace,
    WorkspaceFileRef ref,
  ) async {
    try {
      final content = await provider.readWorkspaceFile(ref);
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop();
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => WorkspaceFileEditorPage(
            workspace: workspace,
            kind: WorkspaceFileKind.added,
            relativePath: ref.originalName,
            initialContent: content,
            fileRef: ref,
          ),
        ),
      );
    } catch (e) {
      if (mounted) showErrorSnackBar(context, '$e');
    }
  }

  Future<void> _openPluginFile(
    PluginProvider pluginProvider,
    InstalledPlugin plugin,
    PluginFileEntry entry,
  ) async {
    try {
      final content = await pluginProvider.readDeveloperFile(
        plugin.id,
        entry.path,
      );
      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop();
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => PluginFileEditorPage(
            pluginId: plugin.id,
            path: entry.path,
            initialContent: content,
            readOnly: !entry.isEditable,
          ),
        ),
      );
    } catch (e) {
      if (mounted) showErrorSnackBar(context, '$e');
    }
  }

  Future<void> _addFiles(
    WorkspaceProvider provider,
    Workspace workspace,
  ) async {
    final files = await pickMultipleFilePayloads(dialogTitle: '添加文件到工作区');
    if (files.isEmpty) return;
    final failures = <String>[];
    for (final file in files) {
      try {
        await provider.importWorkspaceFile(workspace.id, file);
      } catch (e) {
        failures.add('${file.name}: $e');
      }
    }
    if (failures.isNotEmpty && mounted) {
      showErrorSnackBar(context, '部分文件导入失败\n${failures.join('\n')}');
    }
  }

  Future<void> _createWorkspace() async {
    final workspace = await Navigator.push<Workspace>(
      context,
      MaterialPageRoute(builder: (_) => const WorkspaceCreatePage()),
    );
    if (workspace != null && mounted) {
      context.read<WorkspaceProvider>().selectWorkspace(workspace.id);
    }
  }
}
