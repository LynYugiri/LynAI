import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/jotting.dart';
import '../../providers/jotting_provider.dart';
import '../../widgets/latex_renderer.dart';

/// 随记详情/编辑页。
///
/// 阅读态用 [MarkdownWithLatex] 渲染 Markdown 正文；编辑态提供多行输入、
/// 标签编辑与预览切换。新建时 [jottingId] 为 null，保存成功后通过
/// [onSaved] 返回新 id。
class JottingDetail extends StatefulWidget {
  final String? jottingId;
  final bool editing;
  final ValueChanged<bool> onEditingChanged;
  final ValueChanged<String> onSaved;
  final VoidCallback onDeleted;

  const JottingDetail({
    super.key,
    required this.jottingId,
    required this.editing,
    required this.onEditingChanged,
    required this.onSaved,
    required this.onDeleted,
  });

  @override
  State<JottingDetail> createState() => JottingDetailState();
}

/// [JottingDetail] 的状态，供功能页持有 GlobalKey 后调用未保存确认。
class JottingDetailState extends State<JottingDetail> {
  final _contentCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  late bool _editing;
  String _lastSavedContent = '';
  String _lastSavedTags = '';
  bool _preview = false;

  @override
  void initState() {
    super.initState();
    _editing = widget.editing;
    final jotting = widget.jottingId == null
        ? null
        : context.read<JottingProvider>().byId(widget.jottingId!);
    _lastSavedContent = jotting?.content ?? '';
    _lastSavedTags = (jotting?.tags ?? const []).join(', ');
    _contentCtrl.text = _lastSavedContent;
    _tagsCtrl.text = _lastSavedTags;
    _preview = !_editing;
  }

  @override
  void didUpdateWidget(covariant JottingDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jottingId != widget.jottingId) {
      final jotting = widget.jottingId == null
          ? null
          : context.read<JottingProvider>().byId(widget.jottingId!);
      _lastSavedContent = jotting?.content ?? '';
      _lastSavedTags = (jotting?.tags ?? const []).join(', ');
      _contentCtrl.text = _lastSavedContent;
      _tagsCtrl.text = _lastSavedTags;
    }
    if (oldWidget.editing != widget.editing) {
      _editing = widget.editing;
      _preview = !_editing;
    }
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _contentCtrl.text != _lastSavedContent || _tagsCtrl.text != _lastSavedTags;

  Future<bool> confirmDiscardUnsavedChanges() async {
    if (!_dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃未保存更改？'),
        content: const Text('当前随记有未保存的修改，离开后将丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃更改'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<JottingProvider>();
    final jotting = widget.jottingId == null
        ? null
        : provider.byId(widget.jottingId!);

    if (_editing) {
      return _buildEditor(context, jotting);
    }

    if (jotting == null) {
      return const Center(child: Text('随记不存在或已删除'));
    }

    return _buildReader(context, jotting);
  }

  Widget _buildEditor(BuildContext context, Jotting? jotting) {
    return Column(
      children: [
        Expanded(
          child: _preview
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _contentCtrl.text.trim().isEmpty
                      ? const Text('暂无内容')
                      : MarkdownWithLatex(content: _contentCtrl.text),
                )
              : TextField(
                  controller: _contentCtrl,
                  autofocus: widget.jottingId == null,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: '记下此刻的想法…（支持 Markdown）',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _tagsCtrl,
            decoration: const InputDecoration(
              labelText: '标签（逗号分隔，可选）',
              hintText: '例如：灵感, 生活, 读书',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              IconButton(
                tooltip: _preview ? '编辑' : '预览',
                icon: Icon(_preview ? Icons.edit : Icons.visibility_outlined),
                onPressed: () => setState(() => _preview = !_preview),
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  if (!await confirmDiscardUnsavedChanges()) return;
                  if (!mounted) return;
                  widget.onEditingChanged(false);
                  setState(() => _editing = false);
                  _preview = true;
                },
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _save,
                child: const Text('保存'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReader(BuildContext context, Jotting jotting) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in jotting.tags)
                Chip(
                  label: Text('#$tag'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '创建于 ${_formatTime(jotting.createdAt)} · 更新于 ${_formatTime(jotting.updatedAt)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const Divider(height: 24),
          MarkdownWithLatex(content: jotting.content),
          const SizedBox(height: 24),
          Center(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.edit_outlined),
              label: const Text('编辑'),
              onPressed: () {
                widget.onEditingChanged(true);
                setState(() {
                  _editing = true;
                  _preview = false;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('随记内容不能为空')),
      );
      return;
    }
    final provider = context.read<JottingProvider>();
    final tags = _tagsCtrl.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty);
    if (widget.jottingId == null) {
      final id = await provider.add(content, tags: tags.toList());
      if (!mounted) return;
      widget.onSaved(id);
      widget.onEditingChanged(false);
      setState(() {
        _editing = false;
        _preview = true;
      });
      _lastSavedContent = content;
      _lastSavedTags = _tagsCtrl.text;
    } else {
      await provider.update(widget.jottingId!, content: content, tags: tags.toList());
      if (!mounted) return;
      widget.onEditingChanged(false);
      setState(() {
        _editing = false;
        _preview = true;
      });
      _lastSavedContent = content;
      _lastSavedTags = _tagsCtrl.text;
    }
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }
}
