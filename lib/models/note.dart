class Note {
  final String id;
  final String title;
  final String content;
  final String? folderId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool wrap;

  const Note({
    required this.id,
    required this.title,
    required this.content,
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
      if (folderId != null) 'folderId': folderId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'wrap': wrap,
    };
  }

  Note copyWith({
    String? title,
    String? content,
    Object? folderId = _sentinel,
    bool? wrap,
    bool preserveUpdatedAt = false,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      folderId: folderId == _sentinel ? this.folderId : folderId as String?,
      createdAt: createdAt,
      updatedAt: preserveUpdatedAt ? updatedAt : DateTime.now(),
      wrap: wrap ?? this.wrap,
    );
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
