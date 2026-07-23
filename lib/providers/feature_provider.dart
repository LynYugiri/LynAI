import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../models/merge_models.dart';
import '../models/recycle_bin_item.dart';
import '../repositories/feature_repository.dart';
import '../repositories/recycle_bin_repository.dart';
import '../services/storage_v2_service.dart';
import '../services/note_revision_merge.dart';
import '../utils/file_name_utils.dart';

/// 管理笔记、笔记分页、修订、文件夹和修改建议。
class FeatureProvider extends ChangeNotifier {
  final _uuid = const Uuid();
  Future<void> _notesDataSaveQueue = Future.value();
  Future<void> _pendingNotesDataSave = Future.value();

  List<Note> _notes = [];
  List<NoteRevision> _noteRevisions = [];
  List<NoteFolder> _noteFolders = [];
  final Map<String, NoteEditProposal> _noteEditProposals = {};
  final Map<String, NoteRevisionContent> _noteRevisionContentCache = {};
  final Map<String, List<NoteRevision>> _noteTimelineCache = {};
  Map<String, NotePageHeads> _notePageHeads = {};
  List<Map<String, dynamic>> _notePageTombstones = [];
  Map<String, NotePageConflict> _notePageConflicts = {};
  bool _usingStorageV2 = false;
  final FeatureRepository _repository;
  final RecycleBinRepository _recycleBinRepository;
  final Future<String> Function() _authorDeviceId;
  Map<String, List<StorageV2NotePage>> _storageV2PagesByNoteId = {};
  Map<String, String> _activeStorageV2PageIds = {};

  FeatureProvider({
    StorageV2Service? storageV2,
    FeatureRepository? repository,
    RecycleBinRepository? recycleBinRepository,
    Future<String> Function()? authorDeviceId,
  }) : _repository = repository ?? FeatureRepository(storageV2: storageV2),
       _recycleBinRepository =
           recycleBinRepository ?? RecycleBinRepository(storageV2: storageV2),
       _authorDeviceId = authorDeviceId ?? (() async => 'local');

  List<Note> get notes => List.unmodifiable(_notes);
  List<NoteRevision> get noteRevisions => List.unmodifiable(_noteRevisions);
  List<NoteFolder> get noteFolders => List.unmodifiable(_noteFolders);
  List<NoteEditProposal> get noteEditProposals =>
      List.unmodifiable(_noteEditProposals.values);
  bool get usingStorageV2 => _usingStorageV2;

  NotePageHeads? notePageHeads(String pageId) => _notePageHeads[pageId];
  NotePageConflict? notePageConflict(String pageId) =>
      _notePageConflicts[pageId];

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

  Future<List<int>> readNoteRevisionBlob(String hash) {
    return _repository.readNoteBlobBytes(hash);
  }

  Future<void> installNoteRevisionBlobs(Map<String, List<int>> blobs) async {
    for (final entry in blobs.entries) {
      await _repository.installNoteBlob(entry.key, entry.value);
    }
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
    await _loadRevisionContentStates(_noteRevisions);
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
    notifyListeners();
  }

  /// 批量替换一个或多个笔记分区。
  ///
  /// 主要供备份导入使用。未传入的分区保持不变；传入的分区会立即替换内存
  /// 状态并等待对应保存队列完成后再通知 UI。
  Future<void> replaceFeatureData({
    List<NoteFolder>? noteFolders,
    List<Note>? notes,
    List<NoteRevision>? noteRevisions,
  }) async {
    final storageV2Active = await _storageV2ActiveForSave();
    final saveTasks = <Future<void>>[];
    if (noteFolders != null) {
      _noteFolders = List<NoteFolder>.from(noteFolders);
    }
    if (notes != null) {
      _notes = List<Note>.from(notes);
    }
    if (noteRevisions != null) {
      _noteRevisions = List<NoteRevision>.from(noteRevisions);
      _noteRevisionContentCache.clear();
      await _loadRevisionContentStates(_noteRevisions);
      _noteTimelineCache.clear();
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
    final result = await _repository.load();
    _notes = List<Note>.from(result.notes);
    _noteFolders = List<NoteFolder>.from(result.noteFolders);
    _notePageTombstones = result.pageTombstones
        .map(Map<String, dynamic>.from)
        .toList();
    _noteRevisions = result.noteRevisions
        .where(
          (revision) =>
              revision.pageId == null ||
              !_isRevisionTombstoned(revision.pageId!, revision.id),
        )
        .toList();
    final visibleRevisionIds = _noteRevisions
        .map((revision) => revision.id)
        .toSet();
    _noteRevisionContentCache
      ..clear()
      ..addEntries(
        result.revisionContents.entries.where(
          (entry) => visibleRevisionIds.contains(entry.key),
        ),
      );
    _notePageHeads = {
      for (final entry in result.pageHeads.entries)
        if (!_hasPageTombstone(entry.key))
          entry.key: NotePageHeads(
            pageId: entry.key,
            headIds: entry.value.headIds
                .where(
                  (revisionId) =>
                      visibleRevisionIds.contains(revisionId) &&
                      !_isRevisionTombstoned(entry.key, revisionId),
                )
                .toSet(),
            selectedHeadId:
                entry.value.selectedHeadId != null &&
                    visibleRevisionIds.contains(entry.value.selectedHeadId) &&
                    !_isRevisionTombstoned(
                      entry.key,
                      entry.value.selectedHeadId!,
                    )
                ? entry.value.selectedHeadId
                : null,
          ),
    }..removeWhere((_, heads) => heads.headIds.isEmpty);
    _notePageConflicts =
        {
          for (final entry in result.pageConflicts.entries)
            if (!_hasPageTombstone(entry.key)) entry.key: entry.value,
        }..removeWhere((pageId, conflict) {
          return conflict.headIds.length < 2 ||
              conflict.headIds.any(
                (revisionId) =>
                    !visibleRevisionIds.contains(revisionId) ||
                    _isRevisionTombstoned(pageId, revisionId),
              );
        });
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
    for (final entry in List.of(_notePageHeads.entries)) {
      if (entry.value.headIds.length < 2) continue;
      StorageV2NotePage? page;
      for (final candidate in _storageV2PagesByNoteId.values.expand(
        (pages) => pages,
      )) {
        if (candidate.id == entry.key) {
          page = candidate;
          break;
        }
      }
      if (page != null) await reconcileNotePageHeads(page.noteId, page.id);
    }
    final normalizedRevisions = _normalizeNoteRevisionState();
    final cleanedFolderRefs = _removeMissingNoteFolderReferences();
    if (normalizedRevisions || cleanedFolderRefs) {
      await _persistStorageV2NotesData();
    }
    notifyListeners();
  }

  Future<bool> _storageV2ActiveForSave() => _repository.isStorageV2Active();

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
    final pageContent = await _repository.readNotePage(removed);
    await _recycleBinRepository.add(
      RecycleBinItem(
        owner: RecycleBinOwners.core,
        category: RecycleBinCategories.notes,
        type: RecycleBinItemTypes.notePage,
        title: removed.title.isEmpty ? '未命名分页' : removed.title,
        preview: pageContent.replaceAll(RegExp(r'\s+'), ' ').trim(),
        payload: {
          'noteId': noteId,
          'page': removed.toJson(),
          'content': pageContent,
          'revisions': _noteRevisions
              .where(
                (revision) =>
                    revision.noteId == noteId && revision.pageId == removed.id,
              )
              .map((revision) => revision.toJson())
              .toList(),
          'editProposals': _noteEditProposals.values
              .where(
                (proposal) =>
                    proposal.noteId == noteId && proposal.pageId == removed.id,
              )
              .map((proposal) => proposal.toJson())
              .toList(),
        },
      ),
    );
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
    _notePageHeads.remove(removed.id);
    _notePageConflicts.remove(removed.id);
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
    _addPageTombstones(removed.id, removedRevisionIds);
    _noteRevisionContentCache.removeWhere(
      (revisionId, _) => removedRevisionIds.contains(revisionId),
    );
    _clearNoteTimelineCache(noteId);
    try {
      await _repository.deleteFile(removed.relativePath);
    } catch (_) {}
    await _persistStorageV2NotesData();
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

  void _addPageTombstones(String pageId, Iterable<String> revisionIds) {
    final existingIds = _notePageTombstones
        .map((item) => item['id'])
        .whereType<String>()
        .toSet();
    final createdAt = DateTime.now().toIso8601String();
    for (final revisionId in <String>{'*', ...revisionIds}) {
      final id = '$pageId:$revisionId';
      if (!existingIds.add(id)) continue;
      _notePageTombstones.add({
        'id': id,
        'pageId': pageId,
        'revisionId': revisionId,
        'createdAt': createdAt,
      });
    }
  }

  void _addRevisionTombstones(Iterable<NoteRevision> revisions) {
    final byPage = <String, List<String>>{};
    for (final revision in revisions) {
      final pageId = revision.pageId;
      if (pageId == null) continue;
      (byPage[pageId] ??= []).add(revision.id);
    }
    for (final entry in byPage.entries) {
      final existingIds = _notePageTombstones
          .map((item) => item['id'])
          .whereType<String>()
          .toSet();
      final createdAt = DateTime.now().toIso8601String();
      for (final revisionId in entry.value) {
        final id = '${entry.key}:$revisionId';
        if (!existingIds.add(id)) continue;
        _notePageTombstones.add({
          'id': id,
          'pageId': entry.key,
          'revisionId': revisionId,
          'createdAt': createdAt,
        });
      }
    }
  }

  bool _hasPageTombstone(String pageId) {
    return _notePageTombstones.any(
      (item) => item['pageId'] == pageId && item['revisionId'] == '*',
    );
  }

  bool _isRevisionTombstoned(String pageId, String revisionId) {
    return _notePageTombstones.any(
      (item) =>
          item['pageId'] == pageId &&
          (item['revisionId'] == revisionId || item['revisionId'] == '*'),
    );
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
          'parentIds': revision.parentIds,
          'authorDeviceId': revision.authorDeviceId,
          'contentHash': revision.contentHash,
          'createdAt': revision.createdAt.toIso8601String(),
        };
      }).toList(),
      'pageHeads': _notePageHeads.values
          .map(
            (heads) => {
              'id': heads.pageId,
              'pageId': heads.pageId,
              'headIds': heads.headIds.toList()..sort(),
              if (heads.selectedHeadId != null)
                'selectedHeadId': heads.selectedHeadId,
              'updatedAt': DateTime.now().toIso8601String(),
            },
          )
          .toList(),
      'pageTombstones': _notePageTombstones
          .map(Map<String, dynamic>.from)
          .toList(),
      'pageConflicts': _notePageConflicts.values
          .map(
            (conflict) => {
              'pageId': conflict.pageId,
              'headIds': conflict.headIds,
              'localHeadId': conflict.localHeadId,
              'incomingHeadId': conflict.incomingHeadId,
              if (conflict.commonAncestorId != null)
                'commonAncestorId': conflict.commonAncestorId,
              'createdAt': conflict.createdAt.toIso8601String(),
            },
          )
          .toList(),
      'editProposals': proposalRows,
      'editBlocks': proposalBlockRows,
    };
    final operation = _notesDataSaveQueue.then(
      (_) => _repository.saveStorageV2NotesData(data),
    );
    _pendingNotesDataSave = operation;
    _notesDataSaveQueue = operation.catchError((Object error) {
      debugPrint('保存笔记数据失败: $error');
    });
    await operation;
  }

  Future<void> flushPendingSaves() => _pendingNotesDataSave;

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
            parentIds: const [],
            authorDeviceId: await _authorDeviceId(),
            contentHash: await _repository.storeNoteBlob(content),
            createdAt: now,
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
          parentIds: const [],
          authorDeviceId: initialRevision.authorDeviceId,
          contentHash: initialRevision.contentHash,
          createdAt: now,
        ),
      );
      _noteRevisionContentCache[initialRevision.id] =
          NoteRevisionContent.loaded(content);
      _advancePageHeads(_noteRevisions.first);
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

  Future<void> _loadRevisionContentStates(
    Iterable<NoteRevision> revisions,
  ) async {
    for (final revision in revisions) {
      if (revision.contentHash.isEmpty) continue;
      try {
        _noteRevisionContentCache[revision.id] = NoteRevisionContent.loaded(
          await _repository.readNoteBlob(revision.contentHash),
        );
      } catch (e) {
        _noteRevisionContentCache[revision.id] =
            const NoteRevisionContent.missing();
        debugPrint('笔记时间线正文 blob 缺失 ${revision.contentHash}: $e');
      }
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
    if (!visited.add(revisionId)) {
      throw StateError('笔记修订存在循环引用: $revisionId');
    }
    final cached = _noteRevisionContentCache[revisionId];
    if (cached != null) {
      if (cached.isMissing) {
        throw StateError('笔记修订正文缺失: $revisionId');
      }
      return cached.content!;
    }
    final revision = getNoteRevision(revisionId);
    if (revision == null || revision.noteId != noteId) {
      throw StateError('笔记修订不存在: $revisionId');
    }
    final parentContent = revision.parentRevisionId == null
        ? ''
        : _getNoteContentAtRevision(
            noteId,
            revision.parentRevisionId!,
            visited,
          );
    if (revision.contentHash.isNotEmpty) {
      throw StateError('笔记修订正文尚未加载: $revisionId');
    }
    final content = revision.delta.apply(parentContent);
    _noteRevisionContentCache[revisionId] = NoteRevisionContent.loaded(content);
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
      if (revision.parentIds.isEmpty) {
        visiting.remove(revisionId);
        return validChainCache[revisionId] = true;
      }
      final valid = revision.parentIds.every((parentId) {
        final parent = revisionById[parentId];
        return parent != null &&
            parent.noteId == revision.noteId &&
            hasValidChain(parentId, visiting);
      });
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
    _noteRevisionContentCache.removeWhere(
      (revisionId, _) => !revisionById.containsKey(revisionId),
    );
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
    final activePageId = _usingStorageV2
        ? _activeStorageV2PageIds[noteId]
        : null;
    if (activePageId != null && _notePageConflicts.containsKey(activePageId)) {
      throw StateError('当前分页存在未解决冲突，请先完成合并');
    }
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
      final contentHash = await _repository.storeNoteBlob(note.content);
      final rootRevision = NoteRevision(
        id: _uuid.v4(),
        noteId: note.id,
        pageId: activePageId,
        parentIds: const [],
        authorDeviceId: await _authorDeviceId(),
        contentHash: contentHash,
        createdAt: now,
      );
      bootstrappedRoot = rootRevision;
      _noteRevisions.insert(0, rootRevision);
      _noteRevisionContentCache[rootRevision.id] = NoteRevisionContent.loaded(
        note.content,
      );
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
        notifyListeners();
      }
      return getNoteRevision(currentRevisionId);
    }

    final now = DateTime.now();
    final contentHash = await _repository.storeNoteBlob(content);
    final revision = NoteRevision(
      id: _uuid.v4(),
      noteId: note.id,
      pageId: _usingStorageV2 ? _activeStorageV2PageIds[note.id] : null,
      parentIds: parentRevisionId == null ? const [] : [parentRevisionId],
      authorDeviceId: await _authorDeviceId(),
      contentHash: contentHash,
      createdAt: now,
    );
    _noteRevisions.insert(0, revision);
    _noteRevisionContentCache[revision.id] = NoteRevisionContent.loaded(
      content,
    );
    _advancePageHeads(revision);
    _clearNoteTimelineCache(note.id);
    _noteEditProposals.remove(_noteEditProposalKey(note.id));
    _notes[index] = note.copyWith(
      content: content,
      currentRevisionId: revision.id,
    );
    await _persistStorageV2CurrentPageContent(note.id, content, revision.id);
    await _persistStorageV2NotesData();
    notifyListeners();
    return revision;
  }

  void _advancePageHeads(NoteRevision revision) {
    final pageId = revision.pageId;
    if (pageId == null) return;
    final current = _notePageHeads[pageId];
    final heads = {...?current?.headIds};
    heads.removeAll(revision.parentIds);
    heads.add(revision.id);
    _notePageHeads[pageId] = NotePageHeads(
      pageId: pageId,
      headIds: heads,
      selectedHeadId: revision.id,
    );
    final conflict = _notePageConflicts[pageId];
    if (heads.length <= 1 ||
        (conflict != null &&
            (!heads.contains(conflict.localHeadId) ||
                !heads.contains(conflict.incomingHeadId)))) {
      _notePageConflicts.remove(pageId);
    }
  }

  Future<NoteRevision?> reconcileNotePageHeads(
    String noteId,
    String pageId,
  ) async {
    final state = _notePageHeads[pageId];
    if (state == null || state.headIds.length < 2) return null;
    final heads = state.headIds.toList()..sort();
    final existingConflict = _notePageConflicts[pageId];
    final oursId =
        existingConflict != null && heads.contains(existingConflict.localHeadId)
        ? existingConflict.localHeadId
        : state.selectedHeadId != null && heads.contains(state.selectedHeadId)
        ? state.selectedHeadId!
        : heads.first;
    final theirsId =
        existingConflict != null &&
            heads.contains(existingConflict.incomingHeadId) &&
            existingConflict.incomingHeadId != oursId
        ? existingConflict.incomingHeadId
        : heads.firstWhere((id) => id != oursId);
    final ancestorId = _commonAncestor(oursId, theirsId);
    if (ancestorId == null) {
      return await _recordPageConflict(pageId, heads, oursId, theirsId, null);
    }
    NoteMergeResult result;
    try {
      result = mergeNoteMarkdown(
        getNoteContentAtRevision(noteId, ancestorId),
        getNoteContentAtRevision(noteId, oursId),
        getNoteContentAtRevision(noteId, theirsId),
      );
    } on StateError {
      return await _recordPageConflict(
        pageId,
        heads,
        oursId,
        theirsId,
        ancestorId,
      );
    }
    if (result.conflicted) {
      return await _recordPageConflict(
        pageId,
        heads,
        oursId,
        theirsId,
        ancestorId,
      );
    }
    final content = result.content!;
    final revision = NoteRevision(
      id: _uuid.v4(),
      noteId: noteId,
      pageId: pageId,
      parentIds: [oursId, theirsId],
      authorDeviceId: await _authorDeviceId(),
      contentHash: await _repository.storeNoteBlob(content),
      createdAt: DateTime.now(),
    );
    _noteRevisions.insert(0, revision);
    _noteRevisionContentCache[revision.id] = NoteRevisionContent.loaded(
      content,
    );
    _advancePageHeads(revision);
    final noteIndex = _notes.indexWhere((note) => note.id == noteId);
    if (noteIndex != -1 && _activeStorageV2PageIds[noteId] == pageId) {
      _notes[noteIndex] = _notes[noteIndex].copyWith(
        content: content,
        currentRevisionId: revision.id,
      );
      await _persistStorageV2CurrentPageContent(noteId, content, revision.id);
    }
    if ((_notePageHeads[pageId]?.headIds.length ?? 0) > 1) {
      await reconcileNotePageHeads(noteId, pageId);
    }
    await _persistStorageV2NotesData();
    notifyListeners();
    return revision;
  }

  Future<NoteRevision?> _recordPageConflict(
    String pageId,
    List<String> heads,
    String localHeadId,
    String incomingHeadId,
    String? ancestorId,
  ) async {
    _notePageConflicts[pageId] = NotePageConflict(
      pageId: pageId,
      headIds: heads,
      localHeadId: localHeadId,
      incomingHeadId: incomingHeadId,
      commonAncestorId: ancestorId,
      createdAt: DateTime.now(),
    );
    await _persistStorageV2NotesData();
    notifyListeners();
    return null;
  }

  NotePageMergeSession? loadNotePageMergeSession(String noteId, String pageId) {
    final conflict = _notePageConflicts[pageId];
    final heads = _notePageHeads[pageId];
    if (conflict == null || heads == null || heads.headIds.length < 2) {
      return null;
    }
    if (!heads.headIds.contains(conflict.localHeadId) ||
        !heads.headIds.contains(conflict.incomingHeadId)) {
      return null;
    }
    final local = getNoteContentAtRevision(noteId, conflict.localHeadId);
    final incoming = getNoteContentAtRevision(noteId, conflict.incomingHeadId);
    final base = conflict.commonAncestorId == null
        ? ''
        : getNoteContentAtRevision(noteId, conflict.commonAncestorId);
    final automatic = mergeNoteMarkdown(base, local, incoming);
    return NotePageMergeSession(
      noteId: noteId,
      pageId: pageId,
      expectedHeadIds: Set.unmodifiable(heads.headIds),
      localHeadId: conflict.localHeadId,
      incomingHeadId: conflict.incomingHeadId,
      baseRevisionId: conflict.commonAncestorId,
      localContent: local,
      incomingContent: incoming,
      baseContent: base,
      initialResult: automatic.content ?? local,
    );
  }

  Future<NotePageMergeCommitResult> commitNotePageMerge(
    NotePageMergeSession session,
    String content,
  ) async {
    final state = _notePageHeads[session.pageId];
    if (state == null ||
        !setEquals(state.headIds, session.expectedHeadIds) ||
        !state.headIds.contains(session.localHeadId) ||
        !state.headIds.contains(session.incomingHeadId)) {
      return const NotePageMergeCommitResult.staleHeads();
    }
    final revision = NoteRevision(
      id: _uuid.v4(),
      noteId: session.noteId,
      pageId: session.pageId,
      parentIds: [session.localHeadId, session.incomingHeadId],
      authorDeviceId: await _authorDeviceId(),
      contentHash: await _repository.storeNoteBlob(content),
      createdAt: DateTime.now(),
    );
    _noteRevisions.insert(0, revision);
    _noteRevisionContentCache[revision.id] = NoteRevisionContent.loaded(
      content,
    );
    _advancePageHeads(revision);
    _clearNoteTimelineCache(session.noteId);
    final noteIndex = _notes.indexWhere((note) => note.id == session.noteId);
    if (noteIndex != -1 &&
        _activeStorageV2PageIds[session.noteId] == session.pageId) {
      _notes[noteIndex] = _notes[noteIndex].copyWith(
        content: content,
        currentRevisionId: revision.id,
      );
      await _persistStorageV2CurrentPageContent(
        session.noteId,
        content,
        revision.id,
      );
    }
    if ((_notePageHeads[session.pageId]?.headIds.length ?? 0) > 1) {
      await reconcileNotePageHeads(session.noteId, session.pageId);
    }
    await _persistStorageV2NotesData();
    notifyListeners();
    return NotePageMergeCommitResult.committed(revision.id);
  }

  String? _commonAncestor(String left, String right) {
    final leftAncestors = _ancestorDistances(left);
    final rightAncestors = _ancestorDistances(right);
    final common = leftAncestors.keys.toSet().intersection(
      rightAncestors.keys.toSet(),
    );
    if (common.isEmpty) return null;
    return common.reduce((a, b) {
      final aDistance = leftAncestors[a]! + rightAncestors[a]!;
      final bDistance = leftAncestors[b]! + rightAncestors[b]!;
      return aDistance <= bDistance ? a : b;
    });
  }

  Map<String, int> _ancestorDistances(String start) {
    final distances = <String, int>{};
    final queue = <(String, int)>[(start, 0)];
    while (queue.isNotEmpty) {
      final (id, distance) = queue.removeAt(0);
      if ((distances[id] ?? 1 << 30) <= distance) continue;
      distances[id] = distance;
      final revision = getNoteRevision(id);
      if (revision == null) continue;
      for (final parent in revision.parentIds) {
        queue.add((parent, distance + 1));
      }
    }
    return distances;
  }

  Future<void> updateNote(Note note) async {
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index == -1) return;
    final contentChanged = _notes[index].content != note.content;
    final activePageId = _usingStorageV2
        ? _activeStorageV2PageIds[note.id]
        : null;
    if (contentChanged &&
        activePageId != null &&
        _notePageConflicts.containsKey(activePageId)) {
      throw StateError('当前分页存在未解决冲突，请先完成合并');
    }
    if (contentChanged) {
      _noteEditProposals.remove(_noteEditProposalKey(note.id));
    }
    _notes[index] = note;
    if (contentChanged) {
      await _persistStorageV2CurrentPageContent(
        note.id,
        note.content,
        note.currentRevisionId,
      );
    }
    await _persistStorageV2NotesData();
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
    if (newIndex < 0 || newIndex >= indexes.length) return;
    final folderNotes = indexes.map((i) => _notes[i]).toList();
    final note = folderNotes.removeAt(oldIndex);
    folderNotes.insert(newIndex, note);
    for (var i = 0; i < indexes.length; i++) {
      _notes[indexes[i]] = folderNotes[i];
    }
    await _persistStorageV2NotesData();
    notifyListeners();
  }

  Future<void> deleteNote(String id) async {
    final note = getNote(id);
    if (note == null) return;
    final pages = List<StorageV2NotePage>.from(
      _storageV2PagesByNoteId[id] ?? const [],
    );
    final pageContents = <String, String>{};
    for (final page in pages) {
      try {
        pageContents[page.id] = await _repository.readNotePage(page);
      } catch (_) {
        pageContents[page.id] = '';
      }
    }
    await _recycleBinRepository.add(
      RecycleBinItem(
        owner: RecycleBinOwners.core,
        category: RecycleBinCategories.notes,
        type: RecycleBinItemTypes.note,
        title: note.title.isEmpty ? '未命名笔记' : note.title,
        preview: note.content.replaceAll(RegExp(r'\s+'), ' ').trim(),
        payload: {
          'note': note.toJson(),
          'revisions': _noteRevisions
              .where((revision) => revision.noteId == id)
              .map((revision) => revision.toJson())
              .toList(),
          'pages': pages.map((page) => page.toJson()).toList(),
          'pageContents': pageContents,
          'activePageId': _activeStorageV2PageIds[id],
          'editProposals': _noteEditProposals.values
              .where((proposal) => proposal.noteId == id)
              .map((proposal) => proposal.toJson())
              .toList(),
        },
      ),
    );
    final before = _notes.length;
    _notes.removeWhere((n) => n.id == id);
    if (_notes.length == before) return;
    final deletedRevisionIds = _noteRevisions
        .where((revision) => revision.noteId == id)
        .map((revision) => revision.id)
        .toSet();
    final deletedRevisionIdsByPage = <String, List<String>>{};
    for (final revision in _noteRevisions.where(
      (revision) => revision.noteId == id && revision.pageId != null,
    )) {
      (deletedRevisionIdsByPage[revision.pageId!] ??= []).add(revision.id);
    }
    _noteRevisions.removeWhere((revision) => revision.noteId == id);
    _clearNoteTimelineCache(id);
    _noteEditProposals.removeWhere((_, proposal) => proposal.noteId == id);
    _noteRevisionContentCache.removeWhere(
      (revisionId, _) => deletedRevisionIds.contains(revisionId),
    );
    final removedPages = _storageV2PagesByNoteId.remove(id) ?? const [];
    for (final page in removedPages) {
      _notePageHeads.remove(page.id);
      _notePageConflicts.remove(page.id);
      _addPageTombstones(
        page.id,
        deletedRevisionIdsByPage[page.id] ?? const [],
      );
    }
    _activeStorageV2PageIds.remove(id);
    await _persistStorageV2NotesData();
    for (final page in removedPages) {
      try {
        await _repository.deleteFile(page.relativePath);
      } catch (e) {
        debugPrint('删除笔记分页文件失败: $e');
      }
    }
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
    final deletedRevisions = _noteRevisions
        .where((item) => item.noteId == noteId && descendants.contains(item.id))
        .toList(growable: false);
    _addRevisionTombstones(deletedRevisions);
    _noteRevisions.removeWhere((item) => descendants.contains(item.id));
    _noteRevisionContentCache.removeWhere((id, _) => descendants.contains(id));
    _clearNoteTimelineCache(noteId);
    await _persistStorageV2NotesData();
    notifyListeners();
    return true;
  }

  Future<void> setNoteEditProposal(NoteEditProposal proposal) async {
    _noteEditProposals[_noteEditProposalKey(proposal.noteId, proposal.pageId)] =
        proposal;
    await _persistStorageV2NotesData();
    notifyListeners();
  }

  Future<void> removeNoteEditProposal(String noteId) async {
    if (_noteEditProposals.remove(_noteEditProposalKey(noteId)) == null) return;
    await _persistStorageV2NotesData();
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
    notifyListeners();
  }

  Future<void> reorderNoteFolders(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _noteFolders.length) return;
    if (newIndex < 0 || newIndex >= _noteFolders.length) return;
    final folder = _noteFolders.removeAt(oldIndex);
    _noteFolders.insert(newIndex, folder);
    await _persistStorageV2NotesData();
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
    notifyListeners();
  }

  Future<void> restoreNotePayload(Map<String, dynamic> payload) async {
    final noteRaw = payload['note'];
    if (noteRaw is! Map) return;
    final note = Note.fromJson(Map<String, dynamic>.from(noteRaw));
    if (_notes.any((item) => item.id == note.id)) return;
    _notes.insert(0, note);
    final revisions = (payload['revisions'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => NoteRevision.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    _noteRevisions.insertAll(0, revisions);
    final proposals = (payload['editProposals'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (item) => NoteEditProposal.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
    for (final proposal in proposals) {
      _noteEditProposals[_noteEditProposalKey(
            proposal.noteId,
            proposal.pageId,
          )] =
          proposal;
    }
    if (_usingStorageV2) {
      final pages = (payload['pages'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                StorageV2NotePage.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
      final contents = Map<String, dynamic>.from(
        payload['pageContents'] as Map? ?? const {},
      );
      _storageV2PagesByNoteId[note.id] = pages;
      final restoredPageIds = pages.map((page) => page.id).toSet();
      _notePageTombstones.removeWhere(
        (item) => restoredPageIds.contains(item['pageId']),
      );
      final activePageId = payload['activePageId'] as String?;
      if (activePageId != null) _activeStorageV2PageIds[note.id] = activePageId;
      for (final page in pages) {
        _restorePageHead(page);
        await _repository.writeNotePage(
          page,
          contents[page.id]?.toString() ?? '',
        );
      }
      await _persistStorageV2NotesData();
    }
    _noteRevisionContentCache.clear();
    _clearNoteTimelineCache(note.id);
    notifyListeners();
  }

  Future<void> restoreNotePagePayload(Map<String, dynamic> payload) async {
    if (!_usingStorageV2) return;
    final pageRaw = payload['page'];
    if (pageRaw is! Map) return;
    final page = StorageV2NotePage.fromJson(Map<String, dynamic>.from(pageRaw));
    if (!_notes.any((note) => note.id == page.noteId)) return;
    final pages = _storageV2PagesByNoteId[page.noteId] ??= [];
    if (pages.any((item) => item.id == page.id)) return;
    pages.add(page);
    _notePageTombstones.removeWhere((item) => item['pageId'] == page.id);
    _renumberNotePages(pages);
    await _repository.writeNotePage(page, payload['content']?.toString() ?? '');
    final revisions = (payload['revisions'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => NoteRevision.fromJson(Map<String, dynamic>.from(item)))
        .where(
          (revision) => !_noteRevisions.any((item) => item.id == revision.id),
        )
        .toList();
    _noteRevisions.insertAll(0, revisions);
    _restorePageHead(page);
    final proposals = (payload['editProposals'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (item) => NoteEditProposal.fromJson(Map<String, dynamic>.from(item)),
        );
    for (final proposal in proposals) {
      _noteEditProposals[_noteEditProposalKey(
            proposal.noteId,
            proposal.pageId,
          )] =
          proposal;
    }
    await _persistStorageV2NotesData();
    notifyListeners();
  }

  void _restorePageHead(StorageV2NotePage page) {
    final revisionId = page.currentRevisionId;
    if (revisionId == null ||
        !_noteRevisions.any(
          (revision) => revision.id == revisionId && revision.pageId == page.id,
        )) {
      return;
    }
    _notePageHeads[page.id] = NotePageHeads(
      pageId: page.id,
      headIds: {revisionId},
      selectedHeadId: revisionId,
    );
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
