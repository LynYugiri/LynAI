import 'package:file_picker/file_picker.dart' show FileType;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/backup_models.dart';
import '../models/conversation.dart';
import '../models/note.dart';
import '../models/plugin.dart';
import '../models/roleplay.dart';
import '../models/schedule_item.dart';
import '../models/todo_list.dart';
import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/roleplay_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sync_provider.dart';
import '../services/backup_service.dart';
import '../services/backend_client.dart';
import '../services/backup_encryption.dart';
import '../services/storage_v2_service.dart';
import '../services/storage_v2_database.dart';
import '../utils/file_picker_io_utils.dart';
import '../utils/managed_model_id_migration.dart';
import '../widgets/merge_conflict_card.dart';

/// 数据管理页面。
///
/// 提供可选择分区的 ZIP 备份导出、备份读取预览、导入模式选择和冲突处理。
/// 具体归档和恢复逻辑由 [BackupService] 执行。
class DataManagementPage extends StatefulWidget {
  const DataManagementPage({super.key});

  @override
  State<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends State<DataManagementPage> {
  BackupSelection? _exportSelection;
  BackupSelection? _importSelection;
  BackupArchiveData? _archive;
  BackupPreview? _preview;
  ImportMode _mode = ImportMode.merge;
  final Map<String, ImportConflictAction> _conflictActions = {};
  bool _busy = false;
  bool _includeSecrets = false;

  BackupService _service(BuildContext context) {
    return BackupService(
      settingsProvider: context.read<SettingsProvider>(),
      modelConfigProvider: context.read<ModelConfigProvider>(),
      conversationProvider: context.read<ConversationProvider>(),
      featureProvider: context.read<FeatureProvider>(),
      roleplayProvider: context.read<RoleplayProvider>(),
      pluginProvider: context.read<PluginProvider>(),
      storageV2: StorageV2Service(),
    );
  }

  BackupSelection _currentExportSelection(BuildContext context) {
    final current = _exportSelection;
    if (current != null) return current;
    return _selectionForLocalData(context);
  }

  BackupSelection _selectionForLocalData(BuildContext context) {
    final conversations = context.read<ConversationProvider>().conversations;
    final features = context.read<FeatureProvider>();
    final roleplays = context.read<RoleplayProvider>().scenarios;
    final plugins = context.read<PluginProvider>().plugins;
    return BackupSelection(
      Set.of(BackupSection.values),
      settingsParts: Set.of(BackupSettingsPart.values),
      conversationIds: conversations.map((item) => item.id).toSet(),
      noteIds: features.notes.map((item) => item.id).toSet(),
      scheduleIds: features.schedules.map((item) => item.id).toSet(),
      todoListIds: features.todoLists.map((item) => item.id).toSet(),
      roleplaySessionIds: roleplays.map((item) => item.id).toSet(),
      pluginIds: plugins.map((item) => item.id).toSet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exportSelection = _currentExportSelection(context);
    return Scaffold(
      appBar: AppBar(title: const Text('数据管理'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(),
          const SizedBox(height: 12),
          _SyncCard(onManualSync: () => _manualSync(context)),
          const SizedBox(height: 12),
          _ExportCard(
            selection: exportSelection,
            busy: _busy,
            onSelectionChanged: (selection) {
              setState(() => _exportSelection = selection);
            },
            includeSecrets: _includeSecrets,
            onIncludeSecretsChanged: (value) {
              setState(() => _includeSecrets = value);
            },
            onExport: !_busy && exportSelection.sections.isNotEmpty
                ? () => _export(exportSelection)
                : null,
          ),
          const SizedBox(height: 12),
          _ImportCard(
            archive: _archive,
            preview: _preview,
            selection: _importSelection,
            mode: _mode,
            conflictActions: _conflictActions,
            busy: _busy,
            onPick: _busy ? null : _pickImportFile,
            onSelectionChanged: (selection) {
              setState(() {
                _importSelection = selection;
                _refreshPreview();
              });
            },
            onModeChanged: (mode) {
              setState(() {
                _mode = mode;
                _refreshPreview();
              });
            },
            onConflictChanged: (id, action) {
              setState(() => _conflictActions[id] = action);
            },
            onImport: _canImport ? _import : null,
          ),
        ],
      ),
    );
  }

  bool get _canImport {
    final selection = _importSelection;
    return !_busy &&
        _archive != null &&
        selection != null &&
        selection.sections.isNotEmpty;
  }

  Future<void> _export(BackupSelection selection) async {
    setState(() => _busy = true);
    try {
      String? password;
      if (_includeSecrets) {
        password = await _requestPassword(confirm: true);
        if (password == null) return;
      }
      if (!mounted) return;
      final service = _service(context);
      final bytes = _includeSecrets
          ? await service.exportEncryptedBytes(
              selection,
              password: password!,
              includeApiKeys: true,
            )
          : await service.exportZipBytes(selection);
      final extension = _includeSecrets ? 'lynai-backup' : 'zip';
      final fileName = 'lynai-${_backupFileDate(DateTime.now())}.$extension';
      final path = await saveBytesWithPicker(
        dialogTitle: '导出备份',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: bytes,
      );
      if (path == null) return;
      if (!mounted) return;
      _showSnack('备份已导出到 $path');
    } catch (e) {
      _showSnack('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _backupFileDate(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}-${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }

  Future<void> _pickImportFile() async {
    setState(() => _busy = true);
    try {
      final service = _service(context);
      final file = await pickSingleFilePayload(
        dialogTitle: '选择备份文件',
        type: FileType.custom,
        allowedExtensions: ['zip', 'lynai-backup'],
      );
      if (!mounted) return;
      if (file == null) return;
      final bytes = await file.readBytes();
      String? password;
      if (BackupEncryption.isEncrypted(bytes)) {
        password = await _requestPassword();
        if (password == null) return;
      }
      final archive = await service.readBackupBytes(bytes, password: password);
      if (!mounted) return;
      setState(() {
        _archive = archive;
        _importSelection = BackupSelection.fromDataWithSettingsParts(
          archive.data,
          BackupService.settingsPartsFromManifest(
            archive.manifest,
            archive.data,
          ),
        );
        _conflictActions.clear();
        _refreshPreview();
      });
    } catch (e) {
      _showSnack('读取备份失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final archive = _archive!;
      final result = await _service(context).importArchive(
        archive,
        ImportPlan(
          selection: _importSelection!,
          mode: _mode,
          conflictActions: Map.of(_conflictActions),
        ),
      );
      if (!mounted) return;
      if (_importSelection!.settingsParts.contains(
        BackupSettingsPart.apiConfigs,
      )) {
        final modelProvider = context.read<ModelConfigProvider>();
        final settingsProvider = context.read<SettingsProvider>();
        final conversationProvider = context.read<ConversationProvider>();
        final roleplayProvider = context.read<RoleplayProvider>();
        await syncManagedModelsAndApplyMigrations(
          models: modelProvider,
          backend: context.read<BackendClient>(),
          settings: settingsProvider,
          conversations: conversationProvider,
          roleplay: roleplayProvider,
          plugins: context.read<PluginProvider>(),
        );
      }
      setState(() {
        _archive = null;
        _preview = null;
        _importSelection = null;
        _conflictActions.clear();
      });
      _showSnack(
        '导入完成：新增 ${result.added}，覆盖 ${result.replaced}，跳过 ${result.skipped}',
      );
    } catch (e) {
      _showSnack('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _refreshPreview() {
    final archive = _archive;
    final selection = _importSelection;
    if (archive == null || selection == null) {
      _preview = null;
      return;
    }
    _preview = _service(context).preview(archive, selection);
    for (final conflict in _preview!.conflicts) {
      _conflictActions.putIfAbsent(
        conflict.id,
        () => ImportConflictAction.keepLocal,
      );
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), showCloseIcon: true));
  }

  Future<void> _manualSync(BuildContext context) async {
    final sync = context.read<SyncProvider>();
    if (!sync.canSync) {
      _showSnack('请先连接服务端并登录');
      return;
    }
    await sync.manualSync();
  }

  Future<String?> _requestPassword({bool confirm = false}) async {
    final password = TextEditingController();
    final confirmation = TextEditingController();
    try {
      return showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(confirm ? '设置备份密码' : '输入备份密码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: password,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: '密码'),
              ),
              if (confirm)
                TextField(
                  controller: confirmation,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '确认密码'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final value = password.text;
                if (value.isEmpty ||
                    (confirm && value != confirmation.text) ||
                    value.length > BackupEncryption.maxPasswordBytes) {
                  return;
                }
                Navigator.pop(context, value);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } finally {
      password.dispose();
      confirmation.dispose();
    }
  }
}

class _SyncCard extends StatelessWidget {
  const _SyncCard({required this.onManualSync});

  final VoidCallback onManualSync;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sync, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '数据同步',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                FilledButton.icon(
                  onPressed: sync.syncing ? null : onManualSync,
                  icon: sync.syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync_outlined),
                  label: Text(sync.syncing ? '同步中' : '立即同步'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_syncSubtitle(sync)),
            const SizedBox(height: 4),
            Text(
              '从服务端拉取增量并上传本地变更。',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            if (sync.conflicts.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                '待处理同步冲突 (${sync.conflicts.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              ...sync.conflicts.map(
                (conflict) => MergeConflictCard(
                  conflict: conflict.view,
                  choices: [
                    MergeConflictChoice(
                      label: '保留本地',
                      onSelected: () => sync.resolveConflict(
                        conflict.seq,
                        SyncConflictResolution.keepLocal,
                      ),
                    ),
                    MergeConflictChoice(
                      label: '使用云端',
                      onSelected: () => sync.resolveConflict(
                        conflict.seq,
                        SyncConflictResolution.useRemote,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _syncSubtitle(SyncProvider sync) {
    if (!sync.canSync) return '未连接服务端';
    if (sync.syncing) return '同步中…';
    final last = sync.lastSyncAt;
    if (last == null) return '尚未同步';
    return '上次同步: ${last.month}/${last.day} ${last.hour}:${last.minute.toString().padLeft(2, '0')}';
  }
}

/// 隐私提示卡片。
class _InfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.privacy_tip_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '普通备份不包含 API Key。只有启用“加密并包含 API Key”时，密钥才会进入密码加密备份；设备私钥和登录令牌永不备份。',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 数据导出卡片。
///
/// 含分区选择树和导出按钮，支持勾选对话、笔记、日程、待办、情景演绎和插件。
class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.selection,
    required this.busy,
    required this.onSelectionChanged,
    required this.includeSecrets,
    required this.onIncludeSecretsChanged,
    required this.onExport,
  });

  final BackupSelection selection;
  final bool busy;
  final ValueChanged<BackupSelection> onSelectionChanged;
  final bool includeSecrets;
  final ValueChanged<bool> onIncludeSecretsChanged;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final conversations = context.watch<ConversationProvider>().conversations;
    final features = context.watch<FeatureProvider>();
    final roleplays = context.watch<RoleplayProvider>().scenarios;
    final plugins = context.watch<PluginProvider>().plugins;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('数据导出', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _SelectionTree(
              selection: selection,
              availableSections: Set.of(BackupSection.values),
              conversations: conversations,
              notes: features.notes,
              schedules: features.schedules,
              todoLists: features.todoLists,
              roleplays: roleplays,
              plugins: plugins,
              busy: busy,
              onChanged: onSelectionChanged,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: includeSecrets,
              onChanged: busy ? null : onIncludeSecretsChanged,
              title: const Text('加密并包含 API Key'),
              subtitle: const Text(
                '使用 Argon2id 和 XChaCha20-Poly1305；不会包含设备私钥或登录令牌。',
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.upload_file),
                label: Text(includeSecrets ? '导出加密备份' : '导出备份'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 数据导入卡片。
///
/// 支持选取 ZIP 备份文件、预览内容、选择导入分区和冲突处理策略。
class _ImportCard extends StatelessWidget {
  const _ImportCard({
    required this.archive,
    required this.preview,
    required this.selection,
    required this.mode,
    required this.conflictActions,
    required this.busy,
    required this.onPick,
    required this.onSelectionChanged,
    required this.onModeChanged,
    required this.onConflictChanged,
    required this.onImport,
  });

  final BackupArchiveData? archive;
  final BackupPreview? preview;
  final BackupSelection? selection;
  final ImportMode mode;
  final Map<String, ImportConflictAction> conflictActions;
  final bool busy;
  final VoidCallback? onPick;
  final ValueChanged<BackupSelection> onSelectionChanged;
  final ValueChanged<ImportMode> onModeChanged;
  final void Function(String conflictId, ImportConflictAction action)
  onConflictChanged;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final archive = this.archive;
    final selection = this.selection;
    final preview = this.preview;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('数据导入', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.folder_open),
                label: const Text('选择备份文件'),
              ),
            ),
            if (archive != null && selection != null) ...[
              const SizedBox(height: 16),
              _ManifestSummary(manifest: archive.manifest),
              const SizedBox(height: 12),
              _SelectionTree(
                selection: selection,
                availableSections: archive.availableSections,
                conversations: archive.data.conversations ?? const [],
                notes: archive.data.notes ?? const [],
                schedules: archive.data.schedules ?? const [],
                todoLists: archive.data.todoLists ?? const [],
                roleplays: archive.data.roleplaySessions ?? const [],
                plugins:
                    archive.data.plugins
                        ?.map((item) => item.plugin)
                        .toList(growable: false) ??
                    const [],
                busy: busy,
                onChanged: onSelectionChanged,
              ),
              const Divider(height: 24),
              Text('导入方式', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ImportMode.values.map((item) {
                  return ChoiceChip(
                    label: Text(item.label),
                    selected: mode == item,
                    onSelected: busy || item == mode
                        ? null
                        : (_) => onModeChanged(item),
                  );
                }).toList(),
              ),
              if (preview != null && preview.sections.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  preview.sections
                      .map((item) => '${item.section.label}：${item.detail}')
                      .join('\n'),
                ),
              ],
              if (preview != null && preview.warnings.isNotEmpty) ...[
                const SizedBox(height: 8),
                _WarningList(warnings: preview.warnings),
              ],
              if (mode == ImportMode.merge &&
                  preview != null &&
                  preview.conflicts.isNotEmpty) ...[
                const Divider(height: 24),
                Text('冲突处理', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                ...preview.conflicts.map(
                  (conflict) => _ConflictTile(
                    conflict: conflict,
                    action:
                        conflictActions[conflict.id] ??
                        ImportConflictAction.keepLocal,
                    onChanged: busy
                        ? null
                        : (action) => onConflictChanged(conflict.id, action),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.download_done),
                  label: const Text('开始导入'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 备份分区选择树。
///
/// 以 ExpansionTile 嵌套 CheckboxListTile 实现全选/部分选择/未选三态。
class _SelectionTree extends StatelessWidget {
  const _SelectionTree({
    required this.selection,
    required this.availableSections,
    required this.conversations,
    required this.notes,
    required this.schedules,
    required this.todoLists,
    required this.roleplays,
    required this.plugins,
    required this.busy,
    required this.onChanged,
  });

  final BackupSelection selection;
  final Set<BackupSection> availableSections;
  final List<Conversation> conversations;
  final List<Note> notes;
  final List<ScheduleItem> schedules;
  final List<TodoList> todoLists;
  final List<RoleplayScenario> roleplays;
  final List<InstalledPlugin> plugins;
  final bool busy;
  final ValueChanged<BackupSelection> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SettingsSelectionTile(
          selection: selection,
          enabled: availableSections.contains(BackupSection.settings),
          busy: busy,
          onChanged: onChanged,
        ),
        _ItemSelectionTile<Conversation>(
          section: BackupSection.conversations,
          selection: selection,
          enabled: availableSections.contains(BackupSection.conversations),
          items: conversations,
          selectedIds: selection.conversationIds,
          idFor: (item) => item.id,
          titleFor: (item) => item.title,
          subtitleFor: (item) => '${item.messages.length} 条消息',
          copyWithIds: (ids, sections) =>
              selection.copyWith(sections: sections, conversationIds: ids),
          busy: busy,
          onChanged: onChanged,
        ),
        _ItemSelectionTile<Note>(
          section: BackupSection.notes,
          selection: selection,
          enabled: availableSections.contains(BackupSection.notes),
          items: notes,
          selectedIds: selection.noteIds,
          idFor: (item) => item.id,
          titleFor: (item) => item.title.isEmpty ? '未命名笔记' : item.title,
          subtitleFor: (item) => _formatDate(item.updatedAt),
          copyWithIds: (ids, sections) =>
              selection.copyWith(sections: sections, noteIds: ids),
          busy: busy,
          onChanged: onChanged,
        ),
        _ItemSelectionTile<ScheduleItem>(
          section: BackupSection.schedules,
          selection: selection,
          enabled: availableSections.contains(BackupSection.schedules),
          items: schedules,
          selectedIds: selection.scheduleIds,
          idFor: (item) => item.id,
          titleFor: (item) => item.title,
          subtitleFor: (item) => _formatDate(item.start),
          copyWithIds: (ids, sections) =>
              selection.copyWith(sections: sections, scheduleIds: ids),
          busy: busy,
          onChanged: onChanged,
        ),
        _ItemSelectionTile<TodoList>(
          section: BackupSection.todoLists,
          selection: selection,
          enabled: availableSections.contains(BackupSection.todoLists),
          items: todoLists,
          selectedIds: selection.todoListIds,
          idFor: (item) => item.id,
          titleFor: (item) => item.title,
          subtitleFor: (item) => '${item.items.length} 项',
          copyWithIds: (ids, sections) =>
              selection.copyWith(sections: sections, todoListIds: ids),
          busy: busy,
          onChanged: onChanged,
        ),
        _ItemSelectionTile<RoleplayScenario>(
          section: BackupSection.roleplay,
          selection: selection,
          enabled: availableSections.contains(BackupSection.roleplay),
          items: roleplays,
          selectedIds: selection.roleplaySessionIds,
          idFor: (item) => item.id,
          titleFor: (item) => item.title,
          subtitleFor: (item) => _formatDate(item.updatedAt),
          copyWithIds: (ids, sections) =>
              selection.copyWith(sections: sections, roleplaySessionIds: ids),
          busy: busy,
          onChanged: onChanged,
        ),
        _ItemSelectionTile<InstalledPlugin>(
          section: BackupSection.plugins,
          selection: selection,
          enabled: availableSections.contains(BackupSection.plugins),
          items: plugins,
          selectedIds: selection.pluginIds,
          idFor: (item) => item.id,
          titleFor: (item) => item.manifest.name,
          subtitleFor: (item) =>
              '${item.enabled ? '已启用' : '未启用'}，版本 ${item.manifest.version}',
          copyWithIds: (ids, sections) =>
              selection.copyWith(sections: sections, pluginIds: ids),
          busy: busy,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SettingsSelectionTile extends StatelessWidget {
  const _SettingsSelectionTile({
    required this.selection,
    required this.enabled,
    required this.busy,
    required this.onChanged,
  });

  final BackupSelection selection;
  final bool enabled;
  final bool busy;
  final ValueChanged<BackupSelection> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedCount = selection.settingsParts.length;
    final total = BackupSettingsPart.values.length;
    final value = _triStateValue(selectedCount, total);
    return _SectionShell(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.only(left: 20, right: 8, bottom: 8),
        leading: Checkbox(
          tristate: true,
          value: enabled ? value : false,
          onChanged: !enabled || busy ? null : (_) => _toggleAll(),
        ),
        title: const Text('设置', style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('$selectedCount / $total 项'),
        children: BackupSettingsPart.values.map((part) {
          final selected = selection.settingsParts.contains(part);
          return _ChildSelectionRow(
            value: selected,
            title: part.label,
            onChanged: !enabled || busy
                ? null
                : (value) => _togglePart(part, value ?? false),
          );
        }).toList(),
      ),
    );
  }

  void _toggleAll() {
    final allSelected =
        selection.settingsParts.length == BackupSettingsPart.values.length;
    final parts = allSelected
        ? <BackupSettingsPart>{}
        : Set.of(BackupSettingsPart.values);
    final sections = Set<BackupSection>.from(selection.sections);
    if (parts.isEmpty) {
      sections.remove(BackupSection.settings);
    } else {
      sections.add(BackupSection.settings);
    }
    onChanged(selection.copyWith(sections: sections, settingsParts: parts));
  }

  void _togglePart(BackupSettingsPart part, bool selected) {
    final parts = Set<BackupSettingsPart>.from(selection.settingsParts);
    if (selected) {
      parts.add(part);
    } else {
      parts.remove(part);
    }
    final sections = Set<BackupSection>.from(selection.sections);
    if (parts.isEmpty) {
      sections.remove(BackupSection.settings);
    } else {
      sections.add(BackupSection.settings);
    }
    onChanged(selection.copyWith(sections: sections, settingsParts: parts));
  }
}

class _ItemSelectionTile<T> extends StatelessWidget {
  const _ItemSelectionTile({
    required this.section,
    required this.selection,
    required this.enabled,
    required this.items,
    required this.selectedIds,
    required this.titleFor,
    required this.subtitleFor,
    required this.idFor,
    required this.copyWithIds,
    required this.busy,
    required this.onChanged,
  });

  final BackupSection section;
  final BackupSelection selection;
  final bool enabled;
  final List<T> items;
  final Set<String> selectedIds;
  final String Function(T item) titleFor;
  final String Function(T item) subtitleFor;
  final String Function(T item) idFor;
  final BackupSelection Function(Set<String> ids, Set<BackupSection> sections)
  copyWithIds;
  final bool busy;
  final ValueChanged<BackupSelection> onChanged;

  @override
  Widget build(BuildContext context) {
    final itemIds = items.map((item) => idFor(item)).toSet();
    final selectedCount = selectedIds.intersection(itemIds).length;
    final value = _triStateValue(selectedCount, itemIds.length);
    return _SectionShell(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.only(left: 20, right: 8, bottom: 8),
        leading: Checkbox(
          tristate: true,
          value: enabled ? value : false,
          onChanged: !enabled || busy ? null : (_) => _toggleAll(itemIds),
        ),
        title: Text(
          section.label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text('$selectedCount / ${itemIds.length} 项'),
        children: items.map((item) {
          final id = idFor(item);
          return _ChildSelectionRow(
            value: selectedIds.contains(id),
            title: titleFor(item),
            subtitle: subtitleFor(item),
            onChanged: !enabled || busy
                ? null
                : (value) => _toggleItem(id, value ?? false),
          );
        }).toList(),
      ),
    );
  }

  void _toggleAll(Set<String> itemIds) {
    final selectedCount = selectedIds.intersection(itemIds).length;
    final ids = Set<String>.from(selectedIds);
    if (selectedCount == itemIds.length) {
      ids.removeAll(itemIds);
    } else {
      ids.addAll(itemIds);
    }
    _emit(ids);
  }

  void _toggleItem(String id, bool selected) {
    final ids = Set<String>.from(selectedIds);
    if (selected) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    _emit(ids);
  }

  void _emit(Set<String> ids) {
    final sections = Set<BackupSection>.from(selection.sections);
    if (ids.isEmpty) {
      sections.remove(section);
    } else {
      sections.add(section);
    }
    onChanged(copyWithIds(ids, sections));
  }
}

/// 分区外壳组件，为每个可展开分区统一圆角容器样式。
class _SectionShell extends StatelessWidget {
  const _SectionShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.16),
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class _ChildSelectionRow extends StatelessWidget {
  const _ChildSelectionRow({
    required this.value,
    required this.title,
    this.subtitle,
    required this.onChanged,
  });

  final bool value;
  final String title;
  final String? subtitle;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: CheckboxListTile(
        value: value,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
        dense: true,
        visualDensity: VisualDensity.compact,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.only(left: 4, right: 12),
        onChanged: onChanged,
      ),
    );
  }
}

/// 备份清单摘要。
///
/// 显示备份的应用版本和导出时间。
class _ManifestSummary extends StatelessWidget {
  const _ManifestSummary({required this.manifest});

  final Map<String, dynamic> manifest;

  @override
  Widget build(BuildContext context) {
    final appVersion = manifest['appVersion'] as String? ?? '未知版本';
    final createdAt = manifest['createdAt'] as String? ?? '未知时间';
    return Text('备份版本：$appVersion\n导出时间：$createdAt');
  }
}

/// 警告列表组件，以琥珀色背景展示导入预览中发现的问题。
class _WarningList extends StatelessWidget {
  const _WarningList({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(warnings.join('\n')),
    );
  }
}

/// 导入冲突处理项。
///
/// 显示本地与导入项的摘要，并提供保留本地/覆盖的冲突操作选项。
class _ConflictTile extends StatelessWidget {
  const _ConflictTile({
    required this.conflict,
    required this.action,
    required this.onChanged,
  });

  final ImportConflict conflict;
  final ImportConflictAction action;
  final void Function(ImportConflictAction action)? onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeConflictCard(
      conflict: conflict.view,
      choices: ImportConflictAction.values
          .map(
            (item) => MergeConflictChoice(
              label: item.label,
              selected: action == item,
              onSelected: onChanged == null ? null : () => onChanged!(item),
            ),
          )
          .toList(growable: false),
    );
  }
}

// 根据选中数和总数生成三态复选框值：全选 true、未选 false、部分选中 null。
bool? _triStateValue(int selectedCount, int total) {
  if (total == 0 || selectedCount == 0) return false;
  if (selectedCount == total) return true;
  return null;
}

// 将 DateTime 格式化为 "yyyy-MM-dd HH:mm" 的本地显示字符串。
String _formatDate(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
}
