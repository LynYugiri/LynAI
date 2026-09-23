import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/agent_plan.dart';
import '../models/agent_trace.dart';
import '../models/agent_working_memory.dart';
import '../models/composer_draft.dart';
import '../models/composer_reference.dart';
import '../models/conversation.dart';
import '../models/conversation_context.dart';
import '../models/conversation_plugin_artifact.dart';
import '../models/message.dart';
import '../models/model_config.dart';
import '../models/recycle_bin_item.dart';
import '../repositories/composer_draft_repository.dart';
import '../repositories/conversation_repository.dart';
import '../repositories/recycle_bin_repository.dart';
import '../services/storage_v2_service.dart';
import '../utils/chat_search_matcher.dart';
import 'serialized_save_queue.dart';

enum ConversationSearchMatchType { none, title, message, attachment }

class ConversationSearchResult {
  final Conversation conversation;
  final ConversationSearchMatchType matchType;
  final String snippet;
  final List<ChatSearchRange> snippetRanges;

  const ConversationSearchResult({
    required this.conversation,
    this.matchType = ConversationSearchMatchType.none,
    this.snippet = '',
    this.snippetRanges = const [],
  });

  bool get matchInTitle => matchType == ConversationSearchMatchType.title;
}

/// 管理对话历史、消息流式更新和对话持久化。
///
/// 约定：UI 可以先看到内存更新，落盘通过串行保存队列按快照顺序执行。
/// 这样流式刷新、停止生成、重试切换不会让较旧的异步写入覆盖新状态。
class ConversationProvider extends ChangeNotifier with SerializedSaveQueue {
  List<Conversation> _conversations = [];
  final _uuid = const Uuid();
  int _mutationGeneration = 0;
  Timer? _saveDebounce;
  List<Conversation>? _pendingSaveSnapshot;
  static const _sentinel = Object();
  static const _saveDebounceDuration = Duration(milliseconds: 500);
  static const _draftDebounceDuration = Duration(milliseconds: 400);
  final ConversationRepository _repository;
  final RecycleBinRepository _recycleBinRepository;
  final ComposerDraftRepository _composerDraftRepository;
  bool _usingStorageV2 = false;

  /// 输入框草稿，键是槽位（对话 ID，或未创建对话时的 `new`）。
  final Map<String, ComposerDraft> _composerDrafts = {};
  Timer? _draftDebounce;
  Map<String, ComposerDraft>? _pendingDraftSnapshot;

  ConversationProvider({
    StorageV2Service? storageV2,
    ConversationRepository? repository,
    RecycleBinRepository? recycleBinRepository,
    ComposerDraftRepository? composerDraftRepository,
  }) : _repository = repository ?? ConversationRepository(storageV2: storageV2),
       _recycleBinRepository =
           recycleBinRepository ?? RecycleBinRepository(storageV2: storageV2),
       _composerDraftRepository =
           composerDraftRepository ??
           ComposerDraftRepository(storageV2: storageV2);

  void _touchConversation(int index) {
    final updated = _conversations.removeAt(index);
    _conversations.insert(0, updated);
  }

  /// 所有对话，按最近更新时间倒序排列。
  List<Conversation> get conversations => List.unmodifiable(_conversations);
  bool get usingStorageV2 => _usingStorageV2;

  Future<void> replaceConversations(List<Conversation> conversations) async {
    _conversations = List<Conversation>.from(conversations)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _queueSaveConversations(immediate: true);
    await flushPendingSaves();
    notifyListeners();
  }

  /// 从本地 repository 加载对话。
  ///
  /// 单条损坏对话会被跳过；单条损坏消息由 [Conversation.fromJson] 跳过。
  Future<void> loadConversations() async {
    final generation = _mutationGeneration;
    await flushPendingSaves();
    final result = await _repository.load();
    if (generation != _mutationGeneration) return;
    // 草稿是对话的附属状态：读取失败时保留已有缓存，不阻塞对话加载。
    try {
      final drafts = await _composerDraftRepository.load();
      if (generation != _mutationGeneration) return;
      _composerDrafts
        ..clear()
        ..addEntries(drafts.map((entry) => MapEntry(entry.slot, entry.draft)));
    } catch (error) {
      debugPrint('输入框草稿加载失败: $error');
    }
    _conversations = List<Conversation>.from(result.conversations);
    _usingStorageV2 = result.usingStorageV2;
    notifyListeners();
  }

  /// 全部草稿，按槽位索引（含未创建对话的 `new` 槽位）。
  Map<String, ComposerDraft> get composerDrafts =>
      Map.unmodifiable(_composerDrafts);

  /// 读取某个对话的输入框草稿；没有草稿时返回空草稿。
  ComposerDraft composerDraftFor(String? conversationId) =>
      _composerDrafts[ComposerDraftRepository.slotFor(conversationId)] ??
      const ComposerDraft();

  /// 暂存某个对话的输入框草稿；正文与附件都为空时删除该槽位。
  ///
  /// 写盘防抖，`flushPendingSaves()` 会连同对话一起落盘；绑定对话的草稿随对话
  /// 分区同步与备份，未创建对话的槽位只留在本机。
  void saveComposerDraft(String? conversationId, ComposerDraft draft) {
    final slot = ComposerDraftRepository.slotFor(conversationId);
    if (draft.isEmpty) {
      if (_composerDrafts.remove(slot) == null) return;
    } else {
      _composerDrafts[slot] = draft;
    }
    _queueComposerDraftSave();
  }

  void _queueComposerDraftSave({bool immediate = false}) {
    _pendingDraftSnapshot = Map<String, ComposerDraft>.of(_composerDrafts);
    if (immediate) {
      _enqueueComposerDraftSave();
      return;
    }
    _draftDebounce?.cancel();
    _draftDebounce = Timer(_draftDebounceDuration, _enqueueComposerDraftSave);
  }

  void _enqueueComposerDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce = null;
    final snapshot = _pendingDraftSnapshot;
    if (snapshot == null) return;
    _pendingDraftSnapshot = null;
    enqueueSave(() => _composerDraftRepository.save(snapshot));
  }

  /// 把当前对话快照排入保存队列。
  void _queueSaveConversations({bool immediate = false}) {
    _mutationGeneration++;
    _pendingSaveSnapshot = List<Conversation>.from(_conversations);
    if (immediate) {
      _enqueuePendingSave();
      return;
    }
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDebounceDuration, _enqueuePendingSave);
  }

  void _enqueuePendingSave() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    final snapshot = _pendingSaveSnapshot;
    if (snapshot == null) return;
    _pendingSaveSnapshot = null;
    enqueueSave(
      () => _repository.save(snapshot, usingStorageV2: _usingStorageV2),
    );
  }

  @override
  Future<void> onBeforeFlush() async {
    _enqueuePendingSave();
    _enqueueComposerDraftSave();
  }

  Future<bool> migrateModelIds(Map<String, String> migrations) async {
    if (migrations.isEmpty) return false;
    String? migrate(String? id) => id == null ? null : migrations[id] ?? id;
    var changed = false;

    _conversations = _conversations
        .map((conversation) {
          final settings = conversation.settings;
          final modelId = migrate(conversation.modelId)!;
          final settingsModelId = migrate(settings.modelId)!;
          final speechModelId = migrate(settings.speechModelId);
          final imageModelId = migrate(settings.imageModelId);
          final imageRecognitionModelId = migrate(
            settings.imageRecognitionModelId,
          );
          final imageGenerationModelId = migrate(
            settings.imageGenerationModelId,
          );
          if (modelId == conversation.modelId &&
              settingsModelId == settings.modelId &&
              speechModelId == settings.speechModelId &&
              imageModelId == settings.imageModelId &&
              imageRecognitionModelId == settings.imageRecognitionModelId &&
              imageGenerationModelId == settings.imageGenerationModelId) {
            return conversation;
          }
          changed = true;
          return conversation.copyWith(
            modelId: modelId,
            settings: settings.copyWith(
              modelId: settingsModelId,
              speechModelId: speechModelId,
              imageModelId: imageModelId,
              imageRecognitionModelId: imageRecognitionModelId,
              imageGenerationModelId: imageGenerationModelId,
            ),
          );
        })
        .toList(growable: false);

    if (!changed) {
      _pendingSaveSnapshot = List<Conversation>.from(_conversations);
      _queueSaveConversations(immediate: true);
      await flushPendingSaves();
      return false;
    }
    _queueSaveConversations(immediate: true);
    await flushPendingSaves();
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _enqueuePendingSave();
    _enqueueComposerDraftSave();
    _saveDebounce?.cancel();
    _draftDebounce?.cancel();
    super.dispose();
  }

  /// 创建新对话并返回对话 ID。
  String createConversation(
    ConversationSettings settings, {
    String roleId = 'default',
    AgentWorkingMemory? initialMemory,
    String? workspaceId,
    String? workspaceName,
  }) {
    try {
      final now = DateTime.now();
      final conversation = Conversation(
        id: _uuid.v4(),
        title: '新对话 ${_conversations.length + 1}',
        messages: [],
        modelId: settings.modelId,
        settings: settings,
        agentWorkingMemory: initialMemory,
        roleId: roleId,
        workspaceId: _nonEmpty(workspaceId),
        workspaceName: _nonEmpty(workspaceName),
        createdAt: now,
        updatedAt: now,
      );
      _conversations.insert(0, conversation);
      _queueSaveConversations();
      notifyListeners();
      return conversation.id;
    } catch (e) {
      debugPrint('创建对话失败: $e');
      rethrow;
    }
  }

  String createConversationWithMessages(
    ConversationSettings settings, {
    String roleId = 'default',
    AgentWorkingMemory? initialMemory,
    String? workspaceId,
    String? workspaceName,
    required List<
      ({
        String role,
        String content,
        List<MessageImage> images,
        List<ComposerSegment> composerSegments,
      })
    >
    messages,
    Map<int, String>? modelContextByIndex,
  }) {
    try {
      final now = DateTime.now();
      final initialMessages = messages.indexed
          .map(
            (entry) => Message(
              id: _uuid.v4(),
              role: entry.$2.role,
              content: entry.$2.content,
              modelContextContent: modelContextByIndex?[entry.$1],
              images: entry.$2.images,
              composerSegments: entry.$2.composerSegments,
              timestamp: now,
            ),
          )
          .toList(growable: false);
      Message? firstUser;
      for (final message in initialMessages) {
        if (message.role == 'user') {
          firstUser = message;
          break;
        }
      }
      final title = firstUser == null
          ? '新对话 ${_conversations.length + 1}'
          : _titleFromFirstUser(firstUser);
      final conversation = Conversation(
        id: _uuid.v4(),
        title: title,
        messages: initialMessages,
        modelId: settings.modelId,
        settings: settings,
        agentWorkingMemory: initialMemory,
        roleId: roleId,
        workspaceId: _nonEmpty(workspaceId),
        workspaceName: _nonEmpty(workspaceName),
        createdAt: now,
        updatedAt: now,
      );
      _conversations.insert(0, conversation);
      _queueSaveConversations();
      notifyListeners();
      return conversation.id;
    } catch (e) {
      debugPrint('创建对话失败: $e');
      rethrow;
    }
  }

  String _titleFromFirstUser(Message message) {
    final clean = message.content.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    final titleSource = clean.isNotEmpty
        ? clean
        : (message.images.isNotEmpty
              ? '[附件] ${message.images.first.name}'
              : '新对话');
    return titleSource.length > 20
        ? '${titleSource.substring(0, 20)}...'
        : titleSource;
  }

  /// 向指定对话添加一条消息。
  void addMessage(
    String conversationId,
    String role,
    String content, {
    String? modelContextContent,
    List<MessageImage> images = const [],
    String? thinkingContent,
    List<ComposerSegment> composerSegments = const [],
    bool save = true,
  }) {
    try {
      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index == -1) return;

      final message = Message(
        id: _uuid.v4(),
        role: role,
        content: content,
        modelContextContent: modelContextContent,
        images: images,
        thinkingContent: thinkingContent,
        agentTrace: null,
        composerSegments: composerSegments,
        timestamp: DateTime.now(),
      );

      final updatedMessages = List<Message>.from(_conversations[index].messages)
        ..add(message);
      final now = DateTime.now();

      String title = _conversations[index].title;
      if (_conversations[index].messages.isEmpty && role == 'user') {
        title = _titleFromFirstUser(message);
      }

      _conversations[index] = _conversations[index].copyWith(
        title: title,
        messages: updatedMessages,
        updatedAt: now,
      );

      // 将更新的对话移到列表顶部
      final conv = _conversations.removeAt(index);
      _conversations.insert(0, conv);

      if (save) _queueSaveConversations();
      notifyListeners();
    } catch (e) {
      debugPrint('添加消息失败: $e');
    }
  }

  /// 更新对话标题
  void updateConversationTitle(String conversationId, String title) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;
    _conversations[index] = _conversations[index].copyWith(
      title: title,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index);
    _queueSaveConversations();
    notifyListeners();
  }

  /// 更新对话使用的模型ID
  void updateConversationModelId(String conversationId, String modelId) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;
    _conversations[index] = _conversations[index].copyWith(
      modelId: modelId,
      settings: _conversations[index].settings.copyWith(
        modelId: modelId,
        modelName: null,
      ),
      updatedAt: DateTime.now(),
    );
    _touchConversation(index);
    _queueSaveConversations();
    notifyListeners();
  }

  /// 修复已删除模型留下的对话引用。
  void repairModelReferences(List<ModelConfig> models) {
    final chatModels = models
        .where((model) => model.category == ModelConfig.categoryChat)
        .toList(growable: false);
    if (chatModels.isEmpty) return;

    final validIds = chatModels.map((model) => model.id).toSet();
    final fallbackId = chatModels.first.id;
    var changed = false;

    _conversations = _conversations.map((conversation) {
      final nextModelId = validIds.contains(conversation.modelId)
          ? conversation.modelId
          : fallbackId;
      final nextSettingsModelId =
          validIds.contains(conversation.settings.modelId)
          ? conversation.settings.modelId
          : nextModelId;
      if (nextModelId == conversation.modelId &&
          nextSettingsModelId == conversation.settings.modelId) {
        return conversation;
      }
      changed = true;
      return conversation.copyWith(
        modelId: nextModelId,
        settings: conversation.settings.copyWith(
          modelId: nextSettingsModelId,
          modelName: nextSettingsModelId == conversation.settings.modelId
              ? conversation.settings.modelName
              : null,
        ),
      );
    }).toList();

    if (!changed) return;
    _queueSaveConversations();
    notifyListeners();
  }

  /// 更新最后一条消息的内容（用于流式响应）
  void updateLastMessage(
    String conversationId,
    String content, {
    Object? thinkingContent = _sentinel,
    bool save = true,
  }) {
    try {
      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index == -1 || _conversations[index].messages.isEmpty) return;

      final messages = List<Message>.from(_conversations[index].messages);
      final lastMsg = messages.last;
      messages[messages.length - 1] = Message(
        id: lastMsg.id,
        role: lastMsg.role,
        content: content,
        modelContextContent: lastMsg.modelContextContent,
        images: lastMsg.images,
        thinkingContent: identical(thinkingContent, _sentinel)
            ? lastMsg.thinkingContent
            : thinkingContent as String?,
        agentTrace: lastMsg.agentTrace,
        timestamp: lastMsg.timestamp,
        revision: lastMsg.revision,
        updatedAt: lastMsg.updatedAt,
      );

      _conversations[index] = _conversations[index].copyWith(
        messages: messages,
        updatedAt: DateTime.now(),
      );

      // 将更新的对话移到列表顶部
      final conv = _conversations.removeAt(index);
      _conversations.insert(0, conv);

      if (save) _queueSaveConversations();
      notifyListeners();
    } catch (e) {
      debugPrint('更新最后消息失败: $e');
    }
  }

  void appendImagesToLastAssistantMessage(
    String conversationId,
    List<MessageImage> images,
  ) {
    if (images.isEmpty) return;
    try {
      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index == -1 || _conversations[index].messages.isEmpty) return;

      final messages = List<Message>.from(_conversations[index].messages);
      var messageIndex = -1;
      for (var i = messages.length - 1; i >= 0; i--) {
        if (messages[i].role == 'assistant') {
          messageIndex = i;
          break;
        }
      }
      if (messageIndex == -1) return;

      final message = messages[messageIndex];
      messages[messageIndex] = Message(
        id: message.id,
        role: message.role,
        content: message.content,
        modelContextContent: message.modelContextContent,
        images: [...message.images, ...images],
        thinkingContent: message.thinkingContent,
        agentTrace: message.agentTrace,
        timestamp: message.timestamp,
        revision: message.revision,
        updatedAt: message.updatedAt,
      );

      _conversations[index] = _conversations[index].copyWith(
        messages: messages,
        updatedAt: DateTime.now(),
      );
      _touchConversation(index);
      _queueSaveConversations();
      notifyListeners();
    } catch (e) {
      debugPrint('追加图片到消息失败: $e');
    }
  }

  /// Appends an Agent trace event to the latest assistant message.
  void appendAgentTraceEvent(
    String conversationId,
    AgentTraceEvent event, {
    bool save = false,
  }) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1 || _conversations[index].messages.isEmpty) return;
    final messages = List<Message>.from(_conversations[index].messages);
    var msgIdx = -1;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == 'assistant') {
        msgIdx = i;
        break;
      }
    }
    if (msgIdx == -1) return;
    final old = messages[msgIdx];
    final trace = (old.agentTrace ?? const AgentTrace()).append(event);
    messages[msgIdx] = Message(
      id: old.id,
      role: old.role,
      content: old.content,
      modelContextContent: old.modelContextContent,
      images: old.images,
      thinkingContent: old.thinkingContent,
      agentTrace: trace,
      timestamp: old.timestamp,
      revision: old.revision,
      updatedAt: old.updatedAt,
    );
    _conversations[index] = _conversations[index].copyWith(
      messages: messages,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index);
    if (save) _queueSaveConversations();
    notifyListeners();
  }

  /// 删除指定消息
  void deleteMessage(String conversationId, String messageId) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;

    final messages = List<Message>.from(_conversations[index].messages)
      ..removeWhere((m) => m.id == messageId);

    _conversations[index] = _conversations[index].copyWith(
      messages: messages,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index);
    _queueSaveConversations();
    notifyListeners();
  }

  /// 删除从指定消息开始的后续所有消息。
  void deleteMessagesFrom(String conversationId, String messageId) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;
    final messages = List<Message>.from(_conversations[index].messages);
    final messageIndex = messages.indexWhere((m) => m.id == messageId);
    if (messageIndex == -1) return;

    final updatedMessages = messages.take(messageIndex).toList();
    _conversations[index] = _conversations[index].copyWith(
      messages: updatedMessages,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index);
    _queueSaveConversations();
    notifyListeners();
  }

  /// 撤销撤回：把撤回时截断的消息尾部原样放回对话末尾。
  ///
  /// [expectedPrefixLength] 是撤回发生时保留下来的消息数量。只有当对话当前消息
  /// 数仍等于它时才恢复，避免用户在撤销窗口内继续发送后，把旧消息插进新内容中间。
  /// 返回是否真的恢复。
  bool restoreWithdrawnMessages(
    String conversationId,
    List<Message> messages, {
    required int expectedPrefixLength,
  }) {
    if (messages.isEmpty) return false;
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return false;
    final existing = _conversations[index].messages;
    if (existing.length != expectedPrefixLength) return false;
    _conversations[index] = _conversations[index].copyWith(
      messages: [...existing, ...messages],
      updatedAt: DateTime.now(),
    );
    _touchConversation(index);
    _queueSaveConversations();
    notifyListeners();
    return true;
  }

  /// 删除对话
  ///
  /// 输入框草稿属于对话，随回收站快照一起保存：删除后一并移除，从回收站恢复时
  /// 由 [restoreConversation] 写回。
  Future<void> deleteConversation(String conversationId) async {
    final conversation = getConversation(conversationId);
    if (conversation == null) return;
    final draft = _composerDrafts.remove(conversationId);
    await _recycleBinRepository.add(
      RecycleBinItem(
        owner: RecycleBinOwners.core,
        category: RecycleBinCategories.conversations,
        type: RecycleBinItemTypes.conversation,
        title: conversation.title.isEmpty ? '未命名对话' : conversation.title,
        preview: conversation.preview,
        payload: {
          'conversation': conversation.toJson(),
          if (draft != null && !draft.isEmpty) 'composerDraft': draft.toJson(),
        },
      ),
    );
    _queueComposerDraftSave(immediate: true);
    _conversations.removeWhere((c) => c.id == conversationId);
    _queueSaveConversations();
    notifyListeners();
  }

  Future<void> restoreConversation(
    Conversation conversation, {
    ComposerDraft? draft,
  }) async {
    if (_conversations.any((item) => item.id == conversation.id)) return;
    _conversations.insert(0, conversation);
    if (draft != null && !draft.isEmpty) {
      _composerDrafts[conversation.id] = draft;
      _queueComposerDraftSave(immediate: true);
    }
    _queueSaveConversations(immediate: true);
    await flushPendingSaves();
    notifyListeners();
  }

  /// 根据ID获取对话
  Conversation? getConversation(String conversationId) {
    try {
      return _conversations.firstWhere((c) => c.id == conversationId);
    } catch (_) {
      return null;
    }
  }

  /// 更新对话设置快照
  void updateConversationSettings(
    String conversationId,
    ConversationSettings settings,
  ) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;
    _conversations[index] = _conversations[index].copyWith(
      modelId: settings.modelId,
      settings: settings,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index);
    _queueSaveConversations();
    notifyListeners();
  }

  void updateAgentPlan(String conversationId, AgentPlan? plan) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;
    _conversations[index] = _conversations[index].copyWith(
      agentPlan: plan,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index);
    _queueSaveConversations();
    notifyListeners();
  }

  /// 设置或清除 `/压缩` 产生的上下文检查点。
  ///
  /// 只改检查点，不动原始消息：被覆盖的历史仍然完整保留在 [Conversation.messages]。
  void setContextCheckpoint(
    String conversationId,
    ConversationContextCheckpoint? checkpoint,
  ) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;
    _conversations[index] = _conversations[index].copyWith(
      contextCheckpoint: checkpoint,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index);
    _queueSaveConversations();
    notifyListeners();
  }

  /// 把引用并入会话引用池。
  ///
  /// 池子独立于消息上下文，不进入 [buildApiMessages]，也不受上下文压缩影响；
  /// 同键条目只更新时间与标题，超出上限时淘汰最久未引用的条目。
  void rememberComposerReferences(
    String conversationId,
    Iterable<ComposerReference> references,
  ) {
    final list = references
        .where((reference) => reference.id.isNotEmpty)
        .toList(growable: false);
    if (list.isEmpty) return;
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;
    final next = _conversations[index].referencePool.merged(
      list,
      now: DateTime.now(),
    );
    _conversations[index] = _conversations[index].copyWith(
      referencePool: next,
    );
    _queueSaveConversations();
    notifyListeners();
  }

  /// 消息被编辑或撤回后收敛检查点覆盖范围；覆盖集合清空则清除检查点。
  void reconcileContextCheckpoint(String conversationId) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;
    final conversation = _conversations[index];
    final checkpoint = conversation.contextCheckpoint;
    if (checkpoint == null) return;
    final next = checkpoint.withCoveredMessages(
      conversation.messages.map((message) => message.id),
    );
    if (identical(next, checkpoint)) return;
    _conversations[index] = next == null
        ? conversation.copyWith(contextCheckpoint: null)
        : conversation.copyWith(contextCheckpoint: next);
    _queueSaveConversations();
    notifyListeners();
  }

  /// 取当前有效检查点：覆盖集合与现存消息对不上时视为已失效。
  ///
  /// 撤回、分支重置或远端同步改写消息 ID 后，旧检查点描述的历史已不存在，
  /// 继续用它顶替会误导模型，因此按失效处理（只改内存视图，下一次落盘时自然
  /// 以修正后的集合写回）。
  ConversationContextCheckpoint? liveContextCheckpoint(String conversationId) {
    final conversation = getConversation(conversationId);
    final checkpoint = conversation?.contextCheckpoint;
    if (conversation == null || checkpoint == null) return null;
    final alive = conversation.messages.map((message) => message.id).toSet();
    return checkpoint.withCoveredMessages(alive);
  }

  void updateAgentWorkingMemory(
    String conversationId,
    AgentWorkingMemory? memory,
  ) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;
    _conversations[index] = _conversations[index].copyWith(
      agentWorkingMemory: memory,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index);
    _queueSaveConversations();
    notifyListeners();
  }

  /// 绑定或解绑当前对话正在创作的插件工作区。
  void setPluginWorkspace(String conversationId, String? pluginId) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;
    final normalized = pluginId?.trim();
    final next = normalized == null || normalized.isEmpty ? null : normalized;
    if (_conversations[index].pluginWorkspaceId == next) return;
    _conversations[index] = _conversations[index].copyWith(
      pluginWorkspaceId: next,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index);
    _queueSaveConversations();
    notifyListeners();
  }

  /// 把会话绑定到工作区（写入 ID 与名称快照）。
  ///
  /// 返回错误码语义供 Agent 工具转成结构化错误：
  /// - `ok`：绑定或幂等重复绑定成功；
  /// - `already_bound`：已绑定到其他工作区，不静默搬移。
  String bindConversationToWorkspace(
    String conversationId,
    String workspaceId,
    String workspaceName,
  ) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return 'conversation_not_found';
    final normalizedId = workspaceId.trim();
    final normalizedName = workspaceName.trim();
    if (normalizedId.isEmpty || normalizedName.isEmpty) {
      return 'invalid_arguments';
    }
    final current = _conversations[index].workspaceId;
    if (current != null && current != normalizedId) return 'already_bound';
    if (current == normalizedId &&
        _conversations[index].workspaceName == normalizedName) {
      return 'ok';
    }
    _conversations[index] = _conversations[index].copyWith(
      workspaceId: normalizedId,
      workspaceName: normalizedName,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index);
    _queueSaveConversations();
    notifyListeners();
    return 'ok';
  }

  /// 删除工作区时，把该工作区会话转回普通对话（保留消息与角色）。
  void detachWorkspaceFromConversations(String workspaceId) {
    var changed = false;
    _conversations = _conversations
        .map((conversation) {
          if (conversation.workspaceId != workspaceId) return conversation;
          changed = true;
          return conversation.copyWith(
            workspaceId: null,
            workspaceName: null,
            updatedAt: conversation.updatedAt,
          );
        })
        .toList(growable: false);
    if (!changed) return;
    _queueSaveConversations();
    notifyListeners();
  }

  /// 记录一个由 AI 创建的插件草稿产物。
  void addPluginArtifact(
    String conversationId,
    ConversationPluginArtifact artifact,
  ) {
    if (artifact.pluginId.trim().isEmpty) return;
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;
    final artifacts = [
      ..._conversations[index].pluginArtifacts.where(
        (item) => item.pluginId != artifact.pluginId,
      ),
      artifact,
    ];
    artifacts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _conversations[index] = _conversations[index].copyWith(
      pluginArtifacts: artifacts,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index);
    _queueSaveConversations();
    notifyListeners();
  }

  /// 移除对话中的插件草稿卡片，不删除插件本身。
  void removePluginArtifact(String conversationId, String pluginId) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;
    final artifacts = _conversations[index].pluginArtifacts
        .where((item) => item.pluginId != pluginId)
        .toList(growable: false);
    if (artifacts.length == _conversations[index].pluginArtifacts.length) {
      return;
    }
    _conversations[index] = _conversations[index].copyWith(
      pluginArtifacts: artifacts,
      pluginWorkspaceId: _conversations[index].pluginWorkspaceId == pluginId
          ? null
          : _conversations[index].pluginWorkspaceId,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index);
    _queueSaveConversations();
    notifyListeners();
  }

  /// 找到已绑定指定插件的对话 ID。
  String? findPluginWorkspaceConversationId(String pluginId) {
    final normalized = pluginId.trim();
    for (final conversation in _conversations) {
      if (conversation.pluginWorkspaceId == normalized) {
        return conversation.id;
      }
    }
    return null;
  }

  /// 为插件工坊的 AI 协作找到或创建绑定该插件的对话。
  ///
  /// 已存在绑定时复用；不存在则创建标题为「插件 · $pluginName」的空对话，
  /// 并强制启用 Agent 模式。
  String ensurePluginConversation({
    required String pluginId,
    required String pluginName,
    required ConversationSettings settings,
  }) {
    final existing = findPluginWorkspaceConversationId(pluginId);
    if (existing != null) return existing;
    final conversationId = createConversation(
      settings.copyWith(agentEnabled: true),
    );
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      _conversations[index] = _conversations[index].copyWith(
        title:
            '插件 · ${pluginName.trim().isEmpty ? pluginId : pluginName.trim()}',
        pluginWorkspaceId: pluginId.trim(),
      );
      _queueSaveConversations();
      notifyListeners();
    }
    return conversationId;
  }

  /// 更新指定消息的内容
  void updateMessageContent(
    String conversationId,
    String messageId,
    String content, {
    Object? modelContextContent = _sentinel,
    Object? thinkingContent = _sentinel,
  }) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;
    final messages = List<Message>.from(_conversations[index].messages);
    final msgIdx = messages.indexWhere((m) => m.id == messageId);
    if (msgIdx == -1) return;
    final old = messages[msgIdx];
    messages[msgIdx] = Message(
      id: old.id,
      role: old.role,
      content: content,
      modelContextContent: identical(modelContextContent, _sentinel)
          ? old.modelContextContent
          : modelContextContent as String?,
      images: old.images,
      thinkingContent: identical(thinkingContent, _sentinel)
          ? old.thinkingContent
          : thinkingContent as String?,
      agentTrace: old.agentTrace,
      composerSegments: old.composerSegments,
      timestamp: old.timestamp,
      revision: old.revision + 1,
      updatedAt: DateTime.now(),
    );
    _conversations[index] = _conversations[index].copyWith(
      messages: messages,
      updatedAt: DateTime.now(),
    );
    // 将更新的对话移到列表顶部
    final conv = _conversations.removeAt(index);
    _conversations.insert(0, conv);
    _queueSaveConversations();
    notifyListeners();
  }

  void updateMessageImages(
    String conversationId,
    String messageId,
    List<MessageImage> images,
  ) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;
    final messages = List<Message>.from(_conversations[index].messages);
    final msgIdx = messages.indexWhere((m) => m.id == messageId);
    if (msgIdx == -1) return;
    final old = messages[msgIdx];
    messages[msgIdx] = Message(
      id: old.id,
      role: old.role,
      content: old.content,
      modelContextContent: old.modelContextContent,
      images: List<MessageImage>.from(images),
      thinkingContent: old.thinkingContent,
      agentTrace: old.agentTrace,
      timestamp: old.timestamp,
      revision: old.revision + 1,
      updatedAt: DateTime.now(),
    );
    _conversations[index] = _conversations[index].copyWith(
      messages: messages,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index);
    _queueSaveConversations();
    notifyListeners();
  }

  /// 搜索对话（匹配标题、消息内容和附件名）。
  List<ConversationSearchResult> searchConversations(String query) {
    return searchConversationsInScope(query);
  }

  /// 按历史域搜索对话。
  ///
  /// [workspaceOnly] 为 null 时搜索全部（兼容旧调用）；为 true 时只搜索
  /// 工作区会话（再按 [workspaceId] 过滤）；为 false 时只搜索普通会话。
  List<ConversationSearchResult> searchConversationsInScope(
    String query, {
    bool? workspaceOnly,
    String? workspaceId,
  }) {
    final scoped = _conversations.where((conversation) {
      return switch (workspaceOnly) {
        null => true,
        true =>
          conversation.workspaceId != null &&
              (workspaceId == null || conversation.workspaceId == workspaceId),
        false => conversation.workspaceId == null,
      };
    });
    final matcher = ChatSearchMatcher.fromQuery(query);
    if (matcher.isEmpty) {
      return scoped
          .map((c) => ConversationSearchResult(conversation: c))
          .toList();
    }
    if (matcher.hasError) return const [];

    final results = <ConversationSearchResult>[];
    for (final conv in scoped) {
      final titleRanges = matcher.rangesIn(conv.title);
      if (titleRanges.isNotEmpty) {
        results.add(
          ConversationSearchResult(
            conversation: conv,
            matchType: ConversationSearchMatchType.title,
            snippet: conv.title,
            snippetRanges: titleRanges,
          ),
        );
        continue;
      }

      ConversationSearchResult? match;
      for (final msg in conv.messages.reversed) {
        final content = msg.content.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
        final contentRanges = matcher.rangesIn(content);
        if (contentRanges.isNotEmpty) {
          final snippet = _searchSnippet(content, contentRanges.last);
          match = ConversationSearchResult(
            conversation: conv,
            matchType: ConversationSearchMatchType.message,
            snippet: snippet,
            snippetRanges: matcher.rangesIn(snippet),
          );
          break;
        }
        for (final image in msg.images.reversed) {
          final imageRanges = matcher.rangesIn(image.name);
          if (imageRanges.isEmpty) continue;
          match = ConversationSearchResult(
            conversation: conv,
            matchType: ConversationSearchMatchType.attachment,
            snippet: image.name,
            snippetRanges: imageRanges,
          );
          break;
        }
        if (match != null) break;
      }
      if (match != null) results.add(match);
    }

    return results;
  }

  String _searchSnippet(String text, ChatSearchRange range) {
    const contextLength = 56;
    final start = (range.start - contextLength).clamp(0, text.length).toInt();
    final end = (range.end + contextLength).clamp(0, text.length).toInt();
    final prefix = start > 0 ? '...' : '';
    final suffix = end < text.length ? '...' : '';
    return '$prefix${text.substring(start, end)}$suffix';
  }

  List<ConversationSearchResult> searchConversationsByRole(
    String query,
    String roleId,
  ) {
    return searchConversations(
      query,
    ).where((result) => result.conversation.roleId == roleId).toList();
  }

  static String? _nonEmpty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
