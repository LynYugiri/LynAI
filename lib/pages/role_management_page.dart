import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_role.dart';
import '../models/app_settings.dart';
import '../providers/settings_provider.dart';
import '../widgets/chat_role_edit_dialog.dart';

class RoleManagementPage extends StatefulWidget {
  const RoleManagementPage({super.key});

  @override
  State<RoleManagementPage> createState() => _RoleManagementPageState();
}

class _RoleManagementPageState extends State<RoleManagementPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    return Scaffold(
      appBar: AppBar(title: const Text('角色管理'), centerTitle: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRole,
        icon: const Icon(Icons.add),
        label: const Text('添加角色'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _summary(settings),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索角色名称、描述或提示词',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
          const SizedBox(height: 12),
          _groupToolbar(),
          const SizedBox(height: 8),
          _roleGroups(settings),
        ],
      ),
    );
  }

  Widget _summary(AppSettings settings) {
    final current = context.watch<SettingsProvider>().currentRole;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor:
                  (current.themeColor ?? Theme.of(context).colorScheme.primary)
                      .withValues(alpha: 0.14),
              child: Icon(
                Icons.person_pin_circle_outlined,
                color:
                    current.themeColor ?? Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前角色：${current.name}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${settings.roles.length} 个角色 · ${settings.roleGroups.length} 个分组',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupToolbar() {
    return Row(
      children: [
        Text('分组', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        TextButton.icon(
          onPressed: _addGroup,
          icon: const Icon(Icons.create_new_folder_outlined, size: 18),
          label: const Text('新建分组'),
        ),
      ],
    );
  }

  Widget _roleGroups(AppSettings settings) {
    final roles = _filteredRoles(settings.roles);
    final roleById = {for (final role in roles) role.id: role};
    final groupedIds = settings.roleGroups
        .expand((group) => group.roleIds)
        .toSet();
    final ungrouped = roles
        .where((role) => !groupedIds.contains(role.id))
        .toList(growable: false);
    return Column(
      children: [
        _groupCard(title: '未分组', roles: ungrouped),
        for (final group in settings.roleGroups)
          _groupCard(
            title: group.name,
            groupId: group.id,
            roles: group.roleIds
                .map((id) => roleById[id])
                .whereType<ChatRole>()
                .toList(growable: false),
          ),
      ],
    );
  }

  Widget _groupCard({
    required String title,
    required List<ChatRole> roles,
    String? groupId,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: ExpansionTile(
        initiallyExpanded: _query.isNotEmpty || groupId == null,
        title: Text('$title · ${roles.length}'),
        trailing: groupId == null
            ? null
            : PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'rename') _renameGroup(groupId, title);
                  if (value == 'delete') _deleteGroup(groupId);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('重命名')),
                  PopupMenuItem(value: 'delete', child: Text('删除分组')),
                ],
              ),
        children: roles.isEmpty
            ? [
                ListTile(
                  title: Text(
                    _query.isEmpty ? '暂无角色' : '没有匹配角色',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ]
            : roles.map(_roleTile).toList(),
      ),
    );
  }

  Widget _roleTile(ChatRole role) {
    final sp = context.watch<SettingsProvider>();
    final selected = role.id == sp.settings.currentRoleId;
    final groups = sp
        .groupsForRole(role.id)
        .map((group) => group.name)
        .join('、');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            (role.themeColor ??
                    Theme.of(context).colorScheme.surfaceContainerHighest)
                .withValues(alpha: role.themeColor == null ? 1 : 0.2),
        child: Icon(
          selected ? Icons.check : Icons.person_outline,
          color:
              role.themeColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(role.name),
      subtitle: Text(
        [
          if (role.description.isNotEmpty)
            role.description
          else
            role.systemPrompt,
          if (groups.isNotEmpty) '分组：$groups',
        ].join('\n'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: groups.isNotEmpty,
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'select') {
            context.read<SettingsProvider>().selectRole(role.id);
          }
          if (value == 'edit') _editRole(role);
          if (value == 'delete') _deleteRole(role);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'select', child: Text('设为当前')),
          const PopupMenuItem(value: 'edit', child: Text('编辑')),
          if (role.id != ChatRole.defaultId)
            const PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
      onTap: () => context.read<SettingsProvider>().selectRole(role.id),
    );
  }

  List<ChatRole> _filteredRoles(List<ChatRole> roles) {
    final query = _query.toLowerCase();
    if (query.isEmpty) return roles;
    return roles
        .where((role) {
          return role.name.toLowerCase().contains(query) ||
              role.description.toLowerCase().contains(query) ||
              role.systemPrompt.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  void _addRole() {
    showDialog(
      context: context,
      builder: (_) => ChatRoleEditDialog(
        onSave:
            (
              name,
              description,
              prompt,
              modelId,
              modelName,
              themeColor,
              groupIds,
            ) {
              context.read<SettingsProvider>().addRole(
                name: name,
                description: description,
                systemPrompt: prompt,
                modelId: modelId,
                modelName: modelName,
                themeColor: themeColor,
                groupIds: groupIds,
              );
            },
      ),
    );
  }

  void _editRole(ChatRole role) {
    final sp = context.read<SettingsProvider>();
    showDialog(
      context: context,
      builder: (_) => ChatRoleEditDialog(
        initialRole: role,
        onSave:
            (
              name,
              description,
              prompt,
              modelId,
              modelName,
              themeColor,
              groupIds,
            ) {
              sp.updateRole(
                id: role.id,
                name: name,
                description: description,
                systemPrompt: prompt,
                modelId: modelId,
                modelName: modelName,
                themeColor: themeColor,
                groupIds: groupIds,
              );
            },
        onDelete: role.id == ChatRole.defaultId
            ? null
            : () => sp.deleteRole(role.id),
      ),
    );
  }

  Future<void> _deleteRole(ChatRole role) async {
    final confirmed = await _confirm(
      '删除角色',
      '确定删除“${role.name}”吗？相关系统提示词也会一起删除。',
    );
    if (confirmed != true || !mounted) return;
    context.read<SettingsProvider>().deleteRole(role.id);
  }

  Future<void> _addGroup() async {
    final name = await _askName(title: '新建分组', label: '分组名称');
    if (name == null || !mounted) return;
    context.read<SettingsProvider>().addRoleGroup(name);
  }

  Future<void> _renameGroup(String id, String currentName) async {
    final name = await _askName(
      title: '重命名分组',
      label: '分组名称',
      initialValue: currentName,
    );
    if (name == null || !mounted) return;
    context.read<SettingsProvider>().updateRoleGroup(id, name);
  }

  Future<void> _deleteGroup(String id) async {
    final confirmed = await _confirm('删除分组', '删除分组不会删除其中的角色，确定继续吗？');
    if (confirmed != true || !mounted) return;
    context.read<SettingsProvider>().deleteRoleGroup(id);
  }

  Future<String?> _askName({
    required String title,
    required String label,
    String initialValue = '',
  }) async {
    final ctrl = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
