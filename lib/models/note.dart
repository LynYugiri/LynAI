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
    String? title,
    String? content,
    Object? currentRevisionId = _sentinel,
    Object? folderId = _sentinel,
    bool? wrap,
    bool preserveUpdatedAt = false,
  }) {
    return Note(
      id: id,
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

class NoteRevision {
  final String id;
  final String noteId;
  final String? parentRevisionId;
  final DateTime savedAt;
  final NoteTextDelta delta;

  const NoteRevision({
    required this.id,
    required this.noteId,
    required this.parentRevisionId,
    required this.savedAt,
    required this.delta,
  });

  factory NoteRevision.fromJson(Map<String, dynamic> json) {
    return NoteRevision(
      id: json['id'] as String,
      noteId: json['noteId'] as String,
      parentRevisionId: json['parentRevisionId'] as String?,
      savedAt: DateTime.parse(json['savedAt'] as String),
      delta: NoteTextDelta.fromJson(json['delta'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'noteId': noteId,
      if (parentRevisionId != null) 'parentRevisionId': parentRevisionId,
      'savedAt': savedAt.toIso8601String(),
      'delta': delta.toJson(),
    };
  }
}

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

  NoteFolder copyWith({String? title}) {
    return NoteFolder(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

const Object _sentinel = Object();
