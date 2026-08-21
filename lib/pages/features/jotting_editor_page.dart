import 'dart:io';

import 'package:file_picker/file_picker.dart' show FileType;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/jotting.dart';
import '../../providers/feature_provider.dart';
import '../../providers/jotting_provider.dart';
import '../../providers/knowledge_provider.dart';
import '../../providers/task_provider.dart';
import '../../services/storage_v2_service.dart';
import '../../utils/file_picker_io_utils.dart';

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
  List<JottingAttachment> _initialAttachments = const [];
  List<JottingAttachment> _attachments = const [];
  bool _tagsExpanded = false;
  bool _saving = false;

  bool get _isNew => widget.jottingId == null;

  bool get _dirty =>
      _contentController.text != _initialContent ||
      !_sameStringList(_tags, _initialTags) ||
      !_sameReferences(_references, _initialReferences) ||
      !_sameAttachments(_attachments, _initialAttachments);

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
    _initialAttachments = List.unmodifiable(
      item?.attachments ?? const <JottingAttachment>[],
    );
    _attachments = List.of(_initialAttachments);
    _contentController.value = TextEditingValue(
      text: _initialContent,
      selection: TextSelection.collapsed(offset: _initialContent.length),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _contentFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    _contentFocus.dispose();
    _editorScrollController.dispose();
    super.dispose();
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
              Expanded(child: _buildEditor()),
              _buildAttachmentCards(),
              _buildReferenceCards(),
              _buildTagEditor(),
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

  Widget _buildAttachmentCards() {
    if (_attachments.isEmpty) return const SizedBox.shrink();
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
          for (var index = 0; index < _attachments.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _EditorAttachmentCard(
                attachment: _attachments[index],
                onDelete: _saving
                    ? null
                    : () => _removeAttachmentAt(index),
              ),
            ),
        ],
      ),
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
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        child: Row(
          children: [
            Expanded(child: _buildTagArea(scheme)),
            IconButton(
              tooltip: '插入引用',
              icon: const Icon(Icons.link_outlined),
              onPressed: _saving ? null : _pickReference,
            ),
            IconButton(
              tooltip: '添加附件',
              icon: const Icon(Icons.attach_file_outlined),
              onPressed: _saving ? null : _pickAttachment,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagArea(ColorScheme scheme) {
    if (_tags.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: Icon(Icons.sell_outlined, size: 16, color: scheme.primary),
          label: const Text('#标签'),
          tooltip: '添加标签',
          visualDensity: VisualDensity.compact,
          onPressed: _saving ? null : _addTag,
        ),
      );
    }

    final visibleTags = _tagsExpanded ? _tags : _tags.take(3).toList();
    final hiddenCount = _tags.length - visibleTags.length;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tag in visibleTags)
          ActionChip(
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                '#$tag',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            visualDensity: VisualDensity.compact,
            onPressed: _saving ? null : () => _editTag(tag),
          ),
        if (hiddenCount > 0)
          ActionChip(
            label: Text('+$hiddenCount'),
            tooltip: _tagsExpanded ? '折叠标签' : '展开全部标签',
            visualDensity: VisualDensity.compact,
            onPressed: _saving
                ? null
                : () => setState(() => _tagsExpanded = !_tagsExpanded),
          ),
        ActionChip(
          label: const Text('+'),
          tooltip: '添加标签',
          visualDensity: VisualDensity.compact,
          onPressed: _saving ? null : _addTag,
        ),
      ],
    );
  }

  void _removeAttachmentAt(int index) {
    setState(() => _attachments = List.of(_attachments)..removeAt(index));
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
    _contentFocus.requestFocus();
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
    _contentFocus.requestFocus();
  }

  String? _normalizeTag(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty || value.length > Jotting.maxTagLength) return null;
    return value;
  }

  Future<void> _pickReference() async {
    final reference = await showModalBottomSheet<JottingReference>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _JottingReferencePicker(),
    );
    if (!mounted || reference == null) return;
    setState(() {
      _references = List.of(_references)..add(reference);
    });
    _contentFocus.requestFocus();
  }

  Future<void> _pickAttachment() async {
    final files = await pickMultipleFilePayloads(
      dialogTitle: '选择附件',
      type: FileType.any,
    );
    if (files.isEmpty || !mounted) return;
    setState(() => _saving = true);
    try {
      final storage = context.read<StorageV2Service>();
      for (final file in files) {
        final tempDir = await Directory.systemTemp.createTemp('lynai_jotting_');
        final tempFile = File('${tempDir.path}/${file.name}');
        try {
          await file.copyTo(tempFile);
          final mimeType = _mimeTypeForName(file.name);
          final resource = await storage.importResourceFile(
            tempFile.path,
            originalName: file.name,
            mimeType: mimeType,
            role: 'jotting',
          );
          setState(() {
            _attachments = List.of(_attachments)
              ..add(
                JottingAttachment(
                  resourceId: resource.id,
                  originalName: resource.originalName,
                  mimeType: resource.mimeType,
                ),
              );
          });
        } finally {
          await tempDir.delete(recursive: true);
        }
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('添加附件失败：$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _mimeTypeForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
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
            attachments: _attachments,
          );
      if (id != null) {
        await provider.update(
          id,
          content: content,
          tags: _tags,
          references: _references,
          attachments: _attachments,
        );
      }
      if (!mounted) return;
      _initialContent = content;
      _initialTags = List.unmodifiable(_tags);
      _initialReferences = List.unmodifiable(_references);
      _initialAttachments = List.unmodifiable(_attachments);
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

  bool _sameAttachments(
    List<JottingAttachment> left,
    List<JottingAttachment> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (a.resourceId != b.resourceId ||
          a.originalName != b.originalName ||
          a.mimeType != b.mimeType) {
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

class _EditorAttachmentCard extends StatefulWidget {
  const _EditorAttachmentCard({
    required this.attachment,
    required this.onDelete,
  });

  final JottingAttachment attachment;
  final VoidCallback? onDelete;

  @override
  State<_EditorAttachmentCard> createState() => _EditorAttachmentCardState();
}

class _EditorAttachmentCardState extends State<_EditorAttachmentCard> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _resolvePath();
  }

  Future<void> _resolvePath() async {
    try {
      final storage = context.read<StorageV2Service>();
      final resource = await storage.findResourceById(widget.attachment.resourceId);
      final path = resource == null ? null : await storage.resourcePath(resource);
      if (!mounted) return;
      setState(() => _path = path);
    } catch (_) {
      if (!mounted) return;
      setState(() => _path = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        child: Row(
          children: [
            if (widget.attachment.isImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _path == null
                    ? const SizedBox.square(
                        dimension: 44,
                        child: Icon(Icons.image_outlined),
                      )
                    : Image.file(
                        File(_path!),
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const SizedBox.square(
                              dimension: 44,
                              child: Icon(Icons.broken_image_outlined),
                            ),
                      ),
              )
            else
              const Icon(Icons.insert_drive_file_outlined, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.attachment.originalName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (widget.onDelete != null)
              IconButton(
                tooltip: '删除附件',
                icon: const Icon(Icons.close, size: 18),
                onPressed: widget.onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

class _JottingReferencePicker extends StatefulWidget {
  const _JottingReferencePicker();

  @override
  State<_JottingReferencePicker> createState() =>
      _JottingReferencePickerState();
}

class _JottingReferencePickerState extends State<_JottingReferencePicker> {
  final _searchController = TextEditingController();
  JottingReferenceType _type = JottingReferenceType.note;
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
                '插入引用',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 6,
                children: [
                  for (final type in JottingReferenceType.values)
                    ChoiceChip(
                      label: Text(_typeLabel(type)),
                      selected: _type == type,
                      onSelected: (_) => setState(() => _type = type),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
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
                              type: _type,
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

  String _typeLabel(JottingReferenceType type) => switch (type) {
    JottingReferenceType.note => '笔记',
    JottingReferenceType.task => '任务',
    JottingReferenceType.knowledgeEntry => '知识库',
  };

  IconData get _icon => switch (_type) {
    JottingReferenceType.note => Icons.sticky_note_2_outlined,
    JottingReferenceType.task => Icons.checklist,
    JottingReferenceType.knowledgeEntry => Icons.local_library_outlined,
  };

  List<({String id, String title, String snippet})> _items(
    BuildContext context,
  ) {
    final query = _query.trim().toLowerCase();
    switch (_type) {
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
