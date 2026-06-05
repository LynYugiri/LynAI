/// 当前笔记内容和展示状态。
///
/// [content] 是当前可编辑正文；历史版本由 [NoteRevision] 增量链维护。
/// [currentRevisionId] 指向当前内容所在的修订节点，允许从历史版本创建分支。
class Note {
  /// 笔记唯一标识符。
  final String id;

  /// 笔记标题。
  final String title;

  /// 笔记的当前正文内容。
  final String content;

  /// 当前内容所在修订节点的 ID。
  final String? currentRevisionId;

  /// 所属文件夹 ID，为 null 表示在根目录。
  final String? folderId;

  /// 笔记创建时间。
  final DateTime createdAt;

  /// 笔记最后更新时间。
  final DateTime updatedAt;

  /// 是否在编辑器中启用自动换行。
  final bool wrap;

  /// 创建一个笔记实例。
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

  /// 从 JSON 数据创建 [Note] 实例。
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

  /// 将当前实例序列化为 JSON Map。
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

  /// 创建当前实例的副本，可选择性更新部分字段。
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
  /// 文本变更的起始位置（字符偏移）。
  final int start;

  /// 被删除的文本内容。
  final String deletedText;

  /// 新插入的文本内容。
  final String insertedText;

  /// 创建一个笔记文本增量实例。
  const NoteTextDelta({
    required this.start,
    required this.deletedText,
    required this.insertedText,
  });

  /// 从 JSON 数据创建 [NoteTextDelta] 实例。
  factory NoteTextDelta.fromJson(Map<String, dynamic> json) {
    return NoteTextDelta(
      start: json['start'] as int? ?? 0,
      deletedText: json['deletedText'] as String? ?? '',
      insertedText: json['insertedText'] as String? ?? '',
    );
  }

  /// 计算两个文本之间的增量差异。
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

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() {
    return {
      'start': start,
      'deletedText': deletedText,
      'insertedText': insertedText,
    };
  }

  /// 将增量应用到源文本，返回修改后的文本。
  String apply(String source) {
    final end = (start + deletedText.length).clamp(0, source.length);
    final safeStart = start.clamp(0, source.length);
    return source.replaceRange(safeStart, end, insertedText);
  }

  /// 从源文本中撤销此增量，返回还原后的文本。
  String revert(String source) {
    final end = (start + insertedText.length).clamp(0, source.length);
    final safeStart = start.clamp(0, source.length);
    return source.replaceRange(safeStart, end, deletedText);
  }

  /// 该增量是否为空，即无任何文本变更。
  bool get isEmpty => deletedText.isEmpty && insertedText.isEmpty;
}

/// 笔记时间线中的一个修订节点。
///
/// 修订通过 [parentRevisionId] 组成树，而不是单链表，因此用户可以从历史版本
/// 另开分支。Provider 负责缓存和校验可达时间线。
class NoteRevision {
  /// 修订节点唯一标识符。
  final String id;

  /// 所属笔记 ID。
  final String noteId;

  /// 所属笔记页面 ID，为 null 表示主页面。
  final String? pageId;

  /// 父修订节点 ID，为 null 表示根修订。
  final String? parentRevisionId;

  /// 修订保存时间。
  final DateTime savedAt;

  /// 本次修订的文本增量。
  final NoteTextDelta delta;

  /// 创建一个笔记修订实例。
  const NoteRevision({
    required this.id,
    required this.noteId,
    this.pageId,
    required this.parentRevisionId,
    required this.savedAt,
    required this.delta,
  });

  /// 从 JSON 数据创建 [NoteRevision] 实例。
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

  /// 将当前实例序列化为 JSON Map。
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

  /// 创建当前实例的副本，可选择性更新部分字段。
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

/// AI 生成的笔记编辑建议，包含一组编辑块。
///
/// [blocks] 中的每个 [NoteEditBlock] 描述一个独立的编辑操作，用户可选择
/// 接受、拒绝或修改后再应用。
class NoteEditProposal {
  /// 编辑建议唯一标识符。
  final String id;

  /// 所属笔记 ID。
  final String noteId;

  /// 所属笔记页面 ID，为 null 表示主页面。
  final String? pageId;

  /// 基准修订节点 ID，标记此建议基于哪个版本生成。
  final String? baseRevisionId;

  /// 基准内容哈希值，用于检测内容是否已被修改。
  final String baseContentHash;

  /// 建议创建时间。
  final DateTime createdAt;

  /// 编辑建议所包含的编辑块列表。
  final List<NoteEditBlock> blocks;

  /// 创建一个笔记编辑建议实例。
  const NoteEditProposal({
    required this.id,
    required this.noteId,
    this.pageId,
    required this.baseRevisionId,
    required this.baseContentHash,
    required this.createdAt,
    required this.blocks,
  });

  /// 从 JSON 数据创建 [NoteEditProposal] 实例。
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

  /// 创建当前实例的副本，可选择性更新部分字段。
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

  /// 将当前实例序列化为 JSON Map。
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

/// 编辑建议中的一个独立编辑块。
///
/// 描述在指定行位置删除若干行并插入新行的原子操作，可用于逐块审阅和确认。
class NoteEditBlock {
  /// 编辑块唯一标识符。
  final String id;

  /// 编辑起始行号（从 1 开始）。
  final int startLine;

  /// 需要删除的行数。
  final int deleteCount;

  /// 将被删除的原始行内容列表。
  final List<String> deletedLines;

  /// 将被插入的新行内容列表。
  final List<String> insertLines;

  /// 创建一个笔记编辑块实例。
  const NoteEditBlock({
    required this.id,
    required this.startLine,
    required this.deleteCount,
    required this.deletedLines,
    required this.insertLines,
  });

  /// 从 JSON 数据创建 [NoteEditBlock] 实例。
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

  /// 将当前实例序列化为 JSON Map。
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
  /// 文件夹唯一标识符。
  final String id;

  /// 文件夹标题。
  final String title;

  /// 文件夹创建时间。
  final DateTime createdAt;

  /// 文件夹最后更新时间。
  final DateTime updatedAt;

  /// 创建一个笔记文件夹实例。
  const NoteFolder({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 从 JSON 数据创建 [NoteFolder] 实例。
  factory NoteFolder.fromJson(Map<String, dynamic> json) {
    return NoteFolder(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 创建当前实例的副本，可选择性更新部分字段。
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
