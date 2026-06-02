import 'message.dart';

enum RoleplayMessageKind { player, character, system, narrator }

class RoleplayModelSelection {
  final String? modelId;
  final String? modelName;

  const RoleplayModelSelection({this.modelId, this.modelName});

  bool get isEmpty => modelId == null || modelId!.isEmpty;

  factory RoleplayModelSelection.fromJson(Map<String, dynamic> json) {
    return RoleplayModelSelection(
      modelId: json['modelId'] as String?,
      modelName: json['modelName'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (modelId != null && modelId!.isNotEmpty) 'modelId': modelId,
    if (modelName != null && modelName!.isNotEmpty) 'modelName': modelName,
  };

  RoleplayModelSelection copyWith({
    Object? modelId = _sentinel,
    Object? modelName = _sentinel,
  }) {
    return RoleplayModelSelection(
      modelId: identical(modelId, _sentinel)
          ? this.modelId
          : modelId as String?,
      modelName: identical(modelName, _sentinel)
          ? this.modelName
          : modelName as String?,
    );
  }

  static const _sentinel = Object();
}

class RoleplayDirector {
  final String name;
  final String systemPrompt;
  final RoleplayModelSelection model;

  const RoleplayDirector({
    this.name = '系统',
    this.systemPrompt = defaultSystemPrompt,
    this.model = const RoleplayModelSelection(),
  });

  static const defaultSystemPrompt =
      '你是多角色情景演绎的导演。你不扮演任何角色，不生成台词。你只根据场景、角色设定和历史记录，决定下一步由哪个 AI 角色发言，或是否等待用户。不要替用户发言。不要让不存在的角色发言。只返回 JSON。';

  factory RoleplayDirector.fromJson(Map<String, dynamic> json) {
    return RoleplayDirector(
      name: json['name'] as String? ?? '系统',
      systemPrompt: json['systemPrompt'] as String? ?? defaultSystemPrompt,
      model: RoleplayModelSelection.fromJson(
        Map<String, dynamic>.from(
          json['model'] as Map? ??
              {if (json['modelId'] != null) 'modelId': json['modelId']},
        ),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'systemPrompt': systemPrompt,
    if (!model.isEmpty) 'model': model.toJson(),
  };

  RoleplayDirector copyWith({
    String? name,
    String? systemPrompt,
    RoleplayModelSelection? model,
  }) {
    return RoleplayDirector(
      name: name ?? this.name,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      model: model ?? this.model,
    );
  }
}

class RoleplayParticipant {
  final String id;
  final String? sourceRoleId;
  final String name;
  final String description;
  final String systemPrompt;
  final RoleplayModelSelection model;
  final int? themeColor;
  final bool isPlayer;
  final List<String> groupIds;

  const RoleplayParticipant({
    required this.id,
    this.sourceRoleId,
    required this.name,
    this.description = '',
    required this.systemPrompt,
    this.model = const RoleplayModelSelection(),
    this.themeColor,
    this.isPlayer = false,
    this.groupIds = const [],
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
      model: RoleplayModelSelection.fromJson(
        Map<String, dynamic>.from(
          json['model'] as Map? ??
              {if (json['modelId'] != null) 'modelId': json['modelId']},
        ),
      ),
      themeColor: (json['themeColor'] as num?)?.toInt(),
      isPlayer: json['isPlayer'] as bool? ?? false,
      groupIds: (json['groupIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (sourceRoleId != null) 'sourceRoleId': sourceRoleId,
    'name': name,
    'description': description,
    'systemPrompt': systemPrompt,
    if (!model.isEmpty) 'model': model.toJson(),
    if (themeColor != null) 'themeColor': themeColor,
    'isPlayer': isPlayer,
    if (groupIds.isNotEmpty) 'groupIds': groupIds,
  };

  RoleplayParticipant copyWith({
    String? id,
    Object? sourceRoleId = _sentinel,
    String? name,
    String? description,
    String? systemPrompt,
    RoleplayModelSelection? model,
    Object? themeColor = _sentinel,
    bool? isPlayer,
    List<String>? groupIds,
  }) {
    return RoleplayParticipant(
      id: id ?? this.id,
      sourceRoleId: identical(sourceRoleId, _sentinel)
          ? this.sourceRoleId
          : sourceRoleId as String?,
      name: name ?? this.name,
      description: description ?? this.description,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      model: model ?? this.model,
      themeColor: identical(themeColor, _sentinel)
          ? this.themeColor
          : themeColor as int?,
      isPlayer: isPlayer ?? this.isPlayer,
      groupIds: groupIds ?? this.groupIds,
    );
  }

  static const _sentinel = Object();
}

class RoleplayParticipantGroup {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RoleplayParticipantGroup({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RoleplayParticipantGroup.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final id = json['id'] as String? ?? '';
    if (id.isEmpty) throw const FormatException('Malformed roleplay group');
    return RoleplayParticipantGroup(
      id: id,
      name: json['name'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  RoleplayParticipantGroup copyWith({String? name, DateTime? updatedAt}) {
    return RoleplayParticipantGroup(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class RoleplayScenario {
  final String id;
  final String title;
  final String description;
  final String scenario;
  final RoleplayDirector director;
  final RoleplayParticipant defaultPlayer;
  final List<RoleplayParticipant> defaultParticipants;
  final List<RoleplayParticipantGroup> defaultGroups;
  final int maxAutoTurns;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RoleplayScenario({
    required this.id,
    required this.title,
    this.description = '',
    required this.scenario,
    required this.director,
    required this.defaultPlayer,
    this.defaultParticipants = const [],
    this.defaultGroups = const [],
    this.maxAutoTurns = 3,
    this.pinned = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RoleplayScenario.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    if (id.isEmpty || createdAt == null || updatedAt == null) {
      throw const FormatException('Malformed roleplay scenario');
    }
    return RoleplayScenario(
      id: id,
      title: json['title'] as String? ?? '情景演绎',
      description: json['description'] as String? ?? '',
      scenario: json['scenario'] as String? ?? '',
      director: RoleplayDirector.fromJson(
        Map<String, dynamic>.from(json['director'] as Map? ?? const {}),
      ),
      defaultPlayer: RoleplayParticipant.fromJson(
        Map<String, dynamic>.from(
          json['defaultPlayer'] as Map? ??
              {
                'id': 'player',
                'name': '我',
                'systemPrompt': '',
                'isPlayer': true,
              },
        ),
      ),
      defaultParticipants: _participantsFromJson(json['defaultParticipants']),
      defaultGroups: _groupsFromJson(json['defaultGroups']),
      maxAutoTurns: (json['maxAutoTurns'] as num?)?.toInt() ?? 3,
      pinned: json['pinned'] as bool? ?? false,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'scenario': scenario,
    'director': director.toJson(),
    'defaultPlayer': defaultPlayer.toJson(),
    'defaultParticipants': defaultParticipants
        .map((item) => item.toJson())
        .toList(),
    'defaultGroups': defaultGroups.map((item) => item.toJson()).toList(),
    'maxAutoTurns': maxAutoTurns,
    'pinned': pinned,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  RoleplayScenario copyWith({
    String? title,
    String? description,
    String? scenario,
    RoleplayDirector? director,
    RoleplayParticipant? defaultPlayer,
    List<RoleplayParticipant>? defaultParticipants,
    List<RoleplayParticipantGroup>? defaultGroups,
    int? maxAutoTurns,
    bool? pinned,
    DateTime? updatedAt,
  }) {
    return RoleplayScenario(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      scenario: scenario ?? this.scenario,
      director: director ?? this.director,
      defaultPlayer: defaultPlayer ?? this.defaultPlayer,
      defaultParticipants: defaultParticipants ?? this.defaultParticipants,
      defaultGroups: defaultGroups ?? this.defaultGroups,
      maxAutoTurns: maxAutoTurns ?? this.maxAutoTurns,
      pinned: pinned ?? this.pinned,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class RoleplayMessage {
  final String id;
  final String speakerId;
  final String speakerName;
  final String content;
  final RoleplayMessageKind kind;
  final List<MessageImage> attachments;
  final DateTime timestamp;

  const RoleplayMessage({
    required this.id,
    required this.speakerId,
    required this.speakerName,
    required this.content,
    required this.kind,
    this.attachments = const [],
    required this.timestamp,
  });

  factory RoleplayMessage.fromJson(Map<String, dynamic> json) {
    final timestamp = DateTime.tryParse(json['timestamp'] as String? ?? '');
    final id = json['id'] as String? ?? '';
    if (id.isEmpty || timestamp == null) {
      throw const FormatException('Malformed roleplay message');
    }
    return RoleplayMessage(
      id: id,
      speakerId: json['speakerId'] as String? ?? '',
      speakerName: json['speakerName'] as String? ?? '',
      content: json['content'] as String? ?? '',
      kind: RoleplayMessageKind.values.firstWhere(
        (kind) => kind.name == json['kind'],
        orElse: () => RoleplayMessageKind.character,
      ),
      attachments:
          (json['attachments'] as List<dynamic>? ??
                  json['images'] as List<dynamic>? ??
                  const [])
              .whereType<Map>()
              .map(
                (item) =>
                    MessageImage.fromJson(Map<String, dynamic>.from(item)),
              )
              .where((item) => item.path.isNotEmpty)
              .toList(),
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'speakerId': speakerId,
    'speakerName': speakerName,
    'content': content,
    'kind': kind.name,
    if (attachments.isNotEmpty)
      'attachments': attachments.map((item) => item.toJson()).toList(),
    'timestamp': timestamp.toIso8601String(),
  };

  RoleplayMessage copyWith({String? content}) {
    return RoleplayMessage(
      id: id,
      speakerId: speakerId,
      speakerName: speakerName,
      content: content ?? this.content,
      kind: kind,
      attachments: attachments,
      timestamp: timestamp,
    );
  }
}

class RoleplayThread {
  final String id;
  final String scenarioId;
  final String title;
  final String scenarioTitle;
  final String scenario;
  final RoleplayDirector director;
  final List<RoleplayParticipant> participants;
  final List<RoleplayParticipantGroup> groups;
  final String playerParticipantId;
  final List<RoleplayMessage> messages;
  final int maxAutoTurns;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RoleplayThread({
    required this.id,
    required this.scenarioId,
    required this.title,
    required this.scenarioTitle,
    required this.scenario,
    required this.director,
    required this.participants,
    this.groups = const [],
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

  String get preview {
    for (final message in messages) {
      if (message.kind == RoleplayMessageKind.player) {
        final clean = message.content
            .replaceAll(RegExp(r'[\r\n]+'), ' ')
            .trim();
        if (clean.isNotEmpty) {
          return clean.length > 80 ? '${clean.substring(0, 80)}...' : clean;
        }
        if (message.attachments.isNotEmpty) {
          return '[附件] ${message.attachments.first.name}';
        }
      }
    }
    if (messages.isEmpty) return '';
    final clean = messages.last.content
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    return clean.length > 80 ? '${clean.substring(0, 80)}...' : clean;
  }

  factory RoleplayThread.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final scenarioId = json['scenarioId'] as String? ?? '';
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    if (id.isEmpty ||
        scenarioId.isEmpty ||
        createdAt == null ||
        updatedAt == null) {
      throw const FormatException('Malformed roleplay thread');
    }
    return RoleplayThread(
      id: id,
      scenarioId: scenarioId,
      title: json['title'] as String? ?? '情景演绎',
      scenarioTitle: json['scenarioTitle'] as String? ?? '情景演绎',
      scenario: json['scenario'] as String? ?? '',
      director: RoleplayDirector.fromJson(
        Map<String, dynamic>.from(json['director'] as Map? ?? const {}),
      ),
      participants: _participantsFromJson(json['participants']),
      groups: _groupsFromJson(json['groups']),
      playerParticipantId: json['playerParticipantId'] as String? ?? '',
      messages: _messagesFromJson(json['messages']),
      maxAutoTurns: (json['maxAutoTurns'] as num?)?.toInt() ?? 3,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'scenarioId': scenarioId,
    'title': title,
    'scenarioTitle': scenarioTitle,
    'scenario': scenario,
    'director': director.toJson(),
    'participants': participants.map((item) => item.toJson()).toList(),
    'groups': groups.map((item) => item.toJson()).toList(),
    'playerParticipantId': playerParticipantId,
    'messages': messages.map((item) => item.toJson()).toList(),
    'maxAutoTurns': maxAutoTurns,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  RoleplayThread copyWith({
    String? title,
    String? scenarioTitle,
    String? scenario,
    RoleplayDirector? director,
    List<RoleplayParticipant>? participants,
    List<RoleplayParticipantGroup>? groups,
    String? playerParticipantId,
    List<RoleplayMessage>? messages,
    int? maxAutoTurns,
    DateTime? updatedAt,
  }) {
    return RoleplayThread(
      id: id,
      scenarioId: scenarioId,
      title: title ?? this.title,
      scenarioTitle: scenarioTitle ?? this.scenarioTitle,
      scenario: scenario ?? this.scenario,
      director: director ?? this.director,
      participants: participants ?? this.participants,
      groups: groups ?? this.groups,
      playerParticipantId: playerParticipantId ?? this.playerParticipantId,
      messages: messages ?? this.messages,
      maxAutoTurns: maxAutoTurns ?? this.maxAutoTurns,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

List<RoleplayParticipant> _participantsFromJson(Object? raw) {
  final participants = <RoleplayParticipant>[];
  for (final item in raw as List<dynamic>? ?? const []) {
    try {
      if (item is Map) {
        participants.add(
          RoleplayParticipant.fromJson(Map<String, dynamic>.from(item)),
        );
      }
    } catch (_) {}
  }
  return participants;
}

List<RoleplayParticipantGroup> _groupsFromJson(Object? raw) {
  final groups = <RoleplayParticipantGroup>[];
  for (final item in raw as List<dynamic>? ?? const []) {
    try {
      if (item is Map) {
        groups.add(
          RoleplayParticipantGroup.fromJson(Map<String, dynamic>.from(item)),
        );
      }
    } catch (_) {}
  }
  return groups;
}

List<RoleplayMessage> _messagesFromJson(Object? raw) {
  final messages = <RoleplayMessage>[];
  for (final item in raw as List<dynamic>? ?? const []) {
    try {
      if (item is Map) {
        messages.add(RoleplayMessage.fromJson(Map<String, dynamic>.from(item)));
      }
    } catch (_) {}
  }
  return messages;
}
