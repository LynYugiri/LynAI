import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plugin.dart';
import '../models/plugin_config_schema.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../repositories/plugin_repository.dart';
import '../widgets/model_config_picker.dart';
import '../widgets/plugin_icon.dart';

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

  /// 弹出确认对话框后删除指定插件，删除成功后自动返回上一页。
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
    final controller = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(value),
    );
    String? error;
    final result = await showDialog<Object?>(
      context: context,
      builder: (context) => StatefulBuilder(
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
      ),
    );
    controller.dispose();
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
      if (mounted) _showMessage(e.toString().replaceFirst('Exception: ', ''));
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

class _PluginFilesCard extends StatefulWidget {
  const _PluginFilesCard({required this.plugin});

  final InstalledPlugin plugin;

  @override
  State<_PluginFilesCard> createState() => _PluginFilesCardState();
}

class _PluginFilesCardState extends State<_PluginFilesCard> {
  late Future<List<PluginFileEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<PluginProvider>().listFiles(widget.plugin.id);
  }

  @override
  Widget build(BuildContext context) {
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
                );
              }),
              if (hasFilesWrite)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新建文件'),
                    onPressed: _createFile,
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
      final content = await provider.readFile(widget.plugin.id, file.path);
      if (!mounted) return;
      final next = await _showFileDialog(file, content);
      if (next == null || !mounted) return;
      await provider.writeEditableFile(widget.plugin.id, file.path, next);
      setState(() => _future = provider.listFiles(widget.plugin.id));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文件已保存')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<String?> _showFileDialog(PluginFileEntry file, String content) async {
    final controller = TextEditingController(text: content);
    String? error;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final editorBg = isDark ? const Color(0xFF1e1e2e) : const Color(0xFFf5f5f5);
    final editorText = isDark
        ? const Color(0xFFdcdcdc)
        : const Color(0xFF1a1a1a);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(file.path),
          content: SizedBox(
            width: 720,
            child: TextField(
              controller: controller,
              readOnly: !file.isEditable,
              maxLines: 20,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: editorText,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: editorBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark
                        ? const Color(0xFF3a3a50)
                        : const Color(0xFFdddddd),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isDark
                        ? const Color(0xFF3a3a50)
                        : const Color(0xFFdddddd),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF6c5ce7)),
                ),
                errorText: error,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
            if (file.isEditable)
              FilledButton(
                onPressed: () {
                  if (file.type == 'json') {
                    try {
                      final decoded = jsonDecode(controller.text);
                      final formatted = const JsonEncoder.withIndent(
                        '  ',
                      ).convert(decoded);
                      Navigator.pop(context, formatted);
                      return;
                    } catch (_) {
                      setDialogState(() => error = 'JSON 格式错误');
                      return;
                    }
                  }
                  Navigator.pop(context, controller.text);
                },
                child: const Text('保存'),
              ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
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
      setState(() => _future = provider.listFiles(widget.plugin.id));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已恢复默认')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  /// 弹出对话框让用户在插件目录下创建新文件并写入初始内容。
  Future<void> _createFile() async {
    final nameController = TextEditingController();
    final contentController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          String? error;
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: contentController,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: '初始内容 (可选)',
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
      ),
    );
    final resultPath = result;
    final content = contentController.text;
    nameController.dispose();
    contentController.dispose();
    if (resultPath == null || !mounted) return;
    try {
      final provider = context.read<PluginProvider>();
      await provider.writeEditableFile(widget.plugin.id, resultPath, content);
      setState(() => _future = provider.listFiles(widget.plugin.id));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文件已创建')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
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
              '通过右上角按钮导入包含 plugin.json 的插件 ZIP。',
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
    'storage:read' => '读取插件存储',
    'storage:write' => '写入插件存储',
    'webview:bridge' => '使用 WebView Bridge',
    'native:location' => '获取位置',
    'native:open_app' => '打开应用',
    'files:write' => '插件文件读写',
    'network:access' => '网络访问',
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
      'status-dashboard' => '状态仪表盘',
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
      final plugin = await provider.importBuiltIn(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${plugin.manifest.name} 已安装')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('安装失败: $e')));
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('操作失败: $e')));
  }
}
