import '../agent_working_memory.dart';

/// 新手向导生成的可编辑配置草稿。
///
/// 这是 AI 生成结果与本地模板共用的中间结构：用户可在预览页编辑这些纯文本
/// 字段，确认后再由 [OnboardingService] 落地为真实角色、知识库、牌组等资源。
class OnboardingDraft {
  final OnboardingRoleDraft role;
  final AgentWorkingMemory roleMemory;
  final OnboardingAgentDraft agent;
  final List<OnboardingKnowledgeBaseDraft> knowledgeBases;
  final List<OnboardingMemoryDeckDraft> memoryDecks;
  final List<OnboardingTaskListDraft> taskLists;
  final List<OnboardingNoteFolderDraft> noteFolders;
  final OnboardingSkillDraft? skill;

  const OnboardingDraft({
    required this.role,
    required this.roleMemory,
    required this.agent,
    this.knowledgeBases = const [],
    this.memoryDecks = const [],
    this.taskLists = const [],
    this.noteFolders = const [],
    this.skill,
  });

  factory OnboardingDraft.empty() {
    return OnboardingDraft(
      role: OnboardingRoleDraft(
        name: '我的助手',
        description: '根据新手向导生成的专属助手',
        systemPrompt: 'You are a helpful assistant. 请使用中文回答，语气友好、简洁。',
      ),
      roleMemory: AgentWorkingMemory(updatedAt: DateTime.now()),
      agent: OnboardingAgentDraft(enabledByDefault: false, intents: const []),
    );
  }

  factory OnboardingDraft.fromJson(Map<String, dynamic> json) {
    AgentWorkingMemory memory = AgentWorkingMemory(updatedAt: DateTime.now());
    final rawMemory = json['roleMemory'];
    if (rawMemory is Map) {
      try {
        final parsed = AgentWorkingMemory.fromJson(
          Map<String, dynamic>.from(rawMemory),
        );
        if (!parsed.isEmpty) memory = parsed;
      } catch (_) {
        // 忽略损坏记忆，保留空记忆。
      }
    }

    return OnboardingDraft(
      role: json['role'] is Map
          ? OnboardingRoleDraft.fromJson(
              Map<String, dynamic>.from(json['role']),
            )
          : OnboardingRoleDraft(
              name: '我的助手',
              description: '',
              systemPrompt: 'You are a helpful assistant.',
            ),
      roleMemory: memory,
      agent: json['agent'] is Map
          ? OnboardingAgentDraft.fromJson(
              Map<String, dynamic>.from(json['agent']),
            )
          : OnboardingAgentDraft(enabledByDefault: false, intents: const []),
      knowledgeBases: _list(json['knowledgeBases'])
          .map(
            (item) => OnboardingKnowledgeBaseDraft.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      memoryDecks: _list(json['memoryDecks'])
          .map(
            (item) => OnboardingMemoryDeckDraft.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      taskLists: _list(json['taskLists'])
          .map(
            (item) => OnboardingTaskListDraft.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      noteFolders: _list(json['noteFolders'])
          .map(
            (item) => OnboardingNoteFolderDraft.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      skill: json['skill'] is Map
          ? OnboardingSkillDraft.fromJson(
              Map<String, dynamic>.from(json['skill']),
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'role': role.toJson(),
    'roleMemory': roleMemory.toJson(),
    'agent': agent.toJson(),
    'knowledgeBases': knowledgeBases.map((e) => e.toJson()).toList(),
    'memoryDecks': memoryDecks.map((e) => e.toJson()).toList(),
    'taskLists': taskLists.map((e) => e.toJson()).toList(),
    'noteFolders': noteFolders.map((e) => e.toJson()).toList(),
    if (skill != null) 'skill': skill!.toJson(),
  };

  OnboardingDraft copyWith({
    OnboardingRoleDraft? role,
    AgentWorkingMemory? roleMemory,
    OnboardingAgentDraft? agent,
    List<OnboardingKnowledgeBaseDraft>? knowledgeBases,
    List<OnboardingMemoryDeckDraft>? memoryDecks,
    List<OnboardingTaskListDraft>? taskLists,
    List<OnboardingNoteFolderDraft>? noteFolders,
    Object? skill = _unset,
  }) {
    return OnboardingDraft(
      role: role ?? this.role,
      roleMemory: roleMemory ?? this.roleMemory,
      agent: agent ?? this.agent,
      knowledgeBases: knowledgeBases ?? this.knowledgeBases,
      memoryDecks: memoryDecks ?? this.memoryDecks,
      taskLists: taskLists ?? this.taskLists,
      noteFolders: noteFolders ?? this.noteFolders,
      skill: identical(skill, _unset)
          ? this.skill
          : skill as OnboardingSkillDraft?,
    );
  }

  static List<dynamic> _list(Object? raw) {
    if (raw is List) return raw;
    return const [];
  }

  static const _unset = Object();
}

class OnboardingRoleDraft {
  final String name;
  final String description;
  final String systemPrompt;

  const OnboardingRoleDraft({
    required this.name,
    this.description = '',
    required this.systemPrompt,
  });

  factory OnboardingRoleDraft.fromJson(Map<String, dynamic> json) {
    return OnboardingRoleDraft(
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : '我的助手',
      description: (json['description'] as String?)?.trim() ?? '',
      systemPrompt: (json['systemPrompt'] as String?)?.trim().isNotEmpty == true
          ? (json['systemPrompt'] as String).trim()
          : 'You are a helpful assistant.',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description.isNotEmpty) 'description': description,
    'systemPrompt': systemPrompt,
  };

  OnboardingRoleDraft copyWith({
    String? name,
    String? description,
    String? systemPrompt,
  }) {
    return OnboardingRoleDraft(
      name: name ?? this.name,
      description: description ?? this.description,
      systemPrompt: systemPrompt ?? this.systemPrompt,
    );
  }
}

class OnboardingAgentDraft {
  final bool enabledByDefault;
  final List<String> intents;

  const OnboardingAgentDraft({
    this.enabledByDefault = false,
    this.intents = const [],
  });

  factory OnboardingAgentDraft.fromJson(Map<String, dynamic> json) {
    final rawIntents = json['intents'];
    final intents = <String>[];
    if (rawIntents is List) {
      for (final item in rawIntents) {
        final value = item.toString().trim();
        if (value.isNotEmpty) intents.add(value);
      }
    }
    return OnboardingAgentDraft(
      enabledByDefault: json['enabledByDefault'] as bool? ?? false,
      intents: intents.toSet().toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabledByDefault': enabledByDefault,
    'intents': intents,
  };

  OnboardingAgentDraft copyWith({
    bool? enabledByDefault,
    List<String>? intents,
  }) {
    return OnboardingAgentDraft(
      enabledByDefault: enabledByDefault ?? this.enabledByDefault,
      intents: intents ?? this.intents,
    );
  }
}

class OnboardingKnowledgeCategoryDraft {
  final String name;
  final String alias;
  final String annotationRule;
  final String explanationPrompt;

  const OnboardingKnowledgeCategoryDraft({
    required this.name,
    required this.alias,
    this.annotationRule = '',
    this.explanationPrompt = '',
  });

  factory OnboardingKnowledgeCategoryDraft.fromJson(Map<String, dynamic> json) {
    return OnboardingKnowledgeCategoryDraft(
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : '未命名类别',
      alias: (json['alias'] as String?)?.trim() ?? '',
      annotationRule: (json['annotationRule'] as String?)?.trim() ?? '',
      explanationPrompt: (json['explanationPrompt'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'alias': alias,
    if (annotationRule.isNotEmpty) 'annotationRule': annotationRule,
    if (explanationPrompt.isNotEmpty) 'explanationPrompt': explanationPrompt,
  };

  OnboardingKnowledgeCategoryDraft copyWith({
    String? name,
    String? alias,
    String? annotationRule,
    String? explanationPrompt,
  }) {
    return OnboardingKnowledgeCategoryDraft(
      name: name ?? this.name,
      alias: alias ?? this.alias,
      annotationRule: annotationRule ?? this.annotationRule,
      explanationPrompt: explanationPrompt ?? this.explanationPrompt,
    );
  }
}

class OnboardingKnowledgeEntryDraft {
  final String title;
  final String content;
  final String categoryName;

  const OnboardingKnowledgeEntryDraft({
    required this.title,
    this.content = '',
    this.categoryName = '',
  });

  factory OnboardingKnowledgeEntryDraft.fromJson(Map<String, dynamic> json) {
    return OnboardingKnowledgeEntryDraft(
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : '未命名条目',
      content: (json['content'] as String?)?.trim() ?? '',
      categoryName: (json['category'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'content': content,
    if (categoryName.isNotEmpty) 'category': categoryName,
  };

  OnboardingKnowledgeEntryDraft copyWith({
    String? title,
    String? content,
    String? categoryName,
  }) {
    return OnboardingKnowledgeEntryDraft(
      title: title ?? this.title,
      content: content ?? this.content,
      categoryName: categoryName ?? this.categoryName,
    );
  }
}

class OnboardingKnowledgeBaseDraft {
  final String name;
  final String description;
  final List<OnboardingKnowledgeCategoryDraft> categories;
  final List<OnboardingKnowledgeEntryDraft> entries;

  const OnboardingKnowledgeBaseDraft({
    required this.name,
    this.description = '',
    this.categories = const [],
    this.entries = const [],
  });

  factory OnboardingKnowledgeBaseDraft.fromJson(Map<String, dynamic> json) {
    return OnboardingKnowledgeBaseDraft(
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : '我的知识库',
      description: (json['description'] as String?)?.trim() ?? '',
      categories: _list(json['categories'])
          .map(
            (item) => OnboardingKnowledgeCategoryDraft.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      entries: _list(json['entries'])
          .map(
            (item) => OnboardingKnowledgeEntryDraft.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description.isNotEmpty) 'description': description,
    'categories': categories.map((e) => e.toJson()).toList(),
    'entries': entries.map((e) => e.toJson()).toList(),
  };

  OnboardingKnowledgeBaseDraft copyWith({
    String? name,
    String? description,
    List<OnboardingKnowledgeCategoryDraft>? categories,
    List<OnboardingKnowledgeEntryDraft>? entries,
  }) {
    return OnboardingKnowledgeBaseDraft(
      name: name ?? this.name,
      description: description ?? this.description,
      categories: categories ?? this.categories,
      entries: entries ?? this.entries,
    );
  }

  static List<dynamic> _list(Object? raw) => raw is List ? raw : const [];
}

class OnboardingMemoryCardDraft {
  final String front;
  final String back;
  final String hint;

  const OnboardingMemoryCardDraft({
    required this.front,
    required this.back,
    this.hint = '',
  });

  factory OnboardingMemoryCardDraft.fromJson(Map<String, dynamic> json) {
    return OnboardingMemoryCardDraft(
      front: (json['front'] as String?)?.trim() ?? '',
      back: (json['back'] as String?)?.trim() ?? '',
      hint: (json['hint'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'front': front,
    'back': back,
    if (hint.isNotEmpty) 'hint': hint,
  };

  OnboardingMemoryCardDraft copyWith({
    String? front,
    String? back,
    String? hint,
  }) {
    return OnboardingMemoryCardDraft(
      front: front ?? this.front,
      back: back ?? this.back,
      hint: hint ?? this.hint,
    );
  }
}

class OnboardingMemoryDeckDraft {
  final String name;
  final String description;
  final int newPerDayLimit;
  final int reviewPerDayLimit;
  final List<OnboardingMemoryCardDraft> cards;

  const OnboardingMemoryDeckDraft({
    required this.name,
    this.description = '',
    this.newPerDayLimit = 20,
    this.reviewPerDayLimit = 200,
    this.cards = const [],
  });

  factory OnboardingMemoryDeckDraft.fromJson(Map<String, dynamic> json) {
    return OnboardingMemoryDeckDraft(
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : '我的牌组',
      description: (json['description'] as String?)?.trim() ?? '',
      newPerDayLimit: (json['newPerDayLimit'] as num?)?.toInt() ?? 20,
      reviewPerDayLimit: (json['reviewPerDayLimit'] as num?)?.toInt() ?? 200,
      cards: _list(json['cards'])
          .map(
            (item) => OnboardingMemoryCardDraft.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description.isNotEmpty) 'description': description,
    'newPerDayLimit': newPerDayLimit,
    'reviewPerDayLimit': reviewPerDayLimit,
    'cards': cards.map((e) => e.toJson()).toList(),
  };

  OnboardingMemoryDeckDraft copyWith({
    String? name,
    String? description,
    int? newPerDayLimit,
    int? reviewPerDayLimit,
    List<OnboardingMemoryCardDraft>? cards,
  }) {
    return OnboardingMemoryDeckDraft(
      name: name ?? this.name,
      description: description ?? this.description,
      newPerDayLimit: newPerDayLimit ?? this.newPerDayLimit,
      reviewPerDayLimit: reviewPerDayLimit ?? this.reviewPerDayLimit,
      cards: cards ?? this.cards,
    );
  }

  static List<dynamic> _list(Object? raw) => raw is List ? raw : const [];
}

class OnboardingTaskDraft {
  final String title;
  final String note;

  const OnboardingTaskDraft({required this.title, this.note = ''});

  factory OnboardingTaskDraft.fromJson(Map<String, dynamic> json) {
    return OnboardingTaskDraft(
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : '未命名任务',
      note: (json['note'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    if (note.isNotEmpty) 'note': note,
  };

  OnboardingTaskDraft copyWith({String? title, String? note}) {
    return OnboardingTaskDraft(
      title: title ?? this.title,
      note: note ?? this.note,
    );
  }
}

class OnboardingTaskListDraft {
  final String title;
  final List<OnboardingTaskDraft> tasks;

  const OnboardingTaskListDraft({required this.title, this.tasks = const []});

  factory OnboardingTaskListDraft.fromJson(Map<String, dynamic> json) {
    return OnboardingTaskListDraft(
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : '我的任务清单',
      tasks: _list(json['tasks'])
          .map(
            (item) =>
                OnboardingTaskDraft.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'tasks': tasks.map((e) => e.toJson()).toList(),
  };

  OnboardingTaskListDraft copyWith({
    String? title,
    List<OnboardingTaskDraft>? tasks,
  }) {
    return OnboardingTaskListDraft(
      title: title ?? this.title,
      tasks: tasks ?? this.tasks,
    );
  }

  static List<dynamic> _list(Object? raw) => raw is List ? raw : const [];
}

class OnboardingNoteDraft {
  final String title;
  final String content;

  const OnboardingNoteDraft({required this.title, this.content = ''});

  factory OnboardingNoteDraft.fromJson(Map<String, dynamic> json) {
    return OnboardingNoteDraft(
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : '未命名笔记',
      content: (json['content'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'title': title, 'content': content};

  OnboardingNoteDraft copyWith({String? title, String? content}) {
    return OnboardingNoteDraft(
      title: title ?? this.title,
      content: content ?? this.content,
    );
  }
}

class OnboardingNoteFolderDraft {
  final String title;
  final List<OnboardingNoteDraft> notes;

  const OnboardingNoteFolderDraft({required this.title, this.notes = const []});

  factory OnboardingNoteFolderDraft.fromJson(Map<String, dynamic> json) {
    return OnboardingNoteFolderDraft(
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : '我的笔记',
      notes: _list(json['notes'])
          .map(
            (item) =>
                OnboardingNoteDraft.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'notes': notes.map((e) => e.toJson()).toList(),
  };

  OnboardingNoteFolderDraft copyWith({
    String? title,
    List<OnboardingNoteDraft>? notes,
  }) {
    return OnboardingNoteFolderDraft(
      title: title ?? this.title,
      notes: notes ?? this.notes,
    );
  }

  static List<dynamic> _list(Object? raw) => raw is List ? raw : const [];
}

class OnboardingSkillDraft {
  final String pluginId;
  final String name;
  final String title;
  final String description;
  final String whenToUse;
  final List<String> tags;
  final String body;

  const OnboardingSkillDraft({
    required this.pluginId,
    required this.name,
    required this.title,
    this.description = '',
    this.whenToUse = '',
    this.tags = const [],
    required this.body,
  });

  factory OnboardingSkillDraft.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    final tags = <String>[];
    if (rawTags is List) {
      for (final item in rawTags) {
        final value = item.toString().trim();
        if (value.isNotEmpty) tags.add(value);
      }
    }
    return OnboardingSkillDraft(
      pluginId: (json['pluginId'] as String?)?.trim().isNotEmpty == true
          ? (json['pluginId'] as String).trim()
          : 'user-onboarding-skill',
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : 'my_workflow',
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : '我的工作流',
      description: (json['description'] as String?)?.trim() ?? '',
      whenToUse: (json['whenToUse'] as String?)?.trim() ?? '',
      tags: tags.toSet().toList(growable: false),
      body: (json['body'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'pluginId': pluginId,
    'name': name,
    'title': title,
    if (description.isNotEmpty) 'description': description,
    if (whenToUse.isNotEmpty) 'whenToUse': whenToUse,
    if (tags.isNotEmpty) 'tags': tags,
    'body': body,
  };

  OnboardingSkillDraft copyWith({
    String? pluginId,
    String? name,
    String? title,
    String? description,
    String? whenToUse,
    List<String>? tags,
    String? body,
  }) {
    return OnboardingSkillDraft(
      pluginId: pluginId ?? this.pluginId,
      name: name ?? this.name,
      title: title ?? this.title,
      description: description ?? this.description,
      whenToUse: whenToUse ?? this.whenToUse,
      tags: tags ?? this.tags,
      body: body ?? this.body,
    );
  }
}
