import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/jotting.dart';
import '../../providers/feature_provider.dart';
import '../../providers/jotting_provider.dart';
import '../../providers/knowledge_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/latex_renderer.dart';

/// Result returned by [JottingEditorPage] after a durable local save.
class JottingEditorResult {
  const JottingEditorResult({required this.jottingId, required this.created});

  final String jottingId;
  final bool created;
}

/// Full-screen mobile-first editor for creating or updating a local jotting.
///
/// The page owns its dirty/save/back state so the feature timeline can stay
/// mounted underneath the route and retain its scroll/filter context.
class JottingEditorPage extends StatefulWidget {
  const JottingEditorPage({super.key, this.jottingId});

  final String? jottingId;

  @override
  State<JottingEditorPage> createState() => JottingEditorPageState();
}

class JottingEditorPageState extends State<JottingEditorPage> {
  final _contentController = TextEditingController();
  final _contentFocus = FocusNode();
  final _editorScrollController = ScrollController();

  String _initialContent = '';
  List<String> _initialTags = const [];
  List<String> _tags = const [];
  List<JottingReference> _initialReferences = const [];
  List<JottingReference> _references = const [];
  TextSelection _lastSelection = const TextSelection.collapsed(offset: 0);
  bool _preview = false;
  bool _saving = false;

  bool get _isNew => widget.jottingId == null;

  bool get _dirty =>
      _contentController.text != _initialContent ||
      !_sameStringList(_tags, _initialTags) ||
      !_sameReferences(_references, _initialReferences);

  @override
  void initState() {
    super.initState();
    final item = widget.jottingId == null
        ? null
        : context.read<JottingProvider>().byId(widget.jottingId!);
    _initialContent = item?.content ?? '';
    _initialTags = List.unmodifiable(item?.tags ?? const <String>[]);
    _tags = List.of(_initialTags);
    _initialReferences = List.unmodifiable(
      item?.references ?? const <JottingReference>[],
    );
    _references = List.of(_initialReferences);
    _contentController.value = TextEditingValue(
      text: _initialContent,
      selection: TextSelection.collapsed(offset: _initialContent.length),
    );
    _lastSelection = _contentController.selection;
    _contentController.addListener(_trackSelection);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _contentFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _contentController.removeListener(_trackSelection);
    _contentController.dispose();
    _contentFocus.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  void _trackSelection() {
    if (_contentController.selection.isValid) {
      _lastSelection = _contentController.selection;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.jottingId == null
        ? null
        : context.watch<JottingProvider>().byId(widget.jottingId!);
    if (!_isNew && item == null) {
      return const Scaffold(body: Center(child: Text('随记不存在或已删除')));
    }

    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          leading: IconButton(
            tooltip: _isNew ? '取消新建' : '取消编辑',
            icon: Icon(_isNew ? Icons.close : Icons.arrow_back),
            onPressed: _saving ? null : _requestClose,
          ),
          title: Text(_isNew ? '新随记' : '编辑随记'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('完成'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(child: _preview ? _buildPreview() : _buildEditor()),
              _buildReferenceCards(),
              _buildTagEditor(),
              _buildBottomToolbar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return TextField(
      key: const ValueKey('jotting-editor-content'),
      controller: _contentController,
      focusNode: _contentFocus,
      scrollController: _editorScrollController,
      expands: true,
      maxLines: null,
      minLines: null,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55),
      decoration: const InputDecoration(
        hintText: '记下此刻的想法…',
        border: InputBorder.none,
        contentPadding: EdgeInsets.fromLTRB(18, 16, 18, 28),
      ),
    );
  }

  Widget _buildPreview() {
    final content = _contentController.text;
    return SingleChildScrollView(
      key: const ValueKey('jotting-editor-preview'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
      child: content.trim().isEmpty
          ? Text(
              '暂无内容',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            )
          : MarkdownWithLatex(content: content),
    );
  }

  Widget _buildReferenceCards() {
    if (_references.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (var index = 0; index < _references.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _ReferenceCard(
                reference: _references[index],
                onDelete: _saving
                    ? null
                    : () => _removeReferenceAt(index),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTagEditor() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final tag in _tags)
            ActionChip(
              label: Text('#$tag'),
              visualDensity: VisualDensity.compact,
              onPressed: _saving ? null : () => _editTag(tag),
            ),
          ActionChip(
            label: const Text('+'),
            tooltip: '添加标签',
            visualDensity: VisualDensity.compact,
            onPressed: _saving ? null : () => _addTag(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomToolbar() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
      child: SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          children: [
            _toolButton(Icons.sticky_note_2_outlined, '插入笔记', _pickNoteReference),
            _toolButton(Icons.checklist, '插入任务', _pickTaskReference),
            _toolButton(Icons.local_library_outlined, '插入知识库', _pickKnowledgeReference),
            _toolButton(
              _preview ? Icons.edit_outlined : Icons.visibility_outlined,
              _preview ? '返回编辑' : '预览',
              _togglePreview,
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolButton(IconData icon, String tooltip, VoidCallback action) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: _saving ? null : action,
    );
  }

  Future<void> _togglePreview() async {
    if (_preview) {
      setState(() => _preview = false);
      await Future<void>.delayed(Duration.zero);
      if (mounted) _contentFocus.requestFocus();
      return;
    }
    _lastSelection = _normalizedSelection;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _preview = true);
  }

  void _removeReferenceAt(int index) {
    setState(() => _references = List.of(_references)..removeAt(index));
  }

  Future<void> _editTag(String oldTag) async {
    final controller = TextEditingController(text: oldTag);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '标签'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    final normalized = _normalizeTag(result);
    if (normalized == null || normalized == oldTag) return;
    setState(() {
      final next = _tags.where((tag) => tag != oldTag).toList();
      if (!next.contains(normalized)) next.add(normalized);
      _tags = next;
    });
    if (!_preview) _contentFocus.requestFocus();
  }

  Future<void> _addTag() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '标签'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    final normalized = _normalizeTag(result);
    if (normalized == null) return;
    setState(() {
      if (_tags.contains(normalized) || _tags.length >= Jotting.maxTagCount) {
        return;
      }
      _tags = List.of(_tags)..add(normalized);
    });
    if (!_preview) _contentFocus.requestFocus();
  }

  String? _normalizeTag(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty || value.length > Jotting.maxTagLength) return null;
    return value;
  }

  Future<void> _pickNoteReference() => _pickReference(
    icon: Icons.sticky_note_2_outlined,
    label: '笔记',
    picker: const _JottingReferencePicker(type: JottingReferenceType.note),
  );

  Future<void> _pickTaskReference() => _pickReference(
    icon: Icons.checklist,
    label: '任务',
    picker: const _JottingReferencePicker(type: JottingReferenceType.task),
  );

  Future<void> _pickKnowledgeReference() => _pickReference(
    icon: Icons.local_library_outlined,
    label: '知识库',
    picker: const _JottingReferencePicker(
      type: JottingReferenceType.knowledgeEntry,
    ),
  );

  Future<void> _pickReference({
    required IconData icon,
    required String label,
    required Widget picker,
  }) async {
    final reference = await showModalBottomSheet<JottingReference>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => picker,
    );
    if (!mounted || reference == null) return;
    setState(() {
      _references = List.of(_references)..add(reference);
    });
    if (!_preview) _contentFocus.requestFocus();
  }

  Future<void> _requestClose() async {
    if (_saving) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存更改？'),
        content: const Text('当前随记有未保存的修改，离开后将丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃更改'),
          ),
        ],
      ),
    );
    if (!mounted || discard != true) return;
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (_saving) return;
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('随记内容不能为空')));
      return;
    }
    setState(() => _saving = true);
    try {
      final provider = context.read<JottingProvider>();
      final id = widget.jottingId;
      final savedId = id ??
          await provider.add(
            content,
            tags: _tags,
            references: _references,
          );
      if (id != null) {
        await provider.update(
          id,
          content: content,
          tags: _tags,
          references: _references,
        );
      }
      if (!mounted) return;
      _initialContent = content;
      _initialTags = List.unmodifiable(_tags);
      _initialReferences = List.unmodifiable(_references);
      Navigator.of(
        context,
      ).pop(JottingEditorResult(jottingId: savedId, created: id == null));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败，已保留编辑内容：$error')));
      setState(() => _saving = false);
    }
  }

  TextSelection get _normalizedSelection {
    final selection = _contentController.selection.isValid
        ? _contentController.selection
        : _lastSelection;
    if (!selection.isValid) {
      return TextSelection.collapsed(offset: _contentController.text.length);
    }
    return TextSelection(
      baseOffset: _clampOffset(selection.baseOffset),
      extentOffset: _clampOffset(selection.extentOffset),
    );
  }

  int _clampOffset(int value) => value.clamp(0, _contentController.text.length);

  bool _sameStringList(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  bool _sameReferences(
    List<JottingReference> left,
    List<JottingReference> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (a.type != b.type ||
          a.id != b.id ||
          a.title != b.title ||
          a.snippet != b.snippet) {
        return false;
      }
    }
    return true;
  }
}


class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({
    required this.reference,
    required this.onDelete,
  });

  final JottingReference reference;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (reference.type) {
      JottingReferenceType.note => (Icons.sticky_note_2_outlined, Colors.blue),
      JottingReferenceType.task => (Icons.checklist, Colors.green),
      JottingReferenceType.knowledgeEntry => (
        Icons.local_library_outlined,
        Colors.orange,
      ),
    };
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reference.title.isEmpty ? '未命名引用' : reference.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (reference.snippet.isNotEmpty)
                    Text(
                      reference.snippet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                tooltip: '删除引用卡片',
                icon: const Icon(Icons.close, size: 18),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

class _JottingReferencePicker extends StatefulWidget {
  const _JottingReferencePicker({required this.type});

  final JottingReferenceType type;

  @override
  State<_JottingReferencePicker> createState() =>
      _JottingReferencePickerState();
}

class _JottingReferencePickerState extends State<_JottingReferencePicker> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索标题或正文',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('没有可引用的内容'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          leading: Icon(_icon),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: item.snippet.isEmpty
                              ? null
                              : Text(
                                  item.snippet,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => Navigator.pop(
                            context,
                            JottingReference(
                              type: widget.type,
                              id: item.id,
                              title: item.title,
                              snippet: item.snippet,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String get _title => switch (widget.type) {
    JottingReferenceType.note => '插入笔记引用',
    JottingReferenceType.task => '插入任务引用',
    JottingReferenceType.knowledgeEntry => '插入知识库引用',
  };

  IconData get _icon => switch (widget.type) {
    JottingReferenceType.note => Icons.sticky_note_2_outlined,
    JottingReferenceType.task => Icons.checklist,
    JottingReferenceType.knowledgeEntry => Icons.local_library_outlined,
  };

  List<({String id, String title, String snippet})> _items(
    BuildContext context,
  ) {
    final query = _query.trim().toLowerCase();
    switch (widget.type) {
      case JottingReferenceType.note:
        final notes = context.read<FeatureProvider>().notes;
        return [
          for (final note in notes)
            if (_matches(query, note.title, note.content))
              (
                id: note.id,
                title: note.title.trim().isEmpty ? '未命名笔记' : note.title,
                snippet: _firstLine(note.content),
              ),
        ];
      case JottingReferenceType.task:
        final tasks = context.read<TaskProvider>().tasks;
        return [
          for (final task in tasks)
            if (_matches(query, task.title, task.note ?? ''))
              (
                id: task.id,
                title: task.title,
                snippet: _firstLine(task.note ?? ''),
              ),
        ];
      case JottingReferenceType.knowledgeEntry:
        final entries = context.read<KnowledgeProvider>().entries;
        return [
          for (final entry in entries)
            if (entry.enabled && _matches(query, entry.title, entry.content))
              (
                id: entry.id,
                title: entry.title,
                snippet: _firstLine(entry.content),
              ),
        ];
    }
  }

  bool _matches(String query, String title, String content) {
    if (query.isEmpty) return true;
    return title.toLowerCase().contains(query) ||
        content.toLowerCase().contains(query);
  }

  String _firstLine(String content) {
    return content
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  }
}
