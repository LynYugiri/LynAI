part of '../chat_page.dart';

class _SystemPromptEditDialog extends StatefulWidget {
  final String initialTitle;
  final String initialContent;
  final void Function(String title, String content) onSave;
  final VoidCallback? onDelete;

  const _SystemPromptEditDialog({
    this.initialTitle = '',
    this.initialContent = '',
    required this.onSave,
    this.onDelete,
  });

  @override
  State<_SystemPromptEditDialog> createState() =>
      _SystemPromptEditDialogState();
}

class _SystemPromptEditDialogState extends State<_SystemPromptEditDialog> {
  late final _titleCtrl = TextEditingController(text: widget.initialTitle);
  late final _contentCtrl = TextEditingController(text: widget.initialContent);

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.onDelete != null ? '编辑系统提示词' : '添加系统提示词'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: '标题',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contentCtrl,
            maxLines: 8,
            minLines: 3,
            decoration: const InputDecoration(
              labelText: '系统提示词',
              border: OutlineInputBorder(),
              hintText: 'You are a helpful assistant.',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            final title = _titleCtrl.text.trim();
            final content = _contentCtrl.text.trim();
            if (title.isEmpty || content.isEmpty) return;
            Navigator.pop(context);
            widget.onSave(title, content);
          },
          child: const Text('保存'),
        ),
        if (widget.onDelete != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDelete!();
            },
            child: Text('删除', style: TextStyle(color: Colors.red[400])),
          ),
      ],
    );
  }
}
