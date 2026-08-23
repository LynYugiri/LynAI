import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_role.dart';
import '../providers/role_memory_provider.dart';
import '../providers/settings_provider.dart';

/// 角色记忆条目管理页。
class MemoryManagePage extends StatefulWidget {
  const MemoryManagePage({super.key});

  @override
  State<MemoryManagePage> createState() => _MemoryManagePageState();
}

class _MemoryManagePageState extends State<MemoryManagePage> {
  String _target = RoleMemoryProvider.targetMemory;
  String? _roleId;

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final memoryProvider = context.watch<RoleMemoryProvider>();
    final roles = settingsProvider.settings.roles;
    final currentRoleId =
        roles.any((r) => r.id == settingsProvider.settings.currentRoleId)
        ? settingsProvider.settings.currentRoleId
        : ChatRole.defaultId;
    final selectedRoleId = _roleId ?? currentRoleId;

    return Scaffold(
      appBar: AppBar(title: const Text('角色记忆'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedRoleId,
              decoration: const InputDecoration(
                labelText: '角色',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
              items: [
                for (final role in roles)
                  DropdownMenuItem(value: role.id, child: Text(role.name)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _roleId = value);
              },
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: RoleMemoryProvider.targetMemory,
                  label: Text('角色笔记'),
                  icon: Icon(Icons.psychology_outlined),
                ),
                ButtonSegment(
                  value: RoleMemoryProvider.targetUser,
                  label: Text('用户画像'),
                  icon: Icon(Icons.badge_outlined),
                ),
              ],
              selected: {_target},
              onSelectionChanged: (selection) {
                setState(() => _target = selection.first);
              },
            ),
            const SizedBox(height: 12),
            Text(
              '用量：${memoryProvider.usageText(selectedRoleId, _target)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(child: _entriesList(memoryProvider, selectedRoleId)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(memoryProvider, selectedRoleId),
        icon: const Icon(Icons.add),
        label: const Text('添加记忆'),
      ),
    );
  }

  Widget _entriesList(RoleMemoryProvider memoryProvider, String roleId) {
    final entries = memoryProvider.entryTextsFor(roleId, _target);
    if (entries.isEmpty) {
      return const Center(child: Text('暂无记忆条目'));
    }
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ListTile(
          leading: const Icon(Icons.notes),
          title: Text(entry),
          subtitle: Text('${entry.length} 字符'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '替换',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () =>
                    _showReplaceDialog(memoryProvider, roleId, index, entry),
              ),
              IconButton(
                tooltip: '删除',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  final response = memoryProvider.removeAt(
                    roleId,
                    _target,
                    index,
                  );
                  _showResultSnackBar(response);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddDialog(
    RoleMemoryProvider memoryProvider,
    String roleId,
  ) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _target == RoleMemoryProvider.targetMemory ? '添加角色笔记' : '添加用户画像',
        ),
        content: TextField(
          controller: controller,
          maxLines: 5,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入一条高信号、可复用的记忆',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == true && controller.text.trim().isNotEmpty) {
      final response = memoryProvider.add(roleId, _target, controller.text);
      if (mounted) _showResultSnackBar(response);
    }
    controller.dispose();
  }

  Future<void> _showReplaceDialog(
    RoleMemoryProvider memoryProvider,
    String roleId,
    int index,
    String oldEntry,
  ) async {
    final controller = TextEditingController(text: oldEntry);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('替换记忆条目'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('替换'),
          ),
        ],
      ),
    );
    if (result == true && controller.text.trim().isNotEmpty) {
      final response = memoryProvider.replaceAt(
        roleId,
        _target,
        index,
        controller.text,
      );
      if (mounted) _showResultSnackBar(response);
    }
    controller.dispose();
  }

  void _showResultSnackBar(Map<String, dynamic> response) {
    final success = response['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (response['message'] as String? ?? '已保存')
              : (response['error'] as String? ?? '操作失败'),
        ),
        backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }
}
