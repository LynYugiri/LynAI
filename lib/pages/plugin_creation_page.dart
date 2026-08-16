import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pub_semver/pub_semver.dart';

import '../providers/plugin_provider.dart';
import '../services/plugin_scaffold_service.dart';
import '../utils/snackbar_utils.dart';

/// 新建插件向导页面。
///
/// 用户填写插件基础信息并选择脚手架模板后，由 [PluginProvider.createPlugin]
/// 生成一个可继续编辑的本地插件。创建后返回插件 ID 供调用方打开详情页。
class PluginCreationPage extends StatefulWidget {
  const PluginCreationPage({super.key});

  @override
  State<PluginCreationPage> createState() => _PluginCreationPageState();
}

class _PluginCreationPageState extends State<PluginCreationPage> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  final _versionController = TextEditingController(text: '0.1.0');
  final _authorController = TextEditingController();
  final _descriptionController = TextEditingController();
  PluginScaffoldKind _kind = PluginScaffoldKind.luaTool;
  bool _creating = false;

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _versionController.dispose();
    _authorController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新建插件'), centerTitle: true),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '创建一个本地插件草稿。创建后可在插件详情页继续编辑 plugin.json、入口脚本和其他文件。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _idController,
              decoration: const InputDecoration(
                labelText: '插件 ID',
                hintText: 'my-first-plugin',
                helperText: '只能包含字母、数字、下划线、点和横线；创建后不可在编辑器中修改',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final id = value?.trim() ?? '';
                if (id.isEmpty) return '插件 ID 不能为空';
                if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(id)) {
                  return '插件 ID 只能包含字母、数字、下划线、点和横线';
                }
                if (id == '.' || id == '..') {
                  return '插件 ID 不能为 . 或 ..';
                }
                final existing = context.read<PluginProvider>().pluginById(id);
                if (existing != null) return '插件 $id 已存在';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '显示名称',
                hintText: '我的第一个插件',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if ((value?.trim() ?? '').isEmpty) return '显示名称不能为空';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _versionController,
              decoration: const InputDecoration(
                labelText: '版本',
                helperText: '语义化版本，例如 0.1.0',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final version = value?.trim() ?? '';
                if (version.isEmpty) return '版本不能为空';
                try {
                  Version.parse(version);
                } on FormatException {
                  return '版本号需要符合 SemVer，例如 0.1.0';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _authorController,
              decoration: const InputDecoration(
                labelText: '作者',
                hintText: '可选',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '描述',
                hintText: '插件用途简介（可选）',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            Text('选择模板', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            RadioGroup<PluginScaffoldKind>(
              groupValue: _kind,
              onChanged: (value) {
                if (value == null) return;
                setState(() => _kind = value);
              },
              child: Column(
                children: [
                  for (final kind in PluginScaffoldKind.values)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: RadioListTile<PluginScaffoldKind>(
                        value: kind,
                        title: Text(kind.label),
                        subtitle: Text(kind.description),
                        secondary: Icon(_iconFor(kind)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _creating ? null : _submit,
              icon: _creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text(_creating ? '创建中…' : '创建插件'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(PluginScaffoldKind kind) => switch (kind) {
    PluginScaffoldKind.blank => Icons.insert_drive_file_outlined,
    PluginScaffoldKind.luaTool => Icons.handyman_outlined,
    PluginScaffoldKind.skill => Icons.auto_awesome_motion_outlined,
    PluginScaffoldKind.featurePage => Icons.web_outlined,
  };

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _creating = true);
    try {
      final plugin = await context.read<PluginProvider>().createPlugin(
        id: _idController.text.trim(),
        name: _nameController.text.trim(),
        version: _versionController.text.trim(),
        author: _authorController.text.trim(),
        description: _descriptionController.text.trim(),
        kind: _kind,
      );
      if (!mounted) return;
      showShortSnackBar(context, '插件 ${plugin.displayName} 已创建');
      Navigator.pop(context, plugin.id);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, '创建失败', details: e.toString());
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }
}
