enum RoleplayMessageKind { player, character, system, narrator }

class RoleplayDirector {
  final String name;
  final String systemPrompt;
  final String? modelId;

  const RoleplayDirector({
    this.name = '系统',
    this.systemPrompt = defaultSystemPrompt,
    this.modelId,
  });

  static const defaultSystemPrompt =
      '你是多角色情景演绎的导演。你不扮演任何角色，不生成台词。你只根据场景、角色设定和历史记录，决定下一步由哪个 AI 角色发言，或是否等待用户。不要替用户发言。不要让不存在的角色发言。只返回 JSON。';

  factory RoleplayDirector.fromJson(Map<String, dynamic> json) {
    return RoleplayDirector(
      name: json['name'] as String? ?? '系统',
      systemPrompt: json['systemPrompt'] as String? ?? defaultSystemPrompt,
      modelId: json['modelId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'systemPrompt': systemPrompt,
    if (modelId != null) 'modelId': modelId,
  };
}

class RoleplayParticipant {
  final String id;
  final String? sourceRoleId;
  final String name;
  final String description;
  final String systemPrompt;
  final String? modelId;
  final int? themeColor;
  final bool isPlayer;

  const RoleplayParticipant({
    required this.id,
    this.sourceRoleId,
    required this.name,
    this.description = '',
    required this.systemPrompt,
    this.modelId,
    this.themeColor,
    this.isPlayer = false,
  });

  factory RoleplayParticipant.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    if (id.isEmpty) {
      throw const FormatException('Malformed roleplay participant');
    }
    return RoleplayParticipant(
      id: id,
      sourceRoleId: json['sourceRoleId'] as String?,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      modelId: json['modelId'] as String?,
      themeColor: (json['themeColor'] as num?)?.toInt(),
      isPlayer: json['isPlayer'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (sourceRoleId != null) 'sourceRoleId': sourceRoleId,
    'name': name,
    'description': description,
    'systemPrompt': systemPrompt,
    if (modelId != null) 'modelId': modelId,
    if (themeColor != null) 'themeColor': themeColor,
    'isPlayer': isPlayer,
  };
}

class RoleplayMessage {
  final String id;
  final String speakerId;
  final String speakerName;
  final String content;
  final RoleplayMessageKind kind;
  final DateTime timestamp;

  const RoleplayMessage({
    required this.id,
    required this.speakerId,
    required this.speakerName,
    required this.content,
    required this.kind,
    required this.timestamp,
  });

  factory RoleplayMessage.fromJson(Map<String, dynamic> json) {
    final timestamp = DateTime.tryParse(json['timestamp'] as String? ?? '');
    if (timestamp == null) {
      throw const FormatException('Malformed roleplay message timestamp');
    }
    final id = json['id'] as String? ?? '';
    if (id.isEmpty) throw const FormatException('Malformed roleplay message');
    return RoleplayMessage(
      id: id,
      speakerId: json['speakerId'] as String? ?? '',
      speakerName: json['speakerName'] as String? ?? '',
      content: json['content'] as String? ?? '',
      kind: RoleplayMessageKind.values.firstWhere(
        (kind) => kind.name == json['kind'],
        orElse: () => RoleplayMessageKind.character,
      ),
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'speakerId': speakerId,
    'speakerName': speakerName,
    'content': content,
    'kind': kind.name,
    'timestamp': timestamp.toIso8601String(),
  };
}

class RoleplaySession {
  final String id;
  final String title;
  final String scenario;
  final RoleplayDirector director;
  final List<RoleplayParticipant> participants;
  final String playerParticipantId;
  final List<RoleplayMessage> messages;
  final int maxAutoTurns;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RoleplaySession({
    required this.id,
    required this.title,
    required this.scenario,
    required this.director,
    required this.participants,
    required this.playerParticipantId,
    this.messages = const [],
    this.maxAutoTurns = 3,
    required this.createdAt,
    required this.updatedAt,
  });

  RoleplayParticipant? get player {
    for (final participant in participants) {
      if (participant.id == playerParticipantId) return participant;
    }
    return null;
  }

  List<RoleplayParticipant> get characters => participants
      .where((participant) => !participant.isPlayer)
      .toList(growable: false);

  factory RoleplaySession.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    if (id.isEmpty || createdAt == null || updatedAt == null) {
      throw const FormatException('Malformed roleplay session');
    }
    final messages = <RoleplayMessage>[];
    for (final item in json['messages'] as List<dynamic>? ?? const []) {
      try {
        if (item is Map) {
          messages.add(
            RoleplayMessage.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      } catch (_) {}
    }
    return RoleplaySession(
      id: id,
      title: json['title'] as String? ?? '情景演绎',
      scenario: json['scenario'] as String? ?? '',
      director: RoleplayDirector.fromJson(
        Map<String, dynamic>.from(json['director'] as Map? ?? const {}),
      ),
      participants: (json['participants'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) {
            try {
              return RoleplayParticipant.fromJson(
                Map<String, dynamic>.from(item),
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<RoleplayParticipant>()
          .toList(),
      playerParticipantId: json['playerParticipantId'] as String? ?? '',
      messages: messages,
      maxAutoTurns: (json['maxAutoTurns'] as num?)?.toInt() ?? 3,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'scenario': scenario,
    'director': director.toJson(),
    'participants': participants.map((item) => item.toJson()).toList(),
    'playerParticipantId': playerParticipantId,
    'messages': messages.map((item) => item.toJson()).toList(),
    'maxAutoTurns': maxAutoTurns,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  RoleplaySession copyWith({
    String? title,
    String? scenario,
    RoleplayDirector? director,
    List<RoleplayParticipant>? participants,
    String? playerParticipantId,
    List<RoleplayMessage>? messages,
    int? maxAutoTurns,
    DateTime? updatedAt,
  }) {
    return RoleplaySession(
      id: id,
      title: title ?? this.title,
      scenario: scenario ?? this.scenario,
      director: director ?? this.director,
      participants: participants ?? this.participants,
      playerParticipantId: playerParticipantId ?? this.playerParticipantId,
      messages: messages ?? this.messages,
      maxAutoTurns: maxAutoTurns ?? this.maxAutoTurns,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
