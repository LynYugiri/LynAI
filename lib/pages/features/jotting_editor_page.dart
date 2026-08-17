import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/jotting.dart';
import '../../providers/jotting_provider.dart';
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
  TextSelection _lastSelection = const TextSelection.collapsed(offset: 0);
  bool _preview = false;
  bool _saving = false;

  bool get _isNew => widget.jottingId == null;

  bool get _dirty =>
      _contentController.text != _initialContent ||
      !_sameStringList(_tags, _initialTags);

  @override
  void initState() {
    super.initState();
    final item = widget.jottingId == null
        ? null
        : context.read<JottingProvider>().byId(widget.jottingId!);
    _initialContent = item?.content ?? '';
    _initialTags = List.unmodifiable(item?.tags ?? const <String>[]);
    _tags = List.of(_initialTags);
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
              _buildSelectedTags(),
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

  Widget _buildSelectedTags() {
    if (_tags.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final tag in _tags)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InputChip(
                  label: Text('#$tag'),
                  visualDensity: VisualDensity.compact,
                  onDeleted: _saving ? null : () => _removeTag(tag),
                ),
              ),
          ],
        ),
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
            _toolButton(
              Icons.format_bold,
              '粗体',
              () => _wrapSelection('**', placeholder: '粗体'),
            ),
            _toolButton(
              Icons.format_italic,
              '斜体',
              () => _wrapSelection('*', placeholder: '斜体'),
            ),
            _toolButton(Icons.title, '标题', () => _prefixLines('## ')),
            _toolButton(
              Icons.format_list_bulleted,
              '无序列表',
              () => _prefixLines('- '),
            ),
            _toolButton(
              Icons.check_box_outlined,
              '任务列表',
              () => _prefixLines('- [ ] '),
            ),
            _toolButton(Icons.format_quote, '引用', () => _prefixLines('> ')),
            _toolButton(
              Icons.code,
              '行内代码',
              () => _wrapSelection('`', placeholder: 'code'),
            ),
            _toolButton(Icons.link, '链接', _insertLink),
            _toolButton(
              Icons.functions,
              'LaTeX 行内公式',
              () => _wrapSelection(r'$', placeholder: 'x'),
            ),
            _toolButton(Icons.sell_outlined, '标签', _openTagSheet),
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

  Future<void> _openTagSheet() async {
    final provider = context.read<JottingProvider>();
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _JottingTagSheet(
        initialTags: _tags,
        suggestions: provider.tagCounts(),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _tags = List.of(result));
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
      final savedId = id ?? await provider.add(content, tags: _tags);
      if (id != null) {
        await provider.update(id, content: content, tags: _tags);
      }
      if (!mounted) return;
      _initialContent = content;
      _initialTags = List.unmodifiable(_tags);
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

  void _removeTag(String tag) {
    setState(() => _tags = _tags.where((item) => item != tag).toList());
  }

  void _wrapSelection(String marker, {String placeholder = ''}) {
    _wrapSelectionWith(marker, marker, placeholder: placeholder);
  }

  void _wrapSelectionWith(
    String before,
    String after, {
    String placeholder = '',
  }) {
    _ensureEditMode();
    final selection = _normalizedSelection;
    final selected = selection.isCollapsed
        ? placeholder
        : _contentController.text.substring(selection.start, selection.end);
    final replacement = '$before$selected$after';
    _replaceRange(
      selection.start,
      selection.end,
      replacement,
      TextSelection(
        baseOffset: selection.start + before.length,
        extentOffset: selection.start + before.length + selected.length,
      ),
    );
  }

  void _prefixLines(String prefix) {
    _ensureEditMode();
    final range = _expandedLineRange;
    final selected = _contentController.text.substring(range.start, range.end);
    final replacement = selected
        .split('\n')
        .map(
          (line) => line.startsWith(prefix)
              ? line.substring(prefix.length)
              : '$prefix$line',
        )
        .join('\n');
    _replaceRange(range.start, range.end, replacement);
  }

  void _insertLink() {
    _ensureEditMode();
    final selection = _normalizedSelection;
    final selected = selection.isCollapsed
        ? '链接文字'
        : _contentController.text.substring(selection.start, selection.end);
    _replaceRange(
      selection.start,
      selection.end,
      '[$selected](https://)',
      TextSelection.collapsed(offset: selection.start + selected.length + 3),
    );
  }

  void _ensureEditMode() {
    if (!_preview) return;
    setState(() => _preview = false);
  }

  void _replaceRange(
    int start,
    int end,
    String replacement, [
    TextSelection? selection,
  ]) {
    final safeStart = _clampOffset(start);
    final safeEnd = _clampOffset(end);
    final next = _contentController.text.replaceRange(
      safeStart,
      safeEnd,
      replacement,
    );
    _contentController.value = TextEditingValue(
      text: next,
      selection:
          selection ??
          TextSelection.collapsed(offset: safeStart + replacement.length),
    );
    _lastSelection = _contentController.selection;
    _contentFocus.requestFocus();
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

  TextRange get _expandedLineRange {
    final selection = _normalizedSelection;
    final text = _contentController.text;
    var start = _clampOffset(selection.start);
    var end = _clampOffset(selection.end);
    while (start > 0 && text.codeUnitAt(start - 1) != 10) {
      start--;
    }
    while (end < text.length && text.codeUnitAt(end) != 10) {
      end++;
    }
    return TextRange(start: start, end: end);
  }

  int _clampOffset(int value) => value.clamp(0, _contentController.text.length);

  bool _sameStringList(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

class _JottingTagSheet extends StatefulWidget {
  const _JottingTagSheet({
    required this.initialTags,
    required this.suggestions,
  });

  final List<String> initialTags;
  final List<String> suggestions;

  @override
  State<_JottingTagSheet> createState() => _JottingTagSheetState();
}

class _JottingTagSheetState extends State<_JottingTagSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late List<String> _tags;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _tags = List.of(widget.initialTags);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availableSuggestions = widget.suggestions
        .where((tag) => !_tags.contains(tag))
        .take(12)
        .toList(growable: false);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '标签',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              if (_tags.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in _tags)
                      InputChip(
                        label: Text('#$tag'),
                        onDeleted: () => setState(() => _tags.remove(tag)),
                      ),
                  ],
                ),
              if (_tags.isNotEmpty) const SizedBox(height: 12),
              TextField(
                key: const ValueKey('jotting-tag-input'),
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: '添加标签',
                  hintText: '回车或逗号完成',
                  errorText: _errorText,
                  border: const OutlineInputBorder(),
                ),
                onChanged: _consumeCompletedTags,
                onSubmitted: (_) => _commitPendingTag(),
              ),
              if (availableSuggestions.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('常用标签', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in availableSuggestions)
                      ActionChip(
                        label: Text('#$tag'),
                        onPressed: () => _addTag(tag),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    _commitPendingTag();
                    if (_errorText != null) return;
                    Navigator.pop(context, List<String>.unmodifiable(_tags));
                  },
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _consumeCompletedTags(String value) {
    if (!RegExp(r'[,，\s]').hasMatch(value)) return;
    final parts = value.split(RegExp(r'[,，\s]+'));
    for (final part in parts.take(parts.length - 1)) {
      _addTag(part);
    }
    final tail = parts.isEmpty ? '' : parts.last;
    _controller.value = TextEditingValue(
      text: tail,
      selection: TextSelection.collapsed(offset: tail.length),
    );
  }

  void _commitPendingTag() {
    final value = _controller.text;
    if (value.trim().isEmpty) {
      _controller.clear();
      setState(() => _errorText = null);
      return;
    }
    final tag = value.trim().toLowerCase();
    if (tag.length > Jotting.maxTagLength) {
      setState(() => _errorText = '单个标签不能超过 ${Jotting.maxTagLength} 个字符');
      return;
    }
    if (_tags.length >= Jotting.maxTagCount) {
      setState(() => _errorText = '每条随记最多 ${Jotting.maxTagCount} 个标签');
      return;
    }
    if (_tags.contains(tag)) {
      _controller.clear();
      setState(() => _errorText = null);
      return;
    }
    setState(() {
      _tags.add(tag);
      _errorText = null;
    });
    _controller.clear();
  }

  void _addTag(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) {
      setState(() => _errorText = null);
      return;
    }
    if (value.length > Jotting.maxTagLength) {
      setState(() => _errorText = '单个标签不能超过 ${Jotting.maxTagLength} 个字符');
      return;
    }
    if (_tags.length >= Jotting.maxTagCount) {
      setState(() => _errorText = '每条随记最多 ${Jotting.maxTagCount} 个标签');
      return;
    }
    if (_tags.contains(value)) {
      setState(() => _errorText = null);
      return;
    }
    setState(() {
      _tags.add(value);
      _errorText = null;
    });
  }
}
