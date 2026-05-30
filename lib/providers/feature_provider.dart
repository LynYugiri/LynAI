import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../models/schedule_item.dart';
import '../models/todo_list.dart';
import '../repositories/feature_repository.dart';
import '../services/storage_v2_service.dart';
import '../utils/file_name_utils.dart';

/// 管理功能页数据：日程、笔记、笔记修订、文件夹、修改建议和待办清单。
///
/// 这些数据共享一个 Provider，是因为工具调用和备份导入经常需要跨功能区
/// 读写。每个分区仍然使用独立存储键和独立保存队列，避免无关更新互相阻塞。
class FeatureProvider extends ChangeNotifier {
  static const _scheduleWidgetChannel = MethodChannel('lynai/schedule_widget');
  final _uuid = const Uuid();
  Future<void> _scheduleSaveQueue = Future.value();
  Future<void> _noteSaveQueue = Future.value();
  Future<void> _noteRevisionSaveQueue = Future.value();
  Future<void> _noteFolderSaveQueue = Future.value();
  Future<void> _noteEditProposalSaveQueue = Future.value();
  Future<void> _todoListSaveQueue = Future.value();

  List<ScheduleItem> _schedules = [];
  List<Note> _notes = [];
  List<NoteRevision> _noteRevisions = [];
  List<NoteFolder> _noteFolders = [];
  List<TodoList> _todoLists = [];
  final Map<String, NoteEditProposal> _noteEditProposals = {};
  final Map<String, String> _noteRevisionContentCache = {};
  final Map<String, List<NoteRevision>> _noteTimelineCache = {};
  bool _usingStorageV2 = false;
  final FeatureRepository _repository;
  Map<String, List<StorageV2NotePage>> _storageV2PagesByNoteId = {};
  Map<String, String> _activeStorageV2PageIds = {};

  FeatureProvider({StorageV2Service? storageV2, FeatureRepository? repository})
    : _repository = repository ?? FeatureRepository(storageV2: storageV2);

  List<ScheduleItem> get schedules => List.unmodifiable(_schedules);
  List<Note> get notes => List.unmodifiable(_notes);
  List<NoteRevision> get noteRevisions => List.unmodifiable(_noteRevisions);
  List<NoteFolder> get noteFolders => List.unmodifiable(_noteFolders);
  List<TodoList> get todoLists => List.unmodifiable(_todoLists);
  List<NoteEditProposal> get noteEditProposals =>
      List.unmodifiable(_noteEditProposals.values);
  bool get usingStorageV2 => _usingStorageV2;

  List<StorageV2NotePage> notePages(String noteId) {
    return List.unmodifiable(_storageV2PagesByNoteId[noteId] ?? const []);
  }

  StorageV2NotePage? activeNotePage(String noteId) {
    final pages = _storageV2PagesByNoteId[noteId] ?? const [];
    if (pages.isEmpty) return null;
    final activeId = _activeStorageV2PageIds[noteId];
    return pages.firstWhere(
      (page) => page.id == activeId,
      orElse: () => pages.first,
    );
  }

  String _noteEditProposalKey(String noteId, [String? pageId]) {
    if (!_usingStorageV2) return noteId;
    return '$noteId:${pageId ?? _activeStorageV2PageIds[noteId] ?? ''}';
  }

  Future<String> noteExportContent(String noteId) async {
    final note = getNote(noteId);
    if (note == null) return '';
    if (!_usingStorageV2) return note.content;
    final pages = _storageV2PagesByNoteId[noteId] ?? const [];
    if (pages.isEmpty) return note.content;
    final buffer = StringBuffer();
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      if (i > 0) buffer.writeln('\n\n---\n');
      buffer.writeln('<!-- page: ${page.title} -->\n');
      buffer.write(await _repository.readNotePage(page));
    }
    return buffer.toString();
  }

  Future<List<StorageV2PageExport>> notePageExports(String noteId) async {
    final note = getNote(noteId);
    if (note == null) return const [];
    if (!_usingStorageV2) {
      return [
        StorageV2PageExport(
          fileName: '${safeExportFileName(note.title, fallback: 'note')}.md',
          title: note.title,
          content: note.content,
        ),
      ];
    }
    final pages = _storageV2PagesByNoteId[noteId] ?? const [];
    final used = <String>{};
    final exports = <StorageV2PageExport>[];
    for (final page in pages) {
      var fileName = page.fileName.isEmpty
          ? '${safeExportFileName(page.title, fallback: 'page')}.md'
          : page.fileName;
      if (used.contains(fileName)) {
        final base = safeExportFileName(page.title, fallback: 'page');
        var i = 1;
        while (used.contains('${base}_$i.md')) {
          i++;
        }
        fileName = '${base}_$i.md';
      }
      used.add(fileName);
      exports.add(
        StorageV2PageExport(
          fileName: fileName,
          title: page.title,
          content: await _repository.readNotePage(page),
        ),
      );
    }
    return exports;
  }

  Future<String> readNotePageContent(StorageV2NotePage page) {
    return _repository.readNotePage(page);
  }

  Future<void> replaceStorageV2NotesData({
    required List<NoteFolder> noteFolders,
    required List<Note> notes,
    required List<StorageV2NotePage> pages,
    required Map<String, String> pageContents,
    required List<NoteRevision> noteRevisions,
    required List<NoteEditProposal> noteEditProposals,
  }) async {
    if (!_usingStorageV2) {
      await replaceFeatureData(
        noteFolders: noteFolders,
        notes: notes,
        noteRevisions: noteRevisions,
      );
      return;
    }

    final previousPagePaths = _storageV2PagesByNoteId.values
        .expand((item) => item)
        .map((page) => page.relativePath)
        .toSet();
    _noteFolders = List<NoteFolder>.from(noteFolders);
    _notes = List<Note>.from(notes);
    _noteRevisions = List<NoteRevision>.from(noteRevisions);
    _storageV2PagesByNoteId = {};
    for (final page in pages) {
      (_storageV2PagesByNoteId[page.noteId] ??= []).add(page);
    }
    for (final entry in _storageV2PagesByNoteId.entries) {
      entry.value.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    _activeStorageV2PageIds = {};
    for (var i = 0; i < _notes.length; i++) {
      final note = _notes[i];
      final notePages = _storageV2PagesByNoteId[note.id] ?? const [];
      if (notePages.isEmpty) continue;
      final activePage = notePages.firstWhere(
        (page) =>
            note.currentRevisionId != null &&
            page.currentRevisionId == note.currentRevisionId,
        orElse: () => notePages.first,
      );
      _activeStorageV2PageIds[note.id] = activePage.id;
      final content = pageContents[activePage.id] ?? note.content;
      _notes[i] = note.copyWith(content: content, preserveUpdatedAt: true);
    }
    _noteEditProposals
      ..clear()
      ..addEntries(
        noteEditProposals.map(
          (proposal) => MapEntry(
            _noteEditProposalKey(proposal.noteId, proposal.pageId),
            proposal,
          ),
        ),
      );
    _noteRevisionContentCache.clear();
    _noteTimelineCache.clear();
    _normalizeNoteRevisionState();
    _removeMissingNoteFolderReferences();

    for (final page in _storageV2PagesByNoteId.values.expand((item) => item)) {
      final content = pageContents[page.id];
      if (content == null) {
        throw StateError('Missing content for storage_v2 note page ${page.id}');
      }
      await _repository.writeNotePage(page, content);
    }
    final retainedPagePaths = _storageV2PagesByNoteId.values
        .expand((item) => item)
        .map((page) => page.relativePath)
        .toSet();
    for (final path in previousPagePaths.difference(retainedPagePaths)) {
      try {
        await _repository.deleteFile(path);
      } catch (e) {
        debugPrint('删除未引用笔记分页文件失败: $e');
      }
    }
    await _persistStorageV2NotesData();
    await _queueSaveNotes();
    await _queueSaveNoteRevisions();
    await _queueSaveNoteEditProposals();
    notifyListeners();
  }

  /// 批量替换一个或多个功能分区。
  ///
  /// 主要供备份导入使用。未传入的分区保持不变；传入的分区会立即替换内存
  /// 状态并等待对应保存队列完成后再通知 UI。
  Future<void> replaceFeatureData({
    List<ScheduleItem>? schedules,
    List<NoteFolder>? noteFolders,
    List<Note>? notes,
    List<NoteRevision>? noteRevisions,
    List<TodoList>? todoLists,
  }) async {
    final storageV2Active = await _storageV2ActiveForSave();
    final saveTasks = <Future<void>>[];
    if (schedules != null) {
      _schedules = List<ScheduleItem>.from(schedules)
        ..sort((a, b) => a.start.compareTo(b.start));
      saveTasks.add(_queueSaveSchedules());
    }
    if (noteFolders != null) {
      _noteFolders = List<NoteFolder>.from(noteFolders);
      saveTasks.add(_queueSaveNoteFolders());
    }
    if (notes != null) {
      _notes = List<Note>.from(notes);
      saveTasks.add(_queueSaveNotes());
    }
    if (noteRevisions != null) {
      _noteRevisions = List<NoteRevision>.from(noteRevisions);
      _noteRevisionContentCache.clear();
      _noteTimelineCache.clear();
      saveTasks.add(_queueSaveNoteRevisions());
    }
    if (todoLists != null) {
      _todoLists = List<TodoList>.from(todoLists);
      saveTasks.add(_queueSaveTodoLists());
    }
    if (_usingStorageV2 &&
        storageV2Active &&
        (noteFolders != null || notes != null || noteRevisions != null)) {
      await _syncStorageV2NoteFilesWithNotes();
      saveTasks.add(_persistStorageV2NotesData());
    }
    await Future.wait(saveTasks);
    notifyListeners();
  }

  NoteEditProposal? getNoteEditProposal(String noteId) {
    return _noteEditProposals[_noteEditProposalKey(noteId)];
  }

  Future<void> load() async {
    try {
      final result = await _repository.load();
      _schedules = List<ScheduleItem>.from(result.schedules);
      _notes = List<Note>.from(result.notes);
      _noteFolders = List<NoteFolder>.from(result.noteFolders);
      _noteRevisions = List<NoteRevision>.from(result.noteRevisions);
      _todoLists = List<TodoList>.from(result.todoLists);
      _usingStorageV2 = result.usingStorageV2;
      _storageV2PagesByNoteId = Map.fromEntries(
        result.pagesByNoteId.entries.map(
          (entry) =>
              MapEntry(entry.key, List<StorageV2NotePage>.from(entry.value)),
        ),
      );
      _activeStorageV2PageIds = Map<String, String>.from(result.activePageIds);
      _noteEditProposals
        ..clear()
        ..addEntries(
          result.noteEditProposals
              .where(_isUsableNoteEditProposal)
              .map(
                (proposal) => MapEntry(
                  _noteEditProposalKey(proposal.noteId, proposal.pageId),
                  proposal,
                ),
              ),
        );
      await _refreshScheduleWidget();
      await _rescheduleScheduleNotifications();
      final normalizedRevisions = _normalizeNoteRevisionState();
      final cleanedFolderRefs = _removeMissingNoteFolderReferences();
      if (normalizedRevisions) {
        await _queueSaveNoteRevisions();
      }
      if (normalizedRevisions || cleanedFolderRefs) {
        await _queueSaveNotes();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('加载功能数据失败: $e');
      _schedules = [];
      _notes = [];
      _noteRevisions = [];
      _noteFolders = [];
      _noteEditProposals.clear();
      _todoLists = [];
      notifyListeners();
    }
  }

  Future<void> _queueSaveSchedules() {
    final snapshot = List<ScheduleItem>.from(_schedules);
    _scheduleSaveQueue = _scheduleSaveQueue.then(
      (_) => _saveSchedulesSnapshot(snapshot),
    );
    return _scheduleSaveQueue;
  }

  Future<void> _saveSchedulesSnapshot(List<ScheduleItem> snapshot) async {
    try {
      final storageV2Active = await _storageV2ActiveForSave();
      if (_usingStorageV2 || storageV2Active) {
        _usingStorageV2 = _usingStorageV2 || storageV2Active;
        await _repository.saveSchedules(snapshot, usingStorageV2: true);
        await _refreshScheduleWidget();
        await _rescheduleScheduleNotifications();
        return;
      }
      await _repository.saveSchedules(snapshot, usingStorageV2: false);
      await _refreshScheduleWidget();
      await _rescheduleScheduleNotifications();
    } catch (e) {
      debugPrint('保存日程失败: $e');
    }
  }

  Future<void> _refreshScheduleWidget() async {
    if (!Platform.isAndroid) return;
    try {
      await _scheduleWidgetChannel.invokeMethod<void>('refresh');
    } catch (e) {
      debugPrint('刷新日程小组件失败: $e');
    }
  }

  Future<void> _rescheduleScheduleNotifications() async {
    if (!Platform.isAndroid) return;
    try {
      await _scheduleWidgetChannel.invokeMethod<void>(
        'rescheduleNotifications',
      );
    } catch (e) {
      debugPrint('重新安排日程通知失败: $e');
    }
  }

  Future<bool> _storageV2ActiveForSave() => _repository.isStorageV2Active();

  Future<void> _queueSaveNotes() {
    final snapshot = List<Note>.from(_notes);
    _noteSaveQueue = _noteSaveQueue.then((_) => _saveNotesSnapshot(snapshot));
    return _noteSaveQueue;
  }

  Future<void> _queueSaveNoteFolders() {
    final snapshot = List<NoteFolder>.from(_noteFolders);
    _noteFolderSaveQueue = _noteFolderSaveQueue.then(
      (_) => _saveNoteFoldersSnapshot(snapshot),
    );
    return _noteFolderSaveQueue;
  }

  Future<void> _queueSaveNoteRevisions() {
    final snapshot = List<NoteRevision>.from(_noteRevisions);
    _noteRevisionSaveQueue = _noteRevisionSaveQueue.then(
      (_) => _saveNoteRevisionsSnapshot(snapshot),
    );
    return _noteRevisionSaveQueue;
  }

  Future<void> _queueSaveNoteEditProposals() {
    final snapshot = List<NoteEditProposal>.from(_noteEditProposals.values);
    _noteEditProposalSaveQueue = _noteEditProposalSaveQueue.then(
      (_) => _saveNoteEditProposalsSnapshot(snapshot),
    );
    return _noteEditProposalSaveQueue;
  }

  Future<void> _saveNoteFoldersSnapshot(List<NoteFolder> snapshot) async {
    try {
      await _repository.saveLegacyNoteFolders(snapshot);
    } catch (e) {
      debugPrint('保存笔记文件夹失败: $e');
    }
  }

  Future<void> _saveNoteRevisionsSnapshot(List<NoteRevision> snapshot) async {
    try {
      await _repository.saveLegacyNoteRevisions(snapshot);
    } catch (e) {
      debugPrint('保存笔记时间线失败: $e');
    }
  }

  Future<void> _saveNotesSnapshot(List<Note> snapshot) async {
    try {
      await _repository.saveLegacyNotes(snapshot);
    } catch (e) {
      debugPrint('保存笔记失败: $e');
    }
  }

  Future<void> _saveNoteEditProposalsSnapshot(
    List<NoteEditProposal> snapshot,
  ) async {
    try {
      await _repository.saveLegacyNoteEditProposals(snapshot);
    } catch (e) {
      debugPrint('保存笔记修改建议失败: $e');
    }
  }

  bool _isUsableNoteEditProposal(NoteEditProposal proposal) {
    if (proposal.blocks.isEmpty || proposal.baseContentHash.isEmpty) {
      return false;
    }
    final note = getNote(proposal.noteId);
    if (note == null) return false;
    final baseRevisionId = proposal.baseRevisionId;
    if (baseRevisionId != null) {
      final revision = getNoteRevision(baseRevisionId);
      if (revision == null || revision.noteId != proposal.noteId) return false;
    }
    if (_usingStorageV2 && proposal.pageId != null) {
      final pages = _storageV2PagesByNoteId[proposal.noteId] ?? const [];
      if (!pages.any((page) => page.id == proposal.pageId)) return false;
    }
    return true;
  }

  bool _removeMissingNoteFolderReferences() {
    final folderIds = _noteFolders.map((folder) => folder.id).toSet();
    var changed = false;
    _notes = _notes.map((note) {
      final folderId = note.folderId;
      if (folderId == null || folderIds.contains(folderId)) return note;
      changed = true;
      return note.copyWith(folderId: null, preserveUpdatedAt: true);
    }).toList();
    return changed;
  }

  Future<void> selectNotePage(String noteId, String pageId) async {
    if (!_usingStorageV2) return;
    final pages = _storageV2PagesByNoteId[noteId] ?? const [];
    final pageIndex = pages.indexWhere((page) => page.id == pageId);
    if (pageIndex == -1) return;
    final page = pages[pageIndex];
    final index = _notes.indexWhere((note) => note.id == noteId);
    if (index == -1) return;
    final content = await _repository.readNotePage(page);
    _activeStorageV2PageIds[noteId] = page.id;
    _notes[index] = _notes[index].copyWith(
      content: content,
      currentRevisionId: page.currentRevisionId,
      preserveUpdatedAt: true,
    );
    _clearNoteTimelineCache(noteId);
    await _persistStorageV2NotesData();
    notifyListeners();
  }

  Future<String?> addNotePage(String noteId, String title) async {
    if (!_usingStorageV2) return null;
    final note = getNote(noteId);
    if (note == null) return null;
    final pages = _storageV2PagesByNoteId[noteId] ??= [];
    final usedFileNames = pages.map((page) => page.fileName).toSet();
    final base = safeExportFileName(title, fallback: 'page');
    var fileName = '$base.md';
    var suffix = 1;
    while (usedFileNames.contains(fileName)) {
      fileName = '${base}_$suffix.md';
      suffix++;
    }
    final now = DateTime.now();
    final noteDirectoryName = safeStorageSegment(noteId, fallback: 'note');
    final activePageId = _activeStorageV2PageIds[noteId];
    final activeIndex = pages.indexWhere((page) => page.id == activePageId);
    final insertIndex = activeIndex == -1 ? pages.length : activeIndex + 1;
    final page = StorageV2NotePage(
      id: '${noteId}_page_${_uuid.v4()}',
      noteId: noteId,
      title: title,
      fileName: fileName,
      relativePath: 'notes/$noteDirectoryName/$fileName',
      currentRevisionId: null,
      sortOrder: insertIndex,
      createdAt: now,
      updatedAt: now,
    );
    pages.insert(insertIndex, page);
    _renumberNotePages(pages);
    _activeStorageV2PageIds[noteId] = page.id;
    final content = page.title.isEmpty ? '' : '# ${page.title}\n';
    await _repository.writeNotePage(page, content);
    final index = _notes.indexWhere((item) => item.id == noteId);
    if (index != -1) {
      _notes[index] = note.copyWith(content: content, currentRevisionId: null);
    }
    await _persistStorageV2NotesData();
    await _queueSaveNotes();
    notifyListeners();
    return page.id;
  }

  Future<void> renameNotePage(
    String noteId,
    String pageId,
    String title,
  ) async {
    if (!_usingStorageV2) return;
    final pages = _storageV2PagesByNoteId[noteId];
    if (pages == null) return;
    final index = pages.indexWhere((page) => page.id == pageId);
    if (index == -1) return;
    final page = pages[index];
    pages[index] = StorageV2NotePage(
      id: page.id,
      noteId: page.noteId,
      title: title,
      fileName: page.fileName,
      relativePath: page.relativePath,
      currentRevisionId: page.currentRevisionId,
      sortOrder: page.sortOrder,
      createdAt: page.createdAt,
      updatedAt: DateTime.now(),
    );
    await _persistStorageV2NotesData();
    notifyListeners();
  }

  Future<bool> moveNotePage(String noteId, String pageId, int delta) async {
    if (!_usingStorageV2 || delta == 0) return false;
    final pages = _storageV2PagesByNoteId[noteId];
    if (pages == null) return false;
    final index = pages.indexWhere((page) => page.id == pageId);
    if (index == -1) return false;
    final target = (index + delta).clamp(0, pages.length - 1);
    if (target == index) return false;
    final page = pages.removeAt(index);
    pages.insert(target, page);
    _renumberNotePages(pages);
    await _persistStorageV2NotesData();
    notifyListeners();
    return true;
  }

  Future<bool> deleteNotePage(String noteId, String pageId) async {
    if (!_usingStorageV2) return false;
    final pages = _storageV2PagesByNoteId[noteId];
    if (pages == null || pages.length <= 1) return false;
    final index = pages.indexWhere((page) => page.id == pageId);
    if (index == -1) return false;
    final removed = pages.removeAt(index);
    _renumberNotePages(pages);
    if (_activeStorageV2PageIds[noteId] == pageId) {
      final nextIndex = index >= pages.length ? pages.length - 1 : index;
      final nextPage = pages[nextIndex];
      _activeStorageV2PageIds[noteId] = nextPage.id;
      final noteIndex = _notes.indexWhere((note) => note.id == noteId);
      if (noteIndex != -1) {
        _notes[noteIndex] = _notes[noteIndex].copyWith(
          content: await _repository.readNotePage(nextPage),
          currentRevisionId: nextPage.currentRevisionId,
          preserveUpdatedAt: true,
        );
      }
      _clearNoteTimelineCache(noteId);
    }
    _noteEditProposals.remove(_noteEditProposalKey(noteId, removed.id));
    final removedRevisionIds = _noteRevisions
        .where(
          (revision) =>
              revision.noteId == noteId && revision.pageId == removed.id,
        )
        .map((revision) => revision.id)
        .toSet();
    _noteRevisions.removeWhere(
      (revision) => removedRevisionIds.contains(revision.id),
    );
    _noteRevisionContentCache.removeWhere(
      (revisionId, _) => removedRevisionIds.contains(revisionId),
    );
    _clearNoteTimelineCache(noteId);
    try {
      await _repository.deleteFile(removed.relativePath);
    } catch (_) {}
    await _persistStorageV2NotesData();
    await _queueSaveNotes();
    await _queueSaveNoteRevisions();
    notifyListeners();
    return true;
  }

  void _renumberNotePages(List<StorageV2NotePage> pages) {
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      pages[i] = StorageV2NotePage(
        id: page.id,
        noteId: page.noteId,
        title: page.title,
        fileName: page.fileName,
        relativePath: page.relativePath,
        currentRevisionId: page.currentRevisionId,
        sortOrder: i,
        createdAt: page.createdAt,
        updatedAt: page.updatedAt,
      );
    }
  }

  Future<void> _persistStorageV2CurrentPageContent(
    String noteId,
    String content,
    String? currentRevisionId,
  ) async {
    if (!_usingStorageV2) return;
    final page = activeNotePage(noteId);
    if (page == null) return;
    await _repository.writeNotePage(page, content);
    final pages = _storageV2PagesByNoteId[noteId];
    if (pages == null) return;
    final index = pages.indexWhere((item) => item.id == page.id);
    if (index == -1) return;
    pages[index] = StorageV2NotePage(
      id: page.id,
      noteId: page.noteId,
      title: page.title,
      fileName: page.fileName,
      relativePath: page.relativePath,
      currentRevisionId: currentRevisionId,
      sortOrder: page.sortOrder,
      createdAt: page.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _syncStorageV2NoteFilesWithNotes() async {
    final noteIds = _notes.map((note) => note.id).toSet();
    _storageV2PagesByNoteId.removeWhere(
      (noteId, _) => !noteIds.contains(noteId),
    );
    _activeStorageV2PageIds.removeWhere(
      (noteId, _) => !noteIds.contains(noteId),
    );
    for (final note in _notes) {
      final pages = _storageV2PagesByNoteId[note.id];
      StorageV2NotePage page;
      if (pages == null || pages.isEmpty) {
        final now = DateTime.now();
        final fileName =
            '${safeExportFileName(note.title, fallback: 'note')}.md';
        final noteDirectoryName = safeStorageSegment(note.id, fallback: 'note');
        page = StorageV2NotePage(
          id: '${note.id}_page_0',
          noteId: note.id,
          title: note.title.isEmpty ? '未命名分页' : note.title,
          fileName: fileName,
          relativePath: 'notes/$noteDirectoryName/$fileName',
          currentRevisionId: note.currentRevisionId,
          sortOrder: 0,
          createdAt: note.createdAt,
          updatedAt: now,
        );
        _storageV2PagesByNoteId[note.id] = [page];
      } else {
        final activeId = _activeStorageV2PageIds[note.id];
        page = pages.firstWhere(
          (item) => item.id == activeId,
          orElse: () => pages.first,
        );
      }
      _activeStorageV2PageIds[note.id] = page.id;
      await _repository.writeNotePage(page, note.content);
    }
  }

  Future<void> _persistStorageV2NotesData() async {
    if (!_usingStorageV2) return;
    final proposalRows = <Map<String, dynamic>>[];
    final proposalBlockRows = <Map<String, dynamic>>[];
    for (final proposal in _noteEditProposals.values) {
      proposalRows.add({
        'id': proposal.id,
        'noteId': proposal.noteId,
        if (proposal.pageId != null) 'pageId': proposal.pageId,
        if (proposal.baseRevisionId != null)
          'baseRevisionId': proposal.baseRevisionId,
        'baseContentHash': proposal.baseContentHash,
        'createdAt': proposal.createdAt.toIso8601String(),
      });
      for (var i = 0; i < proposal.blocks.length; i++) {
        final block = proposal.blocks[i];
        proposalBlockRows.add({
          'id': block.id,
          'proposalId': proposal.id,
          'startLine': block.startLine,
          'deleteCount': block.deleteCount,
          'deletedLines': block.deletedLines,
          'insertLines': block.insertLines,
          'sortOrder': i,
        });
      }
    }
    final data = <String, dynamic>{
      'folders': _noteFolders.indexed.map((entry) {
        return {...entry.$2.toJson(), 'sortOrder': entry.$1};
      }).toList(),
      'notes': _notes.indexed.map((entry) {
        final note = entry.$2;
        return {
          'id': note.id,
          'title': note.title,
          if (note.folderId != null) 'folderId': note.folderId,
          if (note.currentRevisionId != null)
            'currentRevisionId': note.currentRevisionId,
          'currentPageId': _activeStorageV2PageIds[note.id],
          'createdAt': note.createdAt.toIso8601String(),
          'updatedAt': note.updatedAt.toIso8601String(),
          'wrap': note.wrap,
          'sortOrder': entry.$1,
        };
      }).toList(),
      'pages': _storageV2PagesByNoteId.values
          .expand((pages) => pages)
          .map((page) => page.toJson())
          .toList(),
      'revisions': _noteRevisions.map((revision) {
        return {
          'id': revision.id,
          'noteId': revision.noteId,
          if (revision.pageId != null) 'pageId': revision.pageId,
          if (revision.parentRevisionId != null)
            'parentRevisionId': revision.parentRevisionId,
          'savedAt': revision.savedAt.toIso8601String(),
          'deltaStart': revision.delta.start,
          'deletedText': revision.delta.deletedText,
          'insertedText': revision.delta.insertedText,
        };
      }).toList(),
      'editProposals': proposalRows,
      'editBlocks': proposalBlockRows,
    };
    await _repository.saveStorageV2NotesData(data);
  }

  Future<void> _queueSaveTodoLists() {
    final snapshot = List<TodoList>.from(_todoLists);
    _todoListSaveQueue = _todoListSaveQueue.then(
      (_) => _saveTodoListsSnapshot(snapshot),
    );
    return _todoListSaveQueue;
  }

  Future<void> _saveTodoListsSnapshot(List<TodoList> snapshot) async {
    try {
      final storageV2Active = await _storageV2ActiveForSave();
      _usingStorageV2 = _usingStorageV2 || storageV2Active;
      await _repository.saveTodoLists(
        snapshot,
        usingStorageV2: _usingStorageV2,
      );
    } catch (e) {
      debugPrint('保存待办清单失败: $e');
    }
  }

  Future<String> addSchedule(
    String title,
    DateTime start,
    DateTime end, {
    String? note,
    String kind = ScheduleItem.kindSchedule,
  }) async {
    final effectiveEnd = kind == ScheduleItem.kindTask
        ? start.add(const Duration(minutes: 1))
        : end;
    final schedule = ScheduleItem(
      id: _uuid.v4(),
      title: title,
      start: start,
      end: effectiveEnd,
      note: note,
      kind: kind,
    );
    _schedules.add(schedule);
    _schedules.sort((a, b) => a.start.compareTo(b.start));
    await _queueSaveSchedules();
    notifyListeners();
    return schedule.id;
  }

  Future<void> updateSchedule(ScheduleItem schedule) async {
    final index = _schedules.indexWhere((s) => s.id == schedule.id);
    if (index == -1) return;
    _schedules[index] = schedule;
    _schedules.sort((a, b) => a.start.compareTo(b.start));
    await _queueSaveSchedules();
    notifyListeners();
  }

  Future<void> deleteSchedule(String id) async {
    final before = _schedules.length;
    _schedules.removeWhere((s) => s.id == id);
    if (_schedules.length == before) return;
    await _queueSaveSchedules();
    notifyListeners();
  }

  ScheduleItem? getSchedule(String id) {
    try {
      return _schedules.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<String> addNote(String title, {String? folderId}) {
    return addNoteWithContent(title, '', folderId: folderId);
  }

  Future<String> addNoteWithContent(
    String title,
    String content, {
    String? folderId,
  }) async {
    final now = DateTime.now();
    final initialRevision = content.isEmpty
        ? null
        : NoteRevision(
            id: _uuid.v4(),
            noteId: '',
            parentRevisionId: null,
            savedAt: now,
            delta: NoteTextDelta.between('', content),
          );
    final note = Note(
      id: _uuid.v4(),
      title: title,
      content: content,
      currentRevisionId: initialRevision?.id,
      folderId: _noteFolders.any((f) => f.id == folderId) ? folderId : null,
      createdAt: now,
      updatedAt: now,
    );
    if (initialRevision != null) {
      _noteRevisions.insert(
        0,
        NoteRevision(
          id: initialRevision.id,
          noteId: note.id,
          pageId: _usingStorageV2 ? '${note.id}_page_0' : null,
          parentRevisionId: null,
          savedAt: now,
          delta: initialRevision.delta,
        ),
      );
      _noteRevisionContentCache[initialRevision.id] = content;
    }
    _notes.insert(0, note);
    if (_usingStorageV2) {
      final pageId = '${note.id}_page_0';
      final fileName = '${safeExportFileName(title, fallback: 'note')}.md';
      final noteDirectoryName = safeStorageSegment(note.id, fallback: 'note');
      final page = StorageV2NotePage(
        id: pageId,
        noteId: note.id,
        title: title.isEmpty ? '未命名分页' : title,
        fileName: fileName,
        relativePath: 'notes/$noteDirectoryName/$fileName',
        currentRevisionId: note.currentRevisionId,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      );
      _storageV2PagesByNoteId[note.id] = [page];
      _activeStorageV2PageIds[note.id] = pageId;
      await _repository.writeNotePage(page, content);
      await _persistStorageV2NotesData();
    }
    await _queueSaveNotes();
    if (initialRevision != null) await _queueSaveNoteRevisions();
    notifyListeners();
    return note.id;
  }

  Note? getNote(String id) {
    try {
      return _notes.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  NoteRevision? getNoteRevision(String revisionId) {
    try {
      return _noteRevisions.firstWhere((revision) => revision.id == revisionId);
    } catch (_) {
      return null;
    }
  }

  List<NoteRevision> getNoteTimeline(String noteId) {
    final cached = _noteTimelineCache[noteId];
    if (cached != null) return List.unmodifiable(cached);
    final revisions = _noteRevisions
        .where((revision) => _isRevisionVisibleForActivePage(noteId, revision))
        .toList();
    revisions.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    _noteTimelineCache[noteId] = List.unmodifiable(revisions);
    return List.unmodifiable(revisions);
  }

  Set<String> getNoteCurrentRevisionPath(String noteId) {
    final note = getNote(noteId);
    return _noteRevisionPath(noteId, note?.currentRevisionId);
  }

  Set<String> _noteRevisionPath(String noteId, String? currentRevisionId) {
    if (currentRevisionId == null) return const <String>{};
    final path = <String>{};
    String? revisionId = currentRevisionId;
    while (revisionId != null && path.add(revisionId)) {
      final revision = getNoteRevision(revisionId);
      if (revision == null || revision.noteId != noteId) break;
      revisionId = revision.parentRevisionId;
    }
    return path;
  }

  Set<String> _allProtectedNoteRevisionIds(String noteId) {
    final protected = <String>{...getNoteCurrentRevisionPath(noteId)};
    for (final page in _storageV2PagesByNoteId[noteId] ?? const []) {
      protected.addAll(_noteRevisionPath(noteId, page.currentRevisionId));
    }
    return protected;
  }

  bool _isRevisionVisibleForActivePage(String noteId, NoteRevision revision) {
    if (revision.noteId != noteId) return false;
    if (!_usingStorageV2) return true;
    final activePageId = _activeStorageV2PageIds[noteId];
    return revision.pageId == null || revision.pageId == activePageId;
  }

  String getNoteContentAtRevision(String noteId, String? revisionId) {
    if (revisionId == null) {
      return getNote(noteId)?.content ?? '';
    }
    return _getNoteContentAtRevision(noteId, revisionId, <String>{});
  }

  String _getNoteContentAtRevision(
    String noteId,
    String revisionId,
    Set<String> visited,
  ) {
    if (!visited.add(revisionId)) return '';
    final cached = _noteRevisionContentCache[revisionId];
    if (cached != null) return cached;
    final revision = getNoteRevision(revisionId);
    if (revision == null || revision.noteId != noteId) return '';
    final parentContent = revision.parentRevisionId == null
        ? ''
        : _getNoteContentAtRevision(
            noteId,
            revision.parentRevisionId!,
            visited,
          );
    final content = revision.delta.apply(parentContent);
    _noteRevisionContentCache[revisionId] = content;
    return content;
  }

  bool _normalizeNoteRevisionState() {
    final revisionById = {
      for (final revision in _noteRevisions) revision.id: revision,
    };
    final validChainCache = <String, bool>{};
    final previousRevisionCount = _noteRevisions.length;
    var notesChanged = false;

    bool hasValidChain(String revisionId, Set<String> visiting) {
      final cached = validChainCache[revisionId];
      if (cached != null) return cached;
      final revision = revisionById[revisionId];
      if (revision == null) return validChainCache[revisionId] = false;
      if (!visiting.add(revisionId)) return validChainCache[revisionId] = false;
      final parentId = revision.parentRevisionId;
      if (parentId == null) {
        visiting.remove(revisionId);
        return validChainCache[revisionId] = true;
      }
      final parent = revisionById[parentId];
      final valid =
          parent != null &&
          parent.noteId == revision.noteId &&
          hasValidChain(parentId, visiting);
      visiting.remove(revisionId);
      return validChainCache[revisionId] = valid;
    }

    _noteRevisions = _noteRevisions
        .where((revision) => hasValidChain(revision.id, <String>{}))
        .toList();
    _notes = _notes.map((note) {
      final currentRevisionId = note.currentRevisionId;
      final activePageId = _usingStorageV2
          ? _activeStorageV2PageIds[note.id]
          : null;
      if (currentRevisionId == null ||
          _revisionBelongsToPage(note.id, currentRevisionId, activePageId)) {
        return note;
      }
      notesChanged = true;
      return note.copyWith(currentRevisionId: null, preserveUpdatedAt: true);
    }).toList();
    _storageV2PagesByNoteId.updateAll((_, pages) {
      return pages.map((page) {
        final currentRevisionId = page.currentRevisionId;
        if (currentRevisionId == null ||
            _revisionBelongsToPage(page.noteId, currentRevisionId, page.id)) {
          return page;
        }
        notesChanged = true;
        return StorageV2NotePage(
          id: page.id,
          noteId: page.noteId,
          title: page.title,
          fileName: page.fileName,
          relativePath: page.relativePath,
          currentRevisionId: null,
          sortOrder: page.sortOrder,
          createdAt: page.createdAt,
          updatedAt: page.updatedAt,
        );
      }).toList();
    });
    _noteRevisionContentCache.clear();
    _noteTimelineCache.clear();
    return _noteRevisions.length != previousRevisionCount || notesChanged;
  }

  bool _revisionBelongsToPage(
    String noteId,
    String revisionId,
    String? pageId,
  ) {
    final revision = getNoteRevision(revisionId);
    if (revision == null || revision.noteId != noteId) return false;
    if (!_usingStorageV2) return true;
    return revision.pageId == null || revision.pageId == pageId;
  }

  void _clearNoteTimelineCache(String noteId) {
    _noteTimelineCache.remove(noteId);
  }

  Future<NoteRevision?> saveNoteContent(
    String noteId,
    String content, {
    String? baseRevisionId,
  }) async {
    final index = _notes.indexWhere((note) => note.id == noteId);
    if (index == -1) return null;
    final note = _notes[index];
    final currentParentRevision = note.currentRevisionId == null
        ? null
        : getNoteRevision(note.currentRevisionId!);
    final currentParentRevisionId =
        currentParentRevision != null &&
            _isRevisionVisibleForActivePage(noteId, currentParentRevision)
        ? note.currentRevisionId
        : null;
    final requestedParentRevisionId = baseRevisionId ?? currentParentRevisionId;
    final requestedParent = requestedParentRevisionId == null
        ? null
        : getNoteRevision(requestedParentRevisionId);
    var parentRevisionId =
        requestedParent != null &&
            _isRevisionVisibleForActivePage(noteId, requestedParent)
        ? requestedParentRevisionId
        : currentParentRevisionId;
    var baseContent = parentRevisionId == null
        ? note.content
        : getNoteContentAtRevision(noteId, parentRevisionId);
    NoteRevision? bootstrappedRoot;

    if (parentRevisionId == null && note.content.isNotEmpty) {
      final now = DateTime.now();
      final activePageId = _usingStorageV2
          ? _activeStorageV2PageIds[note.id]
          : null;
      final rootRevision = NoteRevision(
        id: _uuid.v4(),
        noteId: note.id,
        pageId: activePageId,
        parentRevisionId: null,
        savedAt: now,
        delta: NoteTextDelta.between('', note.content),
      );
      bootstrappedRoot = rootRevision;
      _noteRevisions.insert(0, rootRevision);
      _noteRevisionContentCache[rootRevision.id] = note.content;
      _clearNoteTimelineCache(note.id);
      parentRevisionId = rootRevision.id;
      baseContent = note.content;
      _notes[index] = note.copyWith(
        currentRevisionId: rootRevision.id,
        preserveUpdatedAt: true,
      );
    }

    final currentRevisionId = _notes[index].currentRevisionId;
    if (baseRevisionId == currentRevisionId && note.content == content) {
      if (bootstrappedRoot != null) {
        await _persistStorageV2CurrentPageContent(
          note.id,
          note.content,
          bootstrappedRoot.id,
        );
        await _persistStorageV2NotesData();
        await _queueSaveNoteRevisions();
        await _queueSaveNotes();
        notifyListeners();
      }
      return currentRevisionId == null
          ? null
          : getNoteRevision(currentRevisionId);
    }
    if (baseRevisionId != null &&
        baseContent == content &&
        currentRevisionId == baseRevisionId) {
      return getNoteRevision(baseRevisionId);
    }
    if (baseRevisionId == null &&
        currentRevisionId != null &&
        baseContent == content) {
      if (bootstrappedRoot != null) {
        await _persistStorageV2CurrentPageContent(
          note.id,
          note.content,
          bootstrappedRoot.id,
        );
        await _persistStorageV2NotesData();
        await _queueSaveNoteRevisions();
        await _queueSaveNotes();
        notifyListeners();
      }
      return getNoteRevision(currentRevisionId);
    }

    final now = DateTime.now();
    final revision = NoteRevision(
      id: _uuid.v4(),
      noteId: note.id,
      pageId: _usingStorageV2 ? _activeStorageV2PageIds[note.id] : null,
      parentRevisionId: parentRevisionId,
      savedAt: now,
      delta: NoteTextDelta.between(baseContent, content),
    );
    _noteRevisions.insert(0, revision);
    _noteRevisionContentCache[revision.id] = content;
    _clearNoteTimelineCache(note.id);
    final removedProposal =
        _noteEditProposals.remove(_noteEditProposalKey(note.id)) != null;
    _notes[index] = note.copyWith(
      content: content,
      currentRevisionId: revision.id,
    );
    await _persistStorageV2CurrentPageContent(note.id, content, revision.id);
    await _persistStorageV2NotesData();
    await _queueSaveNoteRevisions();
    await _queueSaveNotes();
    if (removedProposal) await _queueSaveNoteEditProposals();
    notifyListeners();
    return revision;
  }

  Future<void> updateNote(Note note) async {
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index == -1) return;
    final contentChanged = _notes[index].content != note.content;
    final removedProposal =
        contentChanged &&
        _noteEditProposals.remove(_noteEditProposalKey(note.id)) != null;
    _notes[index] = note;
    if (contentChanged) {
      await _persistStorageV2CurrentPageContent(
        note.id,
        note.content,
        note.currentRevisionId,
      );
    }
    await _persistStorageV2NotesData();
    await _queueSaveNotes();
    if (removedProposal) await _queueSaveNoteEditProposals();
    notifyListeners();
  }

  Future<void> reorderNotesInFolder(
    String? folderId,
    int oldIndex,
    int newIndex,
  ) async {
    final indexes = <int>[];
    for (var i = 0; i < _notes.length; i++) {
      if (_notes[i].folderId == folderId) indexes.add(i);
    }
    if (oldIndex < 0 || oldIndex >= indexes.length) return;
    if (newIndex < 0 || newIndex > indexes.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final folderNotes = indexes.map((i) => _notes[i]).toList();
    final note = folderNotes.removeAt(oldIndex);
    folderNotes.insert(newIndex, note);
    for (var i = 0; i < indexes.length; i++) {
      _notes[indexes[i]] = folderNotes[i];
    }
    await _persistStorageV2NotesData();
    await _queueSaveNotes();
    notifyListeners();
  }

  Future<void> deleteNote(String id) async {
    final before = _notes.length;
    _notes.removeWhere((n) => n.id == id);
    if (_notes.length == before) return;
    final deletedRevisionIds = _noteRevisions
        .where((revision) => revision.noteId == id)
        .map((revision) => revision.id)
        .toSet();
    _noteRevisions.removeWhere((revision) => revision.noteId == id);
    _clearNoteTimelineCache(id);
    final beforeProposalCount = _noteEditProposals.length;
    _noteEditProposals.removeWhere((_, proposal) => proposal.noteId == id);
    final removedProposal = _noteEditProposals.length != beforeProposalCount;
    _noteRevisionContentCache.removeWhere(
      (revisionId, _) => deletedRevisionIds.contains(revisionId),
    );
    final removedPages = _storageV2PagesByNoteId.remove(id) ?? const [];
    _activeStorageV2PageIds.remove(id);
    for (final page in removedPages) {
      try {
        await _repository.deleteFile(page.relativePath);
      } catch (e) {
        debugPrint('删除笔记分页文件失败: $e');
      }
    }
    await _persistStorageV2NotesData();
    await _queueSaveNotes();
    await _queueSaveNoteRevisions();
    if (removedProposal) await _queueSaveNoteEditProposals();
    notifyListeners();
  }

  Future<NoteRevision?> restoreNoteRevision(
    String noteId,
    String revisionId,
  ) async {
    final revision = getNoteRevision(revisionId);
    if (revision == null || revision.noteId != noteId) return null;
    final content = getNoteContentAtRevision(noteId, revisionId);
    return saveNoteContent(noteId, content, baseRevisionId: revisionId);
  }

  Future<bool> deleteNoteRevision(String noteId, String revisionId) async {
    final revision = getNoteRevision(revisionId);
    if (revision == null || revision.noteId != noteId) return false;
    if (_allProtectedNoteRevisionIds(noteId).contains(revisionId)) return false;
    return _deleteNoteRevisionSet(noteId, {revisionId});
  }

  int countNoteBranchRevisions(String noteId, String parentRevisionId) {
    final currentPath = _allProtectedNoteRevisionIds(noteId);
    final branchRoots = _noteRevisions
        .where(
          (revision) =>
              revision.noteId == noteId &&
              revision.parentRevisionId == parentRevisionId &&
              !currentPath.contains(revision.id),
        )
        .map((revision) => revision.id)
        .toSet();
    if (branchRoots.isEmpty) return 0;
    return _collectRevisionDescendants(noteId, branchRoots).length;
  }

  Future<int> deleteNoteBranchesFromRevision(
    String noteId,
    String parentRevisionId,
  ) async {
    final parent = getNoteRevision(parentRevisionId);
    if (parent == null || parent.noteId != noteId) return 0;
    final currentPath = _allProtectedNoteRevisionIds(noteId);
    final branchRoots = _noteRevisions
        .where(
          (revision) =>
              revision.noteId == noteId &&
              revision.parentRevisionId == parentRevisionId &&
              !currentPath.contains(revision.id),
        )
        .map((revision) => revision.id)
        .toSet();
    if (branchRoots.isEmpty) return 0;
    final descendants = _collectRevisionDescendants(noteId, branchRoots);
    final deleted = await _deleteNoteRevisionSet(noteId, descendants);
    return deleted ? descendants.length : 0;
  }

  Set<String> _collectRevisionDescendants(String noteId, Set<String> roots) {
    final descendants = <String>{...roots};
    var changed = true;
    while (changed) {
      changed = false;
      for (final item in _noteRevisions) {
        final parentId = item.parentRevisionId;
        if (item.noteId == noteId &&
            parentId != null &&
            descendants.contains(parentId) &&
            descendants.add(item.id)) {
          changed = true;
        }
      }
    }
    return descendants;
  }

  Future<bool> _deleteNoteRevisionSet(
    String noteId,
    Set<String> revisionIds,
  ) async {
    if (revisionIds.isEmpty) return false;
    final currentPath = _allProtectedNoteRevisionIds(noteId);
    if (revisionIds.any(currentPath.contains)) return false;
    final descendants = _collectRevisionDescendants(noteId, revisionIds);
    if (descendants.any(currentPath.contains)) return false;
    _noteRevisions.removeWhere((item) => descendants.contains(item.id));
    _noteRevisionContentCache.removeWhere((id, _) => descendants.contains(id));
    _clearNoteTimelineCache(noteId);
    await _persistStorageV2NotesData();
    await _queueSaveNoteRevisions();
    notifyListeners();
    return true;
  }

  Future<void> setNoteEditProposal(NoteEditProposal proposal) async {
    _noteEditProposals[_noteEditProposalKey(proposal.noteId, proposal.pageId)] =
        proposal;
    await _persistStorageV2NotesData();
    await _queueSaveNoteEditProposals();
    notifyListeners();
  }

  Future<void> removeNoteEditProposal(String noteId) async {
    if (_noteEditProposals.remove(_noteEditProposalKey(noteId)) == null) return;
    await _persistStorageV2NotesData();
    await _queueSaveNoteEditProposals();
    notifyListeners();
  }

  Future<String> addNoteFolder(String title) async {
    final now = DateTime.now();
    final folder = NoteFolder(
      id: _uuid.v4(),
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    _noteFolders.insert(0, folder);
    await _persistStorageV2NotesData();
    await _queueSaveNoteFolders();
    notifyListeners();
    return folder.id;
  }

  NoteFolder? getNoteFolder(String id) {
    try {
      return _noteFolders.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateNoteFolder(NoteFolder folder) async {
    final index = _noteFolders.indexWhere((f) => f.id == folder.id);
    if (index == -1) return;
    _noteFolders[index] = folder;
    await _persistStorageV2NotesData();
    await _queueSaveNoteFolders();
    notifyListeners();
  }

  Future<void> reorderNoteFolders(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _noteFolders.length) return;
    if (newIndex < 0 || newIndex > _noteFolders.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final folder = _noteFolders.removeAt(oldIndex);
    _noteFolders.insert(newIndex, folder);
    await _persistStorageV2NotesData();
    await _queueSaveNoteFolders();
    notifyListeners();
  }

  Future<void> deleteNoteFolder(String id) async {
    final before = _noteFolders.length;
    _noteFolders.removeWhere((f) => f.id == id);
    if (_noteFolders.length == before) return;
    _notes = _notes
        .map(
          (note) => note.folderId == id ? note.copyWith(folderId: null) : note,
        )
        .toList();
    await _persistStorageV2NotesData();
    await _queueSaveNoteFolders();
    await _queueSaveNotes();
    notifyListeners();
  }

  Future<String> addTodoList(String title) {
    return addTodoListWithItems(title, <TodoItem>[]);
  }

  Future<String> addTodoListWithItems(
    String title,
    List<TodoItem> items,
  ) async {
    final now = DateTime.now();
    final list = TodoList(
      id: _uuid.v4(),
      title: title,
      items: items,
      createdAt: now,
      updatedAt: now,
    );
    _todoLists.insert(0, list);
    await _queueSaveTodoLists();
    notifyListeners();
    return list.id;
  }

  TodoList? getTodoList(String id) {
    try {
      return _todoLists.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> updateTodoList(TodoList list) async {
    final index = _todoLists.indexWhere((n) => n.id == list.id);
    if (index == -1) return;
    _todoLists[index] = list;
    await _queueSaveTodoLists();
    notifyListeners();
  }

  Future<void> reorderTodoLists(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _todoLists.length) return;
    if (newIndex < 0 || newIndex > _todoLists.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final item = _todoLists.removeAt(oldIndex);
    _todoLists.insert(newIndex, item);
    await _queueSaveTodoLists();
    notifyListeners();
  }

  Future<void> deleteTodoList(String id) async {
    final before = _todoLists.length;
    _todoLists.removeWhere((n) => n.id == id);
    if (_todoLists.length == before) return;
    await _queueSaveTodoLists();
    notifyListeners();
  }
}

class StorageV2PageExport {
  final String fileName;
  final String title;
  final String content;

  const StorageV2PageExport({
    required this.fileName,
    required this.title,
    required this.content,
  });
}
