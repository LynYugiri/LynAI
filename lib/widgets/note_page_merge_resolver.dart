import 'package:flutter/material.dart';

import '../models/merge_models.dart';

class NotePageMergeResolver extends StatefulWidget {
  final NotePageMergeSession session;
  final Future<NotePageMergeCommitResult> Function(String content) onCommit;

  const NotePageMergeResolver({
    super.key,
    required this.session,
    required this.onCommit,
  });

  @override
  State<NotePageMergeResolver> createState() => _NotePageMergeResolverState();
}

class _NotePageMergeResolverState extends State<NotePageMergeResolver> {
  late final TextEditingController _resultController;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _resultController = TextEditingController(
      text: widget.session.initialResult,
    );
  }

  @override
  void dispose() {
    _resultController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('解决分页冲突'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _commit,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.call_merge),
            label: const Text('提交合并'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final sources = wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _source('共同基线', widget.session.baseContent),
                    ),
                    Expanded(
                      child: _source('本地版本', widget.session.localContent),
                    ),
                    Expanded(
                      child: _source('传入版本', widget.session.incomingContent),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _mobileSource('共同基线', widget.session.baseContent),
                    _mobileSource('本地版本', widget.session.localContent),
                    _mobileSource('传入版本', widget.session.incomingContent),
                  ],
                );
          return Column(
            children: [
              Expanded(flex: wide ? 5 : 4, child: sources),
              const Divider(height: 1),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                      child: Text(
                        '合并结果',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        key: const Key('note-merge-result'),
                        controller: _resultController,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _source(String title, String content) {
    return Card.outlined(
      margin: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                content.isEmpty ? '（空）' : content,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileSource(String title, String content) {
    return Card.outlined(
      child: ExpansionTile(
        title: Text(title),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SelectableText(
                content.isEmpty ? '（空）' : content,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _commit() async {
    setState(() => _saving = true);
    final result = await widget.onCommit(_resultController.text);
    if (!mounted) return;
    if (result.status == NotePageMergeCommitStatus.staleHeads) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('分页头已变化，请关闭后重新加载冲突')));
      return;
    }
    Navigator.pop(context, true);
  }
}
