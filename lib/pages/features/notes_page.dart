part of '../feature_page.dart';

class _NotesPage extends StatefulWidget {
  final GlobalKey<_NoteDetailState> noteDetailKey;
  final String? selectedNoteId;
  final bool editing;
  final ValueChanged<String> onSelect;
  final ValueChanged<bool> onEditingChanged;
  final VoidCallback onBack;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final Future<void> Function({String? folderId}) onNewNote;
  final VoidCallback onNewFolder;

  const _NotesPage({
    required this.noteDetailKey,
    required this.selectedNoteId,
    required this.editing,
    required this.onSelect,
    required this.onEditingChanged,
    required this.onBack,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onNewNote,
    required this.onNewFolder,
  });

  @override
  State<_NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<_NotesPage> {
  static const _nativeTools = MethodChannel('lynai/native_tools');

  final _shot = ScreenshotController();
  final Set<String> _expandedFolderIds = {};
  late FeatureProvider _features;

  @override
  void initState() {
    super.initState();
    _features = context.read<FeatureProvider>();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedNoteId != null) {
      return _NoteDetail(
        key: widget.noteDetailKey,
        noteId: widget.selectedNoteId!,
        editing: widget.editing,
        onEditingChanged: widget.onEditingChanged,
        onDeleted: widget.onBack,
        onSelectNote: widget.onSelect,
      );
    }
    final provider = context.watch<FeatureProvider>();
    final notes = provider.notes;
    final folders = provider.noteFolders;
    if (notes.isEmpty && folders.isEmpty) {
      return Column(
        children: [
          _noteSearchBox(),
          const Expanded(
            child: _FeatureEmptyState(
              icon: Icons.sticky_note_2_outlined,
              title: '暂无笔记',
              subtitle: '点击右上角 + 创建第一篇笔记，支持 Markdown 和 LaTeX 渲染。',
            ),
          ),
        ],
      );
    }
    final query = widget.searchQuery.trim();
    final matcher = _SearchMatcher.fromSearchSyntax(query);
    final visibleNotes = notes
        .where((note) => _matchesNote(note, matcher))
        .toList();
    final visibleFolders = folders.where((folder) {
      if (matcher.isEmpty) return true;
      return matcher.matches(folder.title) ||
          visibleNotes.any((note) => note.folderId == folder.id);
    }).toList();
    final looseNotes = visibleNotes
        .where((note) => note.folderId == null || _folderMissing(note, folders))
        .toList();
    final entries = <_NoteListEntry>[
      ...visibleFolders.map(_NoteListEntry.folder),
      ...looseNotes.map(_NoteListEntry.note),
    ];
    return Column(
      children: [
        _noteSearchBox(),
        if (matcher.hasError)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '正则表达式无效',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.redAccent),
              ),
            ),
          ),
        Expanded(
          child: entries.isEmpty
              ? ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: const [
                    ListTile(
                      leading: Icon(Icons.search_off),
                      title: Text('未找到匹配的笔记'),
                    ),
                  ],
                )
              : matcher.isEmpty
              ? ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 88),
                  itemCount: entries.length,
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) =>
                      _reorderTopLevel(entries, oldIndex, newIndex),
                  itemBuilder: (context, index) => _entryCard(
                    entries[index],
                    index: index,
                    draggable: true,
                    query: query,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 88),
                  itemCount: entries.length,
                  itemBuilder: (context, index) => _entryCard(
                    entries[index],
                    index: index,
                    draggable: false,
                    query: query,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _noteSearchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: TextField(
        controller: widget.searchController,
        decoration: InputDecoration(
          hintText: '搜索笔记标题或内容，支持 re:正则 或 /正则/i',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: widget.searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    widget.searchController.clear();
                    widget.onSearchChanged('');
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onChanged: widget.onSearchChanged,
      ),
    );
  }

  bool _matchesNote(Note note, _SearchMatcher matcher) {
    if (matcher.isEmpty) return true;
    return matcher.matches(note.title) || matcher.matches(note.content);
  }

  bool _folderMissing(Note note, List<NoteFolder> folders) {
    final folderId = note.folderId;
    if (folderId == null) return false;
    return !folders.any((folder) => folder.id == folderId);
  }

  Widget _entryCard(
    _NoteListEntry entry, {
    required int index,
    required bool draggable,
    required String query,
  }) {
    final folder = entry.folder;
    if (folder != null) {
      return _folderCard(
        folder,
        index: index,
        draggable: draggable,
        query: query,
      );
    }
    return _noteTile(entry.note!, index: index, draggable: draggable);
  }

  Widget _folderCard(
    NoteFolder folder, {
    required int index,
    required bool draggable,
    required String query,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final expanded = query.isNotEmpty || _expandedFolderIds.contains(folder.id);
    final notes = context
        .watch<FeatureProvider>()
        .notes
        .where(
          (note) =>
              note.folderId == folder.id &&
              _matchesNote(note, _SearchMatcher.fromSearchSyntax(query)),
        )
        .toList();
    return Card(
      key: ValueKey('folder-${folder.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Column(
        children: [
          ListTile(
            leading: draggable
                ? ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  )
                : const Icon(Icons.folder_outlined),
            title: Text(
              folder.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('${notes.length} 篇笔记'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: expanded ? '折叠' : '展开',
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: query.isEmpty
                      ? () => _toggleFolder(folder.id)
                      : null,
                ),
                PopupMenuButton<String>(
                  onSelected: (v) => _folderMenu(v, folder),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('重命名')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
            onTap: query.isEmpty ? () => _toggleFolder(folder.id) : null,
          ),
          if (expanded) ...[
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(Icons.note_add_outlined, color: scheme.primary),
              title: Text('创建笔记', style: TextStyle(color: scheme.primary)),
              onTap: () => widget.onNewNote(folderId: folder.id),
            ),
            if (notes.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '文件夹为空',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              )
            else if (query.isEmpty)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: notes.length,
                onReorder: (oldIndex, newIndex) => _features
                    .reorderNotesInFolder(folder.id, oldIndex, newIndex),
                itemBuilder: (context, noteIndex) => _noteTile(
                  notes[noteIndex],
                  index: noteIndex,
                  draggable: true,
                  nested: true,
                ),
              )
            else
              ...notes.map(
                (note) =>
                    _noteTile(note, index: 0, draggable: false, nested: true),
              ),
          ],
        ],
      ),
    );
  }

  Widget _noteTile(
    Note note, {
    required int index,
    required bool draggable,
    bool nested = false,
  }) {
    final preview = note.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Card(
      key: ValueKey('${nested ? 'nested' : 'note'}-${note.id}'),
      margin: nested
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      elevation: nested ? 0 : null,
      child: ListTile(
        dense: nested,
        leading: draggable
            ? ReorderableDragStartListener(
                index: index,
                child: Icon(nested ? Icons.drag_indicator : Icons.drag_handle),
              )
            : const Icon(Icons.sticky_note_2_outlined),
        title: Text(
          note.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          preview.isEmpty ? '空笔记' : preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) => _noteMenu(v, note),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('重命名')),
            PopupMenuItem(value: 'move', child: Text('移动到文件夹')),
            PopupMenuItem(value: 'export', child: Text('导出到文件')),
            PopupMenuItem(value: 'share_file', child: Text('分享文件')),
            PopupMenuItem(value: 'image', child: Text('导出长图')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
        onTap: () => widget.onSelect(note.id),
      ),
    );
  }

  Future<void> _reorderTopLevel(
    List<_NoteListEntry> entries,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex < 0 || oldIndex >= entries.length) return;
    if (newIndex < 0 || newIndex > entries.length) return;
    final oldEntry = entries[oldIndex];
    final remainingEntries = [...entries]..removeAt(oldIndex);
    final insertionIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (insertionIndex < 0 || insertionIndex > remainingEntries.length) return;
    final remainingFolderCount = remainingEntries
        .where((entry) => entry.isFolder)
        .length;
    if (oldEntry.isFolder && insertionIndex > remainingFolderCount) {
      return;
    }
    if (!oldEntry.isFolder && insertionIndex < remainingFolderCount) {
      return;
    }
    final sameTypeEntries = entries
        .where((entry) => entry.isFolder == oldEntry.isFolder)
        .toList();
    final oldSameTypeIndex = sameTypeEntries.indexWhere(
      (entry) => entry.id == oldEntry.id,
    );
    final newSameTypeIndex = remainingEntries
        .take(insertionIndex)
        .where((entry) => entry.isFolder == oldEntry.isFolder)
        .length;
    final providerNewIndex = newSameTypeIndex > oldSameTypeIndex
        ? newSameTypeIndex + 1
        : newSameTypeIndex;
    if (oldEntry.isFolder) {
      final oldFolderIndex = sameTypeEntries.indexWhere(
        (e) => e.folder!.id == oldEntry.folder!.id,
      );
      await _features.reorderNoteFolders(oldFolderIndex, providerNewIndex);
    } else {
      final oldNoteIndex = sameTypeEntries.indexWhere(
        (e) => e.note!.id == oldEntry.note!.id,
      );
      await _features.reorderNotesInFolder(
        null,
        oldNoteIndex,
        providerNewIndex,
      );
    }
  }

  void _toggleFolder(String id) {
    setState(() {
      if (!_expandedFolderIds.add(id)) _expandedFolderIds.remove(id);
    });
  }

  Future<void> _noteMenu(String value, Note note) async {
    switch (value) {
      case 'rename':
        await _renameNote(note);
      case 'move':
        await _moveNote(note);
      case 'export':
        await _exportNote(note);
      case 'share_file':
        await _shareNoteFile(note);
      case 'image':
        await _exportNoteImage(note);
      case 'delete':
        await _deleteNote(note);
    }
  }

  Future<void> _folderMenu(String value, NoteFolder folder) async {
    switch (value) {
      case 'rename':
        await _renameFolder(folder);
      case 'delete':
        await _deleteFolder(folder);
    }
  }

  Future<void> _renameNote(Note note) async {
    final title = await _textDialog(
      title: '重命名',
      label: '标题',
      initialText: note.title,
    );
    if (title == null || title.isEmpty) return;
    await _features.updateNote(note.copyWith(title: title));
  }

  Future<void> _moveNote(Note note) async {
    final folders = _features.noteFolders;
    final folderId = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('移动到文件夹'),
        children: [
          ListTile(
            leading: note.folderId == null
                ? const Icon(Icons.check, size: 20)
                : const SizedBox(width: 20),
            title: const Text('不放入文件夹'),
            onTap: () => Navigator.pop(ctx, ''),
          ),
          for (final folder in folders)
            ListTile(
              leading: note.folderId == folder.id
                  ? const Icon(Icons.check, size: 20)
                  : const SizedBox(width: 20),
              title: Text(folder.title),
              onTap: () => Navigator.pop(ctx, folder.id),
            ),
        ],
      ),
    );
    if (!mounted || folderId == null) return;
    await _features.updateNote(
      note.copyWith(folderId: folderId.isEmpty ? null : folderId),
    );
  }

  Future<void> _exportNote(Note note) async {
    final fileName = '${safeExportFileName(note.title, fallback: 'note')}.md';
    try {
      final bytes = Uint8List.fromList(utf8.encode(note.content));
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

  Future<void> _shareNoteFile(Note note) async {
    final fileName = '${safeExportFileName(note.title, fallback: 'note')}.md';
    try {
      await shareTextFile(
        fileName: fileName,
        content: note.content,
        text: note.title,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('分享失败: $e')));
    }
  }

  Future<void> _exportNoteImage(Note note) async {
    final theme = Theme.of(context);
    final bytes = <Uint8List>[];
    final pages = splitTextForExport(
      note.content,
      maxLength: _exportTextChunkLength,
    );
    for (var i = 0; i < pages.length; i++) {
      if (!mounted) return;
      final image = await _shot.captureFromLongWidget(
        _NoteShareImage(
          title: note.title,
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
      if (!mounted) return;
      bytes.add(image);
    }
    if (!mounted) return;
    await _writeNoteImage(bytes);
  }

  Future<void> _writeNoteImage(List<Uint8List> images) async {
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

  void _showImageSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(shortSnackBar(message));
  }

  Future<void> _deleteNote(Note note) async {
    final ok = await _confirm(title: '删除笔记', message: '确定删除"${note.title}"吗？');
    if (ok != true || !mounted) return;
    await _features.deleteNote(note.id);
  }

  Future<void> _renameFolder(NoteFolder folder) async {
    final title = await _textDialog(
      title: '重命名文件夹',
      label: '名称',
      initialText: folder.title,
    );
    if (title == null || title.isEmpty) return;
    await _features.updateNoteFolder(folder.copyWith(title: title));
  }

  Future<void> _deleteFolder(NoteFolder folder) async {
    final ok = await _confirm(
      title: '删除文件夹',
      message: '确定删除"${folder.title}"吗？文件夹内笔记会移出文件夹。',
    );
    if (ok != true || !mounted) return;
    await _features.deleteNoteFolder(folder.id);
    setState(() => _expandedFolderIds.remove(folder.id));
  }

  Future<String?> _textDialog({
    required String title,
    required String label,
    String initialText = '',
  }) async {
    final ctrl = TextEditingController(text: initialText);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
          decoration: InputDecoration(labelText: label),
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
    return text;
  }

  Future<bool?> _confirm({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
  }
}

class _NoteListEntry {
  final NoteFolder? folder;
  final Note? note;

  const _NoteListEntry.folder(this.folder) : note = null;
  const _NoteListEntry.note(this.note) : folder = null;

  bool get isFolder => folder != null;
  String get id => folder?.id ?? note!.id;
}

class _NoteTimelineSheet extends StatefulWidget {
  final Note note;
  final FeatureProvider features;
  final void Function(NoteRevision revision, String content) onOpen;
  final void Function(NoteRevision revision, String content) onCompare;
  final Future<void> Function(NoteRevision revision) onRestore;
  final Future<void> Function(String content) onCopy;
  final Future<void> Function(NoteRevision revision, String content)
  onDuplicate;
  final Future<void> Function(NoteRevision revision) onDelete;
  final Future<void> Function(NoteRevision revision, int branchCount)
  onDeleteBranches;

  const _NoteTimelineSheet({
    required this.note,
    required this.features,
    required this.onOpen,
    required this.onCompare,
    required this.onRestore,
    required this.onCopy,
    required this.onDuplicate,
    required this.onDelete,
    required this.onDeleteBranches,
  });

  @override
  State<_NoteTimelineSheet> createState() => _NoteTimelineSheetState();
}

class _NoteTimelineSheetState extends State<_NoteTimelineSheet> {
  final _searchCtrl = TextEditingController();
  final _contentCache = <String, String>{};
  final _previousContentCache = <String, String>{};
  final _statsCache = <String, _NoteDiffStats>{};
  var _query = '';
  var _filter = _NoteTimelineFilter.all;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.features,
      builder: (context, _) {
        final note = widget.features.getNote(widget.note.id) ?? widget.note;
        final timeline = widget.features.getNoteTimeline(note.id);
        _removeStaleCache(timeline);
        final currentPath = widget.features.getNoteCurrentRevisionPath(note.id);
        final entries = _filteredEntries(timeline, currentPath);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.82,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '时间线',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '${timeline.length} 个版本',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '搜索版本内容或时间...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _query = '');
                              },
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip('全部', _NoteTimelineFilter.all),
                        const SizedBox(width: 8),
                        _filterChip('当前路径', _NoteTimelineFilter.currentPath),
                        const SizedBox(width: 8),
                        _filterChip('分支', _NoteTimelineFilter.branches),
                        const SizedBox(width: 8),
                        _filterChip('大改动', _NoteTimelineFilter.largeChanges),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: timeline.isEmpty
                        ? const Center(child: Text('还没有保存过时间线'))
                        : entries.isEmpty
                        ? const Center(child: Text('没有匹配的版本'))
                        : ListView.builder(
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              if (entry.header != null) {
                                return _dateHeader(entry.header!);
                              }
                              return _revisionCard(
                                note,
                                entry.revision!,
                                currentPath,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _filterChip(String label, _NoteTimelineFilter filter) {
    return FilterChip(
      label: Text(label),
      selected: _filter == filter,
      onSelected: (_) => setState(() => _filter = filter),
    );
  }

  List<_NoteTimelineEntry> _filteredEntries(
    List<NoteRevision> timeline,
    Set<String> currentPath,
  ) {
    final query = _query.trim().toLowerCase();
    final revisions = <NoteRevision>[];
    for (final revision in timeline) {
      if (!_matchesFilter(revision, currentPath)) continue;
      if (query.isNotEmpty && !_matchesQuery(revision, query)) continue;
      revisions.add(revision);
    }
    final entries = <_NoteTimelineEntry>[];
    String? previousHeader;
    for (final revision in revisions) {
      final header = _dateGroup(revision.savedAt);
      if (header != previousHeader) {
        entries.add(_NoteTimelineEntry.header(header));
        previousHeader = header;
      }
      entries.add(_NoteTimelineEntry.revision(revision));
    }
    return entries;
  }

  bool _matchesFilter(NoteRevision revision, Set<String> currentPath) {
    return switch (_filter) {
      _NoteTimelineFilter.all => true,
      _NoteTimelineFilter.currentPath => currentPath.contains(revision.id),
      _NoteTimelineFilter.branches => !currentPath.contains(revision.id),
      _NoteTimelineFilter.largeChanges => _isLargeChange(revision),
    };
  }

  bool _matchesQuery(NoteRevision revision, String query) {
    final time = _formatNoteTime(revision.savedAt).toLowerCase();
    if (time.contains(query)) return true;
    final content = _contentFor(revision).toLowerCase();
    return content.contains(query);
  }

  bool _isLargeChange(NoteRevision revision) {
    final stats = _statsFor(revision);
    return stats.addedChars + stats.removedChars >= 240 ||
        stats.addedLines + stats.removedLines >= 8;
  }

  Widget _dateHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _revisionCard(
    Note note,
    NoteRevision revision,
    Set<String> currentPath,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final content = _contentFor(revision);
    final previous = _previousContentFor(revision);
    final current = note.currentRevisionId == revision.id;
    final onCurrentPath = currentPath.contains(revision.id);
    final branchCount = widget.features.countNoteBranchRevisions(
      note.id,
      revision.id,
    );
    final preview = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(
          current
              ? Icons.radio_button_checked
              : onCurrentPath
              ? Icons.timeline
              : Icons.call_split,
          color: current
              ? scheme.primary
              : onCurrentPath
              ? scheme.secondary
              : scheme.tertiary,
        ),
        title: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(_formatNoteTime(revision.savedAt)),
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text(
                current
                    ? '当前'
                    : onCurrentPath
                    ? '当前路径'
                    : '分支',
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${_noteDiffSummary(previous, content)} · ${_noteLineDiffSummary(previous, content)} · ${preview.isEmpty ? '空笔记' : preview}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _revisionAction(
            value,
            revision,
            content,
            onCurrentPath,
            branchCount,
          ),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'open', child: Text('查看此版本')),
            const PopupMenuItem(value: 'compare', child: Text('与当前对比')),
            const PopupMenuItem(value: 'restore', child: Text('恢复为当前版本')),
            const PopupMenuItem(value: 'copy', child: Text('复制内容')),
            const PopupMenuItem(value: 'duplicate', child: Text('另存为新笔记')),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'deleteBranches',
              enabled: branchCount > 0,
              child: Text(
                branchCount > 0 ? '删除从此分出的支线 ($branchCount)' : '没有可删除的支线',
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              enabled: !onCurrentPath,
              child: Text(onCurrentPath ? '当前路径版本不能删除' : '删除版本'),
            ),
          ],
        ),
        onTap: () => widget.onOpen(revision, content),
        onLongPress: () => widget.onCompare(revision, content),
      ),
    );
  }

  void _revisionAction(
    String value,
    NoteRevision revision,
    String content,
    bool onCurrentPath,
    int branchCount,
  ) {
    switch (value) {
      case 'open':
        widget.onOpen(revision, content);
      case 'compare':
        widget.onCompare(revision, content);
      case 'restore':
        widget.onRestore(revision);
      case 'copy':
        widget.onCopy(content);
      case 'duplicate':
        widget.onDuplicate(revision, content);
      case 'deleteBranches':
        if (branchCount > 0) widget.onDeleteBranches(revision, branchCount);
      case 'delete':
        if (!onCurrentPath) widget.onDelete(revision);
    }
  }

  String _dateGroup(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(value.year, value.month, value.day);
    final difference = today.difference(day).inDays;
    if (difference == 0) return '今天';
    if (difference == 1) return '昨天';
    if (difference < 7) return '本周';
    final month = value.month.toString().padLeft(2, '0');
    final date = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$date';
  }

  String _contentFor(NoteRevision revision) {
    return _contentCache.putIfAbsent(
      revision.id,
      () =>
          widget.features.getNoteContentAtRevision(widget.note.id, revision.id),
    );
  }

  String _previousContentFor(NoteRevision revision) {
    return _previousContentCache.putIfAbsent(revision.id, () {
      final parentId = revision.parentRevisionId;
      if (parentId == null) return '';
      return widget.features.getNoteContentAtRevision(widget.note.id, parentId);
    });
  }

  _NoteDiffStats _statsFor(NoteRevision revision) {
    return _statsCache.putIfAbsent(
      revision.id,
      () =>
          _noteDiffStats(_previousContentFor(revision), _contentFor(revision)),
    );
  }

  void _removeStaleCache(List<NoteRevision> timeline) {
    final ids = timeline.map((revision) => revision.id).toSet();
    _contentCache.removeWhere((id, _) => !ids.contains(id));
    _previousContentCache.removeWhere((id, _) => !ids.contains(id));
    _statsCache.removeWhere((id, _) => !ids.contains(id));
  }
}

enum _NoteTimelineFilter { all, currentPath, branches, largeChanges }

class _NoteTimelineEntry {
  final String? header;
  final NoteRevision? revision;

  const _NoteTimelineEntry.header(this.header) : revision = null;
  const _NoteTimelineEntry.revision(this.revision) : header = null;
}
