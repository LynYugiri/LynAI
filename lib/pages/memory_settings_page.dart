import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/role_memory_provider.dart';
import '../providers/settings_provider.dart';
import 'memory_manage_page.dart';

/// 角色记忆设置页。
///
/// 收纳所有与角色记忆相关的配置：开关、字符预算、维护提醒间隔，
/// 以及进入条目管理。
class MemorySettingsPage extends StatelessWidget {
  const MemorySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;

    return Scaffold(
      appBar: AppBar(title: const Text('记忆管理'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text(
                    '角色笔记记忆',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('每个角色记住环境事实、约定和经验'),
                  value: settings.roleMemoryEnabled,
                  onChanged: (value) => context
                      .read<SettingsProvider>()
                      .setRoleMemoryEnabled(value),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text(
                    '用户画像记忆',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('每个角色记住用户偏好、沟通风格'),
                  value: settings.roleUserProfileEnabled,
                  onChanged: (value) => context
                      .read<SettingsProvider>()
                      .setRoleUserProfileEnabled(value),
                ),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                ListTile(
                  title: const Text('角色笔记容量上限'),
                  subtitle: Text(
                    '${settings.roleMemoryCharLimit} 字符（约 ${(settings.roleMemoryCharLimit / 2.75).round()} token）',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editNumber(
                    context,
                    title: '角色笔记容量上限',
                    value: settings.roleMemoryCharLimit,
                    allowZero: false,
                    onSave: (value) {
                      context.read<SettingsProvider>().setRoleMemoryLimits(
                        memoryCharLimit: value,
                      );
                      context.read<RoleMemoryProvider>().updateLimits(
                        memory: value,
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('用户画像容量上限'),
                  subtitle: Text(
                    '${settings.roleUserCharLimit} 字符（约 ${(settings.roleUserCharLimit / 2.75).round()} token）',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editNumber(
                    context,
                    title: '用户画像容量上限',
                    value: settings.roleUserCharLimit,
                    allowZero: false,
                    onSave: (value) {
                      context.read<SettingsProvider>().setRoleMemoryLimits(
                        userCharLimit: value,
                      );
                      context.read<RoleMemoryProvider>().updateLimits(
                        user: value,
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('记忆维护提醒间隔'),
                  subtitle: Text(
                    settings.roleMemoryNudgeInterval <= 0
                        ? '已关闭'
                        : '每 ${settings.roleMemoryNudgeInterval} 轮用户输入提醒一次',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editNumber(
                    context,
                    title: '记忆维护提醒间隔',
                    value: settings.roleMemoryNudgeInterval,
                    hint: '0 表示关闭；默认 10',
                    onSave: (value) {
                      context
                          .read<SettingsProvider>()
                          .setRoleMemoryNudgeInterval(value);
                    },
                  ),
                ),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.notes),
              title: const Text(
                '管理记忆条目',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('查看、添加、替换或删除每个角色的记忆'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MemoryManagePage()),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
            child: Text(
              '记忆按角色隔离，并在每次请求时注入系统提示词。'
              '预算满时，模型会被引导在同一批操作中合并或删除旧条目后再写入。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editNumber(
    BuildContext context, {
    required String title,
    required int value,
    String? hint,
    bool allowZero = true,
    required ValueChanged<int> onSave,
  }) async {
    final controller = TextEditingController(text: '$value');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: hint),
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
    if (result != true) {
      controller.dispose();
      return;
    }
    final parsed = int.tryParse(controller.text.trim());
    final invalid = parsed == null || parsed < 0 || (parsed == 0 && !allowZero);
    if (invalid) {
      controller.dispose();
      if (context.mounted) {
        final message = allowZero ? '请输入不小于 0 的整数' : '请输入大于 0 的整数';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }
    controller.dispose();
    onSave(parsed);
  }
}
