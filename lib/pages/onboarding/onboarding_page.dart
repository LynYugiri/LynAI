import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/agent_working_memory.dart';
import '../../models/onboarding/onboarding_draft.dart';
import '../../providers/feature_provider.dart';
import '../../providers/knowledge_provider.dart';
import '../../providers/memory_card_provider.dart';
import '../../providers/model_config_provider.dart';
import '../../providers/onboarding_wizard_controller.dart';
import '../../providers/plugin_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/task_provider.dart';
import '../../services/api_service.dart';
import '../../services/backend_client.dart';
import '../../services/onboarding_service.dart';

/// 新手向导页。
///
/// 用户在首次启动时选择用途与身份，向导生成可编辑的初始配置草稿，
/// 确认后应用为角色、Agent 默认值、知识库、牌组、任务清单、笔记和 SKILL。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const _purposeOptions = <String, String>{
    'chat': '聊天问答',
    'writing': '写作创作',
    'coding': '编程开发',
    'research': '学习研究',
    'knowledge': '知识库',
    'todos': '日程待办',
    'cards': '记忆卡学习',
    'roleplay': '角色扮演',
    'automation': '插件与自动化',
    'privacy': '本地优先',
  };

  static const _occupationOptions = <String, String>{
    'student': '学生',
    'developer': '开发者',
    'researcher': '研究人员',
    'creator': '内容创作者',
    'professional': '职场人士',
    'freelancer': '自由职业',
    'teacher': '教师',
    'other': '其他',
  };

  static const _featureOptions = <String, String>{
    'dashboard': '功能总览',
    'history': '对话历史',
    'schedule': '日程表',
    'notes': '笔记',
    'todos': '待办清单',
    'roleplay': '情景演绎',
    'knowledge': '知识库',
    'cards': '记忆卡',
    'jottings': '随记',
  };

  final OnboardingWizardController _controller = OnboardingWizardController();
  final TextEditingController _occupationCustomController =
      TextEditingController();
  final TextEditingController _freeTextController = TextEditingController();
  final PageController _questionPageController = PageController();

  late Set<String> _selectedPurposes;
  late String _occupation;
  int _questionIndex = 0;
  OnboardingService? _service;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _controller.loadLastInput(settings);
    _selectedPurposes = _controller.input.purposes.toSet();
    _occupation = _controller.input.occupation;
    _occupationCustomController.text = _controller.input.occupationCustom;
    _freeTextController.text = _controller.input.freeText;
  }

  @override
  void dispose() {
    _controller.dispose();
    _occupationCustomController.dispose();
    _freeTextController.dispose();
    _questionPageController.dispose();
    super.dispose();
  }

  OnboardingService _ensureService() {
    return _service ??= OnboardingService(
      apiService: ApiService(backend: context.read<BackendClient>()),
      modelConfigProvider: context.read<ModelConfigProvider>(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('欢迎使用 LynAI'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [TextButton(onPressed: _skip, child: const Text('跳过'))],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            if (_controller.applying || _controller.applyResult != null) {
              return _buildSummary();
            }
            if (_controller.generating) {
              return _buildGenerating();
            }
            final draft = _controller.draft;
            if (draft != null) {
              return _buildDraftEditor(draft);
            }
            return _buildQuestions();
          },
        ),
      ),
    );
  }

  Future<void> _skip() async {
    await _finish(skipped: true);
  }

  Future<void> _finish({bool skipped = false}) async {
    await _controller.finish(
      context.read<SettingsProvider>(),
      skipped: skipped,
    );
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  Future<void> _generate() async {
    _saveInputToController();
    await _controller.generate(_ensureService());
  }

  void _saveInputToController() {
    _controller.setPurposes(_selectedPurposes.toList(growable: false));
    _controller.setOccupation(
      _occupation,
      custom: _occupationCustomController.text.trim(),
    );
    _controller.setFreeText(_freeTextController.text);
  }

  // ─── Step 1: 三个问题分步 ──────────────────────────────────

  void _goToQuestion(int index) {
    if (index < 0 || index > 2 || index == _questionIndex) return;
    _questionPageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
    );
  }

  Widget _buildQuestions() {
    return Column(
      children: [
        _buildQuestionProgress(),
        Expanded(
          child: PageView(
            controller: _questionPageController,
            onPageChanged: (index) => setState(() => _questionIndex = index),
            children: [
              _buildPurposeQuestion(),
              _buildOccupationQuestion(),
              _buildFreeTextQuestion(),
            ],
          ),
        ),
        _buildQuestionNavBar(),
      ],
    );
  }

  Widget _buildQuestionProgress() {
    final primary = Theme.of(context).colorScheme.primary;
    final surfaceVariant = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '第 ${_questionIndex + 1} / 3 步',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(3, (index) {
              final active = index <= _questionIndex;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == 2 ? 0 : 6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? primary : surfaceVariant,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionNavBar() {
    final isLast = _questionIndex == 2;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            if (_questionIndex > 0) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _goToQuestion(_questionIndex - 1),
                  child: const Text('上一步'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: isLast
                    ? _generate
                    : () => _goToQuestion(_questionIndex + 1),
                icon: Icon(isLast ? Icons.auto_awesome : Icons.arrow_forward),
                label: Text(isLast ? '生成我的初始配置' : '下一步'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildPurposeQuestion() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        _buildQuestionTitle('你想用 LynAI 做什么？', '可多选，之后还可以在设置中修改'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _purposeOptions.entries
              .map((entry) {
                final selected = _selectedPurposes.contains(entry.key);
                return FilterChip(
                  label: Text(entry.value),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (value) {
                    setState(() {
                      if (value) {
                        _selectedPurposes.add(entry.key);
                      } else {
                        _selectedPurposes.remove(entry.key);
                      }
                    });
                  },
                );
              })
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _buildOccupationQuestion() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        _buildQuestionTitle('你的身份/职业', '单选，也可以填写自定义身份'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _occupationOptions.entries
              .map((entry) {
                return ChoiceChip(
                  label: Text(entry.value),
                  selected: _occupation == entry.key,
                  onSelected: (_) => setState(() => _occupation = entry.key),
                );
              })
              .toList(growable: false),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _occupationCustomController,
          decoration: const InputDecoration(
            labelText: '自定义身份（可选）',
            hintText: '例如：考研学生、独立游戏开发者',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildFreeTextQuestion() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        _buildQuestionTitle('补充描述', '自由说说你想怎么用 LynAI（可选）'),
        const SizedBox(height: 16),
        TextField(
          controller: _freeTextController,
          minLines: 6,
          maxLines: 12,
          autofocus: _questionIndex == 2,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            hintText: '例如：我在准备考研，希望帮我整理笔记、制定复习计划，回复简洁一点',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '生成的初始配置都可以在下一步里编辑或删除，不会强制创建任何模块。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  // ─── Step 2 ────────────────────────────────────────────────

  Widget _buildGenerating() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('正在用 deepseek-v4-pro 生成你的专属配置…'),
          SizedBox(height: 8),
          Text('如果暂时不可用，会自动使用本地模板', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  // ─── Step 3: 草稿编辑 ──────────────────────────────────────

  Widget _buildDraftEditor(OnboardingDraft draft) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionCard(
          title: '角色',
          subtitle: '${draft.role.name} · ${draft.role.description}',
          onEdit: () => _editRole(draft),
          child: Text(
            draft.role.systemPrompt,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _sectionCard(
          title: '角色记忆',
          subtitle: '${draft.roleMemory.entries.length} 条记忆',
          onEdit: () => _editMemory(draft),
          child: Text(
            draft.roleMemory.goal.isEmpty ? '未设置目标' : draft.roleMemory.goal,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _sectionCard(
          title: 'Agent 默认值',
          subtitle: draft.agent.enabledByDefault ? '默认开启' : '默认关闭',
          onEdit: () => _editAgent(draft),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: draft.agent.intents
                .map((intent) => Chip(label: Text(intent)))
                .toList(growable: false),
          ),
        ),
        _sectionCard(
          title: '默认功能页',
          subtitle:
              _featureOptions[draft.defaultFeature] ?? draft.defaultFeature,
          onEdit: () => _editDefaultFeature(draft),
        ),
        for (final base in draft.knowledgeBases)
          _sectionCard(
            title: '知识库：${base.name}',
            subtitle:
                '${base.categories.length} 个类别 · ${base.entries.length} 篇条目',
            onEdit: () => _editKnowledgeBase(draft, base),
            onDelete: () => _deleteKnowledgeBase(draft, base),
          ),
        for (final deck in draft.memoryDecks)
          _sectionCard(
            title: '记忆卡牌组：${deck.name}',
            subtitle: '${deck.cards.length} 张卡片',
            onEdit: () => _editMemoryDeck(draft, deck),
            onDelete: () => _deleteMemoryDeck(draft, deck),
          ),
        for (final list in draft.taskLists)
          _sectionCard(
            title: '任务清单：${list.title}',
            subtitle: '${list.tasks.length} 个任务',
            onEdit: () => _editTaskList(draft, list),
            onDelete: () => _deleteTaskList(draft, list),
          ),
        for (final folder in draft.noteFolders)
          _sectionCard(
            title: '笔记文件夹：${folder.title}',
            subtitle: '${folder.notes.length} 篇笔记',
            onEdit: () => _editNoteFolder(draft, folder),
            onDelete: () => _deleteNoteFolder(draft, folder),
          ),
        if (draft.skill != null)
          _sectionCard(
            title: 'SKILL：${draft.skill!.title}',
            subtitle: '插件 ${draft.skill!.pluginId}',
            onEdit: () => _editSkill(draft),
            onDelete: () => _deleteSkill(draft),
          ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => _controller.regenerate(_ensureService()),
          icon: const Icon(Icons.refresh),
          label: const Text('重新生成'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _apply,
          icon: const Icon(Icons.check),
          label: const Text('确认并应用'),
        ),
      ],
    );
  }

  Widget _sectionCard({
    required String title,
    String? subtitle,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
    Widget? child,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                    tooltip: '编辑',
                  ),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                    tooltip: '删除',
                  ),
              ],
            ),
            ?child,
          ],
        ),
      ),
    );
  }

  // ─── 编辑弹窗 ──────────────────────────────────────────────

  Future<void> _editRole(OnboardingDraft draft) async {
    final name = TextEditingController(text: draft.role.name);
    final description = TextEditingController(text: draft.role.description);
    final prompt = TextEditingController(text: draft.role.systemPrompt);
    final saved = await _showEditorDialog(
      title: '编辑角色',
      fields: [
        _FieldSpec('名称', name),
        _FieldSpec('描述', description),
        _FieldSpec('系统提示词', prompt, maxLines: 5),
      ],
    );
    if (saved) {
      _controller.updateDraft(
        draft.copyWith(
          role: draft.role.copyWith(
            name: name.text.trim(),
            description: description.text.trim(),
            systemPrompt: prompt.text.trim(),
          ),
        ),
      );
    }
  }

  Future<void> _editMemory(OnboardingDraft draft) async {
    final goal = TextEditingController(text: draft.roleMemory.goal);
    final entries = TextEditingController(
      text: draft.roleMemory.entries.map((e) => e.content).join('\n---\n'),
    );
    final saved = await _showEditorDialog(
      title: '编辑角色记忆',
      fields: [
        _FieldSpec('目标', goal),
        _FieldSpec('记忆条目（每行一条，--- 分隔）', entries, maxLines: 8),
      ],
    );
    if (saved) {
      final now = DateTime.now();
      final items = entries.text
          .split(RegExp(r'\n---\n|^---$', multiLine: true))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .take(6)
          .toList(growable: false);
      final newEntries = items.indexed
          .map(
            (indexed) => AgentMemoryEntry(
              id: 'onboarding-memory-${indexed.$1 + 1}',
              kind: AgentMemoryEntry.note,
              content: indexed.$2,
              pinned: true,
              createdAt: now,
            ),
          )
          .toList(growable: false);
      _controller.updateDraft(
        draft.copyWith(
          roleMemory: AgentWorkingMemory(
            goal: goal.text.trim(),
            entries: newEntries,
            updatedAt: now,
          ),
        ),
      );
    }
  }

  Future<void> _editAgent(OnboardingDraft draft) async {
    final enabled = await _showBoolDialog(
      title: '默认开启 Agent',
      initial: draft.agent.enabledByDefault,
    );
    if (enabled == null) return;
    final intents = await _showIntentsDialog(draft.agent.intents);
    if (intents == null) return;
    _controller.updateDraft(
      draft.copyWith(
        agent: OnboardingAgentDraft(
          enabledByDefault: enabled,
          intents: intents,
        ),
      ),
    );
  }

  Future<void> _editDefaultFeature(OnboardingDraft draft) async {
    final feature = await _showFeatureDialog(draft.defaultFeature);
    if (feature == null) return;
    _controller.updateDraft(draft.copyWith(defaultFeature: feature));
  }

  Future<void> _editKnowledgeBase(
    OnboardingDraft draft,
    OnboardingKnowledgeBaseDraft base,
  ) async {
    final name = TextEditingController(text: base.name);
    final description = TextEditingController(text: base.description);
    final saved = await _showEditorDialog(
      title: '编辑知识库',
      fields: [_FieldSpec('名称', name), _FieldSpec('描述', description)],
    );
    if (saved) {
      _controller.updateDraft(
        draft.copyWith(
          knowledgeBases: draft.knowledgeBases
              .map(
                (item) => identical(item, base)
                    ? base.copyWith(
                        name: name.text.trim(),
                        description: description.text.trim(),
                      )
                    : item,
              )
              .toList(growable: false),
        ),
      );
    }
  }

  Future<void> _deleteKnowledgeBase(
    OnboardingDraft draft,
    OnboardingKnowledgeBaseDraft base,
  ) async {
    _controller.updateDraft(
      draft.copyWith(
        knowledgeBases: draft.knowledgeBases
            .where((item) => !identical(item, base))
            .toList(growable: false),
      ),
    );
  }

  Future<void> _editMemoryDeck(
    OnboardingDraft draft,
    OnboardingMemoryDeckDraft deck,
  ) async {
    final name = TextEditingController(text: deck.name);
    final description = TextEditingController(text: deck.description);
    final saved = await _showEditorDialog(
      title: '编辑牌组',
      fields: [_FieldSpec('名称', name), _FieldSpec('描述', description)],
    );
    if (saved) {
      _controller.updateDraft(
        draft.copyWith(
          memoryDecks: draft.memoryDecks
              .map(
                (item) => identical(item, deck)
                    ? deck.copyWith(
                        name: name.text.trim(),
                        description: description.text.trim(),
                      )
                    : item,
              )
              .toList(growable: false),
        ),
      );
    }
  }

  Future<void> _deleteMemoryDeck(
    OnboardingDraft draft,
    OnboardingMemoryDeckDraft deck,
  ) async {
    _controller.updateDraft(
      draft.copyWith(
        memoryDecks: draft.memoryDecks
            .where((item) => !identical(item, deck))
            .toList(growable: false),
      ),
    );
  }

  Future<void> _editTaskList(
    OnboardingDraft draft,
    OnboardingTaskListDraft list,
  ) async {
    final title = TextEditingController(text: list.title);
    final saved = await _showEditorDialog(
      title: '编辑任务清单',
      fields: [_FieldSpec('标题', title)],
    );
    if (saved) {
      _controller.updateDraft(
        draft.copyWith(
          taskLists: draft.taskLists
              .map(
                (item) => identical(item, list)
                    ? list.copyWith(title: title.text.trim())
                    : item,
              )
              .toList(growable: false),
        ),
      );
    }
  }

  Future<void> _deleteTaskList(
    OnboardingDraft draft,
    OnboardingTaskListDraft list,
  ) async {
    _controller.updateDraft(
      draft.copyWith(
        taskLists: draft.taskLists
            .where((item) => !identical(item, list))
            .toList(growable: false),
      ),
    );
  }

  Future<void> _editNoteFolder(
    OnboardingDraft draft,
    OnboardingNoteFolderDraft folder,
  ) async {
    final title = TextEditingController(text: folder.title);
    final saved = await _showEditorDialog(
      title: '编辑笔记文件夹',
      fields: [_FieldSpec('标题', title)],
    );
    if (saved) {
      _controller.updateDraft(
        draft.copyWith(
          noteFolders: draft.noteFolders
              .map(
                (item) => identical(item, folder)
                    ? folder.copyWith(title: title.text.trim())
                    : item,
              )
              .toList(growable: false),
        ),
      );
    }
  }

  Future<void> _deleteNoteFolder(
    OnboardingDraft draft,
    OnboardingNoteFolderDraft folder,
  ) async {
    _controller.updateDraft(
      draft.copyWith(
        noteFolders: draft.noteFolders
            .where((item) => !identical(item, folder))
            .toList(growable: false),
      ),
    );
  }

  Future<void> _editSkill(OnboardingDraft draft) async {
    final skill = draft.skill;
    if (skill == null) return;
    final title = TextEditingController(text: skill.title);
    final description = TextEditingController(text: skill.description);
    final whenToUse = TextEditingController(text: skill.whenToUse);
    final body = TextEditingController(text: skill.body);
    final saved = await _showEditorDialog(
      title: '编辑 SKILL',
      fields: [
        _FieldSpec('标题', title),
        _FieldSpec('描述', description),
        _FieldSpec('何时使用', whenToUse),
        _FieldSpec('正文', body, maxLines: 10),
      ],
    );
    if (saved) {
      _controller.updateDraft(
        draft.copyWith(
          skill: skill.copyWith(
            title: title.text.trim(),
            description: description.text.trim(),
            whenToUse: whenToUse.text.trim(),
            body: body.text.trim(),
          ),
        ),
      );
    }
  }

  Future<void> _deleteSkill(OnboardingDraft draft) async {
    _controller.updateDraft(draft.copyWith(skill: null));
  }

  Future<void> _apply() async {
    await _controller.apply(
      _ensureService(),
      settingsProvider: context.read<SettingsProvider>(),
      knowledgeProvider: context.read<KnowledgeProvider>(),
      memoryCardProvider: context.read<MemoryCardProvider>(),
      taskProvider: context.read<TaskProvider>(),
      featureProvider: context.read<FeatureProvider>(),
      pluginProvider: context.read<PluginProvider>(),
    );
  }

  // ─── 应用结果 ──────────────────────────────────────────────

  Widget _buildSummary() {
    final result = _controller.applyResult;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
          const SizedBox(height: 16),
          Text('初始配置已应用', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          if (result == null)
            const LinearProgressIndicator()
          else ...[
            if (result.role != null) _summaryLine(result.role!),
            for (final item in result.knowledgeBases) _summaryLine(item),
            for (final item in result.memoryDecks) _summaryLine(item),
            for (final item in result.taskLists) _summaryLine(item),
            for (final item in result.noteFolders) _summaryLine(item),
            if (result.skill != null) _summaryLine(result.skill!),
          ],
          const Spacer(),
          FilledButton(
            onPressed: () => _finish(),
            child: const Text('进入 LynAI'),
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(String text) {
    final failed = text.startsWith('失败');
    return ListTile(
      dense: true,
      leading: Icon(
        failed ? Icons.error_outline : Icons.check,
        color: failed ? Colors.red : Colors.green,
      ),
      title: Text(text),
    );
  }

  // ─── 通用弹窗 helpers ──────────────────────────────────────

  Future<bool> _showEditorDialog({
    required String title,
    required List<_FieldSpec> fields,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final field in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: field.controller,
                    minLines: field.maxLines,
                    maxLines: field.maxLines,
                    decoration: InputDecoration(
                      labelText: field.label,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<bool?> _showBoolDialog({
    required String title,
    required bool initial,
  }) async {
    var value = initial;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SwitchListTile(
          title: const Text('默认开启'),
          value: value,
          onChanged: (next) {
            value = next;
            Navigator.pop(ctx, value);
          },
        ),
      ),
    );
  }

  Future<List<String>?> _showIntentsDialog(List<String> current) async {
    final selected = current.toSet();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择 Agent 能力'),
        content: SingleChildScrollView(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: OnboardingService.validIntents
                .map((intent) {
                  final isSelected = selected.contains(intent);
                  return FilterChip(
                    label: Text(intent),
                    selected: isSelected,
                    onSelected: (value) {
                      if (value) {
                        selected.add(intent);
                      } else {
                        selected.remove(intent);
                      }
                    },
                  );
                })
                .toList(growable: false),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, selected.toList(growable: false)),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<String?> _showFeatureDialog(String current) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择默认功能页'),
        children: _featureOptions.entries
            .map((entry) {
              return SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, entry.key),
                child: Row(
                  children: [
                    Icon(
                      current == entry.key
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    const SizedBox(width: 8),
                    Text(entry.value),
                  ],
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _FieldSpec {
  final String label;
  final TextEditingController controller;
  final int maxLines;

  const _FieldSpec(this.label, this.controller, {this.maxLines = 1});
}
