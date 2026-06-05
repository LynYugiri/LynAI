import 'message.dart';

/// 角色扮演消息的类型。
///
/// 区分消息来源：玩家发言、角色发言、系统指令或旁白叙述。
enum RoleplayMessageKind { player, character, system, narrator }

/// 角色扮演中为某个角色或导演指定的模型选择。
class RoleplayModelSelection {
  /// 所选模型的配置 ID。
  final String? modelId;

  /// 所选模型的名称。
  final String? modelName;

  /// 创建一个角色扮演模型选择实例。
  const RoleplayModelSelection({this.modelId, this.modelName});

  /// 是否未指定任何模型。
  bool get isEmpty => modelId == null || modelId!.isEmpty;

  /// 从 JSON 数据创建 [RoleplayModelSelection] 实例。
  factory RoleplayModelSelection.fromJson(Map<String, dynamic> json) {
    return RoleplayModelSelection(
      modelId: json['modelId'] as String?,
      modelName: json['modelName'] as String?,
    );
  }

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() => {
    if (modelId != null && modelId!.isNotEmpty) 'modelId': modelId,
    if (modelName != null && modelName!.isNotEmpty) 'modelName': modelName,
  };

  /// 创建当前实例的副本，可选择性更新部分字段。
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

/// 角色扮演导演配置。
///
/// 导演不扮演任何角色，只负责根据场景和角色设定决定下一步由哪个 AI 角色发言。
class RoleplayDirector {
  /// 导演名称。
  final String name;

  /// 导演的系统提示词，定义其决策规则。
  final String systemPrompt;

  /// 导演使用的模型选择。
  final RoleplayModelSelection model;

  /// 创建一个角色扮演导演实例。
  const RoleplayDirector({
    this.name = '系统',
    this.systemPrompt = defaultSystemPrompt,
    this.model = const RoleplayModelSelection(),
  });

  /// 导演的默认系统提示词。
  static const defaultSystemPrompt =
      '你是多角色情景演绎的导演。你不扮演任何角色，不生成台词。你只根据场景、角色设定和历史记录，决定下一步由哪个 AI 角色发言，或是否等待用户。不要替用户发言。不要让不存在的角色发言。只返回 JSON。';

  /// 从 JSON 数据创建 [RoleplayDirector] 实例。
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

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() => {
    'name': name,
    'systemPrompt': systemPrompt,
    if (!model.isEmpty) 'model': model.toJson(),
  };

  /// 创建当前实例的副本，可选择性更新部分字段。
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

/// 角色扮演中的一个参与者（角色或玩家）。
class RoleplayParticipant {
  /// 参与者唯一标识符。
  final String id;

  /// 来源角色 ID，用于跟踪角色模板的来源。
  final String? sourceRoleId;

  /// 参与者名称。
  final String name;

  /// 参与者描述，供 AI 理解角色背景。
  final String description;

  /// 参与者的系统提示词，定义其发言风格和行为规则。
  final String systemPrompt;

  /// 参与者独立使用的模型选择。
  final RoleplayModelSelection model;

  /// 主题颜色值，用于 UI 中区分不同角色。
  final int? themeColor;

  /// 是否为玩家自身。
  final bool isPlayer;

  /// 所属角色分组的 ID 列表。
  final List<String> groupIds;

  /// 创建一个角色扮演参与者实例。
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

  /// 从 JSON 数据创建 [RoleplayParticipant] 实例。
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

  /// 将当前实例序列化为 JSON Map。
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

  /// 创建当前实例的副本，可选择性更新部分字段。
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

/// 角色扮演参与者分组。
///
/// 用于将多个角色归类到同一分组中，方便批量管理或按组切换。
class RoleplayParticipantGroup {
  /// 分组唯一标识符。
  final String id;

  /// 分组名称。
  final String name;

  /// 分组创建时间。
  final DateTime createdAt;

  /// 分组最后更新时间。
  final DateTime updatedAt;

  /// 创建一个参与者分组实例。
  const RoleplayParticipantGroup({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 从 JSON 数据创建 [RoleplayParticipantGroup] 实例。
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

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// 创建当前实例的副本，可选择性更新部分字段。
  RoleplayParticipantGroup copyWith({String? name, DateTime? updatedAt}) {
    return RoleplayParticipantGroup(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 角色扮演场景模板。
///
/// 定义一次情景演绎的完整设定，包括导演、参与者、群组和默认玩家配置。
/// 从场景模板可以创建多个演绎线程。
class RoleplayScenario {
  /// 场景模板唯一标识符。
  final String id;

  /// 场景模板标题。
  final String title;

  /// 场景模板的简要描述。
  final String description;

  /// 场景的详细设定文本。
  final String scenario;

  /// 导演配置。
  final RoleplayDirector director;

  /// 默认玩家参与者配置。
  final RoleplayParticipant defaultPlayer;

  /// 默认 AI 角色参与者列表。
  final List<RoleplayParticipant> defaultParticipants;

  /// 默认角色分组列表。
  final List<RoleplayParticipantGroup> defaultGroups;

  /// AI 角色自动连续发言的最大轮次。
  final int maxAutoTurns;

  /// 是否置顶显示。
  final bool pinned;

  /// 场景模板创建时间。
  final DateTime createdAt;

  /// 场景模板最后更新时间。
  final DateTime updatedAt;

  /// 创建一个角色扮演场景模板实例。
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

  /// 从 JSON 数据创建 [RoleplayScenario] 实例。
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

  /// 将当前实例序列化为 JSON Map。
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

  /// 创建当前实例的副本，可选择性更新部分字段。
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

/// 角色扮演中的一条消息记录。
class RoleplayMessage {
  /// 消息唯一标识符。
  final String id;

  /// 发言者 ID。
  final String speakerId;

  /// 发言者名称。
  final String speakerName;

  /// 消息文本内容。
  final String content;

  /// 消息类型，区分玩家、角色、系统或旁白。
  final RoleplayMessageKind kind;

  /// 消息附带的图片和文件列表。
  final List<MessageImage> attachments;

  /// 消息时间戳。
  final DateTime timestamp;

  /// 创建一个角色扮演消息实例。
  const RoleplayMessage({
    required this.id,
    required this.speakerId,
    required this.speakerName,
    required this.content,
    required this.kind,
    this.attachments = const [],
    required this.timestamp,
  });

  /// 从 JSON 数据创建 [RoleplayMessage] 实例。
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

  /// 将当前实例序列化为 JSON Map。
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

  /// 创建当前实例的副本，可选择性更新内容字段。
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

/// 角色扮演的一次演绎会话。
///
/// 从场景模板创建，保存实际演绎过程中的参与者、消息和状态。每个线程
/// 独立的参与者列表允许用户在演绎中临时调整角色配置。
class RoleplayThread {
  /// 会话唯一标识符。
  final String id;

  /// 来源场景模板 ID。
  final String scenarioId;

  /// 会话标题。
  final String title;

  /// 来源场景模板的标题。
  final String scenarioTitle;

  /// 场景设定文本。
  final String scenario;

  /// 导演配置。
  final RoleplayDirector director;

  /// 当前会话中的参与者列表。
  final List<RoleplayParticipant> participants;

  /// 当前会话中的角色分组列表。
  final List<RoleplayParticipantGroup> groups;

  /// 玩家参与者的 ID。
  final String playerParticipantId;

  /// 会话中所有消息记录。
  final List<RoleplayMessage> messages;

  /// AI 角色自动连续发言的最大轮次。
  final int maxAutoTurns;

  /// 会话创建时间。
  final DateTime createdAt;

  /// 会话最后更新时间。
  final DateTime updatedAt;

  /// 创建一个角色扮演会话实例。
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

  /// 获取当前会话中的玩家参与者。
  RoleplayParticipant? get player {
    for (final participant in participants) {
      if (participant.id == playerParticipantId) return participant;
    }
    return null;
  }

  /// 获取当前会话中所有 AI 角色参与者列表。
  List<RoleplayParticipant> get characters => participants
      .where((participant) => !participant.isPlayer)
      .toList(growable: false);

  /// 生成会话的预览文本，优先显示最近一条玩家消息。
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

  /// 从 JSON 数据创建 [RoleplayThread] 实例。
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

  /// 将当前实例序列化为 JSON Map。
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

  /// 创建当前实例的副本，可选择性更新部分字段。
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

/// 从 JSON 数据解析参与者列表。
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

/// 从 JSON 数据解析分组列表。
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

/// 从 JSON 数据解析消息列表。
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
