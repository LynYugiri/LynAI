import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/agent_defaults.dart';
import '../models/agent_working_memory.dart';
import '../models/memory_card.dart';
import '../models/model_config.dart';
import '../models/onboarding/onboarding_draft.dart';
import '../models/onboarding/onboarding_input.dart';
import '../providers/feature_provider.dart';
import '../providers/knowledge_provider.dart';
import '../providers/memory_card_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/task_provider.dart';
import '../repositories/plugin_repository.dart';
import 'api_service.dart';
import 'lynai_permission_definitions.dart';
import 'plugin_scaffold_service.dart';
import '../models/plugin.dart' show PluginDevState;

/// 新手向导生成与应用服务。
///
/// 负责把用户输入转换为 [OnboardingDraft]（AI 或本地模板），并调用各
/// Provider 将草稿落地为真实角色、知识库、牌组、任务清单、笔记与 SKILL。
/// 服务层不依赖 BuildContext，也不直接读写数据库。
class OnboardingService {
  static const defaultModelName = 'deepseek-v4-pro';

  static const validIntents = {
    'notes',
    'todos',
    'schedules',
    'knowledge',
    'plugins',
    'minimal',
  };

  static const _maxKnowledgeBases = 1;
  static const _maxCategoriesPerBase = 4;
  static const _maxEntriesPerBase = 2;
  static const _maxMemoryDecks = 1;
  static const _maxCardsPerDeck = 10;
  static const _maxTaskLists = 2;
  static const _maxTasksPerList = 5;
  static const _maxNoteFolders = 1;
  static const _maxNotesPerFolder = 2;
  static const _maxRoleMemoryEntries = 6;

  final ApiService? apiService;
  final ModelConfigProvider? modelConfigProvider;
  final Uuid _uuid;

  OnboardingService({this.apiService, this.modelConfigProvider, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  // ─── 生成入口 ──────────────────────────────────────────────

  /// 生成配置草稿。优先使用 deepseek-v4-pro，失败或无模型时回退本地模板。
  Future<OnboardingDraft> generate({
    required OnboardingInput input,
    OnboardingDraft? currentDraft,
  }) async {
    final aiDraft = await _tryGenerateWithAi(input, currentDraft);
    return aiDraft ?? buildLocalDraft(input);
  }

  /// 只重新生成欢迎语，不触碰已经应用或编辑过的配置草稿。
  Future<String> generateWelcome({
    required OnboardingInput input,
    required OnboardingDraft draft,
  }) async {
    final aiWelcome = await _tryGenerateWelcomeWithAi(input, draft);
    if (aiWelcome != null && aiWelcome.trim().isNotEmpty) {
      return aiWelcome.trim();
    }
    return _buildLocalWelcome(input, draft);
  }

  Future<String?> _tryGenerateWelcomeWithAi(
    OnboardingInput input,
    OnboardingDraft draft,
  ) async {
    final api = apiService;
    final selected = _selectModel();
    if (api == null || selected == null) return null;

    try {
      final response = await api
          .sendChatRequest(selected, [
            {
              'role': 'system',
              'content':
                  '你是 LynAI 的欢迎语生成器。根据用户的用途、身份和已生成的配置，'
                  '写一段 3-5 句的中文欢迎语，包含：打招呼并报出助手名字、'
                  '说明用户以后可以怎么使唤它、列出已创建的模块、邀请用户花 30 秒'
                  '了解界面。只输出欢迎语文本本身，不要 Markdown，不要引号，不要标题。',
            },
            {
              'role': 'user',
              'content': [
                _buildAiUserPrompt(input, draft),
                '当前欢迎语：${draft.welcomeMessage.trim().isEmpty ? '无' : draft.welcomeMessage}',
                '请换一种说法输出新的欢迎语。',
              ].join('\n'),
            },
          ], thinking: false)
          .timeout(const Duration(seconds: 15));
      return response.content.trim();
    } catch (_) {
      return null;
    }
  }

  Future<OnboardingDraft?> _tryGenerateWithAi(
    OnboardingInput input,
    OnboardingDraft? currentDraft,
  ) async {
    final api = apiService;
    final selected = _selectModel();
    if (api == null || selected == null) return null;

    try {
      final response = await api
          .sendChatRequest(selected, [
            {
              'role': 'system',
              'content':
                  '你是 LynAI 的本地个性化配置生成器。根据用户用途、身份和补充描述生成 JSON 配置草稿。'
                  '只输出 JSON，不要 Markdown，不要解释。所有文本使用中文（用户指定其他语言时除外）。'
                  '生成要克制：最多 1 个知识库、4 个类别、2 篇条目；1 个牌组、10 张卡；'
                  '2 个任务清单、每个 5 个任务；1 个笔记文件夹、2 篇笔记；1 个 SKILL。',
            },
            {
              'role': 'user',
              'content': _buildAiUserPrompt(input, currentDraft),
            },
          ], thinking: false)
          .timeout(const Duration(seconds: 15));

      final content = response.content.trim();
      final json = _extractJsonObject(content);
      if (json == null) return null;
      final draft = _draftFromAiJson(json);
      if (draft == null) return null;
      if (draft.welcomeMessage.trim().isEmpty) {
        return draft.copyWith(
          welcomeMessage: _buildLocalWelcome(input, draft),
        );
      }
      return draft;
    } catch (_) {
      return null;
    }
  }

  /// 选择新手向导使用的模型：优先 [defaultModelName]，否则使用第一个可用
  /// Chat 模型；没有可用模型时返回 null。
  ModelConfig? _selectModel() {
    final provider = modelConfigProvider;
    if (provider == null) return null;
    final chatModels = provider.enabledModelsByCategory(
      ModelConfig.categoryChat,
    );
    if (chatModels.isEmpty) return null;
    for (final model in chatModels) {
      if (model.modelName == defaultModelName) return model;
    }
    return chatModels.first;
  }

  String _buildAiUserPrompt(OnboardingInput input, OnboardingDraft? current) {
    final buffer = StringBuffer()
      ..writeln('用户用途：${_purposeSummary(input)}')
      ..writeln('身份职业：${_occupationLabel(input)}');
    if (input.freeText.trim().isNotEmpty) {
      buffer.writeln('补充描述：${input.freeText.trim()}');
    }
    if (current != null) {
      buffer.writeln('当前用户已经编辑过的草稿如下，请在其基础上修改，而不是完全重写：');
      buffer.writeln(jsonEncode(current.toJson()));
    }
    buffer.writeln('请输出 JSON 草稿。');
    return buffer.toString();
  }

  Map<String, dynamic>? _extractJsonObject(String content) {
    final trimmed = content.trim();
    final firstBrace = trimmed.indexOf('{');
    final lastBrace = trimmed.lastIndexOf('}');
    if (firstBrace < 0 || lastBrace <= firstBrace) return null;
    try {
      final decoded = jsonDecode(trimmed.substring(firstBrace, lastBrace + 1));
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // fall through
    }
    return null;
  }

  // ─── AI JSON 校验与裁剪 ────────────────────────────────────

  OnboardingDraft? _draftFromAiJson(Map<String, dynamic> json) {
    try {
      final roleJson = json['role'];
      if (roleJson is! Map) return null;
      final role = OnboardingRoleDraft.fromJson(
        Map<String, dynamic>.from(roleJson),
      );

      AgentWorkingMemory memory = AgentWorkingMemory(updatedAt: DateTime.now());
      final memoryJson = json['roleMemory'];
      if (memoryJson is Map) {
        final parsed = AgentWorkingMemory.fromJson(
          Map<String, dynamic>.from(memoryJson),
        );
        if (!parsed.isEmpty) memory = _sanitizeMemory(parsed);
      }

      final agentJson = json['agent'];
      final agent = agentJson is Map
          ? OnboardingAgentDraft.fromJson(Map<String, dynamic>.from(agentJson))
          : OnboardingAgentDraft(enabledByDefault: false, intents: const []);
      final sanitizedAgent = OnboardingAgentDraft(
        enabledByDefault: agent.enabledByDefault,
        intents: agent.intents
            .where(validIntents.contains)
            .toSet()
            .toList(growable: false),
      );

      final knowledgeBases = _list(json['knowledgeBases'])
          .take(_maxKnowledgeBases)
          .map(
            (item) => OnboardingKnowledgeBaseDraft.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((item) => item.name.trim().isNotEmpty)
          .map(_sanitizeKnowledgeBase)
          .toList(growable: false);

      final memoryDecks = _list(json['memoryDecks'])
          .take(_maxMemoryDecks)
          .map(
            (item) => OnboardingMemoryDeckDraft.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((item) => item.name.trim().isNotEmpty)
          .map(_sanitizeMemoryDeck)
          .toList(growable: false);

      final taskLists = _list(json['taskLists'])
          .take(_maxTaskLists)
          .map(
            (item) => OnboardingTaskListDraft.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((item) => item.title.trim().isNotEmpty)
          .map(_sanitizeTaskList)
          .toList(growable: false);

      final noteFolders = _list(json['noteFolders'])
          .take(_maxNoteFolders)
          .map(
            (item) => OnboardingNoteFolderDraft.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((item) => item.title.trim().isNotEmpty)
          .map(_sanitizeNoteFolder)
          .toList(growable: false);

      OnboardingSkillDraft? skill;
      if (json['skill'] is Map) {
        skill = _sanitizeSkill(
          OnboardingSkillDraft.fromJson(
            Map<String, dynamic>.from(json['skill']),
          ),
        );
      }

      return OnboardingDraft(
        role: role,
        roleMemory: memory,
        agent: sanitizedAgent,
        knowledgeBases: knowledgeBases,
        memoryDecks: memoryDecks,
        taskLists: taskLists,
        noteFolders: noteFolders,
        skill: skill,
        welcomeMessage: (json['welcome'] as String?)?.trim() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  AgentWorkingMemory _sanitizeMemory(AgentWorkingMemory memory) {
    final entries = memory.entries
        .where(
          (entry) => entry.id.isNotEmpty && entry.content.trim().isNotEmpty,
        )
        .take(_maxRoleMemoryEntries)
        .map(
          (entry) => AgentMemoryEntry(
            id: entry.id,
            kind: AgentMemoryEntry.kinds.contains(entry.kind)
                ? entry.kind
                : AgentMemoryEntry.note,
            content: entry.content.trim(),
            source: entry.source,
            pinned: entry.pinned,
            createdAt: entry.createdAt,
          ),
        )
        .toList(growable: false);
    return AgentWorkingMemory(
      goal: memory.goal.trim(),
      entries: entries,
      updatedAt: memory.updatedAt,
    );
  }

  OnboardingKnowledgeBaseDraft _sanitizeKnowledgeBase(
    OnboardingKnowledgeBaseDraft base,
  ) {
    return OnboardingKnowledgeBaseDraft(
      name: base.name.trim(),
      description: base.description.trim(),
      categories: base.categories
          .take(_maxCategoriesPerBase)
          .where((item) => item.name.trim().isNotEmpty)
          .map(
            (item) => OnboardingKnowledgeCategoryDraft(
              name: item.name.trim(),
              alias: item.alias.trim(),
              annotationRule: item.annotationRule.trim(),
              explanationPrompt: item.explanationPrompt.trim(),
            ),
          )
          .toList(growable: false),
      entries: base.entries
          .take(_maxEntriesPerBase)
          .where((item) => item.title.trim().isNotEmpty)
          .map(
            (item) => OnboardingKnowledgeEntryDraft(
              title: item.title.trim(),
              content: item.content.trim(),
              categoryName: item.categoryName.trim(),
            ),
          )
          .toList(growable: false),
    );
  }

  OnboardingMemoryDeckDraft _sanitizeMemoryDeck(
    OnboardingMemoryDeckDraft deck,
  ) {
    return OnboardingMemoryDeckDraft(
      name: deck.name.trim(),
      description: deck.description.trim(),
      newPerDayLimit: deck.newPerDayLimit.clamp(1, 999),
      reviewPerDayLimit: deck.reviewPerDayLimit.clamp(1, 9999),
      cards: deck.cards
          .take(_maxCardsPerDeck)
          .where(
            (item) =>
                item.front.trim().isNotEmpty && item.back.trim().isNotEmpty,
          )
          .map(
            (item) => OnboardingMemoryCardDraft(
              front: item.front.trim(),
              back: item.back.trim(),
              hint: item.hint.trim(),
            ),
          )
          .toList(growable: false),
    );
  }

  OnboardingTaskListDraft _sanitizeTaskList(OnboardingTaskListDraft list) {
    return OnboardingTaskListDraft(
      title: list.title.trim(),
      tasks: list.tasks
          .take(_maxTasksPerList)
          .where((item) => item.title.trim().isNotEmpty)
          .map(
            (item) => OnboardingTaskDraft(
              title: item.title.trim(),
              note: item.note.trim(),
            ),
          )
          .toList(growable: false),
    );
  }

  OnboardingNoteFolderDraft _sanitizeNoteFolder(
    OnboardingNoteFolderDraft folder,
  ) {
    return OnboardingNoteFolderDraft(
      title: folder.title.trim(),
      notes: folder.notes
          .take(_maxNotesPerFolder)
          .where((item) => item.title.trim().isNotEmpty)
          .map(
            (item) => OnboardingNoteDraft(
              title: item.title.trim(),
              content: item.content.trim(),
            ),
          )
          .toList(growable: false),
    );
  }

  OnboardingSkillDraft? _sanitizeSkill(OnboardingSkillDraft skill) {
    if (skill.name.trim().isEmpty || skill.body.trim().isEmpty) return null;
    final pluginId = _validPluginId(skill.pluginId);
    return OnboardingSkillDraft(
      pluginId: pluginId,
      name: skill.name.trim(),
      title: skill.title.trim().isEmpty
          ? skill.name.trim()
          : skill.title.trim(),
      description: skill.description.trim(),
      whenToUse: skill.whenToUse.trim(),
      tags: skill.tags
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(),
      body: skill.body.trim(),
    );
  }

  String _validPluginId(String raw) {
    final value = raw.trim();
    if (RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(value) &&
        value != '.' &&
        value != '..' &&
        !PluginRepository.builtInPluginIds.contains(value)) {
      return value;
    }
    return 'user-onboarding-skill';
  }

  // ─── 本地模板 ──────────────────────────────────────────────

  OnboardingDraft buildLocalDraft(OnboardingInput input) {
    final purposes = input.purposes.toSet();
    final isStudent = input.occupation == 'student';
    final wantsKnowledge =
        purposes.contains('knowledge') || purposes.contains('cards');
    final wantsTasks =
        purposes.contains('todos') || purposes.contains('schedule');
    final wantsNotes =
        purposes.contains('writing') || purposes.contains('notes');
    final wantsSkill =
        purposes.contains('automation') || purposes.contains('knowledge');

    final role = OnboardingRoleDraft(
      name: input.occupationCustom.trim().isNotEmpty
          ? '${input.occupationCustom.trim()}的助手'
          : _roleNameFor(input),
      description: _roleDescriptionFor(input),
      systemPrompt: _rolePromptFor(input),
    );

    final memory = AgentWorkingMemory(
      goal: input.freeText.trim().isEmpty
          ? _memoryGoalFor(input)
          : input.freeText.trim(),
      entries: [
        AgentMemoryEntry(
          id: _uuid.v4(),
          kind: AgentMemoryEntry.fact,
          content: '用户身份：${_occupationLabel(input)}',
          pinned: true,
          createdAt: DateTime.now(),
        ),
        if (input.freeText.trim().isNotEmpty)
          AgentMemoryEntry(
            id: _uuid.v4(),
            kind: AgentMemoryEntry.note,
            content: '用户目标：${input.freeText.trim()}',
            pinned: true,
            createdAt: DateTime.now(),
          ),
      ],
      updatedAt: DateTime.now(),
    );

    final agent = OnboardingAgentDraft(
      enabledByDefault: wantsKnowledge || wantsTasks,
      intents: [
        if (wantsTasks) ...['todos', 'schedules'],
        if (wantsKnowledge) 'knowledge',
        if (wantsNotes) 'notes',
        if (purposes.contains('automation')) 'plugins',
      ],
    );

    final draft = OnboardingDraft(
      role: role,
      roleMemory: memory,
      agent: agent,
      knowledgeBases: wantsKnowledge
          ? [
              OnboardingKnowledgeBaseDraft(
                name: input.occupation == 'student' ? '学习资料库' : '我的知识库',
                description: '由新手向导创建，用于沉淀常用资料和知识点。',
                categories: [
                  OnboardingKnowledgeCategoryDraft(
                    name: '课程笔记',
                    alias: 'course_notes',
                    annotationRule: '与课程或教材知识点相关的条目归入此类别',
                  ),
                  OnboardingKnowledgeCategoryDraft(
                    name: '错题与难点',
                    alias: 'difficulties',
                    annotationRule: '错题、易错点或反复遗忘的内容归入此类别',
                  ),
                ],
                entries: [
                  OnboardingKnowledgeEntryDraft(
                    title: '如何使用这个知识库',
                    content:
                        '把课程资料、错题和重要概念记录在这里。'
                        '对话中可以让 AI 检索知识库，也可以手动搜索和整理条目。',
                    categoryName: '课程笔记',
                  ),
                ],
              ),
            ]
          : const [],
      memoryDecks: purposes.contains('cards') || isStudent
          ? [
              OnboardingMemoryDeckDraft(
                name: input.occupation == 'student' ? '课程记忆卡' : '学习记忆卡',
                description: '由新手向导创建，适合每天少量复习。',
                newPerDayLimit: 20,
                reviewPerDayLimit: 100,
                cards: const [
                  OnboardingMemoryCardDraft(
                    front: 'LynAI 记忆卡怎么用？',
                    back: '每天复习少量卡片，正面提问，背面答案。',
                  ),
                ],
              ),
            ]
          : const [],
      taskLists: wantsTasks
          ? [
              OnboardingTaskListDraft(
                title: input.occupation == 'student' ? '学习计划' : '工作任务',
                tasks: const [
                  OnboardingTaskDraft(title: '浏览 LynAI 的对话和工具能力'),
                  OnboardingTaskDraft(title: '在设置中确认默认模型和 Agent 权限'),
                ],
              ),
            ]
          : const [],
      noteFolders: wantsNotes
          ? [
              OnboardingNoteFolderDraft(
                title: input.occupation == 'student' ? '学习笔记' : '我的笔记',
                notes: [
                  OnboardingNoteDraft(
                    title: '欢迎使用 LynAI',
                    content:
                        '这里是你的笔记文件夹。\n\n'
                        '可以写 Markdown、插入 LaTeX 公式，也可以让 AI 根据对话内容生成笔记。',
                  ),
                ],
              ),
            ]
          : const [],
      skill: wantsSkill
          ? OnboardingSkillDraft(
              pluginId: 'user-onboarding-workflow',
              name: 'daily_review_workflow',
              title: '每日复习工作流',
              description: '帮助用户整理当天学习内容并生成复习清单。',
              whenToUse: '当用户要求复盘今天的学习、工作或整理复习计划时使用。',
              tags: const ['复习', '工作流'],
              body: _defaultSkillBody(input),
            )
          : null,
    );
    return draft.copyWith(welcomeMessage: _buildLocalWelcome(input, draft));
  }

  String _buildLocalWelcome(OnboardingInput input, OnboardingDraft draft) {
    final buffer = StringBuffer()
      ..write('我是你的${draft.role.name}。');
    final goal = input.freeText.trim();
    if (goal.isNotEmpty) {
      buffer.write('以后你可以直接告诉我「$goal」，我会在需要时调用笔记、待办和知识库。');
    } else {
      buffer.write(
        '以后有想做的事直接告诉我，比如整理资料、安排日程、写笔记或复习，'
        '我会在需要时调用对应的工具。',
      );
    }

    final modules = <String>[
      if (draft.knowledgeBases.isNotEmpty) draft.knowledgeBases.first.name,
      if (draft.memoryDecks.isNotEmpty) draft.memoryDecks.first.name,
      if (draft.taskLists.isNotEmpty) draft.taskLists.first.title,
      if (draft.noteFolders.isNotEmpty) draft.noteFolders.first.title,
      if (draft.skill != null) draft.skill!.title,
    ];
    if (modules.isNotEmpty) {
      buffer.write('我已经为你准备好了：${modules.join('、')}。');
    }
    buffer.write('最后，花 30 秒带你认识一下 LynAI 怎么点。');
    return buffer.toString();
  }

  String _roleNameFor(OnboardingInput input) {
    switch (input.occupation) {
      case 'student':
        return '学习助手';
      case 'developer':
        return '开发助手';
      case 'researcher':
        return '研究助手';
      case 'creator':
        return '创作助手';
      case 'professional':
        return '效率助手';
      case 'freelancer':
        return '工作助手';
      case 'teacher':
        return '教学助手';
      default:
        return '我的助手';
    }
  }

  String _roleDescriptionFor(OnboardingInput input) {
    return '根据新手向导生成：面向${_occupationLabel(input)}，主要用于${_purposeSummary(input)}。';
  }

  String _rolePromptFor(OnboardingInput input) {
    final buffer = StringBuffer()
      ..writeln('你是 LynAI 中为用户定制的${_roleNameFor(input)}。')
      ..writeln('用户身份：${_occupationLabel(input)}。');
    if (input.purposes.isNotEmpty) {
      buffer.writeln('用户主要用途：${_purposeSummary(input)}。');
    }
    if (input.freeText.trim().isNotEmpty) {
      buffer.writeln('用户补充要求：${input.freeText.trim()}');
    }
    buffer.writeln('请使用中文回答，语气友好、简洁，优先给出可执行的建议。');
    return buffer.toString().trim();
  }

  String _memoryGoalFor(OnboardingInput input) {
    if (input.occupation == 'student') return '帮助用户管理学习资料并制定复习计划';
    if (input.purposes.contains('todos') ||
        input.purposes.contains('schedule')) {
      return '帮助用户管理日程和待办';
    }
    if (input.purposes.contains('knowledge')) return '帮助用户沉淀和检索知识';
    return '帮助用户更高效地使用 LynAI';
  }

  String _purposeSummary(OnboardingInput input) {
    if (input.purposes.isEmpty) return '日常对话';
    return input.purposes
        .map((key) => OnboardingInput.purposeLabels[key] ?? key)
        .join('、');
  }

  String _occupationLabel(OnboardingInput input) {
    final custom = input.occupationCustom.trim();
    if (custom.isNotEmpty) return custom;
    if (input.occupation == 'other' || input.occupation.isEmpty) {
      return 'LynAI 用户';
    }
    return OnboardingInput.occupationLabels[input.occupation] ?? 'LynAI 用户';
  }

  String _defaultSkillBody(OnboardingInput input) {
    return '''
# 每日复习工作流

<!-- 由 LynAI 新手向导生成，可按需修改。 -->

## 适用场景

当用户要求复盘今天的学习/工作内容，或制定复习计划时使用。

## 步骤

1. 询问用户今天学习了或完成了哪些内容。
2. 把这些内容按主题分成 3-5 条要点。
3. 为每条要点生成一个可用于记忆卡的正反面问答。
4. 如果用户同意，可以建议把这些卡片加入记忆卡牌组。

## 注意

- 保持中文输出。
- 不要一次生成超过 10 张卡片。
- 用户拒绝时不要自行写入任何数据。
''';
  }

  // ─── 权限映射 ──────────────────────────────────────────────

  List<String> permissionsForIntents(Iterable<String> intents) {
    final permissions = <String>{};
    for (final intent in intents) {
      switch (intent) {
        case 'notes':
          permissions.addAll([
            LynAIPermissions.notesRead,
            LynAIPermissions.notesWrite,
            LynAIPermissions.notesPropose,
          ]);
        case 'todos':
          permissions.addAll([
            LynAIPermissions.todosRead,
            LynAIPermissions.todosWrite,
          ]);
        case 'schedules':
          permissions.addAll([
            LynAIPermissions.schedulesRead,
            LynAIPermissions.schedulesWrite,
          ]);
        case 'knowledge':
          permissions.addAll([
            LynAIPermissions.storageRead,
            LynAIPermissions.notesRead,
          ]);
        case 'plugins':
          permissions.addAll([
            LynAIPermissions.pluginCallFunction,
            LynAIPermissions.luaExecute,
            LynAIPermissions.pluginSkillFilesWrite,
          ]);
        case 'minimal':
          permissions.add(LynAIPermissions.modelChat);
      }
    }
    if (permissions.isEmpty) {
      permissions.add(LynAIPermissions.modelChat);
    }
    return permissions
        .where(LynAIPermissions.agentAssignable.contains)
        .toList(growable: false);
  }

  String safeSystemPrompt(String prompt) {
    const toolSafety =
        'Never print or expose DSML, XML-style tool tags, pseudo tool calls, '
        'or raw function-calling markup to the user. When tools are available, '
        'use only the native OpenAI tool-calling interface. If tool calling is '
        'unavailable or disallowed, reply in plain natural language instead of '
        'simulating a tool call in text.';
    final trimmed = prompt.trim();
    if (trimmed.contains(toolSafety)) return trimmed;
    return '$trimmed\n\n$toolSafety';
  }

  // ─── 落地管道 ──────────────────────────────────────────────

  Future<OnboardingApplyResult> applyDraft({
    required OnboardingDraft draft,
    required SettingsProvider settingsProvider,
    required KnowledgeProvider knowledgeProvider,
    required MemoryCardProvider memoryCardProvider,
    required TaskProvider taskProvider,
    required FeatureProvider featureProvider,
    required PluginProvider pluginProvider,
  }) async {
    final result = OnboardingApplyResult();

    // 1. 角色与 Agent。
    try {
      final roleId = await _applyRole(draft, settingsProvider);
      settingsProvider.selectRole(roleId);
      await settingsProvider.updateAgentDefaults(
        enabled: draft.agent.enabledByDefault,
        permissions: permissionsForIntents(draft.agent.intents),
        maxToolRounds: defaultAgentMaxToolRounds,
      );
      result.role = '已创建角色「${draft.role.name}」';
    } catch (e) {
      result.role = '失败：$e';
    }

    // 2. 知识库。
    for (final base in draft.knowledgeBases) {
      try {
        await _applyKnowledgeBase(base, knowledgeProvider);
        result.knowledgeBases.add('已创建知识库「${base.name}」');
      } catch (e) {
        result.knowledgeBases.add('失败：$e');
      }
    }

    // 3. 记忆卡牌组。
    for (final deck in draft.memoryDecks) {
      try {
        await _applyMemoryDeck(deck, memoryCardProvider);
        result.memoryDecks.add('已创建牌组「${deck.name}」');
      } catch (e) {
        result.memoryDecks.add('失败：$e');
      }
    }

    // 4. 任务清单。
    for (final list in draft.taskLists) {
      try {
        await _applyTaskList(list, taskProvider);
        result.taskLists.add('已创建清单「${list.title}」');
      } catch (e) {
        result.taskLists.add('失败：$e');
      }
    }

    // 5. 笔记文件夹。
    for (final folder in draft.noteFolders) {
      try {
        await _applyNoteFolder(folder, featureProvider);
        result.noteFolders.add('已创建笔记文件夹「${folder.title}」');
      } catch (e) {
        result.noteFolders.add('失败：$e');
      }
    }

    // 6. SKILL 插件。
    if (draft.skill != null) {
      try {
        await _applySkill(draft.skill!, pluginProvider);
        result.skill = '已创建并启用 SKILL「${draft.skill!.title}」';
      } catch (e) {
        result.skill = '失败：$e';
      }
    }

    return result;
  }

  Future<String> _applyRole(
    OnboardingDraft draft,
    SettingsProvider settingsProvider,
  ) async {
    final safePrompt = safeSystemPrompt(draft.role.systemPrompt);
    final existing = settingsProvider.settings.roles.where((role) {
      return role.name.trim().toLowerCase() ==
          draft.role.name.trim().toLowerCase();
    }).firstOrNull;
    if (existing == null) {
      return settingsProvider.addRole(
        name: draft.role.name.trim(),
        description: draft.role.description.trim(),
        systemPrompt: safePrompt,
        defaultMemory: draft.roleMemory,
      );
    }
    settingsProvider.updateRole(
      id: existing.id,
      name: draft.role.name.trim(),
      description: draft.role.description.trim(),
      systemPrompt: safePrompt,
      modelId: existing.modelId,
      modelName: existing.modelName,
      themeColor: existing.themeColor,
      defaultMemory: draft.roleMemory,
    );
    return existing.id;
  }

  Future<String> _applyKnowledgeBase(
    OnboardingKnowledgeBaseDraft base,
    KnowledgeProvider provider,
  ) async {
    final existing = provider.knowledgeBases.where((item) {
      return item.name.trim().toLowerCase() == base.name.trim().toLowerCase();
    }).firstOrNull;
    final baseId =
        existing?.id ??
        await provider.addKnowledgeBase(
          name: base.name.trim(),
          description: base.description.trim().isEmpty
              ? null
              : base.description.trim(),
        );

    for (final category in base.categories) {
      final alias = _availableAlias(provider, category.alias);
      final existingCategory = provider.categories.where((item) {
        return item.knowledgeBaseId == baseId &&
            item.name.trim().toLowerCase() ==
                category.name.trim().toLowerCase();
      }).firstOrNull;
      if (existingCategory == null) {
        await provider.addCategory(
          knowledgeBaseId: baseId,
          name: category.name.trim(),
          alias: alias,
          annotationRule: category.annotationRule.trim(),
          explanationPrompt: category.explanationPrompt.trim(),
        );
      }
    }

    for (final entry in base.entries) {
      final categoryId = provider.categories
          .where((item) {
            return item.knowledgeBaseId == baseId &&
                item.name.trim().toLowerCase() ==
                    entry.categoryName.trim().toLowerCase();
          })
          .firstOrNull
          ?.id;
      final existingEntry = provider.entries.where((item) {
        return item.knowledgeBaseId == baseId &&
            item.title.trim().toLowerCase() == entry.title.trim().toLowerCase();
      }).firstOrNull;
      if (existingEntry == null) {
        await provider.addEntry(
          knowledgeBaseId: baseId,
          categoryId: categoryId,
          title: entry.title.trim(),
          content: entry.content.trim(),
        );
      }
    }
    return baseId;
  }

  String _availableAlias(KnowledgeProvider provider, String raw) {
    final normalized = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (RegExp(r'^[a-z][a-z0-9_-]{0,31}$').hasMatch(normalized) &&
        provider.categoryByAlias(normalized) == null) {
      return normalized;
    }
    final safeStem = normalized.length <= 24
        ? normalized
        : normalized.substring(0, 24);
    final stem = safeStem.isEmpty ? 'category' : safeStem;
    final suffix = _uuid.v4().replaceAll('-', '').substring(0, 7);
    return '${stem}_$suffix';
  }

  Future<void> _applyMemoryDeck(
    OnboardingMemoryDeckDraft deck,
    MemoryCardProvider provider,
  ) async {
    final deckId = await provider.ensureDeckByName(deck.name.trim());
    final now = DateTime.now();
    final cards = <MemoryCard>[];
    final seen = <String>{
      for (final card in provider.cardsForDeck(deckId))
        '${card.front.trim()}\u0000${card.back.trim()}',
    };
    for (final item in deck.cards) {
      if (item.front.trim().isEmpty || item.back.trim().isEmpty) continue;
      if (!seen.add('${item.front.trim()}\u0000${item.back.trim()}')) continue;
      cards.add(
        MemoryCard(
          id: _uuid.v4(),
          deckId: deckId,
          front: item.front.trim(),
          back: item.back.trim(),
          hint: item.hint.trim().isEmpty ? null : item.hint.trim(),
          sourceKind: MemoryCardSourceKind.manual,
          status: MemoryCardStatus.newCard,
          intervalDays: 0,
          easeFactor: 2.5,
          repetitions: 0,
          lapses: 0,
          reviewCount: 0,
          enabled: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    if (cards.isNotEmpty) await provider.addCards(cards);
  }

  Future<void> _applyTaskList(
    OnboardingTaskListDraft list,
    TaskProvider provider,
  ) async {
    final existing = provider.lists.where((item) {
      return item.title.trim().toLowerCase() == list.title.trim().toLowerCase();
    }).firstOrNull;
    final listId = existing?.id ?? await provider.addList(list.title.trim());
    final existingTitles = provider.tasksForList(listId).map((task) {
      return task.title.trim().toLowerCase();
    }).toSet();
    for (final item in list.tasks) {
      if (item.title.trim().isEmpty) continue;
      if (!existingTitles.add(item.title.trim().toLowerCase())) continue;
      await provider.addTask(
        title: item.title.trim(),
        note: item.note.trim().isEmpty ? null : item.note.trim(),
        listId: listId,
      );
    }
  }

  Future<void> _applyNoteFolder(
    OnboardingNoteFolderDraft folder,
    FeatureProvider provider,
  ) async {
    final existing = provider.noteFolders.where((item) {
      return item.title.trim().toLowerCase() ==
          folder.title.trim().toLowerCase();
    }).firstOrNull;
    final folderId =
        existing?.id ?? await provider.addNoteFolder(folder.title.trim());
    final existingTitles = provider.notes
        .where((note) => note.folderId == folderId)
        .map((note) => note.title.trim().toLowerCase())
        .toSet();
    for (final item in folder.notes) {
      if (item.title.trim().isEmpty) continue;
      if (!existingTitles.add(item.title.trim().toLowerCase())) continue;
      await provider.addNoteWithContent(
        item.title.trim(),
        item.content.trim(),
        folderId: folderId,
      );
    }
  }

  Future<void> _applySkill(
    OnboardingSkillDraft skill,
    PluginProvider provider,
  ) async {
    final pluginId = _validPluginId(skill.pluginId);
    var plugin = provider.pluginById(pluginId);
    if (plugin == null) {
      await provider.createPlugin(
        id: pluginId,
        name: skill.title.trim(),
        version: '0.1.0',
        author: 'LynAI Onboarding',
        description: skill.description.trim(),
        kind: PluginScaffoldKind.skill,
      );
      plugin = provider.pluginById(pluginId);
      if (plugin == null) throw Exception('插件创建失败: $pluginId');
    } else if (plugin.devState == PluginDevState.active) {
      await provider.setDevState(pluginId, PluginDevState.testing);
    }

    final skillPath = 'skills/${skill.name.trim()}.md';
    final manifest = <String, dynamic>{
      'id': pluginId,
      'name': skill.title.trim(),
      'version': plugin.manifest.version.toString(),
      'author': 'LynAI Onboarding',
      'description': skill.description.trim(),
      'entry': 'main.lua',
      'permissions': <String>[],
      'skills': [
        {
          'name': skill.name.trim(),
          'title': skill.title.trim(),
          if (skill.description.trim().isNotEmpty)
            'description': skill.description.trim(),
          if (skill.whenToUse.trim().isNotEmpty)
            'whenToUse': skill.whenToUse.trim(),
          if (skill.tags.isNotEmpty) 'tags': skill.tags,
        },
      ],
      'editableFiles': [
        {'path': skillPath, 'title': skill.title.trim(), 'type': 'markdown'},
      ],
    };

    await provider.writeEditableFile(
      pluginId,
      'plugin.json',
      const JsonEncoder.withIndent('  ').convert(manifest),
    );
    await provider.writeEditableFile(pluginId, skillPath, skill.body.trim());
    await provider.setEnabled(pluginId, true);
    await provider.setDevState(pluginId, PluginDevState.active);
  }

  static List<dynamic> _list(Object? raw) {
    if (raw is List) return raw;
    return const [];
  }
}

class OnboardingApplyResult {
  String? role;
  final List<String> knowledgeBases = [];
  final List<String> memoryDecks = [];
  final List<String> taskLists = [];
  final List<String> noteFolders = [];
  String? skill;

  bool get hasFailure {
    return role != null && role!.startsWith('失败') ||
        knowledgeBases.any((item) => item.startsWith('失败')) ||
        memoryDecks.any((item) => item.startsWith('失败')) ||
        taskLists.any((item) => item.startsWith('失败')) ||
        noteFolders.any((item) => item.startsWith('失败')) ||
        (skill != null && skill!.startsWith('失败'));
  }
}
