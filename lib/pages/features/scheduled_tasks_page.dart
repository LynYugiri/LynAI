import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/local_time.dart';
import '../../models/plugin.dart';
import '../../models/scheduled_task.dart';
import '../../providers/plugin_provider.dart';
import '../../providers/scheduled_task_provider.dart';
import '../../services/scheduled_task_scheduler.dart';

/// 定时任务管理页。
///
/// 展示插件 manifest 任务与用户创建任务，支持创建/编辑/启停/立即运行。
/// 调度本身由 [ScheduledTaskScheduler] 负责，本页只操作 Provider。
class ScheduledTasksPage extends StatelessWidget {
  const ScheduledTasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScheduledTaskProvider>();
    final tasks = provider.tasks;
    if (tasks.isEmpty) {
      return _emptyState(context);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: tasks.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FilledButton.icon(
              onPressed: () => _showEditor(context),
              icon: const Icon(Icons.add),
              label: const Text('新建定时任务'),
            ),
          );
        }
        final task = tasks[index - 1];
        return _TaskCard(task: task);
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_send_outlined, size: 56),
          const SizedBox(height: 12),
          const Text('还没有定时任务'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _showEditor(context),
            icon: const Icon(Icons.add),
            label: const Text('新建定时任务'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditor(BuildContext context, {ScheduledTask? task}) async {
    final plugins = context.read<PluginProvider>().plugins;
    final available = plugins
        .where((plugin) => plugin.enabled && !plugin.hasError)
        .toList();
    if (task == null && available.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先安装并启用一个插件')));
      }
      return;
    }
    if (task != null &&
        !available.any((plugin) => plugin.id == task.pluginId)) {
      final current = plugins.where((plugin) => plugin.id == task.pluginId);
      available.addAll(current);
    }
    final values = await showDialog<_ScheduledTaskDraft>(
      context: context,
      builder: (context) =>
          _ScheduledTaskEditorDialog(task: task, plugins: available),
    );
    if (values == null || !context.mounted) return;
    try {
      if (task == null) {
        await context.read<ScheduledTaskProvider>().create(
          name: values.name,
          pluginId: values.pluginId,
          repeat: values.repeat,
          time: values.time,
          daysOfWeek: values.daysOfWeek,
          scriptKind: ScheduledTaskScriptKind.inline,
          script: values.script,
          source: ScheduledTaskSource.user,
        );
      } else {
        await context.read<ScheduledTaskProvider>().update(
          id: task.id,
          name: values.name,
          repeat: values.repeat,
          time: values.time,
          daysOfWeek: values.daysOfWeek,
          scriptKind: ScheduledTaskScriptKind.inline,
          script: values.script,
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存定时任务失败: $error')));
    }
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});

  final ScheduledTask task;

  @override
  Widget build(BuildContext context) {
    final plugin = context.read<PluginProvider>().pluginById(task.pluginId);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          task.enabled ? Icons.schedule : Icons.schedule_outlined,
          color: task.enabled ? null : Theme.of(context).disabledColor,
        ),
        title: Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${plugin?.displayName ?? task.pluginId} · ${_scheduleLabel(task)}',
            ),
            if (task.nextRunAt != null)
              Text('下次执行 ${_formatDateTime(task.nextRunAt!)}'),
            if (task.lastStatus != null)
              Text(
                '上次 ${_statusLabel(task)}',
                style: TextStyle(
                  color: task.lastStatus == ScheduledTaskRunStatus.failed
                      ? Theme.of(context).colorScheme.error
                      : null,
                  fontSize: 12,
                ),
              ),
            if (task.runHistory.isNotEmpty)
              Text(
                '最近 ${task.runHistory.take(3).map(_historyLabel).join(' · ')}',
                style: const TextStyle(fontSize: 12),
              ),
            if (task.source == ScheduledTaskSource.manifest)
              Text(
                '来自插件 manifest，定义随插件更新',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: task.enabled,
              onChanged: (value) => context
                  .read<ScheduledTaskProvider>()
                  .setEnabled(task.id, value),
            ),
            PopupMenuButton<String>(
              onSelected: (value) => _handleMenu(context, value),
              itemBuilder: (context) => [
                if (task.source == ScheduledTaskSource.user)
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                const PopupMenuItem(value: 'run', child: Text('立即运行')),
                if (task.source == ScheduledTaskSource.user)
                  const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleMenu(BuildContext context, String value) async {
    if (value == 'edit') {
      final plugins = context.read<PluginProvider>().plugins;
      final draft = await showDialog<_ScheduledTaskDraft>(
        context: context,
        builder: (context) =>
            _ScheduledTaskEditorDialog(task: task, plugins: plugins),
      );
      if (draft == null || !context.mounted) return;
      try {
        await context.read<ScheduledTaskProvider>().update(
          id: task.id,
          name: draft.name,
          repeat: draft.repeat,
          time: draft.time,
          daysOfWeek: draft.daysOfWeek,
          scriptKind: ScheduledTaskScriptKind.inline,
          script: draft.script,
        );
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存定时任务失败: $error')));
      }
    } else if (value == 'run') {
      ScheduledTaskScheduler? scheduler;
      try {
        scheduler = context.read<ScheduledTaskScheduler>();
      } on ProviderNotFoundException {
        scheduler = null;
      }
      if (scheduler == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('定时任务调度器未就绪')));
        }
        return;
      }
      final ran = await scheduler.runNow(task.id);
      if (context.mounted && !ran) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('任务当前不可运行')));
      }
    } else if (value == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除定时任务'),
          content: Text('确定删除「${task.name}」吗？'),
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
      if (confirmed == true && context.mounted) {
        await context.read<ScheduledTaskProvider>().delete(task.id);
      }
    }
  }
}

class _ScheduledTaskDraft {
  final String name;
  final String pluginId;
  final ScheduledTaskRepeat repeat;
  final LocalTime time;
  final List<int> daysOfWeek;
  final String script;

  const _ScheduledTaskDraft({
    required this.name,
    required this.pluginId,
    required this.repeat,
    required this.time,
    required this.daysOfWeek,
    required this.script,
  });
}

class _ScheduledTaskEditorDialog extends StatefulWidget {
  final ScheduledTask? task;
  final List<InstalledPlugin> plugins;

  const _ScheduledTaskEditorDialog({required this.task, required this.plugins});

  @override
  State<_ScheduledTaskEditorDialog> createState() =>
      _ScheduledTaskEditorDialogState();
}

class _ScheduledTaskEditorDialogState
    extends State<_ScheduledTaskEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _timeController;
  late final TextEditingController _scriptController;
  late String _pluginId;
  late ScheduledTaskRepeat _repeat;
  late List<int> _daysOfWeek;
  String? _error;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _nameController = TextEditingController(text: task?.name ?? '');
    _timeController = TextEditingController(
      text: task?.time.toString() ?? '21:00',
    );
    _scriptController = TextEditingController(
      text: task?.scriptKind == ScheduledTaskScriptKind.inline
          ? (task?.script ?? '')
          : '',
    );
    _pluginId = task?.pluginId ?? widget.plugins.first.id;
    _repeat = task?.repeat ?? ScheduledTaskRepeat.daily;
    _daysOfWeek = List.of(task?.daysOfWeek ?? const [1, 2, 3, 4, 5]);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _timeController.dispose();
    _scriptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.task == null ? '新建定时任务' : '编辑定时任务'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _pluginId,
                decoration: InputDecoration(
                  labelText: widget.task == null ? '执行环境插件' : '执行环境插件（不可修改）',
                ),
                items: [
                  for (final plugin in widget.plugins)
                    DropdownMenuItem(
                      value: plugin.id,
                      child: Text(plugin.displayName),
                    ),
                ],
                onChanged: widget.task == null
                    ? (value) {
                        if (value != null) _pluginId = value;
                      }
                    : null,
              ),
              TextField(
                controller: _timeController,
                decoration: const InputDecoration(
                  labelText: '时间',
                  hintText: 'HH:mm，例如 21:00',
                ),
              ),
              DropdownButtonFormField<ScheduledTaskRepeat>(
                initialValue: _repeat,
                decoration: const InputDecoration(labelText: '重复'),
                items: const [
                  DropdownMenuItem(
                    value: ScheduledTaskRepeat.daily,
                    child: Text('每天'),
                  ),
                  DropdownMenuItem(
                    value: ScheduledTaskRepeat.weekly,
                    child: Text('每周'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _repeat = value);
                },
              ),
              if (_repeat == ScheduledTaskRepeat.weekly)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final day in const [
                      (1, '一'),
                      (2, '二'),
                      (3, '三'),
                      (4, '四'),
                      (5, '五'),
                      (6, '六'),
                      (7, '日'),
                    ])
                      FilterChip(
                        label: Text('周${day.$2}'),
                        selected: _daysOfWeek.contains(day.$1),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _daysOfWeek = [..._daysOfWeek, day.$1]..sort();
                          } else {
                            _daysOfWeek = _daysOfWeek
                                .where((item) => item != day.$1)
                                .toList();
                          }
                        }),
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _scriptController,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Lua 脚本',
                  hintText:
                      'function run(ctx)\n  -- 可调用插件入口定义的全局函数和 lynai.*\nend',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    final time = LocalTime.tryParse(_timeController.text.trim());
    final script = _scriptController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入名称');
      return;
    }
    if (time == null) {
      setState(() => _error = '时间必须使用 HH:mm 格式');
      return;
    }
    if (_repeat == ScheduledTaskRepeat.weekly && _daysOfWeek.isEmpty) {
      setState(() => _error = '每周任务至少选择一天');
      return;
    }
    if (script.isEmpty) {
      setState(() => _error = '请输入 Lua 脚本');
      return;
    }
    Navigator.pop(
      context,
      _ScheduledTaskDraft(
        name: name,
        pluginId: _pluginId,
        repeat: _repeat,
        time: time,
        daysOfWeek: _daysOfWeek,
        script: script,
      ),
    );
  }
}

String _scheduleLabel(ScheduledTask task) {
  if (task.repeat == ScheduledTaskRepeat.daily) return '每天 ${task.time}';
  final labels = task.daysOfWeek
      .map((day) => const ['一', '二', '三', '四', '五', '六', '日'][day - 1])
      .join('、');
  return '每周 $labels ${task.time}';
}

String _historyLabel(ScheduledTaskRunRecord record) {
  final time = _formatDateTime(record.at);
  final status = switch (record.status) {
    ScheduledTaskRunStatus.success => '成功',
    ScheduledTaskRunStatus.failed => '失败',
    ScheduledTaskRunStatus.skipped => '跳过',
    ScheduledTaskRunStatus.cancelled => '取消',
  };
  return '$time $status';
}

String _statusLabel(ScheduledTask task) {
  final error = task.lastError;
  final status = switch (task.lastStatus) {
    ScheduledTaskRunStatus.success => '成功',
    ScheduledTaskRunStatus.failed => '失败',
    ScheduledTaskRunStatus.skipped => '跳过',
    ScheduledTaskRunStatus.cancelled => '取消',
    null => '未执行',
  };
  return error == null || error.isEmpty ? status : '$status：$error';
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String pad(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${pad(local.month)}-${pad(local.day)} '
      '${pad(local.hour)}:${pad(local.minute)}';
}
