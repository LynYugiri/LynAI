class ScheduleItem {
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String? note;

  const ScheduleItem({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.note,
  });

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    return ScheduleItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      start: DateTime.parse(json['start'] as String),
      end: DateTime.parse(json['end'] as String),
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      if (note != null) 'note': note,
    };
  }

  ScheduleItem copyWith({
    String? title,
    DateTime? start,
    DateTime? end,
    Object? note = _sentinel,
  }) {
    return ScheduleItem(
      id: id,
      title: title ?? this.title,
      start: start ?? this.start,
      end: end ?? this.end,
      note: identical(note, _sentinel) ? this.note : note as String?,
    );
  }

  static const _sentinel = Object();
}
