import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plugin.dart';
import '../providers/plugin_provider.dart';
import '../services/lynai_permission_definitions.dart';

/// 插件安装完成后的权限授权弹窗。
///
/// 列出插件声明及依赖调用所需的敏感权限，默认全选，并支持一键「全选」。
/// 用户确认后通过 [PluginProvider.setGrantedPermissions] 保存授权结果；
/// 免授权权限不会出现在选择列表中，而是随安装自动授予。
Future<void> showPluginPermissionAuthorizationDialog(
  BuildContext context, {
  required String pluginId,
}) async {
  final provider = context.read<PluginProvider>();
  final plugin = provider.pluginById(pluginId);
  if (plugin == null) return;

  final listable = provider.listablePermissionIds(plugin);
  final sensitive = listable
      .where((permission) => !isAutoGrantedPluginPermission(permission))
      .toList(growable: false);
  if (sensitive.isEmpty) return;

  final selected = await showDialog<Set<String>>(
    context: context,
    builder: (context) => PluginPermissionAuthorizationDialog(
      plugin: plugin,
      sensitivePermissions: _orderedPermissions(sensitive),
      autoGrantedPermissions: _orderedPermissions(
        listable.where(isAutoGrantedPluginPermission).toList(growable: false),
      ),
    ),
  );
  if (selected == null || !context.mounted) return;
  await context.read<PluginProvider>().setGrantedPermissions(
    pluginId,
    selected.toList(growable: false),
  );
}

/// 按系统权限定义顺序排列权限 ID，未注册 ID 放在末尾以兼容旧插件。
List<String> _orderedPermissions(Iterable<String> permissions) {
  final ids = permissions.toSet();
  final ordered = <String>[];
  for (final definition in lynaiPermissionDefinitions) {
    if (ids.remove(definition.id)) ordered.add(definition.id);
  }
  final rest = ids.toList(growable: false)..sort();
  return [...ordered, ...rest];
}

class PluginPermissionAuthorizationDialog extends StatefulWidget {
  const PluginPermissionAuthorizationDialog({
    super.key,
    required this.plugin,
    required this.sensitivePermissions,
    required this.autoGrantedPermissions,
  });

  final InstalledPlugin plugin;
  final List<String> sensitivePermissions;
  final List<String> autoGrantedPermissions;

  @override
  State<PluginPermissionAuthorizationDialog> createState() =>
      _PluginPermissionAuthorizationDialogState();
}

class _PluginPermissionAuthorizationDialogState
    extends State<PluginPermissionAuthorizationDialog> {
  late Set<String> _selected;

  bool get _allSelected =>
      widget.sensitivePermissions.isNotEmpty &&
      _selected.length == widget.sensitivePermissions.length;

  @override
  void initState() {
    super.initState();
    // 演示和首次使用默认全选，用户可以取消后再确认。
    _selected = widget.sensitivePermissions.toSet();
  }

  void _selectAll(bool selected) {
    setState(() {
      _selected = selected ? widget.sensitivePermissions.toSet() : <String>{};
    });
  }

  void _toggle(String permission, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(permission);
      } else {
        _selected.remove(permission);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final autoGrantedLabel = widget.autoGrantedPermissions
        .map(
          (permission) =>
              lynaiPermissionDefinitionById[permission]?.title ?? permission,
        )
        .join('、');
    return AlertDialog(
      title: Text('授权「${widget.plugin.displayName}」权限'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '插件已安装。请选择要授予它的权限，未授权的功能在运行时会受到限制。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _allSelected,
              onChanged: (value) => _selectAll(value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('全选'),
              subtitle: Text(
                '已选 ${_selected.length}/${widget.sensitivePermissions.length} 项',
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.sensitivePermissions.length,
                itemBuilder: (context, index) {
                  final permission = widget.sensitivePermissions[index];
                  final definition = lynaiPermissionDefinitionById[permission];
                  return CheckboxListTile(
                    value: _selected.contains(permission),
                    onChanged: (value) => _toggle(permission, value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(definition?.title ?? permission),
                    subtitle: Text(definition?.description ?? permission),
                    secondary: definition?.risk == LynAIPermissionRisk.elevated
                        ? Icon(
                            Icons.warning_amber_rounded,
                            size: 20,
                            color: theme.colorScheme.tertiary,
                          )
                        : null,
                  );
                },
              ),
            ),
            if (widget.autoGrantedPermissions.isNotEmpty) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '自动授予：$autoGrantedLabel',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('暂不授权'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected),
          child: Text('允许所选（${_selected.length}）'),
        ),
      ],
    );
  }
}
