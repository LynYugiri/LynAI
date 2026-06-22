class AgentWorkingMemory {
  static const maxEntries = 40;

  final String goal;
  final List<AgentMemoryEntry> entries;
  final DateTime updatedAt;

  const AgentWorkingMemory({
    this.goal = '',
    this.entries = const [],
    required this.updatedAt,
  });

  factory AgentWorkingMemory.empty() {
    return AgentWorkingMemory(updatedAt: DateTime.now());
  }

  factory AgentWorkingMemory.fromJson(Map<String, dynamic> json) {
    return AgentWorkingMemory(
      goal: json['goal'] as String? ?? '',
      entries: (json['entries'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                AgentMemoryEntry.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((entry) => entry.id.isNotEmpty && entry.content.isNotEmpty)
          .toList(growable: false),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  bool get isEmpty => goal.trim().isEmpty && entries.isEmpty;

  Map<String, dynamic> toJson() => {
    if (goal.trim().isNotEmpty) 'goal': goal,
    if (entries.isNotEmpty)
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    'updatedAt': updatedAt.toIso8601String(),
  };

  AgentWorkingMemory copyWith({
    String? goal,
    List<AgentMemoryEntry>? entries,
    DateTime? updatedAt,
  }) {
    return AgentWorkingMemory(
      goal: goal ?? this.goal,
      entries: entries ?? this.entries,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  AgentWorkingMemory compacted({
    int maxEntries = AgentWorkingMemory.maxEntries,
  }) {
    if (maxEntries <= 0) return copyWith(entries: const []);
    if (entries.length <= maxEntries) return this;
    final pinned = entries
        .where((entry) => entry.pinned)
        .toList(growable: false);
    final normal = entries
        .where((entry) => !entry.pinned)
        .toList(growable: false);
    if (pinned.length >= maxEntries) {
      return copyWith(entries: pinned.sublist(pinned.length - maxEntries));
    }
    final keepNormal = maxEntries - pinned.length;
    final next = [...pinned, ...normal.skip(normal.length - keepNormal)];
    next.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return copyWith(entries: next);
  }
}

class AgentMemoryEntry {
  static const fact = 'fact';
  static const decision = 'decision';
  static const subagentResult = 'subagent_result';
  static const skillLoaded = 'skill_loaded';
  static const blocker = 'blocker';
  static const artifact = 'artifact';
  static const note = 'note';

  static const kinds = {
    fact,
    decision,
    subagentResult,
    skillLoaded,
    blocker,
    artifact,
    note,
  };

  final String id;
  final String kind;
  final String content;
  final String source;
  final Map<String, dynamic>? details;
  final bool pinned;
  final DateTime createdAt;

  const AgentMemoryEntry({
    required this.id,
    required this.kind,
    required this.content,
    this.source = 'agent',
    this.details,
    this.pinned = false,
    required this.createdAt,
  });

  factory AgentMemoryEntry.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String? ?? note;
    final details = json['details'];
    return AgentMemoryEntry(
      id: json['id'] as String? ?? '',
      kind: kinds.contains(kind) ? kind : note,
      content: json['content'] as String? ?? '',
      source: json['source'] as String? ?? 'agent',
      details: details is Map ? Map<String, dynamic>.from(details) : null,
      pinned: json['pinned'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'content': content,
    if (source.isNotEmpty && source != 'agent') 'source': source,
    if (details != null && details!.isNotEmpty) 'details': details,
    if (pinned) 'pinned': true,
    'createdAt': createdAt.toIso8601String(),
  };
}
