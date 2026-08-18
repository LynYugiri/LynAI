import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plugin.dart';
import '../providers/calendar_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/task_provider.dart';
import '../services/code_syntax_service.dart';
import '../services/plugin_lua_runtime_service.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/latex_renderer.dart';
import '../widgets/text_editing_controller_host.dart';
import 'plugin_file_editor_page.dart' show PluginPagePreviewPage;

/// 插件工坊能力编辑器与就地运行/预览工具。
///
/// 让作者在工坊内可视化增删改 manifest 的 tools/functions/commands/skills/
/// featurePages/settings，并对 tool/function/command 就地运行、对 Skill 与
/// 功能页就地预览，避免只能手写 `plugin.json` + `main.lua`。

/// 就地运行插件 Lua handler 的入口。
///
/// 复用 [PluginLuaRuntimeService] 的执行入口，从当前 Provider 图中尽力读取
/// 运行时所需 Provider；缺失时传 null，相关宿主能力会返回错误而非崩溃。
class PluginStudioRunner {
  PluginStudioRunner._();

  static Future<Map<String, dynamic>> runTool(
    BuildContext context,
    InstalledPlugin plugin,
    PluginToolDefinition tool,
    Map<String, dynamic> arguments,
  ) {
    return PluginLuaRuntimeService().executeTool(
      plugin: plugin,
      tool: tool,
      arguments: arguments,
      features: _maybeRead<FeatureProvider>(context),
      tasks: _maybeRead<TaskProvider>(context),
      calendar: _maybeRead<CalendarProvider>(context),
      modelConfigs: _maybeRead<ModelConfigProvider>(context),
      plugins: _maybeRead<PluginProvider>(context),
      settings: _maybeRead<SettingsProvider>(context),
    );
  }

  static Future<Map<String, dynamic>> runFunction(
    BuildContext context,
    InstalledPlugin plugin,
    PluginFunctionDefinition function,
    Map<String, dynamic> arguments,
  ) {
    return PluginLuaRuntimeService().executeFunction(
      plugin: plugin,
      function: function,
      arguments: arguments,
      features: _maybeRead<FeatureProvider>(context),
      tasks: _maybeRead<TaskProvider>(context),
      calendar: _maybeRead<CalendarProvider>(context),
      modelConfigs: _maybeRead<ModelConfigProvider>(context),
      plugins: _maybeRead<PluginProvider>(context),
      settings: _maybeRead<SettingsProvider>(context),
    );
  }

  static Future<Map<String, dynamic>> runCommand(
    BuildContext context,
    InstalledPlugin plugin,
    PluginCommandDefinition command,
    Map<String, dynamic> arguments,
  ) {
    return PluginLuaRuntimeService().executeCommandHandler(
      plugin: plugin,
      command: command,
      arguments: arguments,
      features: _maybeRead<FeatureProvider>(context),
      tasks: _maybeRead<TaskProvider>(context),
      calendar: _maybeRead<CalendarProvider>(context),
      modelConfigs: _maybeRead<ModelConfigProvider>(context),
      plugins: _maybeRead<PluginProvider>(context),
      settings: _maybeRead<SettingsProvider>(context),
    );
  }

  static T? _maybeRead<T>(BuildContext context) {
    try {
      return Provider.of<T>(context, listen: false);
    } catch (_) {
      return null;
    }
  }
}

/// 能力区块外壳：标题、数量与右上角「添加」按钮。
class _CapabilitySection extends StatelessWidget {
  const _CapabilitySection({
    required this.title,
    required this.count,
    required this.onAdd,
    required this.child,
  });

  final String title;
  final int count;
  final VoidCallback onAdd;
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
            Row(
              children: [
                Text(
                  '$title · $count',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _Items extends StatelessWidget {
  const _Items({required this.empty, required this.children});

  final String empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return Text(empty, style: Theme.of(context).textTheme.bodySmall);
    }
    return Column(children: children);
  }
}

/// 工具列表编辑器。
class PluginStudioToolsEditor extends StatelessWidget {
  const PluginStudioToolsEditor({super.key, required this.plugin});

  final InstalledPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final tools = plugin.manifest.tools;
    return _CapabilitySection(
      title: '工具 (tools)',
      count: tools.length,
      onAdd: () => _editTool(context, null),
      child: _Items(
        empty: '未声明工具。工具是模型可调用的能力。',
        children: [
          for (var i = 0; i < tools.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.build_outlined, size: 18),
              title: Text(tools[i].name),
              subtitle: Text(
                tools[i].description.isEmpty
                    ? tools[i].handler
                    : tools[i].description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '运行',
                    icon: const Icon(Icons.play_arrow_outlined, size: 18),
                    onPressed: () => _runTool(context, tools[i]),
                  ),
                  IconButton(
                    tooltip: '编辑',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _editTool(context, i),
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _removeTool(context, i),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _runTool(
    BuildContext context,
    PluginToolDefinition tool,
  ) async {
    await runHandlerDialog(
      context,
      title: '运行工具 ${tool.name}',
      runner: (args) => PluginStudioRunner.runTool(context, plugin, tool, args),
    );
  }

  Future<void> _editTool(BuildContext context, int? index) async {
    final current = index == null ? null : plugin.manifest.tools[index];
    final result = await _showToolDialog(context, current);
    if (result == null || !context.mounted) return;
    final next = _replaceAt(plugin.manifest.tools, index, result);
    await _save(context, () async {
      await context.read<PluginProvider>().setManifestTools(plugin.id, next);
    }, '工具已更新');
  }

  Future<void> _removeTool(BuildContext context, int index) async {
    final next = _removeAt(plugin.manifest.tools, index);
    await _save(context, () async {
      await context.read<PluginProvider>().setManifestTools(plugin.id, next);
    }, '工具已删除');
  }
}

/// 函数列表编辑器。
class PluginStudioFunctionsEditor extends StatelessWidget {
  const PluginStudioFunctionsEditor({super.key, required this.plugin});

  final InstalledPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final functions = plugin.manifest.functions;
    return _CapabilitySection(
      title: '函数 (functions)',
      count: functions.length,
      onAdd: () => _editFunction(context, null),
      child: _Items(
        empty: '未声明函数。函数是插件内部或跨插件调用的能力。',
        children: [
          for (var i = 0; i < functions.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.functions, size: 18),
              title: Text(functions[i].name),
              subtitle: Text(
                functions[i].expose
                    ? '${functions[i].handler} · 对外暴露'
                    : functions[i].handler,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '运行',
                    icon: const Icon(Icons.play_arrow_outlined, size: 18),
                    onPressed: () => _runFunction(context, functions[i]),
                  ),
                  IconButton(
                    tooltip: '编辑',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _editFunction(context, i),
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _removeFunction(context, i),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _runFunction(
    BuildContext context,
    PluginFunctionDefinition function,
  ) async {
    await runHandlerDialog(
      context,
      title: '运行函数 ${function.name}',
      runner: (args) =>
          PluginStudioRunner.runFunction(context, plugin, function, args),
    );
  }

  Future<void> _editFunction(BuildContext context, int? index) async {
    final current = index == null ? null : plugin.manifest.functions[index];
    final result = await _showFunctionDialog(context, current);
    if (result == null || !context.mounted) return;
    final next = _replaceAt(plugin.manifest.functions, index, result);
    await _save(context, () async {
      await context
          .read<PluginProvider>()
          .setManifestFunctions(plugin.id, next);
    }, '函数已更新');
  }

  Future<void> _removeFunction(BuildContext context, int index) async {
    final next = _removeAt(plugin.manifest.functions, index);
    await _save(context, () async {
      await context
          .read<PluginProvider>()
          .setManifestFunctions(plugin.id, next);
    }, '函数已删除');
  }
}

/// 命令列表编辑器。
class PluginStudioCommandsEditor extends StatelessWidget {
  const PluginStudioCommandsEditor({super.key, required this.plugin});

  final InstalledPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final commands = plugin.manifest.commands;
    return _CapabilitySection(
      title: '命令 (commands)',
      count: commands.length,
      onAdd: () => _editCommand(context, null),
      child: _Items(
        empty: '未声明命令。命令是命令面板的选项源。',
        children: [
          for (var i = 0; i < commands.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bolt_outlined, size: 18),
              title: Text(commands[i].name),
              subtitle: Text(
                commands[i].description.isEmpty
                    ? commands[i].handler
                    : commands[i].description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '运行',
                    icon: const Icon(Icons.play_arrow_outlined, size: 18),
                    onPressed: () => _runCommand(context, commands[i]),
                  ),
                  IconButton(
                    tooltip: '编辑',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _editCommand(context, i),
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _removeCommand(context, i),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _runCommand(
    BuildContext context,
    PluginCommandDefinition command,
  ) async {
    await runHandlerDialog(
      context,
      title: '运行命令 ${command.name}',
      runner: (args) =>
          PluginStudioRunner.runCommand(context, plugin, command, args),
    );
  }

  Future<void> _editCommand(BuildContext context, int? index) async {
    final current = index == null ? null : plugin.manifest.commands[index];
    final result = await _showCommandDialog(context, current);
    if (result == null || !context.mounted) return;
    final next = _replaceAt(plugin.manifest.commands, index, result);
    await _save(context, () async {
      await context
          .read<PluginProvider>()
          .setManifestCommands(plugin.id, next);
    }, '命令已更新');
  }

  Future<void> _removeCommand(BuildContext context, int index) async {
    final next = _removeAt(plugin.manifest.commands, index);
    await _save(context, () async {
      await context
          .read<PluginProvider>()
          .setManifestCommands(plugin.id, next);
    }, '命令已删除');
  }
}

/// Skill 列表编辑器（含正文预览）。
class PluginStudioSkillsEditor extends StatelessWidget {
  const PluginStudioSkillsEditor({super.key, required this.plugin});

  final InstalledPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final skills = plugin.manifest.skills;
    return _CapabilitySection(
      title: 'Skill',
      count: skills.length,
      onAdd: () => _editSkill(context, null),
      child: _Items(
        empty: '未声明 Skill。Skill 是按需加载的方法论/工作流正文。',
        children: [
          for (var i = 0; i < skills.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.auto_awesome_motion_outlined,
                size: 18,
              ),
              title: Text(
                skills[i].title.isEmpty ? skills[i].name : skills[i].title,
              ),
              subtitle: Text(
                'skills/${skills[i].name}.md',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '预览正文',
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    onPressed: () => _previewSkill(context, skills[i]),
                  ),
                  IconButton(
                    tooltip: '编辑',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _editSkill(context, i),
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _removeSkill(context, i),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _previewSkill(
    BuildContext context,
    PluginSkillDefinition skill,
  ) async {
    try {
      final content = await context
          .read<PluginProvider>()
          .readDeveloperFile(plugin.id, 'skills/${skill.name}.md');
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SkillPreviewPage(
            plugin: plugin,
            skill: skill,
            content: content,
          ),
        ),
      );
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

  Future<void> _editSkill(BuildContext context, int? index) async {
    final current = index == null ? null : plugin.manifest.skills[index];
    final result = await _showSkillDialog(context, current);
    if (result == null || !context.mounted) return;
    final next = _replaceAt(plugin.manifest.skills, index, result);
    await _save(context, () async {
      await context.read<PluginProvider>().setManifestSkills(plugin.id, next);
    }, 'Skill 已更新');
  }

  Future<void> _removeSkill(BuildContext context, int index) async {
    final next = _removeAt(plugin.manifest.skills, index);
    await _save(context, () async {
      await context.read<PluginProvider>().setManifestSkills(plugin.id, next);
    }, 'Skill 已删除');
  }
}

/// 功能页列表编辑器（含预览）。
class PluginStudioFeaturePagesEditor extends StatelessWidget {
  const PluginStudioFeaturePagesEditor({super.key, required this.plugin});

  final InstalledPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final pages = plugin.manifest.featurePages;
    return _CapabilitySection(
      title: '功能页 (featurePages)',
      count: pages.length,
      onAdd: () => _editPage(context, null),
      child: _Items(
        empty: '未声明功能页。功能页是 WebView 展示的用户界面。',
        children: [
          for (var i = 0; i < pages.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.web_outlined, size: 18),
              title: Text(pages[i].title.isEmpty ? pages[i].id : pages[i].title),
              subtitle: Text(
                pages[i].entry,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '预览',
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    onPressed: () => _previewPage(context, pages[i]),
                  ),
                  IconButton(
                    tooltip: '编辑',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _editPage(context, i),
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _removePage(context, i),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _previewPage(
    BuildContext context,
    PluginFeaturePageDefinition page,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PluginPagePreviewPage(pluginId: plugin.id, pageId: page.id),
      ),
    );
  }

  Future<void> _editPage(BuildContext context, int? index) async {
    final current = index == null ? null : plugin.manifest.featurePages[index];
    final result = await _showFeaturePageDialog(context, current);
    if (result == null || !context.mounted) return;
    final next = _replaceAt(plugin.manifest.featurePages, index, result);
    await _save(context, () async {
      await context
          .read<PluginProvider>()
          .setManifestFeaturePages(plugin.id, next);
    }, '功能页已更新');
  }

  Future<void> _removePage(BuildContext context, int index) async {
    final next = _removeAt(plugin.manifest.featurePages, index);
    await _save(context, () async {
      await context
          .read<PluginProvider>()
          .setManifestFeaturePages(plugin.id, next);
    }, '功能页已删除');
  }
}

/// 设置项列表编辑器。
class PluginStudioSettingsEditor extends StatelessWidget {
  const PluginStudioSettingsEditor({super.key, required this.plugin});

  final InstalledPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final settings = plugin.manifest.settings;
    return _CapabilitySection(
      title: '设置项 (settings)',
      count: settings.length,
      onAdd: () => _editSetting(context, null),
      child: _Items(
        empty: '未声明设置项。设置项在插件管理页渲染为表单。',
        children: [
          for (var i = 0; i < settings.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune, size: 18),
              title: Text(
                settings[i].title.isEmpty
                    ? settings[i].key
                    : settings[i].title,
              ),
              subtitle: Text(
                '${settings[i].key} · ${settings[i].type}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '编辑',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _editSetting(context, i),
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _removeSetting(context, i),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editSetting(BuildContext context, int? index) async {
    final current = index == null ? null : plugin.manifest.settings[index];
    final result = await _showSettingDialog(context, current);
    if (result == null || !context.mounted) return;
    final next = _replaceAt(plugin.manifest.settings, index, result);
    await _save(context, () async {
      await context.read<PluginProvider>().setManifestSettings(plugin.id, next);
    }, '设置项已更新');
  }

  Future<void> _removeSetting(BuildContext context, int index) async {
    final next = _removeAt(plugin.manifest.settings, index);
    await _save(context, () async {
      await context.read<PluginProvider>().setManifestSettings(plugin.id, next);
    }, '设置项已删除');
  }
}

/// Skill 正文预览页。
class SkillPreviewPage extends StatelessWidget {
  const SkillPreviewPage({
    super.key,
    required this.plugin,
    required this.skill,
    required this.content,
  });

  final InstalledPlugin plugin;
  final PluginSkillDefinition skill;
  final String content;

  @override
  Widget build(BuildContext context) {
    final title = skill.title.isEmpty ? skill.name : skill.title;
    return Scaffold(
      appBar: AppBar(title: Text('${plugin.displayName} · $title')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: MarkdownWithLatex(content: content),
      ),
    );
  }
}

/// 就地运行 handler 的通用流程：收参数 → 执行 → 展示结果 JSON。
Future<void> runHandlerDialog(
  BuildContext context, {
  required String title,
  required Future<Map<String, dynamic>> Function(Map<String, dynamic>) runner,
}) async {
  final args = await _showJsonDialog(
    context,
    title: '$title · 参数',
    initial: const <String, dynamic>{},
  );
  if (args == null || !context.mounted) return;
  final map = args is Map ? args : <String, dynamic>{};
  final stopwatch = Stopwatch()..start();
  Map<String, dynamic> result;
  try {
    result = await runner(
      map.map((key, value) => MapEntry(key.toString(), value)),
    );
  } catch (e) {
    result = {'ok': false, 'error': e.toString()};
  }
  stopwatch.stop();
  if (!context.mounted) return;
  await _showRunResult(context, title, result, stopwatch.elapsed);
}

// ---- 列表工具 ----

List<T> _replaceAt<T>(List<T> list, int? index, T item) {
  if (index == null) return [...list, item];
  final next = [...list];
  next[index] = item;
  return next;
}

List<T> _removeAt<T>(List<T> list, int index) {
  final next = [...list];
  next.removeAt(index);
  return next;
}

Future<void> _save(
  BuildContext context,
  Future<void> Function() action,
  String success,
) async {
  try {
    await action();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
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

// ---- 通用 JSON / 结果对话框 ----

Future<Object?> _showJsonDialog(
  BuildContext context, {
  required String title,
  required Object initial,
}) async {
  String? error;
  final result = await showDialog<Object?>(
    context: context,
    builder: (context) => TextEditingControllerHost(
      initialTexts: [const JsonEncoder.withIndent('  ').convert(initial)],
      builder: (context, controllers) {
        final controller = controllers.single;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 520,
              child: TextField(
                controller: controller,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(
                  fontFamily: codeFontFamily,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  errorText: error,
                  hintText: '必须是合法 JSON',
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

Future<void> _showRunResult(
  BuildContext context,
  String title,
  Map<String, dynamic> result,
  Duration elapsed,
) async {
  final json = const JsonEncoder.withIndent('  ').convert(result);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$title · 结果'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${elapsed.inMilliseconds} ms',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                json,
                style: const TextStyle(
                  fontFamily: codeFontFamily,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

// ---- 各实体编辑对话框 ----

Future<PluginToolDefinition?> _showToolDialog(
  BuildContext context,
  PluginToolDefinition? current,
) async {
  String? error;
  final result = await showDialog<PluginToolDefinition>(
    context: context,
    builder: (context) => TextEditingControllerHost(
      initialTexts: [
        current?.name ?? '',
        current?.description ?? '',
        current?.handler ?? '',
        const JsonEncoder.withIndent('  ').convert(
          current?.parameters ??
              const {'type': 'object', 'properties': <String, dynamic>{}},
        ),
      ],
      builder: (context, controllers) {
        final name = controllers[0];
        final description = controllers[1];
        final handler = controllers[2];
        final parameters = controllers[3];
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(current == null ? '添加工具' : '编辑工具'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: '名称 (name)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: description,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: '描述 (description)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: handler,
                      decoration: const InputDecoration(
                        labelText: 'Lua 函数名 (handler)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: parameters,
                      maxLines: 8,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(
                        fontFamily: codeFontFamily,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: '参数 JSON Schema (parameters)',
                        border: const OutlineInputBorder(),
                        errorText: error,
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
              FilledButton(
                onPressed: () {
                  Map<String, dynamic> params;
                  try {
                    final decoded = jsonDecode(parameters.text);
                    if (decoded is! Map) {
                      setDialogState(() => error = 'parameters 必须是 JSON 对象');
                      return;
                    }
                    params = decoded.map(
                      (key, value) => MapEntry(key.toString(), value),
                    );
                  } catch (_) {
                    setDialogState(() => error = 'parameters JSON 格式错误');
                    return;
                  }
                  final def = PluginToolDefinition(
                    name: name.text.trim(),
                    description: description.text.trim(),
                    handler: handler.text.trim().isEmpty
                        ? name.text.trim()
                        : handler.text.trim(),
                    parameters: params,
                  );
                  final invalid = def.validate();
                  if (invalid != null) {
                    setDialogState(() => error = invalid);
                    return;
                  }
                  Navigator.pop(context, def);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    ),
  );
  return result;
}

Future<PluginFunctionDefinition?> _showFunctionDialog(
  BuildContext context,
  PluginFunctionDefinition? current,
) async {
  String? error;
  final result = await showDialog<PluginFunctionDefinition>(
    context: context,
    builder: (context) => TextEditingControllerHost(
      initialTexts: [
        current?.name ?? '',
        current?.title ?? '',
        current?.handler ?? '',
        current?.description ?? '',
        (current?.requires ?? const []).join(', '),
        const JsonEncoder.withIndent('  ').convert(
          current?.parameters ??
              const {'type': 'object', 'properties': <String, dynamic>{}},
        ),
      ],
      builder: (context, controllers) {
        final name = controllers[0];
        final title = controllers[1];
        final handler = controllers[2];
        final description = controllers[3];
        final requires = controllers[4];
        final parameters = controllers[5];
        var expose = current?.expose ?? false;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(current == null ? '添加函数' : '编辑函数'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: '名称 (name)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: title,
                      decoration: const InputDecoration(
                        labelText: '标题 (title)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: handler,
                      decoration: const InputDecoration(
                        labelText: 'Lua 函数名 (handler)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: description,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: '描述 (description)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: requires,
                      decoration: const InputDecoration(
                        labelText: '额外权限 (requires，逗号分隔)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: parameters,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(
                        fontFamily: codeFontFamily,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: '参数 JSON Schema (parameters)',
                        border: const OutlineInputBorder(),
                        errorText: error,
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: expose,
                      title: const Text('对外暴露 (expose)'),
                      onChanged: (next) => setDialogState(() => expose = next),
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
              FilledButton(
                onPressed: () {
                  Map<String, dynamic> params;
                  try {
                    final decoded = jsonDecode(parameters.text);
                    if (decoded is! Map) {
                      setDialogState(() => error = 'parameters 必须是 JSON 对象');
                      return;
                    }
                    params = decoded.map(
                      (key, value) => MapEntry(key.toString(), value),
                    );
                  } catch (_) {
                    setDialogState(() => error = 'parameters JSON 格式错误');
                    return;
                  }
                  final def = PluginFunctionDefinition(
                    name: name.text.trim(),
                    title: title.text.trim().isEmpty
                        ? name.text.trim()
                        : title.text.trim(),
                    handler: handler.text.trim().isEmpty
                        ? name.text.trim()
                        : handler.text.trim(),
                    description: description.text.trim(),
                    parameters: params,
                    expose: expose,
                    requires: requires.text
                        .split(',')
                        .map((item) => item.trim())
                        .where((item) => item.isNotEmpty)
                        .toList(growable: false),
                  );
                  final invalid = def.validate();
                  if (invalid != null) {
                    setDialogState(() => error = invalid);
                    return;
                  }
                  Navigator.pop(context, def);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    ),
  );
  return result;
}

Future<PluginCommandDefinition?> _showCommandDialog(
  BuildContext context,
  PluginCommandDefinition? current,
) async {
  String? error;
  final result = await showDialog<PluginCommandDefinition>(
    context: context,
    builder: (context) => TextEditingControllerHost(
      initialTexts: [
        current?.name ?? '',
        current?.title ?? '',
        current?.handler ?? '',
        current?.description ?? '',
        current?.model ?? '',
        const JsonEncoder.withIndent('  ').convert(
          current?.parameters ??
              const {'type': 'object', 'properties': <String, dynamic>{}},
        ),
      ],
      builder: (context, controllers) {
        final name = controllers[0];
        final title = controllers[1];
        final handler = controllers[2];
        final description = controllers[3];
        final model = controllers[4];
        final parameters = controllers[5];
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(current == null ? '添加命令' : '编辑命令'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: '名称 (name)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: title,
                      decoration: const InputDecoration(
                        labelText: '标题 (title)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: handler,
                      decoration: const InputDecoration(
                        labelText: 'Lua 函数名 (handler)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: description,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: '描述 (description)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: model,
                      decoration: const InputDecoration(
                        labelText: '覆盖模型 ID (model，可选)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: parameters,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(
                        fontFamily: codeFontFamily,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: '参数 JSON Schema (parameters)',
                        border: const OutlineInputBorder(),
                        errorText: error,
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
              FilledButton(
                onPressed: () {
                  Map<String, dynamic> params;
                  try {
                    final decoded = jsonDecode(parameters.text);
                    if (decoded is! Map) {
                      setDialogState(() => error = 'parameters 必须是 JSON 对象');
                      return;
                    }
                    params = decoded.map(
                      (key, value) => MapEntry(key.toString(), value),
                    );
                  } catch (_) {
                    setDialogState(() => error = 'parameters JSON 格式错误');
                    return;
                  }
                  final def = PluginCommandDefinition(
                    name: name.text.trim(),
                    title: title.text.trim().isEmpty
                        ? name.text.trim()
                        : title.text.trim(),
                    handler: handler.text.trim().isEmpty
                        ? name.text.trim()
                        : handler.text.trim(),
                    description: description.text.trim(),
                    parameters: params,
                    model: model.text.trim().isEmpty
                        ? null
                        : model.text.trim(),
                  );
                  final invalid = def.validate();
                  if (invalid != null) {
                    setDialogState(() => error = invalid);
                    return;
                  }
                  Navigator.pop(context, def);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    ),
  );
  return result;
}

Future<PluginSkillDefinition?> _showSkillDialog(
  BuildContext context,
  PluginSkillDefinition? current,
) async {
  String? error;
  final result = await showDialog<PluginSkillDefinition>(
    context: context,
    builder: (context) => TextEditingControllerHost(
      initialTexts: [
        current?.name ?? '',
        current?.title ?? '',
        current?.description ?? '',
        current?.whenToUse ?? '',
        (current?.tags ?? const []).join(', '),
      ],
      builder: (context, controllers) {
        final name = controllers[0];
        final title = controllers[1];
        final description = controllers[2];
        final whenToUse = controllers[3];
        final tags = controllers[4];
        var modelInvocable = current?.modelInvocable ?? true;
        var userInvocable = current?.userInvocable ?? true;
        var editable = current?.editable ?? true;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(current == null ? '添加 Skill' : '编辑 Skill'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: '名称 (name，对应 skills/<name>.md)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: title,
                      decoration: const InputDecoration(
                        labelText: '标题 (title)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: description,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: '摘要 (description)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: whenToUse,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: '触发场景 (whenToUse)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: tags,
                      decoration: const InputDecoration(
                        labelText: '标签 (tags，逗号分隔)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: modelInvocable,
                      title: const Text('模型可按需调用 (modelInvocable)'),
                      onChanged: (next) =>
                          setDialogState(() => modelInvocable = next),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: userInvocable,
                      title: const Text('用户可手动调用 (userInvocable)'),
                      onChanged: (next) =>
                          setDialogState(() => userInvocable = next),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: editable,
                      title: const Text('允许编辑正文 (editable)'),
                      onChanged: (next) => setDialogState(() => editable = next),
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
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
              FilledButton(
                onPressed: () {
                  final def = PluginSkillDefinition(
                    name: name.text.trim(),
                    title: title.text.trim(),
                    description: description.text.trim(),
                    whenToUse: whenToUse.text.trim(),
                    tags: tags.text
                        .split(',')
                        .map((item) => item.trim())
                        .where((item) => item.isNotEmpty)
                        .toList(growable: false),
                    modelInvocable: modelInvocable,
                    userInvocable: userInvocable,
                    editable: editable,
                  );
                  final invalid = def.validate();
                  if (invalid != null) {
                    setDialogState(() => error = invalid);
                    return;
                  }
                  Navigator.pop(context, def);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    ),
  );
  return result;
}

Future<PluginFeaturePageDefinition?> _showFeaturePageDialog(
  BuildContext context,
  PluginFeaturePageDefinition? current,
) async {
  String? error;
  final result = await showDialog<PluginFeaturePageDefinition>(
    context: context,
    builder: (context) => TextEditingControllerHost(
      initialTexts: [
        current?.id ?? '',
        current?.title ?? '',
        current?.icon ?? '',
        current?.entry ?? 'index.html',
      ],
      builder: (context, controllers) {
        final id = controllers[0];
        final title = controllers[1];
        final icon = controllers[2];
        final entry = controllers[3];
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(current == null ? '添加功能页' : '编辑功能页'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: id,
                    decoration: const InputDecoration(
                      labelText: 'ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: '标题',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: icon,
                    decoration: const InputDecoration(
                      labelText: '图标 (icon，可空)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: entry,
                    decoration: const InputDecoration(
                      labelText: '入口文件 (entry)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
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
                  final def = PluginFeaturePageDefinition(
                    id: id.text.trim(),
                    title: title.text.trim(),
                    icon: icon.text.trim(),
                    entry: entry.text.trim(),
                  );
                  final invalid = def.validate();
                  if (invalid != null) {
                    setDialogState(() => error = invalid);
                    return;
                  }
                  Navigator.pop(context, def);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    ),
  );
  return result;
}

Future<PluginSettingDefinition?> _showSettingDialog(
  BuildContext context,
  PluginSettingDefinition? current,
) async {
  String? error;
  final result = await showDialog<PluginSettingDefinition>(
    context: context,
    builder: (context) => TextEditingControllerHost(
      initialTexts: [
        current?.key ?? '',
        current?.title ?? '',
        _stringifyDefault(current?.defaultValue),
        const JsonEncoder.withIndent('  ').convert(
          current?.options ?? const <Map<String, dynamic>>[],
        ),
      ],
      builder: (context, controllers) {
        final key = controllers[0];
        final title = controllers[1];
        final defaultValue = controllers[2];
        final options = controllers[3];
        var type = current?.type ?? 'string';
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(current == null ? '添加设置项' : '编辑设置项'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: key,
                      decoration: const InputDecoration(
                        labelText: '键 (key)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: title,
                      decoration: const InputDecoration(
                        labelText: '标题 (title)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      decoration: const InputDecoration(
                        labelText: '类型 (type)',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'string', child: Text('string')),
                        DropdownMenuItem(
                          value: 'boolean',
                          child: Text('boolean'),
                        ),
                        DropdownMenuItem(value: 'select', child: Text('select')),
                      ],
                      onChanged: (next) =>
                          setDialogState(() => type = next ?? 'string'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: defaultValue,
                      decoration: InputDecoration(
                        labelText: '默认值 (default)',
                        helperText: type == 'boolean'
                            ? '填 true 或 false'
                            : type == 'select'
                            ? '填选项 value'
                            : '字符串默认值',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (type == 'select') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: options,
                        maxLines: 5,
                        keyboardType: TextInputType.multiline,
                        style: const TextStyle(
                          fontFamily: codeFontFamily,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          labelText: '选项 (options，JSON 数组)',
                          border: const OutlineInputBorder(),
                          errorText: error,
                        ),
                      ),
                    ],
                  ],
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
                  if (key.text.trim().isEmpty) {
                    setDialogState(() => error = 'key 不能为空');
                    return;
                  }
                  List<Map<String, dynamic>> optionList = const [];
                  if (type == 'select') {
                    try {
                      final decoded = jsonDecode(options.text);
                      if (decoded is! List) {
                        setDialogState(() => error = 'options 必须是 JSON 数组');
                        return;
                      }
                      optionList = decoded
                          .whereType<Map>()
                          .map((item) => Map<String, dynamic>.from(item))
                          .toList(growable: false);
                    } catch (_) {
                      setDialogState(() => error = 'options JSON 格式错误');
                      return;
                    }
                  }
                  final def = PluginSettingDefinition(
                    key: key.text.trim(),
                    type: type,
                    title: title.text.trim(),
                    defaultValue: _parseDefault(type, defaultValue.text),
                    options: optionList,
                  );
                  Navigator.pop(context, def);
                },
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    ),
  );
  return result;
}

String _stringifyDefault(Object? value) {
  if (value == null) return '';
  if (value is bool || value is num) return value.toString();
  return value.toString();
}

Object? _parseDefault(String type, String text) {
  if (text.isEmpty) return null;
  if (type == 'boolean') return text.trim().toLowerCase() == 'true';
  return text;
}
