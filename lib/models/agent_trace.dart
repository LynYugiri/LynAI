/// Per-message Agent execution trace used for UI/audit display.
class AgentTrace {
  final List<AgentTraceEvent> events;

  const AgentTrace({this.events = const []});

  factory AgentTrace.fromJson(Map<String, dynamic> json) {
    return AgentTrace(
      events: (json['events'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => AgentTraceEvent.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((event) => event.id.isNotEmpty && event.title.isNotEmpty)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'events': events.map((event) => event.toJson()).toList(growable: false),
  };

  AgentTrace append(AgentTraceEvent event) {
    return AgentTrace(events: [...events, event]);
  }
}

class AgentTraceEvent {
  static const assistantNote = 'assistant_note';
  static const toolCall = 'tool_call';
  static const toolResult = 'tool_result';
  static const planUpdate = 'plan_update';
  static const memoryUpdate = 'memory_update';
  static const error = 'error';

  static const types = {
    assistantNote,
    toolCall,
    toolResult,
    planUpdate,
    memoryUpdate,
    error,
  };

  final String id;
  final String type;
  final String title;
  final String? content;
  final Map<String, dynamic>? metadata;
  final DateTime timestamp;

  const AgentTraceEvent({
    required this.id,
    required this.type,
    required this.title,
    this.content,
    this.metadata,
    required this.timestamp,
  });

  factory AgentTraceEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? assistantNote;
    final metadata = json['metadata'];
    return AgentTraceEvent(
      id: json['id'] as String? ?? '',
      type: types.contains(type) ? type : assistantNote,
      title: json['title'] as String? ?? '',
      content: json['content'] as String?,
      metadata: metadata is Map ? Map<String, dynamic>.from(metadata) : null,
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    if (content != null && content!.isNotEmpty) 'content': content,
    if (metadata != null && metadata!.isNotEmpty) 'metadata': metadata,
    'timestamp': timestamp.toIso8601String(),
  };
}
