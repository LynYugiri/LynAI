/// 当前笔记内容和展示状态。
///
/// [content] 是当前可编辑正文；历史版本由 [NoteRevision] 增量链维护。
/// [currentRevisionId] 指向当前内容所在的修订节点，允许从历史版本创建分支。
class Note {
  final String id;
  final String title;
  final String content;
  final String? currentRevisionId;
  final String? folderId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool wrap;

  const Note({
    required this.id,
    required this.title,
    required this.content,
    this.currentRevisionId,
    this.folderId,
    required this.createdAt,
    required this.updatedAt,
    this.wrap = true,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      currentRevisionId: json['currentRevisionId'] as String?,
      folderId: json['folderId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      wrap: json['wrap'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      if (currentRevisionId != null) 'currentRevisionId': currentRevisionId,
      if (folderId != null) 'folderId': folderId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'wrap': wrap,
    };
  }

  Note copyWith({
    String? id,
    String? title,
    String? content,
    Object? currentRevisionId = _sentinel,
    Object? folderId = _sentinel,
    bool? wrap,
    bool preserveUpdatedAt = false,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      currentRevisionId: currentRevisionId == _sentinel
          ? this.currentRevisionId
          : currentRevisionId as String?,
      folderId: folderId == _sentinel ? this.folderId : folderId as String?,
      createdAt: createdAt,
      updatedAt: preserveUpdatedAt ? updatedAt : DateTime.now(),
      wrap: wrap ?? this.wrap,
    );
  }
}

/// 两个笔记版本之间的最小文本增量。
///
/// 通过最长公共前后缀计算得到，既能从父版本 apply 到子版本，也能从子版本
/// revert 回父版本。修订链只保存 delta，避免每次保存复制完整正文。
class NoteTextDelta {
  final int start;
  final String deletedText;
  final String insertedText;

  const NoteTextDelta({
    required this.start,
    required this.deletedText,
    required this.insertedText,
  });

  factory NoteTextDelta.fromJson(Map<String, dynamic> json) {
    return NoteTextDelta(
      start: json['start'] as int? ?? 0,
      deletedText: json['deletedText'] as String? ?? '',
      insertedText: json['insertedText'] as String? ?? '',
    );
  }

  factory NoteTextDelta.between(String before, String after) {
    var prefix = 0;
    final maxPrefix = before.length < after.length
        ? before.length
        : after.length;
    while (prefix < maxPrefix &&
        before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
      prefix++;
    }

    var beforeSuffix = before.length;
    var afterSuffix = after.length;
    while (beforeSuffix > prefix &&
        afterSuffix > prefix &&
        before.codeUnitAt(beforeSuffix - 1) ==
            after.codeUnitAt(afterSuffix - 1)) {
      beforeSuffix--;
      afterSuffix--;
    }

    return NoteTextDelta(
      start: prefix,
      deletedText: before.substring(prefix, beforeSuffix),
      insertedText: after.substring(prefix, afterSuffix),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'start': start,
      'deletedText': deletedText,
      'insertedText': insertedText,
    };
  }

  String apply(String source) {
    final end = (start + deletedText.length).clamp(0, source.length);
    final safeStart = start.clamp(0, source.length);
    return source.replaceRange(safeStart, end, insertedText);
  }

  String revert(String source) {
    final end = (start + insertedText.length).clamp(0, source.length);
    final safeStart = start.clamp(0, source.length);
    return source.replaceRange(safeStart, end, deletedText);
  }

  bool get isEmpty => deletedText.isEmpty && insertedText.isEmpty;
}

/// 笔记时间线中的一个修订节点。
///
/// 修订通过 [parentRevisionId] 组成树，而不是单链表，因此用户可以从历史版本
/// 另开分支。Provider 负责缓存和校验可达时间线。
class NoteRevision {
  final String id;
  final String noteId;
  final String? pageId;
  final String? parentRevisionId;
  final DateTime savedAt;
  final NoteTextDelta delta;

  const NoteRevision({
    required this.id,
    required this.noteId,
    this.pageId,
    required this.parentRevisionId,
    required this.savedAt,
    required this.delta,
  });

  factory NoteRevision.fromJson(Map<String, dynamic> json) {
    final delta = json['delta'];
    final hasFlatDelta = json['deltaStart'] != null;
    return NoteRevision(
      id: json['id'] as String,
      noteId: json['noteId'] as String,
      pageId: json['pageId'] as String?,
      parentRevisionId: json['parentRevisionId'] as String?,
      savedAt: DateTime.parse(json['savedAt'] as String),
      delta: delta is Map
          ? NoteTextDelta.fromJson(Map<String, dynamic>.from(delta))
          : hasFlatDelta
          ? NoteTextDelta(
              start: json['deltaStart'] as int? ?? 0,
              deletedText: json['deletedText'] as String? ?? '',
              insertedText: json['insertedText'] as String? ?? '',
            )
          : const NoteTextDelta(start: 0, deletedText: '', insertedText: ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'noteId': noteId,
      if (pageId != null) 'pageId': pageId,
      if (parentRevisionId != null) 'parentRevisionId': parentRevisionId,
      'savedAt': savedAt.toIso8601String(),
      'delta': delta.toJson(),
    };
  }

  NoteRevision copyWith({
    String? id,
    String? noteId,
    Object? pageId = _sentinel,
    Object? parentRevisionId = _sentinel,
    DateTime? savedAt,
    NoteTextDelta? delta,
  }) {
    return NoteRevision(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      pageId: pageId == _sentinel ? this.pageId : pageId as String?,
      parentRevisionId: parentRevisionId == _sentinel
          ? this.parentRevisionId
          : parentRevisionId as String?,
      savedAt: savedAt ?? this.savedAt,
      delta: delta ?? this.delta,
    );
  }
}

class NoteEditProposal {
  final String id;
  final String noteId;
  final String? pageId;
  final String? baseRevisionId;
  final String baseContentHash;
  final DateTime createdAt;
  final List<NoteEditBlock> blocks;

  const NoteEditProposal({
    required this.id,
    required this.noteId,
    this.pageId,
    required this.baseRevisionId,
    required this.baseContentHash,
    required this.createdAt,
    required this.blocks,
  });

  factory NoteEditProposal.fromJson(Map<String, dynamic> json) {
    return NoteEditProposal(
      id: json['id'] as String,
      noteId: json['noteId'] as String,
      pageId: json['pageId'] as String?,
      baseRevisionId: json['baseRevisionId'] as String?,
      baseContentHash: json['baseContentHash'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      blocks: (json['blocks'] as List<dynamic>? ?? [])
          .map((block) => NoteEditBlock.fromJson(block as Map<String, dynamic>))
          .toList(),
    );
  }

  NoteEditProposal copyWith({
    Object? pageId = _sentinel,
    Object? baseRevisionId = _sentinel,
    String? baseContentHash,
    DateTime? createdAt,
    List<NoteEditBlock>? blocks,
  }) {
    return NoteEditProposal(
      id: id,
      noteId: noteId,
      pageId: pageId == _sentinel ? this.pageId : pageId as String?,
      baseRevisionId: baseRevisionId == _sentinel
          ? this.baseRevisionId
          : baseRevisionId as String?,
      baseContentHash: baseContentHash ?? this.baseContentHash,
      createdAt: createdAt ?? this.createdAt,
      blocks: blocks ?? this.blocks,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'noteId': noteId,
      if (pageId != null) 'pageId': pageId,
      if (baseRevisionId != null) 'baseRevisionId': baseRevisionId,
      'baseContentHash': baseContentHash,
      'createdAt': createdAt.toIso8601String(),
      'blocks': blocks.map((block) => block.toJson()).toList(),
    };
  }
}

class NoteEditBlock {
  final String id;
  final int startLine;
  final int deleteCount;
  final List<String> deletedLines;
  final List<String> insertLines;

  const NoteEditBlock({
    required this.id,
    required this.startLine,
    required this.deleteCount,
    required this.deletedLines,
    required this.insertLines,
  });

  factory NoteEditBlock.fromJson(Map<String, dynamic> json) {
    return NoteEditBlock(
      id: json['id'] as String,
      startLine: json['startLine'] as int? ?? 1,
      deleteCount: json['deleteCount'] as int? ?? 0,
      deletedLines: (json['deletedLines'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
      insertLines: (json['insertLines'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startLine': startLine,
      'deleteCount': deleteCount,
      'deletedLines': deletedLines,
      'insertLines': insertLines,
    };
  }
}

/// 笔记文件夹，只保存标题和创建时间。
///
/// 文件夹不持有笔记列表；笔记通过 `folderId` 引用文件夹，删除文件夹时由
/// Provider 清理笔记引用。
class NoteFolder {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NoteFolder({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NoteFolder.fromJson(Map<String, dynamic> json) {
    return NoteFolder(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  NoteFolder copyWith({String? id, String? title}) {
    return NoteFolder(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

const Object _sentinel = Object();
