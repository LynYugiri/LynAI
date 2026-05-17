class ScheduleItem {
  static const kindSchedule = 'schedule';
  static const kindTask = 'task';

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String? note;
  final String kind;

  const ScheduleItem({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.note,
    this.kind = kindSchedule,
  });

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    return ScheduleItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      start: DateTime.parse(json['start'] as String).toLocal(),
      end: DateTime.parse(json['end'] as String).toLocal(),
      note: json['note'] as String?,
      kind: json['kind'] as String? ?? kindSchedule,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'start': start.toLocal().toIso8601String(),
      'end': end.toLocal().toIso8601String(),
      if (note != null) 'note': note,
      if (kind != kindSchedule) 'kind': kind,
    };
  }

  ScheduleItem copyWith({
    String? title,
    DateTime? start,
    DateTime? end,
    Object? note = _sentinel,
    String? kind,
  }) {
    return ScheduleItem(
      id: id,
      title: title ?? this.title,
      start: start ?? this.start,
      end: end ?? this.end,
      note: identical(note, _sentinel) ? this.note : note as String?,
      kind: kind ?? this.kind,
    );
  }

  bool get isTask => kind == kindTask;

  static const _sentinel = Object();
}
