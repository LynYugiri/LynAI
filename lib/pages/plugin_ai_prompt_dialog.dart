import 'package:flutter/material.dart';

import '../models/plugin.dart';

/// 插件工坊“交给 AI”的指令输入对话框。
///
/// 返回用户确认的指令文本；取消返回 null。
Future<String?> showPluginAiPromptDialog(
  BuildContext context, {
  required InstalledPlugin plugin,
}) {
  final controller = TextEditingController(
    text: '请先查看当前插件文件和 manifest，说明你准备怎么改，然后直接修改草稿文件。',
  );
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('交给 AI 修改「${plugin.displayName}」'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '描述你想让 AI 怎么修改这个插件',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (plugin.hasError)
                ActionChip(
                  avatar: const Icon(Icons.build_outlined, size: 16),
                  label: const Text('修复加载错误'),
                  onPressed: () => controller.text =
                      '插件当前加载错误：'
                      '${plugin.loadError}。请读取 plugin.json 和相关文件，修复后写入。',
                ),
              ActionChip(
                avatar: const Icon(Icons.description_outlined, size: 16),
                label: const Text('补充 README'),
                onPressed: () => controller.text = '请为这个插件补充或完善 README.md。',
              ),
              ActionChip(
                avatar: const Icon(Icons.add_outlined, size: 16),
                label: const Text('完善工具参数'),
                onPressed: () => controller.text =
                    '请检查 manifest 中声明的工具，'
                    '完善参数 schema 和对应的 Lua handler 实现。',
              ),
            ],
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
            final prompt = controller.text.trim();
            if (prompt.isEmpty) return;
            Navigator.pop(context, prompt);
          },
          child: const Text('开始修改'),
        ),
      ],
    ),
  );
}
