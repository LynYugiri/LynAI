import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/agent_plan.dart';
import '../models/agent_trace.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/model_config.dart';
import '../models/recycle_bin_item.dart';
import '../repositories/conversation_repository.dart';
import '../repositories/recycle_bin_repository.dart';
import '../services/storage_v2_service.dart';

/// 管理对话历史、消息流式更新和对话持久化。
///
/// 约定：UI 可以先看到内存更新，落盘通过串行保存队列按快照顺序执行。
/// 这样流式刷新、停止生成、重试切换不会让较旧的异步写入覆盖新状态。
class ConversationProvider extends ChangeNotifier {
  List<Conversation> _conversations = [];
  final _uuid = const Uuid();
  Future<void> _saveQueue = Future.value();
  Timer? _saveDebounce;
  List<Conversation>? _pendingSaveSnapshot;
  Completer<void>? _pendingSaveCompleter;
  static const _sentinel = Object();
  static const _saveDebounceDuration = Duration(milliseconds: 500);
  final ConversationRepository _repository;
  final RecycleBinRepository _recycleBinRepository;
  bool _usingStorageV2 = false;

  ConversationProvider({
    StorageV2Service? storageV2,
    ConversationRepository? repository,
    RecycleBinRepository? recycleBinRepository,
  }) : _repository = repository ?? ConversationRepository(storageV2: storageV2),
       _recycleBinRepository =
           recycleBinRepository ?? RecycleBinRepository(storageV2: storageV2);

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
    try {
      final result = await _repository.load();
      _conversations = List<Conversation>.from(result.conversations);
      _usingStorageV2 = result.usingStorageV2;
      notifyListeners();
    } catch (e) {
      debugPrint('加载对话失败: $e');
      _conversations = [];
      notifyListeners();
    }
  }

  /// 把当前对话快照排入保存队列。
  void _queueSaveConversations({bool immediate = false}) {
    _pendingSaveSnapshot = List<Conversation>.from(_conversations);
    _pendingSaveCompleter ??= Completer<void>();
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
    final completer = _pendingSaveCompleter;
    if (snapshot == null || completer == null) return;
    _pendingSaveSnapshot = null;
    _pendingSaveCompleter = null;
    _saveQueue = _saveQueue
        .then((_) => _saveConversationsSnapshot(snapshot))
        .whenComplete(() {
          if (!completer.isCompleted) completer.complete();
        });
  }

  Future<void> flushPendingSaves() {
    _enqueuePendingSave();
    return _saveQueue;
  }

  Future<void> _saveConversationsSnapshot(List<Conversation> snapshot) async {
    try {
      await _repository.save(snapshot, usingStorageV2: _usingStorageV2);
    } catch (e) {
      debugPrint('保存对话失败: $e');
    }
  }

  @override
  void dispose() {
    _enqueuePendingSave();
    _saveDebounce?.cancel();
    super.dispose();
  }

  /// 创建新对话并返回对话 ID。
  String createConversation(
    ConversationSettings settings, {
    String roleId = 'default',
  }) {
    try {
      final now = DateTime.now();
      final conversation = Conversation(
        id: _uuid.v4(),
        title: '新对话 ${_conversations.length + 1}',
        messages: [],
        modelId: settings.modelId,
        settings: settings,
        roleId: roleId,
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
    required List<({String role, String content, List<MessageImage> images})>
    messages,
  }) {
    try {
      final now = DateTime.now();
      final initialMessages = messages
          .map(
            (item) => Message(
              id: _uuid.v4(),
              role: item.role,
              content: item.content,
              images: item.images,
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
        roleId: roleId,
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
    List<MessageImage> images = const [],
    String? thinkingContent,
    bool save = true,
  }) {
    try {
      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index == -1) return;

      final message = Message(
        id: _uuid.v4(),
        role: role,
        content: content,
        images: images,
        thinkingContent: thinkingContent,
        agentTrace: null,
        timestamp: DateTime.now(),
      );

      final updatedMessages = List<Message>.from(_conversations[index].messages)
        ..add(message);
      final now = DateTime.now();

      String title = _conversations[index].title;
      if (_conversations[index].messages.isEmpty && role == 'user') {
        title = _titleFromFirstUser(message);
      }

      _conversations[index] = Conversation(
        id: _conversations[index].id,
        title: title,
        messages: updatedMessages,
        modelId: _conversations[index].modelId,
        settings: _conversations[index].settings,
        agentPlan: _conversations[index].agentPlan,
        roleId: _conversations[index].roleId,
        createdAt: _conversations[index].createdAt,
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
    _conversations[index] = Conversation(
      id: _conversations[index].id,
      title: title,
      messages: _conversations[index].messages,
      modelId: _conversations[index].modelId,
      settings: _conversations[index].settings,
      agentPlan: _conversations[index].agentPlan,
      roleId: _conversations[index].roleId,
      createdAt: _conversations[index].createdAt,
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
    _conversations[index] = Conversation(
      id: _conversations[index].id,
      title: _conversations[index].title,
      messages: _conversations[index].messages,
      modelId: modelId,
      settings: _conversations[index].settings.copyWith(
        modelId: modelId,
        modelName: null,
      ),
      agentPlan: _conversations[index].agentPlan,
      roleId: _conversations[index].roleId,
      createdAt: _conversations[index].createdAt,
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
        images: lastMsg.images,
        thinkingContent: identical(thinkingContent, _sentinel)
            ? lastMsg.thinkingContent
            : thinkingContent as String?,
        agentTrace: lastMsg.agentTrace,
        timestamp: lastMsg.timestamp,
      );

      _conversations[index] = Conversation(
        id: _conversations[index].id,
        title: _conversations[index].title,
        messages: messages,
        modelId: _conversations[index].modelId,
        settings: _conversations[index].settings,
        agentPlan: _conversations[index].agentPlan,
        roleId: _conversations[index].roleId,
        createdAt: _conversations[index].createdAt,
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
      images: old.images,
      thinkingContent: old.thinkingContent,
      agentTrace: trace,
      timestamp: old.timestamp,
    );
    _conversations[index] = Conversation(
      id: _conversations[index].id,
      title: _conversations[index].title,
      messages: messages,
      modelId: _conversations[index].modelId,
      settings: _conversations[index].settings,
      agentPlan: _conversations[index].agentPlan,
      roleId: _conversations[index].roleId,
      createdAt: _conversations[index].createdAt,
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

    _conversations[index] = Conversation(
      id: _conversations[index].id,
      title: _conversations[index].title,
      messages: messages,
      modelId: _conversations[index].modelId,
      settings: _conversations[index].settings,
      agentPlan: _conversations[index].agentPlan,
      roleId: _conversations[index].roleId,
      createdAt: _conversations[index].createdAt,
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
    _conversations[index] = Conversation(
      id: _conversations[index].id,
      title: _conversations[index].title,
      messages: updatedMessages,
      modelId: _conversations[index].modelId,
      settings: _conversations[index].settings,
      agentPlan: _conversations[index].agentPlan,
      roleId: _conversations[index].roleId,
      createdAt: _conversations[index].createdAt,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index);
    _queueSaveConversations();
    notifyListeners();
  }

  /// 删除对话
  Future<void> deleteConversation(String conversationId) async {
    final conversation = getConversation(conversationId);
    if (conversation == null) return;
    await _recycleBinRepository.add(
      RecycleBinItem(
        owner: RecycleBinOwners.core,
        category: RecycleBinCategories.conversations,
        type: RecycleBinItemTypes.conversation,
        title: conversation.title.isEmpty ? '未命名对话' : conversation.title,
        preview: conversation.preview,
        payload: {'conversation': conversation.toJson()},
      ),
    );
    _conversations.removeWhere((c) => c.id == conversationId);
    _queueSaveConversations();
    notifyListeners();
  }

  Future<void> restoreConversation(Conversation conversation) async {
    if (_conversations.any((item) => item.id == conversation.id)) return;
    _conversations.insert(0, conversation);
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
    _conversations[index] = Conversation(
      id: _conversations[index].id,
      title: _conversations[index].title,
      messages: _conversations[index].messages,
      modelId: settings.modelId,
      settings: settings,
      agentPlan: _conversations[index].agentPlan,
      roleId: _conversations[index].roleId,
      createdAt: _conversations[index].createdAt,
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

  /// 更新指定消息的内容
  void updateMessageContent(
    String conversationId,
    String messageId,
    String content, {
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
      images: old.images,
      thinkingContent: identical(thinkingContent, _sentinel)
          ? old.thinkingContent
          : thinkingContent as String?,
      agentTrace: old.agentTrace,
      timestamp: old.timestamp,
    );
    _conversations[index] = Conversation(
      id: _conversations[index].id,
      title: _conversations[index].title,
      messages: messages,
      modelId: _conversations[index].modelId,
      settings: _conversations[index].settings,
      agentPlan: _conversations[index].agentPlan,
      roleId: _conversations[index].roleId,
      createdAt: _conversations[index].createdAt,
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
      images: List<MessageImage>.from(images),
      thinkingContent: old.thinkingContent,
      agentTrace: old.agentTrace,
      timestamp: old.timestamp,
    );
    _conversations[index] = Conversation(
      id: _conversations[index].id,
      title: _conversations[index].title,
      messages: messages,
      modelId: _conversations[index].modelId,
      settings: _conversations[index].settings,
      agentPlan: _conversations[index].agentPlan,
      roleId: _conversations[index].roleId,
      createdAt: _conversations[index].createdAt,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index);
    _queueSaveConversations();
    notifyListeners();
  }

  /// 搜索对话（匹配标题和消息内容）
  /// 返回匹配的对话列表，每个对话附带匹配的文本片段
  List<Map<String, dynamic>> searchConversations(String query) {
    if (query.isEmpty) {
      return _conversations.map((c) => {'conversation': c}).toList();
    }

    final lowerQuery = query.toLowerCase();
    final results = <Map<String, dynamic>>[];

    for (final conv in _conversations) {
      // 检查标题是否匹配
      if (conv.title.toLowerCase().contains(lowerQuery)) {
        results.add({
          'conversation': conv,
          'matchInTitle': true,
          'matchContent': '',
        });
        continue;
      }

      // 检查消息内容和附件名是否匹配
      for (final msg in conv.messages) {
        final attachmentMatch = msg.images.any(
          (image) => image.name.toLowerCase().contains(lowerQuery),
        );
        if (msg.content.toLowerCase().contains(lowerQuery) || attachmentMatch) {
          results.add({
            'conversation': conv,
            'matchInTitle': false,
            'matchContent': msg.content.isNotEmpty
                ? msg.content
                : msg.images.map((image) => image.name).join(', '),
          });
          break;
        }
      }
    }

    return results;
  }

  List<Map<String, dynamic>> searchConversationsByRole(
    String query,
    String roleId,
  ) {
    return searchConversations(query)
        .where(
          (result) => (result['conversation'] as Conversation).roleId == roleId,
        )
        .toList();
  }
}
