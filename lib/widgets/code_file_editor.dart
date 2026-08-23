import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/plugin.dart';
import '../services/code_syntax_service.dart';
import '../utils/snackbar_utils.dart';

/// 带语法高亮的代码编辑控制器。
///
/// 将包含高亮样式的富文本写入 [TextEditingController.value]，编辑时通过
/// 差分更新避免重新构建全量字符串。插件编辑器与工作区文件编辑器共用。
class CodeEditingController extends TextEditingController {
  CodeEditingController({required super.text, required this.language});

  final String language;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = (style ?? const TextStyle()).copyWith(
      fontFamily: codeFontFamily,
      color: const Color(0xFFABB2BF),
    );
    return createCodeHighlighter(base).formatCode(text, language: language);
  }
}

/// 通用全屏代码文件编辑器。
///
/// 提供语法高亮、横向滚动、自动换行、保存、未保存离开确认与状态栏。
/// [onSave] 负责把正文写回真正的存储后端；[previewPageBuilder] 非空时
/// 显示“预览页面”动作（预览前会先保存未保存修改）。
class CodeFileEditorPage extends StatefulWidget {
  const CodeFileEditorPage({
    super.key,
    required this.path,
    required this.initialContent,
    required this.onSave,
    this.readOnly = false,
    this.previewPageBuilder,
  });

  final String path;
  final String initialContent;
  final Future<void> Function(String content) onSave;
  final bool readOnly;
  final Widget Function(BuildContext context)? previewPageBuilder;

  @override
  State<CodeFileEditorPage> createState() => _CodeFileEditorPageState();
}

class _CodeFileEditorPageState extends State<CodeFileEditorPage> {
  late final CodeEditingController _controller;
  final _scrollController = ScrollController();
  final _horizontalController = ScrollController();
  var _savedContent = '';
  var _wrap = false;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _savedContent = widget.initialContent;
    _controller = CodeEditingController(
      text: widget.initialContent,
      language: fileTypeFromPath(widget.path),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  bool get _dirty => _controller.text != _savedContent;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard()) {
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.path),
          actions: [
            if (fileTypeFromPath(widget.path) == 'json' && !widget.readOnly)
              IconButton(
                tooltip: '格式化 JSON',
                onPressed: _formatJson,
                icon: const Icon(Icons.data_object),
              ),
            IconButton(
              tooltip: _wrap ? '关闭自动换行' : '开启自动换行',
              onPressed: () => setState(() => _wrap = !_wrap),
              icon: Icon(_wrap ? Icons.wrap_text : Icons.short_text),
            ),
            if (widget.previewPageBuilder != null)
              IconButton(
                tooltip: '预览页面',
                onPressed: _saving ? null : _previewPage,
                icon: const Icon(Icons.preview_outlined),
              ),
            IconButton(
              tooltip: '保存',
              onPressed: widget.readOnly || _saving ? null : _save,
              icon: const Icon(Icons.save),
            ),
          ],
        ),
        body: Column(
          children: [
            if (widget.readOnly)
              MaterialBanner(
                content: const Text('此文件不可编辑'),
                actions: [
                  TextButton(
                    onPressed: () => ScaffoldMessenger.of(
                      context,
                    ).hideCurrentMaterialBanner(),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            Expanded(child: _editor()),
            _statusBar(),
          ],
        ),
      ),
    );
  }

  Widget _editor() {
    final editor = TextField(
      controller: _controller,
      scrollController: _scrollController,
      readOnly: widget.readOnly,
      expands: true,
      maxLines: null,
      minLines: null,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      cursorColor: const Color(0xFF61AFEF),
      style: const TextStyle(
        fontFamily: codeFontFamily,
        fontSize: 14,
        height: 1.45,
      ),
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.all(16),
      ),
    );
    final surface = Container(color: const Color(0xFF282C34), child: editor);
    if (_wrap) return surface;
    final width = (_longestLine() * 8.5 + 48).clamp(1200.0, 6000.0);
    return Scrollbar(
      controller: _horizontalController,
      notificationPredicate: (notification) => notification.depth == 1,
      child: SingleChildScrollView(
        controller: _horizontalController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: width, child: surface),
      ),
    );
  }

  Widget _statusBar() {
    final lines = _controller.text.split('\n').length;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Text(fileTypeFromPath(widget.path)),
            const SizedBox(width: 12),
            Text('$lines 行'),
            const Spacer(),
            if (_dirty) const Text('未保存'),
          ],
        ),
      ),
    );
  }

  int _longestLine() {
    return _controller.text
        .split('\n')
        .fold<int>(
          0,
          (longest, line) => line.length > longest ? line.length : longest,
        );
  }

  Future<bool> _confirmSyntaxErrorsIfAny() async {
    final summary = parseCodeSyntax(
      fileTypeFromPath(widget.path),
      _controller.text,
    );
    if (!summary.supported || !summary.parsed || !summary.hasError) {
      return true;
    }
    if (!context.mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('检测到语法错误'),
        content: const Text('当前文件可能存在语法错误，仍要保存吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('仍要保存'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _save() async {
    if (!await _confirmSyntaxErrorsIfAny()) return;
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_controller.text);
      _savedContent = _controller.text;
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文件已保存')));
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          details: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _previewPage() async {
    final builder = widget.previewPageBuilder;
    if (builder == null) return;
    if (_dirty && !widget.readOnly) {
      await _save();
      if (!mounted || _dirty) return;
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: builder));
  }

  void _formatJson() {
    try {
      final decoded = jsonDecode(_controller.text);
      _controller.text = const JsonEncoder.withIndent('  ').convert(decoded);
      setState(() {});
    } catch (_) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('JSON 格式错误')));
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存修改？'),
        content: const Text('当前文件还有未保存修改，继续返回会丢失这些内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    return result == true;
  }
}
