import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/floating_translation_controller.dart';

class TranslationHistoryPage extends StatelessWidget {
  const TranslationHistoryPage({super.key, required this.controller});

  final FloatingTranslationController controller;

  String _formatTime(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('翻译历史'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '清空历史',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('清空翻译历史？'),
                  content: const Text('此操作不可撤销。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('清空'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await controller.clearTranslationHistory();
              }
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final history = controller.translationHistory;
          if (history.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '还没有翻译记录。\n在悬浮窗中点击"翻译"后会出现在这里。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: history.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = history[index];
              final timestamp = item['timestamp'];
              final time = timestamp is int ? _formatTime(timestamp) : '';
              final original = item['originalText']?.toString() ?? '';
              final translated = item['translatedText']?.toString() ?? '';
              final packageName = item['packageName']?.toString() ?? '';
              return ListTile(
                title: Text(
                  translated,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (time.isNotEmpty)
                      Text(time, style: const TextStyle(fontSize: 12)),
                    Text(
                      '原文: $original',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    if (packageName.isNotEmpty)
                      Text(
                        '应用: $packageName',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
                onLongPress: () {
                  final full = '原文:\n$original\n\n译文:\n$translated';
                  Clipboard.setData(ClipboardData(text: full));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
                },
              );
            },
          );
        },
      ),
    );
  }
}
