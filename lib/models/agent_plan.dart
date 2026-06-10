/// Conversation-level Agent plan state.
class AgentPlan {
  final String id;
  final String title;
  final List<AgentPlanItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AgentPlan({
    required this.id,
    required this.title,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AgentPlan.fromJson(Map<String, dynamic> json) {
    return AgentPlan(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => AgentPlanItem.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
          .toList(growable: false),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'items': items.map((item) => item.toJson()).toList(growable: false),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  AgentPlan copyWith({
    String? id,
    String? title,
    List<AgentPlanItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AgentPlan(
      id: id ?? this.id,
      title: title ?? this.title,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class AgentPlanItem {
  static const pending = 'pending';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const failed = 'failed';
  static const skipped = 'skipped';
  static const needsConfirmation = 'needs_confirmation';

  static const statuses = {
    pending,
    inProgress,
    completed,
    failed,
    skipped,
    needsConfirmation,
  };

  final String id;
  final String title;
  final String status;
  final String? summary;

  const AgentPlanItem({
    required this.id,
    required this.title,
    this.status = pending,
    this.summary,
  });

  factory AgentPlanItem.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as String? ?? pending;
    return AgentPlanItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      status: statuses.contains(status) ? status : pending,
      summary: json['summary'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'status': status,
    if (summary != null && summary!.isNotEmpty) 'summary': summary,
  };

  AgentPlanItem copyWith({String? status, Object? summary = _sentinel}) {
    return AgentPlanItem(
      id: id,
      title: title,
      status: status ?? this.status,
      summary: identical(summary, _sentinel)
          ? this.summary
          : summary as String?,
    );
  }

  static const _sentinel = Object();
}
