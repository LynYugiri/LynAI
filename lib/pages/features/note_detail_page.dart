part of '../feature_page.dart';

class _NoteDetail extends StatefulWidget {
  final String noteId;
  final bool editing;
  final ValueChanged<bool> onEditingChanged;
  final VoidCallback onDeleted;
  final ValueChanged<String> onSelectNote;

  const _NoteDetail({
    required this.noteId,
    required this.editing,
    required this.onEditingChanged,
    required this.onDeleted,
    required this.onSelectNote,
  });

  @override
  State<_NoteDetail> createState() => _NoteDetailState();
}

class _NoteDetailState extends State<_NoteDetail> {
  static const _nativeTools = MethodChannel('lynai/native_tools');

  final _shot = ScreenshotController();
  late final TextEditingController _ctrl;
  final _editorFocus = FocusNode();
  final _findFocus = FocusNode();
  final _editorScroll = ScrollController();
  final _findCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  late FeatureProvider _features;
  var _showFind = false;
  var _showReplace = false;
  var _showLatexPanel = false;
  var _caseSensitiveFind = false;
  var _regexFind = false;
  var _currentMatch = -1;
  String? _findError;
  var _matches = <TextRange>[];
  var _lastSavedDraft = '';
  var _lastEditorSelection = const TextSelection.collapsed(offset: 0);
  var _trackedEditorText = '';
  var _trackedEditorSelection = const TextSelection.collapsed(offset: 0);
  var _undoStack = <_NoteEditStep>[];
  var _redoStack = <_NoteEditStep>[];
  var _applyingEditHistory = false;
  String? _activeRevisionId;
  var _proposalSidebarExpanded = true;
  Offset? _proposalBubbleOffset;
  String? _pendingExternalSyncContent;

  @override
  void initState() {
    super.initState();
    _features = context.read<FeatureProvider>();
    final note = _features.getNote(widget.noteId);
    _lastSavedDraft = note?.content ?? '';
    _trackedEditorText = _lastSavedDraft;
    _ctrl = TextEditingController(text: _lastSavedDraft);
    _ctrl.addListener(_onEditorTextChanged);
    _editorFocus.addListener(_refreshLatexPanel);
    _findCtrl.addListener(_refreshMatches);
  }

  @override
  void didUpdateWidget(covariant _NoteDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId) {
      final note = _features.getNote(widget.noteId);
      _loadEditorSnapshot(note?.content ?? '', revisionId: null);
      _proposalSidebarExpanded = true;
      _proposalBubbleOffset = null;
      _refreshMatches();
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onEditorTextChanged);
    _editorFocus.removeListener(_refreshLatexPanel);
    _findCtrl.removeListener(_refreshMatches);
    _ctrl.dispose();
    _editorFocus.dispose();
    _findFocus.dispose();
    _editorScroll.dispose();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = context.watch<FeatureProvider>().getNote(widget.noteId);
    if (note == null) return const Center(child: Text('笔记不存在'));
    final proposal = context.watch<FeatureProvider>().getNoteEditProposal(
      widget.noteId,
    );
    final hasProposal = proposal != null && proposal.blocks.isNotEmpty;
    if (!hasProposal && _proposalSidebarExpanded != true) {
      _proposalSidebarExpanded = true;
    }
    final viewingRevision = _activeRevisionId == null
        ? null
        : _features.getNoteRevision(_activeRevisionId!);
    final viewingHistorical = viewingRevision != null;
    _queueExternalNoteSyncIfNeeded(note, hasProposal: hasProposal);
    final canUndo = widget.editing && _undoStack.isNotEmpty;
    final canRedo = widget.editing && _redoStack.isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Row(
            children: [
              const Spacer(),
              IconButton(
                tooltip: '后退',
                onPressed: canUndo ? _undo : null,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: '前进',
                onPressed: canRedo ? _redo : null,
                icon: const Icon(Icons.redo),
              ),
              IconButton(
                tooltip: '时间线',
                icon: const Icon(Icons.timeline),
                onPressed: () => _openTimeline(note),
              ),
              IconButton(
                tooltip: widget.editing ? '预览' : '编辑',
                icon: Icon(widget.editing ? Icons.visibility : Icons.edit),
                onPressed: () {
                  widget.onEditingChanged(!widget.editing);
                },
              ),
              IconButton(
                tooltip: '保存',
                icon: const Icon(Icons.save),
                onPressed: _canSave ? () => _save() : null,
              ),
              IconButton(
                tooltip: '查找 / 替换',
                icon: const Icon(Icons.find_replace),
                onPressed: _openFind,
              ),
              PopupMenuButton<String>(
                onSelected: (v) => _menu(v, note),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'save', child: Text('保存')),
                  const PopupMenuItem(value: 'rename', child: Text('重命名')),
                  const PopupMenuItem(value: 'find', child: Text('查找 / 替换')),
                  const PopupMenuItem(value: 'goto', child: Text('跳转到行')),
                  const PopupMenuItem(value: 'latex', child: Text('LaTeX 工具')),
                  const PopupMenuItem(value: 'export', child: Text('导出到文件')),
                  const PopupMenuItem(value: 'share_file', child: Text('分享文件')),
                  const PopupMenuItem(value: 'image', child: Text('导出图片')),
                  const PopupMenuItem(
                    value: 'share_image',
                    child: Text('分享长图'),
                  ),
                  CheckedPopupMenuItem(
                    value: 'wrap',
                    checked: note.wrap,
                    child: const Text('自动换行'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
        if (viewingHistorical) _historyBanner(note, viewingRevision),
        if (widget.editing && !hasProposal) _editorToolbar(note),
        if (widget.editing && _showLatexPanel && !hasProposal) _latexPanel(),
        if (_showFind && !hasProposal) _findReplaceBar(),
        Expanded(
          child: _noteBody(note, proposal, hasProposal, viewingHistorical),
        ),
        _editorStatus(note),
      ],
    );
  }

  Widget _noteBody(
    Note note,
    NoteEditProposal? proposal,
    bool hasProposal,
    bool viewingHistorical,
  ) {
    final base = hasProposal && !viewingHistorical && _proposalSidebarExpanded
        ? _buildAiProposalReviewView(note, proposal!)
        : widget.editing
        ? _noteEditor(note)
        : Screenshot(
            controller: _shot,
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: MediaQuery.sizeOf(context).width - 32,
                  ),
                  child: MarkdownWithLatex(
                    content: _ctrl.text,
                    onEditLatexBlock: _editLatexBlockFromPreview,
                  ),
                ),
              ),
            ),
          );
    if (!hasProposal || viewingHistorical || _proposalSidebarExpanded) {
      return base;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final bubbleSize = _proposalBubbleSize(proposal!);
        final defaultOffset = Offset(
          (constraints.maxWidth - bubbleSize.width - 16).clamp(
            0.0,
            double.infinity,
          ),
          (constraints.maxHeight - bubbleSize.height - 16).clamp(
            0.0,
            double.infinity,
          ),
        );
        final offset = _clampProposalBubbleOffset(
          _proposalBubbleOffset ?? defaultOffset,
          constraints.biggest,
          bubbleSize,
        );
        return Stack(
          children: [
            Positioned.fill(child: base),
            Positioned(
              left: offset.dx,
              top: offset.dy,
              child: _proposalBubble(note, proposal, constraints.biggest),
            ),
          ],
        );
      },
    );
  }

  Widget _noteEditor(Note note) {
    final editorSurface = Container(
      color: Theme.of(context).colorScheme.surface,
      child: _buildNoteEditorField(note),
    );
    return editorSurface;
  }

  Widget _buildNoteEditorField(Note note) {
    final longestLine = _ctrl.text
        .split('\n')
        .fold<int>(
          0,
          (longest, line) => line.length > longest ? line.length : longest,
        );
    final editorWidth = (longestLine * 8.5 + 48).clamp(1600.0, 6000.0);
    final editor = TextField(
      controller: _ctrl,
      focusNode: _editorFocus,
      scrollController: _editorScroll,
      expands: true,
      maxLines: null,
      minLines: null,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(
        fontFamily: 'Hurmit Nerd Font',
        fontSize: 14,
        height: 1.45,
      ),
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.all(16),
      ),
      scrollPhysics: const ClampingScrollPhysics(),
    );
    if (note.wrap) return editor;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(width: editorWidth, child: editor),
    );
  }

  Widget _buildAiProposalReviewView(Note note, NoteEditProposal proposal) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final preview = Container(
          color: Theme.of(context).colorScheme.surface,
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            controller: _editorScroll,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: wide
                    ? constraints.maxWidth - 320
                    : constraints.maxWidth - 32,
              ),
              child: MarkdownWithLatex(
                content: _ctrl.text,
                onEditLatexBlock: _editLatexBlockFromPreview,
              ),
            ),
          ),
        );
        final sidebar = _aiProposalSidebar(note, proposal, wide: wide);
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: preview),
              SizedBox(width: 300, child: sidebar),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: preview),
            SizedBox(height: 260, child: sidebar),
          ],
        );
      },
    );
  }

  Widget _aiProposalSidebar(
    Note note,
    NoteEditProposal proposal, {
    required bool wide,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: wide ? EdgeInsets.zero : const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
          left: wide
              ? BorderSide(color: scheme.outlineVariant)
              : BorderSide.none,
          top: !wide
              ? BorderSide(color: scheme.outlineVariant)
              : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.auto_fix_high, color: scheme.tertiary),
              Text(
                '逐行建议 · ${proposal.blocks.length} 处',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              IconButton(
                tooltip: '收起建议',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    setState(() => _proposalSidebarExpanded = false),
                icon: const Icon(Icons.close_fullscreen, size: 18),
              ),
              TextButton(
                onPressed: () => _rejectAllProposal(note.id),
                child: const Text('全部拒绝'),
              ),
              FilledButton.tonal(
                onPressed: () => _acceptAllProposal(note, proposal),
                child: const Text('全部接受'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: proposal.blocks.length,
              itemBuilder: (context, index) =>
                  _aiSidebarSuggestion(note, proposal, proposal.blocks[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _proposalBubble(
    Note note,
    NoteEditProposal proposal,
    Size availableSize,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final bubbleSize = _proposalBubbleSize(proposal);
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final current =
                _proposalBubbleOffset ??
                Offset(
                  availableSize.width - bubbleSize.width - 16,
                  availableSize.height - bubbleSize.height - 16,
                );
            _proposalBubbleOffset = _clampProposalBubbleOffset(
              current + details.delta,
              availableSize,
              bubbleSize,
            );
          });
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => setState(() => _proposalSidebarExpanded = true),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_fix_high, color: scheme.tertiary),
                const SizedBox(width: 8),
                Text(
                  '${proposal.blocks.length} 条建议',
                  style: TextStyle(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _aiSidebarSuggestion(
    Note note,
    NoteEditProposal proposal,
    NoteEditBlock block,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final removed = block.deletedLines.isEmpty
        ? null
        : block.deletedLines.join('\n');
    final inserted = block.insertLines.isEmpty
        ? '删除这些行'
        : block.insertLines.join('\n');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '第 ${block.startLine} 行',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                block.deleteCount == 0 ? '插入' : '替换/删除',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              IconButton(
                tooltip: '定位到这一行',
                visualDensity: VisualDensity.compact,
                onPressed: () => _locateProposalLine(block.startLine),
                icon: const Icon(Icons.my_location_outlined, size: 18),
              ),
            ],
          ),
          if (removed != null) ...[
            const SizedBox(height: 8),
            Text(
              '原文',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            _renderProposalSnippet(
              removed,
              wrapCodeBlocks: true,
              style: TextStyle(
                color: scheme.error,
                fontSize: 11,
                height: 1.35,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '建议',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          _renderProposalSnippet(
            inserted,
            wrapCodeBlocks: true,
            style: TextStyle(color: scheme.primary, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _rejectProposalBlock(proposal, block.id),
                child: const Text('拒绝'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _acceptProposalBlock(note, proposal, block),
                child: const Text('接受'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _renderProposalSnippet(
    String text, {
    required TextStyle style,
    required bool wrapCodeBlocks,
  }) {
    if (text.isEmpty) return Text(' ', style: style);
    return DefaultTextStyle.merge(
      style: style,
      child: MarkdownWithLatex(
        content: text,
        selectable: false,
        wrapCodeBlocks: wrapCodeBlocks,
        textStyle: style,
      ),
    );
  }

  void _onEditorTextChanged() {
    final textChanged = _ctrl.text != _trackedEditorText;
    if (textChanged && !_applyingEditHistory) {
      _undoStack.add(
        _NoteEditStep.fromChange(
          beforeText: _trackedEditorText,
          afterText: _ctrl.text,
          beforeSelection: _trackedEditorSelection,
          afterSelection: _ctrl.selection,
        ),
      );
      _redoStack.clear();
    }
    if (textChanged && _showFind) _refreshMatches();
    if (_ctrl.selection.isValid) _lastEditorSelection = _ctrl.selection;
    _trackedEditorText = _ctrl.text;
    _trackedEditorSelection = _ctrl.selection.isValid
        ? _ctrl.selection
        : _lastEditorSelection;
    if (_showLatexPanel) setState(() {});
    if (textChanged && mounted) setState(() {});
  }

  void _refreshLatexPanel() {
    if (_showLatexPanel && mounted) setState(() {});
  }

  Future<void> _save() async {
    final note = _features.getNote(widget.noteId);
    final content = _ctrl.text;
    if (note == null) return;
    if (!_canSave) {
      _lastSavedDraft = content;
      return;
    }
    final revision = await _features.saveNoteContent(
      widget.noteId,
      content,
      baseRevisionId: _activeRevisionId,
    );
    if (!mounted) return;
    _lastSavedDraft = content;
    _activeRevisionId = null;
    if (revision != null) {
      ScaffoldMessenger.of(context).showSnackBar(shortSnackBar('已保存到时间线'));
    }
    setState(() {});
  }

  bool get _canSave {
    final note = _features.getNote(widget.noteId);
    if (note == null) return false;
    final baseContent = _activeRevisionId == null
        ? note.content
        : _features.getNoteContentAtRevision(widget.noteId, _activeRevisionId);
    return _activeRevisionId != null || _ctrl.text != baseContent;
  }

  bool get _hasUnsavedChanges => _ctrl.text != _lastSavedDraft;

  void _loadEditorSnapshot(String text, {required String? revisionId}) {
    _activeRevisionId = revisionId;
    _lastSavedDraft = text;
    _resetEditorState(text);
  }

  void _resetEditorState(String text) {
    final selection = TextSelection.collapsed(offset: text.length);
    _undoStack = [];
    _redoStack = [];
    _trackedEditorText = text;
    _trackedEditorSelection = selection;
    _lastEditorSelection = selection;
    _ctrl.value = TextEditingValue(text: text, selection: selection);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final step = _undoStack.removeLast();
    _redoStack.add(step);
    _applyEditHistory(step.undo(_ctrl.text), step.beforeSelection);
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final step = _redoStack.removeLast();
    _undoStack.add(step);
    _applyEditHistory(step.redo(_ctrl.text), step.afterSelection);
  }

  void _applyEditHistory(String text, TextSelection selection) {
    _applyingEditHistory = true;
    _ctrl.value = TextEditingValue(text: text, selection: selection);
    _applyingEditHistory = false;
    if (mounted) setState(() {});
  }

  Widget _historyBanner(Note note, NoteRevision revision) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '正在查看 ${_formatNoteTime(revision.savedAt)} 的历史版本，基于它保存会新开分支并切到新分支。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () => _showCompareDialog(
              currentLabel: '当前版本',
              currentText: note.content,
              otherLabel: '历史版本',
              otherText: _ctrl.text,
            ),
            child: const Text('对比'),
          ),
          TextButton(
            onPressed: () {
              _returnToCurrentRevision(note);
            },
            child: const Text('回到当前'),
          ),
        ],
      ),
    );
  }

  Future<void> _openTimeline(Note note) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _NoteTimelineSheet(
        note: note,
        features: _features,
        onOpen: (revision, content) => _openRevisionFromTimeline(
          note: note,
          revision: revision,
          content: content,
        ),
        onCompare: (revision, content) {
          Navigator.pop(context);
          _showCompareDialog(
            currentLabel: '当前版本',
            currentText: note.content,
            otherLabel: _formatNoteTime(revision.savedAt),
            otherText: content,
          );
        },
        onRestore: (revision) => _restoreRevisionFromTimeline(note, revision),
        onCopy: (content) => _copyRevisionContent(content),
        onDuplicate: (revision, content) =>
            _duplicateRevision(note, revision, content),
        onDelete: (revision) => _deleteRevisionFromTimeline(note, revision),
        onDeleteBranches: (revision, branchCount) =>
            _deleteBranchesFromTimeline(note, revision, branchCount),
      ),
    );
  }

  String _diffSummary(String before, String after) {
    return '${_noteDiffSummary(before, after)} · ${_noteLineDiffSummary(before, after)}';
  }

  Future<void> _restoreRevisionFromTimeline(
    Note note,
    NoteRevision revision,
  ) async {
    Navigator.pop(context);
    if (!await _confirmDiscardUnsavedChanges()) return;
    if (!mounted) return;
    final restored = await _features.restoreNoteRevision(note.id, revision.id);
    if (!mounted || restored == null) return;
    final content = _features.getNoteContentAtRevision(note.id, restored.id);
    setState(() => _loadEditorSnapshot(content, revisionId: null));
    ScaffoldMessenger.of(context).showSnackBar(shortSnackBar('已恢复为当前版本'));
  }

  Future<void> _copyRevisionContent(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(shortSnackBar('版本内容已复制'));
  }

  Future<void> _duplicateRevision(
    Note note,
    NoteRevision revision,
    String content,
  ) async {
    final title = '${note.title} ${_formatNoteTime(revision.savedAt)}';
    final id = await _features.addNoteWithContent(
      title,
      content,
      folderId: note.folderId,
    );
    if (!mounted) return;
    widget.onEditingChanged(false);
    Navigator.pop(context);
    widget.onSelectNote(id);
    ScaffoldMessenger.of(context).showSnackBar(shortSnackBar('已另存为新笔记'));
  }

  Future<void> _deleteRevisionFromTimeline(
    Note note,
    NoteRevision revision,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除版本？'),
        content: const Text('删除此版本会同时删除基于它的分支版本，当前路径上的版本不能删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await _features.deleteNoteRevision(note.id, revision.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(shortSnackBar(deleted ? '版本已删除' : '当前路径版本不能删除'));
  }

  Future<void> _deleteBranchesFromTimeline(
    Note note,
    NoteRevision revision,
    int branchCount,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除整条支线？'),
        content: Text(
          '将删除从 ${_formatNoteTime(revision.savedAt)} 分出的 $branchCount 个非当前路径版本，当前路径会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除支线'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await _features.deleteNoteBranchesFromRevision(
      note.id,
      revision.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      shortSnackBar(deleted > 0 ? '已删除 $deleted 个支线版本' : '没有可删除的支线'),
    );
  }

  Future<void> _showCompareDialog({
    required String currentLabel,
    required String currentText,
    required String otherLabel,
    required String otherText,
  }) {
    final diffLines = _buildDiffLines(otherText, currentText);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('版本对比'),
        content: SizedBox(
          width: 820,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$otherLabel -> $currentLabel'),
                const SizedBox(height: 8),
                Text(_diffSummary(otherText, currentText)),
                const SizedBox(height: 4),
                Text(
                  _lineChangeDetail(otherText, currentText),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                _diffLegend(otherLabel: otherLabel, currentLabel: currentLabel),
                const SizedBox(height: 8),
                _diffView(diffLines),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _lineChangeDetail(String before, String after) {
    final stats = _noteDiffStats(before, after);
    if (!stats.hasChanges) return '行级变化：无';
    return '行级变化：新增 ${stats.addedLines} 行，删除 ${stats.removedLines} 行';
  }

  List<_DiffLine> _buildDiffLines(String before, String after) {
    final beforeLines = before.split('\n');
    final afterLines = after.split('\n');
    final n = beforeLines.length;
    final m = afterLines.length;
    final maxCells = 60000;
    if (n * m > maxCells) {
      return _fallbackDiffLines(beforeLines, afterLines);
    }
    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        dp[i][j] = beforeLines[i] == afterLines[j]
            ? dp[i + 1][j + 1] + 1
            : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
      }
    }
    final lines = <_DiffLine>[];
    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (beforeLines[i] == afterLines[j]) {
        lines.add(
          _DiffLine(
            type: _DiffLineType.context,
            beforeLine: i + 1,
            afterLine: j + 1,
            text: beforeLines[i],
          ),
        );
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        lines.add(
          _DiffLine(
            type: _DiffLineType.removed,
            beforeLine: i + 1,
            afterLine: null,
            text: beforeLines[i],
          ),
        );
        i++;
      } else {
        lines.add(
          _DiffLine(
            type: _DiffLineType.added,
            beforeLine: null,
            afterLine: j + 1,
            text: afterLines[j],
          ),
        );
        j++;
      }
    }
    while (i < n) {
      lines.add(
        _DiffLine(
          type: _DiffLineType.removed,
          beforeLine: i + 1,
          afterLine: null,
          text: beforeLines[i],
        ),
      );
      i++;
    }
    while (j < m) {
      lines.add(
        _DiffLine(
          type: _DiffLineType.added,
          beforeLine: null,
          afterLine: j + 1,
          text: afterLines[j],
        ),
      );
      j++;
    }
    return lines;
  }

  List<_DiffLine> _fallbackDiffLines(
    List<String> beforeLines,
    List<String> afterLines,
  ) {
    final lines = <_DiffLine>[];
    final shared = beforeLines.length < afterLines.length
        ? beforeLines.length
        : afterLines.length;
    for (var i = 0; i < shared; i++) {
      if (beforeLines[i] == afterLines[i]) {
        lines.add(
          _DiffLine(
            type: _DiffLineType.context,
            beforeLine: i + 1,
            afterLine: i + 1,
            text: beforeLines[i],
          ),
        );
      } else {
        lines.add(
          _DiffLine(
            type: _DiffLineType.removed,
            beforeLine: i + 1,
            afterLine: null,
            text: beforeLines[i],
          ),
        );
        lines.add(
          _DiffLine(
            type: _DiffLineType.added,
            beforeLine: null,
            afterLine: i + 1,
            text: afterLines[i],
          ),
        );
      }
    }
    for (var i = shared; i < beforeLines.length; i++) {
      lines.add(
        _DiffLine(
          type: _DiffLineType.removed,
          beforeLine: i + 1,
          afterLine: null,
          text: beforeLines[i],
        ),
      );
    }
    for (var i = shared; i < afterLines.length; i++) {
      lines.add(
        _DiffLine(
          type: _DiffLineType.added,
          beforeLine: null,
          afterLine: i + 1,
          text: afterLines[i],
        ),
      );
    }
    return lines;
  }

  Widget _diffLegend({
    required String otherLabel,
    required String currentLabel,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _diffLegendChip('-', otherLabel, scheme.errorContainer, scheme.error),
        _diffLegendChip(
          '+',
          currentLabel,
          scheme.primaryContainer,
          scheme.primary,
        ),
        _diffLegendChip(
          ' ',
          '未改上下文',
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      ],
    );
  }

  Widget _diffLegendChip(String sign, String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$sign $label',
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _diffView(List<_DiffLine> lines) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                _diffHeaderCell('旧行', 56),
                _diffHeaderCell('新行', 56),
                const Expanded(
                  child: Text(
                    '内容',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: lines.length,
              itemBuilder: (context, index) => _diffRow(lines[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _diffHeaderCell(String label, double width) {
    return SizedBox(
      width: width,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _diffRow(_DiffLine line) {
    final scheme = Theme.of(context).colorScheme;
    final rowStyle = switch (line.type) {
      _DiffLineType.added => (
        scheme.primaryContainer.withValues(alpha: 0.42),
        scheme.primary,
        '+',
      ),
      _DiffLineType.removed => (
        scheme.errorContainer.withValues(alpha: 0.42),
        scheme.error,
        '-',
      ),
      _DiffLineType.context => (scheme.surface, scheme.onSurfaceVariant, ' '),
    };
    return Container(
      color: rowStyle.$1,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              line.beforeLine?.toString() ?? '',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontFamily: 'Hurmit Nerd Font',
                fontSize: 12,
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              line.afterLine?.toString() ?? '',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontFamily: 'Hurmit Nerd Font',
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${rowStyle.$3} ${line.text.isEmpty ? ' ' : line.text}',
              style: TextStyle(
                color: rowStyle.$2,
                fontFamily: 'Hurmit Nerd Font',
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _returnToCurrentRevision(Note note) async {
    if (!await _confirmDiscardUnsavedChanges()) return;
    if (!mounted) return;
    setState(() => _loadEditorSnapshot(note.content, revisionId: null));
  }

  Future<void> _acceptProposalBlock(
    Note note,
    NoteEditProposal proposal,
    NoteEditBlock block,
  ) async {
    await _applyProposalBlocks(note, proposal, [block]);
  }

  void _locateProposalLine(int lineNumber) {
    final offset = _offsetForLine(lineNumber);
    if (widget.editing) {
      setState(() {
        _ctrl.selection = TextSelection.collapsed(offset: offset);
        _lastEditorSelection = _ctrl.selection;
        _trackedEditorSelection = _ctrl.selection;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToOffset(offset);
      if (widget.editing) _editorFocus.requestFocus();
    });
  }

  Future<void> _acceptAllProposal(Note note, NoteEditProposal proposal) async {
    await _applyProposalBlocks(note, proposal, proposal.blocks);
  }

  Future<void> _applyProposalBlocks(
    Note note,
    NoteEditProposal proposal,
    List<NoteEditBlock> blocks,
  ) async {
    if (blocks.isEmpty) return;
    final latestNote = _features.getNote(note.id);
    if (latestNote == null) return;
    final currentText = _ctrl.text;
    final editorHash = _contentHash(currentText);
    final latestHash = _contentHash(latestNote.content);
    if (editorHash != proposal.baseContentHash ||
        latestHash != proposal.baseContentHash) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(shortSnackBar('笔记内容已变化，请让 AI 重新生成修改建议'));
      await _features.removeNoteEditProposal(note.id);
      return;
    }
    final next = _applyProposalBlocksToText(currentText, blocks);
    if (next == null) {
      ScaffoldMessenger.of(context).showSnackBar(shortSnackBar('修改建议行号已失效'));
      await _features.removeNoteEditProposal(note.id);
      return;
    }
    final revision = await _features.saveNoteContent(
      note.id,
      next,
      baseRevisionId: proposal.baseRevisionId,
    );
    if (!mounted) return;
    final acceptedIds = blocks.map((block) => block.id).toSet();
    final remaining = proposal.blocks
        .where((block) => !acceptedIds.contains(block.id))
        .toList();
    if (remaining.isEmpty) {
      await _features.removeNoteEditProposal(note.id);
    } else {
      await _features.setNoteEditProposal(
        proposal.copyWith(
          baseRevisionId: revision?.id ?? note.currentRevisionId,
          baseContentHash: _contentHash(next),
          createdAt: DateTime.now(),
          blocks: remaining.map((block) {
            final shift = _proposalLineShift(blocks, block.startLine);
            return NoteEditBlock(
              id: block.id,
              startLine: block.startLine + shift,
              deleteCount: block.deleteCount,
              deletedLines: block.deletedLines,
              insertLines: block.insertLines,
            );
          }).toList(),
        ),
      );
    }
    if (!mounted) return;
    setState(() => _loadEditorSnapshot(next, revisionId: null));
    ScaffoldMessenger.of(context).showSnackBar(
      shortSnackBar(revision == null ? '建议没有产生新修改' : '已接受建议并保存到时间线'),
    );
  }

  void _queueExternalNoteSyncIfNeeded(Note note, {required bool hasProposal}) {
    if (_activeRevisionId != null || hasProposal || _hasUnsavedChanges) {
      _pendingExternalSyncContent = null;
      return;
    }
    if (note.content == _lastSavedDraft) {
      _pendingExternalSyncContent = null;
      return;
    }
    if (_pendingExternalSyncContent == note.content) return;
    _pendingExternalSyncContent = note.content;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final latestNote = _features.getNote(widget.noteId);
      if (latestNote == null ||
          latestNote.content != _pendingExternalSyncContent) {
        return;
      }
      _pendingExternalSyncContent = null;
      setState(() => _loadEditorSnapshot(latestNote.content, revisionId: null));
    });
  }

  Future<void> _rejectProposalBlock(
    NoteEditProposal proposal,
    String blockId,
  ) async {
    final remaining = proposal.blocks
        .where((block) => block.id != blockId)
        .toList();
    if (remaining.isEmpty) {
      await _features.removeNoteEditProposal(proposal.noteId);
      return;
    }
    await _features.setNoteEditProposal(proposal.copyWith(blocks: remaining));
  }

  Future<void> _rejectAllProposal(String noteId) async {
    await _features.removeNoteEditProposal(noteId);
  }

  String? _applyProposalBlocksToText(
    String content,
    List<NoteEditBlock> blocks,
  ) {
    final lines = content.isEmpty ? [''] : content.split('\n');
    final sorted = [...blocks]
      ..sort((a, b) => b.startLine.compareTo(a.startLine));
    var previousStart = lines.length + 1;
    for (final block in sorted) {
      final start = block.startLine - 1;
      final end = start + block.deleteCount;
      if (block.startLine < 1 || start > lines.length || end > lines.length) {
        return null;
      }
      if (end > previousStart - 1) return null;
      lines.replaceRange(start, end, block.insertLines);
      previousStart = block.startLine;
    }
    return lines.join('\n');
  }

  int _proposalLineShift(List<NoteEditBlock> accepted, int line) {
    var shift = 0;
    for (final block in accepted) {
      if (block.startLine >= line) continue;
      shift += block.insertLines.length - block.deleteCount;
    }
    return shift;
  }

  String _contentHash(String content) {
    return sha256.convert(utf8.encode(content)).toString();
  }

  int _offsetForLine(int lineNumber) {
    if (lineNumber <= 1) return 0;
    final text = _ctrl.text;
    var currentLine = 1;
    for (var i = 0; i < text.length; i++) {
      if (currentLine >= lineNumber) return i;
      if (text.codeUnitAt(i) == 10) currentLine++;
    }
    return text.length;
  }

  Size _proposalBubbleSize(NoteEditProposal proposal) {
    final digits = proposal.blocks.length.toString().length;
    return Size(88 + digits * 12, 48);
  }

  Offset _clampProposalBubbleOffset(
    Offset offset,
    Size availableSize,
    Size bubbleSize,
  ) {
    final maxX = (availableSize.width - bubbleSize.width).clamp(
      0.0,
      double.infinity,
    );
    final maxY = (availableSize.height - bubbleSize.height).clamp(
      0.0,
      double.infinity,
    );
    return Offset(offset.dx.clamp(0.0, maxX), offset.dy.clamp(0.0, maxY));
  }

  Future<void> _openRevisionFromTimeline({
    required Note note,
    required NoteRevision revision,
    required String content,
  }) async {
    Navigator.pop(context);
    if (!await _confirmDiscardUnsavedChanges()) return;
    if (!mounted) return;
    final revisionId = revision.id == note.currentRevisionId
        ? null
        : revision.id;
    setState(() => _loadEditorSnapshot(content, revisionId: revisionId));
  }

  Future<bool> _confirmDiscardUnsavedChanges() async {
    if (!_hasUnsavedChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存修改？'),
        content: const Text('当前修改还没有保存到时间线，继续会丢失这些修改。'),
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
    return discard == true;
  }

  Widget _editorToolbar(Note note) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
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
            _toolButton(
              Icons.format_strikethrough,
              '删除线',
              () => _wrapSelection('~~', placeholder: '删除线'),
            ),
            _toolButton(
              Icons.code,
              '行内代码',
              () => _wrapSelection('`', placeholder: 'code'),
            ),
            _toolDivider(),
            _toolButton(Icons.title, '标题', () => _prefixLines('## ')),
            _toolButton(
              Icons.format_list_bulleted,
              '无序列表',
              () => _prefixLines('- '),
            ),
            _toolButton(
              Icons.format_list_numbered,
              '有序列表',
              _numberSelectionLines,
            ),
            _toolButton(
              Icons.check_box_outlined,
              '任务列表',
              () => _prefixLines('- [ ] '),
            ),
            _toolButton(Icons.format_quote, '引用', () => _prefixLines('> ')),
            _toolDivider(),
            _toolButton(Icons.data_object, '代码块', _insertCodeBlock),
            _toolButton(Icons.table_chart_outlined, '表格', _insertTable),
            _toolButton(
              Icons.horizontal_rule,
              '分割线',
              () => _insertText('\n---\n'),
            ),
            _toolButton(Icons.link, '链接', _insertLink),
            _toolButton(Icons.image_outlined, '图片', _insertImage),
            _toolDivider(),
            _toolButton(Icons.functions, 'LaTeX 行内公式', _insertInlineLatex),
            _toolButton(
              Icons.calculate_outlined,
              'LaTeX 块公式',
              _insertBlockLatex,
            ),
            _toolButton(Icons.science_outlined, 'LaTeX 工具', _toggleLatexPanel),
            _toolDivider(),
            _toolButton(Icons.find_replace, '查找 / 替换', _openFind),
            _toolButton(Icons.low_priority, '跳转行', _showGoToLineDialog),
            _toolButton(
              note.wrap ? Icons.wrap_text : Icons.short_text,
              note.wrap ? '关闭自动换行' : '开启自动换行',
              () => _features.updateNote(note.copyWith(wrap: !note.wrap)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }

  Widget _toolDivider() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }

  Widget _latexPanel() {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.sizeOf(context);
    final compact = media.width < 600;
    final maxHeight = (media.height * (compact ? 0.36 : 0.42))
        .clamp(220.0, 310.0)
        .toDouble();
    return Material(
      color: Color.lerp(scheme.surface, scheme.tertiaryContainer, 0.18),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: scheme.outlineVariant),
            bottom: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _latexPanelHeader(compact, scheme),
              const SizedBox(height: 6),
              AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) => _latexPreview(_latexPreviewSource),
              ),
              const SizedBox(height: 8),
              _latexPalette('结构', _latexStructures),
              _latexPalette('希腊', _latexGreek),
              _latexPalette('运算', _latexOperators),
              _latexPalette('关系', _latexRelations),
              _latexPalette('箭头', _latexArrows),
            ],
          ),
        ),
      ),
    );
  }

  Widget _latexPanelHeader(bool compact, ColorScheme scheme) {
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.functions, color: scheme.tertiary),
        const SizedBox(width: 8),
        Text(
          'LaTeX 编辑器',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton.icon(
          onPressed: _insertInlineLatex,
          icon: const Icon(Icons.short_text),
          label: const Text('行内'),
        ),
        TextButton.icon(
          onPressed: _insertBlockLatex,
          icon: const Icon(Icons.view_agenda_outlined),
          label: const Text('块级'),
        ),
        TextButton.icon(
          onPressed: _editCurrentLatexFormula,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('编辑当前公式'),
        ),
        IconButton(
          tooltip: '关闭 LaTeX 工具',
          icon: const Icon(Icons.close),
          onPressed: _toggleLatexPanel,
        ),
      ],
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, const SizedBox(height: 4), actions],
      );
    }
    return Row(
      children: [
        title,
        const SizedBox(width: 8),
        Expanded(child: actions),
      ],
    );
  }

  Widget _latexPreview(String source) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            source.isEmpty ? '选中公式或把光标放在公式内可即时预览' : source,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Hurmit Nerd Font',
              fontSize: 12,
              color: source.isEmpty
                  ? scheme.onSurfaceVariant
                  : scheme.onSurfaceVariant,
            ),
          ),
          if (source.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Math.tex(
                source,
                mathStyle: MathStyle.display,
                textStyle: TextStyle(fontSize: 20, color: scheme.onSurface),
                onErrorFallback: (_) => Text(
                  'LaTeX 语法错误：请检查括号、命令或环境是否闭合',
                  style: TextStyle(
                    color: scheme.error,
                    fontSize: 12,
                    fontFamily: 'Hurmit Nerd Font',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _latexPalette(String title, List<_LatexSnippet> snippets) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final snippet in snippets)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(snippet.label),
                  tooltip: snippet.source,
                  onPressed: () => _insertLatexSnippet(snippet),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _findReplaceBar() {
    final scheme = Theme.of(context).colorScheme;
    final matchText = _matches.isEmpty
        ? '无匹配'
        : '${_currentMatch + 1}/${_matches.length}';
    final controls = Wrap(
      spacing: 2,
      runSpacing: 2,
      alignment: WrapAlignment.end,
      children: [
        IconButton(
          tooltip: '上一个',
          icon: const Icon(Icons.keyboard_arrow_up),
          onPressed: _previousMatch,
        ),
        IconButton(
          tooltip: '下一个',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: _nextMatch,
        ),
        IconButton(
          tooltip: _caseSensitiveFind ? '区分大小写' : '不区分大小写',
          icon: Icon(
            Icons.text_fields,
            color: _caseSensitiveFind ? scheme.primary : null,
          ),
          onPressed: () {
            setState(() => _caseSensitiveFind = !_caseSensitiveFind);
            _refreshMatches();
          },
        ),
        IconButton(
          tooltip: _regexFind ? '正则匹配' : '普通匹配',
          icon: Icon(
            Icons.data_object,
            color: _regexFind ? scheme.primary : null,
          ),
          onPressed: () {
            setState(() => _regexFind = !_regexFind);
            _refreshMatches();
          },
        ),
        IconButton(
          tooltip: _showReplace ? '隐藏替换' : '显示替换',
          icon: const Icon(Icons.swap_horiz),
          onPressed: () => setState(() => _showReplace = !_showReplace),
        ),
        IconButton(
          tooltip: '关闭',
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _showFind = false),
        ),
      ],
    );
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _findCtrl,
                    focusNode: _findFocus,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: _regexFind ? '查找正则' : '查找',
                      prefixIcon: const Icon(Icons.search),
                      suffixText: matchText,
                      errorText: _findError,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _nextMatch(),
                  ),
                ),
                controls,
              ],
            ),
            if (_showReplace) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replaceCtrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: '替换为',
                        prefixIcon: Icon(Icons.edit_note),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _replaceCurrent(),
                    ),
                  ),
                  TextButton(
                    onPressed: _replaceCurrent,
                    child: const Text('替换'),
                  ),
                  TextButton(onPressed: _replaceAll, child: const Text('全部替换')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _editorStatus(Note note) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final currentText = _ctrl.text;
        final currentSelection = _ctrl.selection;
        final lineCount = currentText.isEmpty
            ? 1
            : '\n'.allMatches(currentText).length + 1;
        final currentLine = _lineForOffset(
          currentSelection.baseOffset < 0 ? 0 : currentSelection.baseOffset,
        );
        final currentColumn = _columnForOffset(
          currentSelection.baseOffset < 0 ? 0 : currentSelection.baseOffset,
        );
        final currentWords = RegExp(
          r'[^\s]+',
        ).allMatches(currentText.trim()).length;
        final saved = currentText == _lastSavedDraft;
        final viewLabel = _activeRevisionId == null ? '当前' : '历史';
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$viewLabel · 行 $currentLine/$lineCount · 列 $currentColumn · 字符 ${currentText.length} · 词 $currentWords · ${note.wrap ? '自动换行' : '横向滚动'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                saved ? '已保存' : '编辑中',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: saved
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openFind() {
    if (!widget.editing) {
      widget.onEditingChanged(true);
    }
    setState(() {
      _showFind = true;
      _showReplace = _showReplace || _findCtrl.text.isNotEmpty;
    });
    final selected = _selectedText;
    if (selected.isNotEmpty && !selected.contains('\n')) {
      _findCtrl.text = selected;
      _findCtrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: selected.length,
      );
    }
    _refreshMatches();
    _findFocus.requestFocus();
  }

  void _refreshMatches() {
    final query = _findCtrl.text;
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _matches = [];
          _currentMatch = -1;
          _findError = null;
        });
      }
      return;
    }
    final matcher = _regexFind
        ? _SearchMatcher.regex(query, caseSensitive: _caseSensitiveFind)
        : _SearchMatcher.literal(query, caseSensitive: _caseSensitiveFind);
    final matches = matcher
        .allMatches(_ctrl.text)
        .where((match) => match.end > match.start)
        .map((match) => TextRange(start: match.start, end: match.end))
        .toList();
    var current = matches.indexWhere((range) {
      final offset = _ctrl.selection.baseOffset;
      return offset >= range.start && offset <= range.end;
    });
    if (current == -1 && matches.isNotEmpty) current = 0;
    if (!mounted) return;
    setState(() {
      _matches = matches;
      _currentMatch = current;
      _findError = matcher.hasError ? '正则表达式无效' : null;
    });
  }

  void _nextMatch() => _selectMatch(_currentMatch + 1);

  void _previousMatch() => _selectMatch(_currentMatch - 1);

  void _selectMatch(int index) {
    if (_matches.isEmpty) return;
    if (!widget.editing) {
      widget.onEditingChanged(true);
    }
    final next = index % _matches.length;
    final normalized = next < 0 ? next + _matches.length : next;
    final match = _matches[normalized];
    setState(() => _currentMatch = normalized);
    _ctrl.selection = TextSelection(
      baseOffset: match.start,
      extentOffset: match.end,
    );
    _scrollToOffset(match.start);
    _editorFocus.requestFocus();
  }

  void _replaceCurrent() {
    final index = _matchIndexAtCursor();
    if (index < 0 || index >= _matches.length) return;
    final match = _matches[index];
    _replaceRange(match.start, match.end, _replaceCtrl.text);
    _refreshMatches();
    if (_matches.isNotEmpty) {
      _selectMatch(index.clamp(0, _matches.length - 1));
    }
  }

  void _replaceAll() {
    if (_matches.isEmpty) return;
    final replacement = _replaceCtrl.text;
    final buffer = StringBuffer();
    var cursor = 0;
    for (final match in _matches) {
      buffer
        ..write(_ctrl.text.substring(cursor, match.start))
        ..write(replacement);
      cursor = match.end;
    }
    buffer.write(_ctrl.text.substring(cursor));
    final count = _matches.length;
    _setText(buffer.toString(), TextSelection.collapsed(offset: buffer.length));
    _refreshMatches();
    ScaffoldMessenger.of(context).showSnackBar(shortSnackBar('已替换 $count 处'));
  }

  Future<void> _showGoToLineDialog() async {
    final ctrl = TextEditingController();
    final line = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转到行'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '行号'),
          onSubmitted: (_) => Navigator.pop(ctx, int.tryParse(ctrl.text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)),
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (line == null || line < 1) return;
    _goToLine(line);
  }

  void _goToLine(int line) {
    final lines = _ctrl.text.split('\n');
    final targetLine = line.clamp(1, lines.length);
    var offset = 0;
    for (var i = 0; i < targetLine - 1; i++) {
      offset += lines[i].length + 1;
    }
    _ctrl.selection = TextSelection.collapsed(offset: offset);
    _scrollToOffset(offset);
    _editorFocus.requestFocus();
  }

  void _wrapSelection(String marker, {String placeholder = ''}) {
    _wrapSelectionWith(marker, marker, placeholder: placeholder);
  }

  void _wrapSelectionWith(
    String before,
    String after, {
    String placeholder = '',
  }) {
    final selection = _normalizedSelection;
    final selected = selection.isCollapsed
        ? placeholder
        : _ctrl.text.substring(selection.start, selection.end);
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
    final range = _expandedLineRange;
    final selected = _ctrl.text.substring(range.start, range.end);
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

  void _numberSelectionLines() {
    final range = _expandedLineRange;
    final lines = _ctrl.text.substring(range.start, range.end).split('\n');
    final numbered = <String>[];
    for (var i = 0; i < lines.length; i++) {
      numbered.add(
        '${i + 1}. ${lines[i].replaceFirst(RegExp(r'^\d+\.\s*'), '')}',
      );
    }
    _replaceRange(range.start, range.end, numbered.join('\n'));
  }

  void _insertCodeBlock() {
    _wrapSelectionWith('\n```\n', '\n```\n', placeholder: 'code');
  }

  void _toggleLatexPanel() {
    setState(() => _showLatexPanel = !_showLatexPanel);
    if (_showLatexPanel) _editorFocus.requestFocus();
  }

  Future<void> _insertInlineLatex() =>
      _insertLatexWithEditor(preferBlock: false);

  Future<void> _insertBlockLatex() => _insertLatexWithEditor(preferBlock: true);

  Future<void> _editCurrentLatexFormula() async {
    final segment = _currentLatexSegment;
    if (segment == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(shortSnackBar('请先选中公式或把光标放到公式内'));
      return;
    }
    final edited = await _openLatexFormulaEditor(
      title: '编辑公式',
      initialFormula: segment.formula,
      preferBlock: _isBlockLatex(segment.source),
    );
    if (edited == null) return;
    _replaceRange(
      segment.start,
      segment.end,
      _wrapLatexFormula(edited, segment.source),
    );
  }

  Future<void> _insertLatexWithEditor({required bool preferBlock}) async {
    final formula = await _openLatexFormulaEditor(
      title: preferBlock ? '插入块级公式' : '插入行内公式',
      initialFormula: '',
      preferBlock: preferBlock,
    );
    if (formula == null) return;
    final wrapped = preferBlock ? '\n\$\$\n$formula\n\$\$\n' : '\$$formula\$';
    _replaceSelection(wrapped);
  }

  void _insertLatexSnippet(_LatexSnippet snippet) {
    final selection = _normalizedSelection;
    final selected = selection.isCollapsed
        ? 'x'
        : _ctrl.text.substring(selection.start, selection.end);
    final replacement = snippet.source.replaceAll(_latexPlaceholder, selected);
    final placeholderStart = snippet.source.indexOf(_latexPlaceholder);
    final selectionStart = placeholderStart == -1
        ? selection.start + replacement.length
        : selection.start + placeholderStart;
    final selectionEnd = selectionStart + selected.length;
    _replaceRange(
      selection.start,
      selection.end,
      replacement,
      TextSelection(baseOffset: selectionStart, extentOffset: selectionEnd),
    );
  }

  void _insertTable() {
    _insertText('\n| 列 1 | 列 2 |\n| --- | --- |\n| 内容 | 内容 |\n');
  }

  void _insertLink() {
    final selected = _selectedText;
    final text = selected.isEmpty ? '链接文字' : selected;
    _replaceSelection('[$text](https://)');
  }

  void _insertImage() {
    final selected = _selectedText;
    final text = selected.isEmpty ? '图片描述' : selected;
    _replaceSelection('![$text](https://)');
  }

  void _insertText(String text) => _replaceSelection(text);

  void _replaceSelection(String replacement) {
    final selection = _normalizedSelection;
    _replaceRange(selection.start, selection.end, replacement);
  }

  void _replaceRange(
    int start,
    int end,
    String replacement, [
    TextSelection? selection,
  ]) {
    final next = _ctrl.text.replaceRange(start, end, replacement);
    _setText(
      next,
      selection ?? TextSelection.collapsed(offset: start + replacement.length),
    );
    _editorFocus.requestFocus();
  }

  void _setText(String text, TextSelection selection) {
    _ctrl.value = TextEditingValue(text: text, selection: selection);
  }

  void _scrollToOffset(int offset) {
    if (!_editorScroll.hasClients) return;
    final line = _lineForOffset(offset);
    final target = ((line - 1) * 22.0).clamp(
      0.0,
      _editorScroll.position.maxScrollExtent,
    );
    _editorScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  TextSelection get _normalizedSelection {
    final selection = _ctrl.selection.isValid
        ? _ctrl.selection
        : _lastEditorSelection;
    if (!selection.isValid) {
      return TextSelection.collapsed(offset: _ctrl.text.length);
    }
    final start = selection.start.clamp(0, _ctrl.text.length);
    final end = selection.end.clamp(0, _ctrl.text.length);
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  TextRange get _expandedLineRange {
    final selection = _normalizedSelection;
    final text = _ctrl.text;
    var start = selection.start;
    var end = selection.end;
    while (start > 0 && text.codeUnitAt(start - 1) != 10) {
      start--;
    }
    while (end < text.length && text.codeUnitAt(end) != 10) {
      end++;
    }
    return TextRange(start: start, end: end);
  }

  String get _selectedText {
    final selection = _normalizedSelection;
    if (selection.isCollapsed) return '';
    return _ctrl.text.substring(selection.start, selection.end);
  }

  int _lineForOffset(int offset) {
    final safeOffset = offset.clamp(0, _ctrl.text.length);
    return '\n'.allMatches(_ctrl.text.substring(0, safeOffset)).length + 1;
  }

  int _columnForOffset(int offset) {
    final safeOffset = offset.clamp(0, _ctrl.text.length);
    final lineStart = _ctrl.text.lastIndexOf(
      '\n',
      safeOffset == 0 ? 0 : safeOffset - 1,
    );
    return safeOffset - lineStart;
  }

  String get _latexPreviewSource {
    return _currentLatexSegment?.formula ?? '';
  }

  _LatexSegment? get _currentLatexSegment {
    final selected = _selectedText.trim();
    if (selected.isNotEmpty) {
      final source = _stripLatexDelimiters(selected);
      if (source.isNotEmpty && _shouldPreviewLatexSource(selected)) {
        final selection = _normalizedSelection;
        return _LatexSegment(selection.start, selection.end, selected, source);
      }
    }
    final selection = _normalizedSelection;
    return _latexSegmentAt(selection.baseOffset);
  }

  _LatexSegment? _latexSegmentAt(int offset) {
    final text = _ctrl.text;
    if (text.isEmpty) return null;
    final safeOffset = offset.clamp(0, text.length);
    final blockRanges = <_LatexSegment>[
      ..._latexSegments(text, RegExp(r'\$\$(.+?)\$\$', dotAll: true)),
      ..._latexSegments(text, RegExp(r'\\\[(.+?)\\\]', dotAll: true)),
    ];
    final ranges = <_LatexSegment>[
      ...blockRanges,
      ..._latexSegments(text, RegExp(r'\\\((.+?)\\\)')),
      ..._inlineLatexRanges(text, blockRanges),
    ];
    ranges.sort((a, b) {
      final aContains = safeOffset >= a.start && safeOffset <= a.end;
      final bContains = safeOffset >= b.start && safeOffset <= b.end;
      if (aContains != bContains) return aContains ? -1 : 1;
      return (a.end - a.start).compareTo(b.end - b.start);
    });
    for (final range in ranges) {
      if (safeOffset >= range.start &&
          safeOffset <= range.end &&
          _shouldPreviewLatexSource(range.source)) {
        return range;
      }
    }
    return null;
  }

  bool _shouldPreviewLatexSource(String source) {
    if (source.startsWith(r'$$')) return true;
    if (source.startsWith(r'\[') || source.startsWith(r'\(')) return true;
    return LatexRenderer.hasLatexContent(source);
  }

  List<_LatexSegment> _latexSegments(String text, RegExp pattern) {
    return pattern
        .allMatches(text)
        .map(
          (match) => _LatexSegment(
            match.start,
            match.end,
            match.group(0) ?? '',
            _stripLatexDelimiters(match.group(0) ?? ''),
          ),
        )
        .toList();
  }

  List<_LatexSegment> _inlineLatexRanges(
    String text,
    List<_LatexSegment> blockRanges,
  ) {
    return RegExp(r'\$(.+?)\$')
        .allMatches(text)
        .where(
          (match) => !blockRanges.any((range) {
            return match.start >= range.start && match.end <= range.end;
          }),
        )
        .map(
          (match) => _LatexSegment(
            match.start,
            match.end,
            match.group(0) ?? '',
            _stripLatexDelimiters(match.group(0) ?? ''),
          ),
        )
        .toList();
  }

  Future<String?> _openLatexFormulaEditor({
    required String title,
    required String initialFormula,
    required bool preferBlock,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => LatexFormulaEditorPage(
          title: title,
          initialFormula: initialFormula,
          preferBlock: preferBlock,
        ),
      ),
    );
  }

  Future<void> _editLatexBlockFromPreview(
    String source,
    int start,
    int end,
  ) async {
    final edited = await _openLatexFormulaEditor(
      title: '编辑公式',
      initialFormula: _stripLatexDelimiters(source),
      preferBlock: _isBlockLatex(source),
    );
    if (edited == null) return;
    _replaceRange(start, end, _wrapLatexFormula(edited, source));
  }

  int _matchIndexAtCursor() {
    final offset = _ctrl.selection.baseOffset;
    final exactIndex = _matches.indexWhere(
      (range) => offset >= range.start && offset <= range.end,
    );
    if (exactIndex != -1) return exactIndex;
    return _currentMatch;
  }

  bool _isBlockLatex(String source) {
    final trimmed = source.trimLeft();
    return trimmed.startsWith(r'$$') || trimmed.startsWith(r'\[');
  }

  String _wrapLatexFormula(String formula, String originalSource) {
    final trimmed = formula.trim();
    final source = originalSource.trim();
    if (source.startsWith(r'\[') && source.endsWith(r'\]')) {
      return '\\[$trimmed\\]';
    }
    if (source.startsWith(r'\(') && source.endsWith(r'\)')) {
      return '\\($trimmed\\)';
    }
    if (source.startsWith(r'$$') && source.endsWith(r'$$')) {
      return '\$\$\n$trimmed\n\$\$';
    }
    return '\$$trimmed\$';
  }

  String _stripLatexDelimiters(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith(r'$$') && trimmed.endsWith(r'$$')) {
      return trimmed.substring(2, trimmed.length - 2).trim();
    }
    if (trimmed.startsWith(r'\[') && trimmed.endsWith(r'\]')) {
      return trimmed.substring(2, trimmed.length - 2).trim();
    }
    if (trimmed.startsWith(r'\(') && trimmed.endsWith(r'\)')) {
      return trimmed.substring(2, trimmed.length - 2).trim();
    }
    if (trimmed.startsWith(r'$') && trimmed.endsWith(r'$')) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }

  Future<void> _menu(String value, Note note) async {
    switch (value) {
      case 'save':
        await _save();
      case 'rename':
        await _rename(note);
      case 'find':
        _openFind();
      case 'goto':
        await _showGoToLineDialog();
      case 'latex':
        if (!widget.editing) widget.onEditingChanged(true);
        _toggleLatexPanel();
      case 'export':
        await _export(note);
      case 'share_file':
        await _shareFile(note);
      case 'image':
        await _exportImage();
      case 'share_image':
        await _shareImage();
      case 'wrap':
        await _features.updateNote(note.copyWith(wrap: !note.wrap));
      case 'delete':
        await _delete(note);
    }
  }

  Future<void> _rename(Note note) async {
    final ctrl = TextEditingController(text: note.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
          decoration: const InputDecoration(labelText: '标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (!mounted) return;
    if (title != null && title.isNotEmpty) {
      await _features.updateNote(note.copyWith(title: title));
    }
  }

  Future<void> _export(Note note) async {
    final fileName = '${safeExportFileName(note.title, fallback: 'note')}.md';
    try {
      final bytes = Uint8List.fromList(utf8.encode(_ctrl.text));
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出笔记',
        fileName: fileName,
        bytes: bytes,
      );
      if (path == null) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes, flush: true);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('笔记已导出到 $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }

  Future<void> _shareFile(Note note) async {
    final fileName = '${safeExportFileName(note.title, fallback: 'note')}.md';
    try {
      await shareTextFile(
        fileName: fileName,
        content: _ctrl.text,
        text: note.title,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('分享失败: $e')));
    }
  }

  Future<void> _exportImage() async {
    final note = _features.getNote(widget.noteId);
    if (note == null) return;
    final images = await _captureNoteImages(note.title, _ctrl.text);
    if (images.isEmpty) return;
    try {
      final message = await shareOrSavePngImages(
        images: images,
        filePrefix: 'note',
        nativeTools: _nativeTools,
        clipboardMessage: '笔记图片已复制到剪贴板',
        galleryMessage: '笔记图片已保存到图库',
      );
      if (!mounted || message == null) return;
      _showImageSnack(message);
    } catch (e) {
      if (!mounted) return;
      _showImageSnack('导出图片失败: $e');
    }
  }

  Future<void> _shareImage() async {
    final note = _features.getNote(widget.noteId);
    if (note == null) return;
    final images = await _captureNoteImages(note.title, _ctrl.text);
    if (images.isEmpty) return;
    try {
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final files = <XFile>[];
      for (var i = 0; i < images.length; i++) {
        final file = File(
          '${dir.path}/${numberedImageFileName('note', timestamp, i, images.length)}',
        );
        await file.writeAsBytes(images[i], flush: true);
        files.add(XFile(file.path));
      }
      await SharePlus.instance.share(ShareParams(files: files));
    } catch (e) {
      if (!mounted) return;
      _showImageSnack('分享失败: $e');
    }
  }

  Future<List<Uint8List>> _captureNoteImages(
    String title,
    String content,
  ) async {
    final theme = Theme.of(context);
    final pages = splitTextForExport(
      content,
      maxLength: _exportTextChunkLength,
    );
    final images = <Uint8List>[];
    for (var i = 0; i < pages.length; i++) {
      if (!mounted) return images;
      final image = await _shot.captureFromLongWidget(
        _NoteShareImage(
          title: title,
          content: pages[i],
          seedColor: theme.colorScheme.primary,
          brightness: theme.brightness,
          pageNumber: pages.length == 1 ? null : i + 1,
          pageCount: pages.length == 1 ? null : pages.length,
        ),
        pixelRatio: _exportImagePixelRatio,
        context: context,
        constraints: const BoxConstraints(maxWidth: 720),
      );
      if (!mounted) return images;
      images.add(image);
    }
    return images;
  }

  void _showImageSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(shortSnackBar(message));
  }

  Future<void> _delete(Note note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除笔记'),
        content: Text('确定删除"${note.title}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _features.deleteNote(note.id);
    widget.onDeleted();
  }
}

const _latexPlaceholder = '__LYNAI_LATEX_SELECTION__';

class _LatexSegment {
  final int start;
  final int end;
  final String source;
  final String formula;

  const _LatexSegment(this.start, this.end, this.source, this.formula);
}

class _NoteEditStep {
  final NoteTextDelta delta;
  final TextSelection beforeSelection;
  final TextSelection afterSelection;

  const _NoteEditStep({
    required this.delta,
    required this.beforeSelection,
    required this.afterSelection,
  });

  factory _NoteEditStep.fromChange({
    required String beforeText,
    required String afterText,
    required TextSelection beforeSelection,
    required TextSelection afterSelection,
  }) {
    return _NoteEditStep(
      delta: NoteTextDelta.between(beforeText, afterText),
      beforeSelection: beforeSelection,
      afterSelection: afterSelection,
    );
  }

  String undo(String source) => delta.revert(source);

  String redo(String source) => delta.apply(source);
}

class _LatexSnippet {
  final String label;
  final String source;

  const _LatexSnippet(this.label, this.source);
}

const _latexStructures = [
  _LatexSnippet('分数', r'\frac{__LYNAI_LATEX_SELECTION__}{y}'),
  _LatexSnippet('根号', r'\sqrt{__LYNAI_LATEX_SELECTION__}'),
  _LatexSnippet('n 次根', r'\sqrt[n]{__LYNAI_LATEX_SELECTION__}'),
  _LatexSnippet('上标', r'__LYNAI_LATEX_SELECTION__^{2}'),
  _LatexSnippet('下标', r'__LYNAI_LATEX_SELECTION___{i}'),
  _LatexSnippet('求和', r'\sum_{i=1}^{n} __LYNAI_LATEX_SELECTION__'),
  _LatexSnippet('积分', r'\int_{a}^{b} __LYNAI_LATEX_SELECTION__\,dx'),
  _LatexSnippet('极限', r'\lim_{x \to 0} __LYNAI_LATEX_SELECTION__'),
  _LatexSnippet('向量', r'\vec{__LYNAI_LATEX_SELECTION__}'),
  _LatexSnippet('帽记号', r'\hat{__LYNAI_LATEX_SELECTION__}'),
  _LatexSnippet('横线', r'\overline{__LYNAI_LATEX_SELECTION__}'),
  _LatexSnippet('矩阵 2x2', r'\begin{bmatrix} a & b \\ c & d \end{bmatrix}'),
  _LatexSnippet(
    '分段',
    r'\begin{cases} x^2, & x \ge 0 \\ -x, & x < 0 \end{cases}',
  ),
  _LatexSnippet(
    '对齐',
    r'\begin{aligned} a &= b + c \\ d &= e + f \end{aligned}',
  ),
];

const _latexGreek = [
  _LatexSnippet('α', r'\alpha'),
  _LatexSnippet('β', r'\beta'),
  _LatexSnippet('γ', r'\gamma'),
  _LatexSnippet('δ', r'\delta'),
  _LatexSnippet('ε', r'\epsilon'),
  _LatexSnippet('θ', r'\theta'),
  _LatexSnippet('λ', r'\lambda'),
  _LatexSnippet('μ', r'\mu'),
  _LatexSnippet('π', r'\pi'),
  _LatexSnippet('ρ', r'\rho'),
  _LatexSnippet('σ', r'\sigma'),
  _LatexSnippet('φ', r'\varphi'),
  _LatexSnippet('ω', r'\omega'),
  _LatexSnippet('Γ', r'\Gamma'),
  _LatexSnippet('Δ', r'\Delta'),
  _LatexSnippet('Ω', r'\Omega'),
];

const _latexOperators = [
  _LatexSnippet('×', r'\times'),
  _LatexSnippet('÷', r'\div'),
  _LatexSnippet('±', r'\pm'),
  _LatexSnippet('∓', r'\mp'),
  _LatexSnippet('⋅', r'\cdot'),
  _LatexSnippet('∞', r'\infty'),
  _LatexSnippet('∂', r'\partial'),
  _LatexSnippet('∇', r'\nabla'),
  _LatexSnippet('∫', r'\int'),
  _LatexSnippet('∮', r'\oint'),
  _LatexSnippet('∑', r'\sum'),
  _LatexSnippet('∏', r'\prod'),
  _LatexSnippet('sin', r'\sin'),
  _LatexSnippet('cos', r'\cos'),
  _LatexSnippet('ln', r'\ln'),
];

const _latexRelations = [
  _LatexSnippet('≤', r'\le'),
  _LatexSnippet('≥', r'\ge'),
  _LatexSnippet('≠', r'\ne'),
  _LatexSnippet('≈', r'\approx'),
  _LatexSnippet('≡', r'\equiv'),
  _LatexSnippet('∝', r'\propto'),
  _LatexSnippet('∈', r'\in'),
  _LatexSnippet('∉', r'\notin'),
  _LatexSnippet('⊂', r'\subset'),
  _LatexSnippet('⊆', r'\subseteq'),
  _LatexSnippet('∪', r'\cup'),
  _LatexSnippet('∩', r'\cap'),
];

const _latexArrows = [
  _LatexSnippet('→', r'\to'),
  _LatexSnippet('←', r'\leftarrow'),
  _LatexSnippet('⇒', r'\Rightarrow'),
  _LatexSnippet('⇔', r'\Leftrightarrow'),
  _LatexSnippet('↦', r'\mapsto'),
  _LatexSnippet('↑', r'\uparrow'),
  _LatexSnippet('↓', r'\downarrow'),
];

class _NoteShareImage extends StatelessWidget {
  final String title;
  final String content;
  final Color seedColor;
  final Brightness brightness;
  final int? pageNumber;
  final int? pageCount;

  const _NoteShareImage({
    required this.title,
    required this.content,
    required this.seedColor,
    required this.brightness,
    this.pageNumber,
    this.pageCount,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final bgColor = Color.lerp(
      scheme.surface,
      scheme.primary,
      isDark ? 0.08 : 0.035,
    )!;
    final cardColor = Color.lerp(
      scheme.surface,
      scheme.surfaceContainerHighest,
      isDark ? 0.35 : 0.18,
    )!;
    final mutedColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 720,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: bgColor),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.sticky_note_2_outlined,
                    color: scheme.onPrimary,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? 'LynAI 笔记' : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Markdown 笔记 · ${DateTime.now().year}/${DateTime.now().month}/${DateTime.now().day}',
                        style: TextStyle(color: mutedColor, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: MarkdownWithLatex(
                content: content,
                selectable: false,
                wrapCodeBlocks: true,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              pageNumber == null || pageCount == null
                  ? 'Exported from LynAI'
                  : 'Exported from LynAI · $pageNumber/$pageCount',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: mutedColor,
                fontSize: 18,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
