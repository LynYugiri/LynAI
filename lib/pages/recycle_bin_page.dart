import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/conversation.dart';
import '../models/plugin.dart';
import '../models/recycle_bin_item.dart';
import '../models/roleplay.dart';
import '../models/schedule_item.dart';
import '../models/todo_list.dart';
import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/recycle_bin_provider.dart';
import '../providers/roleplay_provider.dart';
import '../providers/settings_provider.dart';
import '../services/plugin_lua_runtime_service.dart';

class RecycleBinPage extends StatefulWidget {
  const RecycleBinPage({super.key});

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  String? _category;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) context.read<RecycleBinProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecycleBinProvider>();
    final categories = provider.categories;
    final items = _category == null
        ? provider.items
        : provider.items.where((item) => item.category == _category).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        centerTitle: true,
        actions: [
          if (provider.items.isNotEmpty)
            TextButton(
              onPressed: () => _confirmClear(context),
              child: const Text('清空'),
            ),
        ],
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : provider.items.isEmpty
          ? const _EmptyRecycleBin()
          : Column(
              children: [
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text('全部 ${provider.items.length}'),
                          selected: _category == null,
                          onSelected: (_) => setState(() => _category = null),
                        ),
                      ),
                      for (final category in categories)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text('${category.title} ${category.count}'),
                            selected: _category == category.id,
                            onSelected: (_) =>
                                setState(() => _category = category.id),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(_iconFor(item.type)),
                          ),
                          title: Text(item.title),
                          subtitle: Text(
                            [
                              provider.categoryTitle(item.category),
                              _formatDeletedAt(item.deletedAt),
                              if (item.preview.isNotEmpty) item.preview,
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'restore') await _restore(item);
                              if (value == 'delete') await _deleteForever(item);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'restore',
                                child: Text('恢复'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('永久删除'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  IconData _iconFor(String type) {
    return switch (type) {
      RecycleBinItemTypes.conversation => Icons.chat_bubble_outline,
      RecycleBinItemTypes.note ||
      RecycleBinItemTypes.notePage => Icons.note_outlined,
      RecycleBinItemTypes.schedule => Icons.event_outlined,
      RecycleBinItemTypes.todoList => Icons.checklist,
      RecycleBinItemTypes.roleplayScenario ||
      RecycleBinItemTypes.roleplayThread => Icons.theater_comedy_outlined,
      RecycleBinItemTypes.pluginFile => Icons.insert_drive_file_outlined,
      RecycleBinItemTypes.pluginData => Icons.extension_outlined,
      _ => Icons.delete_outline,
    };
  }

  Future<void> _restore(RecycleBinItem item) async {
    final recycleBinProvider = context.read<RecycleBinProvider>();
    try {
      switch (item.type) {
        case RecycleBinItemTypes.conversation:
          final raw = item.payload['conversation'];
          if (raw is! Map) throw Exception('回收站数据损坏');
          await context.read<ConversationProvider>().restoreConversation(
            Conversation.fromJson(Map<String, dynamic>.from(raw)),
          );
        case RecycleBinItemTypes.note:
          await context.read<FeatureProvider>().restoreNotePayload(
            item.payload,
          );
        case RecycleBinItemTypes.notePage:
          await context.read<FeatureProvider>().restoreNotePagePayload(
            item.payload,
          );
        case RecycleBinItemTypes.schedule:
          final raw = item.payload['schedule'];
          if (raw is! Map) throw Exception('回收站数据损坏');
          await context.read<FeatureProvider>().restoreSchedule(
            ScheduleItem.fromJson(Map<String, dynamic>.from(raw)),
          );
        case RecycleBinItemTypes.todoList:
          final raw = item.payload['todoList'];
          if (raw is! Map) throw Exception('回收站数据损坏');
          await context.read<FeatureProvider>().restoreTodoList(
            TodoList.fromJson(Map<String, dynamic>.from(raw)),
          );
        case RecycleBinItemTypes.roleplayScenario:
          final raw = item.payload['scenario'];
          if (raw is! Map) throw Exception('回收站数据损坏');
          final threads =
              (item.payload['threads'] as List<dynamic>? ?? const [])
                  .whereType<Map>()
                  .map(
                    (thread) => RoleplayThread.fromJson(
                      Map<String, dynamic>.from(thread),
                    ),
                  )
                  .toList();
          await context.read<RoleplayProvider>().restoreScenario(
            RoleplayScenario.fromJson(Map<String, dynamic>.from(raw)),
            threads,
          );
        case RecycleBinItemTypes.roleplayThread:
          final raw = item.payload['thread'];
          if (raw is! Map) throw Exception('回收站数据损坏');
          await context.read<RoleplayProvider>().restoreThread(
            RoleplayThread.fromJson(Map<String, dynamic>.from(raw)),
          );
        case RecycleBinItemTypes.pluginFile:
          await _restorePluginFile(item);
        case RecycleBinItemTypes.pluginData:
          await _restorePluginData(item);
        default:
          throw Exception('此类型暂不支持在页面恢复');
      }
      await recycleBinProvider.deleteForever(item.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已恢复')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('恢复失败: $e')));
      }
    }
  }

  Future<void> _restorePluginFile(RecycleBinItem item) async {
    final pluginId = RecycleBinOwners.pluginId(item.owner);
    final path = item.payload['path'] as String?;
    final content = item.payload['content'] as String?;
    if (pluginId == null || path == null || content == null) {
      throw Exception('插件文件回收站数据损坏');
    }
    final plugins = context.read<PluginProvider>();
    if (plugins.pluginById(pluginId) == null) throw Exception('来源插件未安装');
    await plugins.writeEditableFile(pluginId, path, content);
  }

  Future<void> _restorePluginData(RecycleBinItem item) async {
    final pluginId = RecycleBinOwners.pluginId(item.owner);
    final handler = item.payload['restoreHandler']?.toString().trim() ?? '';
    if (pluginId == null) throw Exception('插件数据回收站来源损坏');
    if (handler.isEmpty) throw Exception('插件未提供恢复 handler');
    final plugin = context.read<PluginProvider>().pluginById(pluginId);
    if (plugin == null) throw Exception('来源插件未安装');
    if (!plugin.enabled) throw Exception('来源插件未启用');
    final result = await PluginLuaRuntimeService().executeFunction(
      plugin: plugin,
      function: PluginFunctionDefinition(
        name: 'recycleBin.restore',
        title: '恢复回收站项目',
        handler: handler,
      ),
      arguments: {'item': item.toJson()},
      features: context.read<FeatureProvider>(),
      modelConfigs: context.read<ModelConfigProvider>(),
      plugins: context.read<PluginProvider>(),
      settings: context.read<SettingsProvider>(),
    );
    if (result['ok'] != true) {
      throw Exception(result['error']?.toString() ?? '插件恢复失败');
    }
  }

  Future<void> _deleteForever(RecycleBinItem item) async {
    final recycleBinProvider = context.read<RecycleBinProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除'),
        content: Text('永久删除“${item.title}”？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runPluginDeleteForeverHandler(item);
    await recycleBinProvider.deleteForever(item.id);
  }

  Future<void> _runPluginDeleteForeverHandler(RecycleBinItem item) async {
    if (item.type != RecycleBinItemTypes.pluginData) return;
    final pluginId = RecycleBinOwners.pluginId(item.owner);
    final handler =
        item.payload['deleteForeverHandler']?.toString().trim() ?? '';
    if (pluginId == null || handler.isEmpty) return;
    final plugin = context.read<PluginProvider>().pluginById(pluginId);
    if (plugin == null || !plugin.enabled) return;
    final result = await PluginLuaRuntimeService().executeFunction(
      plugin: plugin,
      function: PluginFunctionDefinition(
        name: 'recycleBin.deleteForever',
        title: '永久删除回收站项目',
        handler: handler,
      ),
      arguments: {'item': item.toJson()},
      features: context.read<FeatureProvider>(),
      modelConfigs: context.read<ModelConfigProvider>(),
      plugins: context.read<PluginProvider>(),
      settings: context.read<SettingsProvider>(),
    );
    if (result['ok'] != true) {
      throw Exception(result['error']?.toString() ?? '插件清理失败');
    }
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空回收站'),
        content: const Text('清空后所有项目都无法恢复，确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<RecycleBinProvider>().clear();
    }
  }

  String _formatDeletedAt(DateTime time) {
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class _EmptyRecycleBin extends StatelessWidget {
  const _EmptyRecycleBin();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_sweep_outlined, size: 64),
          SizedBox(height: 12),
          Text('回收站为空'),
        ],
      ),
    );
  }
}
