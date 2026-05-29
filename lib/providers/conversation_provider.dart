import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/storage_migration_service.dart';
import '../services/storage_v2_service.dart';

/// 管理对话历史、消息流式更新和对话持久化。
///
/// 约定：UI 可以先看到内存更新，落盘通过串行保存队列按快照顺序执行。
/// 这样流式刷新、停止生成、重试切换不会让较旧的异步写入覆盖新状态。
class ConversationProvider extends ChangeNotifier {
  List<Conversation> _conversations = [];
  final _uuid = const Uuid();
  static const _storageKey = 'conversations';
  Future<void> _saveQueue = Future.value();
  static const _sentinel = Object();
  final StorageV2Service _storageV2;
  bool _usingStorageV2 = false;

  ConversationProvider({StorageV2Service? storageV2})
    : _storageV2 = storageV2 ?? StorageV2Service();

  void _touchConversation(int index, Conversation conversation) {
    _conversations[index] = conversation;
    final updated = _conversations.removeAt(index);
    _conversations.insert(0, updated);
  }

  /// 所有对话，按最近更新时间倒序排列。
  List<Conversation> get conversations => List.unmodifiable(_conversations);
  bool get usingStorageV2 => _usingStorageV2;

  Future<void> replaceConversations(List<Conversation> conversations) async {
    _conversations = List<Conversation>.from(conversations)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _queueSaveConversations();
    await _saveQueue;
    notifyListeners();
  }

  /// 从 SharedPreferences 加载对话。
  ///
  /// 单条损坏对话会被跳过；单条损坏消息由 [Conversation.fromJson] 跳过。
  Future<void> loadConversations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getInt('storage_schema_version') ?? 1) >=
              StorageMigrationService.currentSchemaVersion &&
          await _storageV2.exists()) {
        await _loadStorageV2Conversations();
        notifyListeners();
        return;
      }
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        final conversations = <Conversation>[];
        for (final item in jsonList) {
          try {
            conversations.add(
              Conversation.fromJson(item as Map<String, dynamic>),
            );
          } catch (e) {
            debugPrint('跳过损坏的对话记录: $e');
          }
        }
        _conversations = conversations;
        _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('加载对话失败: $e');
      _conversations = [];
      notifyListeners();
    }
  }

  /// 把当前对话快照排入保存队列。
  void _queueSaveConversations() {
    final snapshot = List<Conversation>.from(_conversations);
    _saveQueue = _saveQueue.then((_) => _saveConversationsSnapshot(snapshot));
  }

  Future<void> _saveConversationsSnapshot(List<Conversation> snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_usingStorageV2 ||
          ((prefs.getInt('storage_schema_version') ?? 1) >=
                  StorageMigrationService.currentSchemaVersion &&
              await _storageV2.exists())) {
        _usingStorageV2 = true;
        await _saveStorageV2Conversations(snapshot);
        return;
      }
      final jsonString = jsonEncode(snapshot.map((c) => c.toJson()).toList());
      await prefs.setString(_storageKey, jsonString);
    } catch (e) {
      debugPrint('保存对话失败: $e');
    }
  }

  Future<void> _loadStorageV2Conversations() async {
    final json = await _storageV2.loadDataFile('conversations.json');
    final resources = {
      for (final item in await _storageV2.loadResources()) item.id: item,
    };
    final attachmentsByMessageId = <String, List<MessageImage>>{};
    for (final item
        in json['messageAttachments'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final raw = Map<String, dynamic>.from(item);
      final messageId = raw['messageId'] as String?;
      if (messageId == null) continue;
      var path = raw['path'] as String? ?? '';
      final resourceId = raw['resourceId'] as String?;
      final resource = resourceId == null ? null : resources[resourceId];
      if (resource != null) {
        path = await _storageV2.resourcePath(resource) ?? '';
      }
      (attachmentsByMessageId[messageId] ??= []).add(
        MessageImage(
          path: path,
          name:
              raw['displayName'] as String? ?? raw['name'] as String? ?? 'file',
          size: raw['size'] as int? ?? 0,
          mimeType: raw['mimeType'] as String? ?? 'application/octet-stream',
        ),
      );
    }
    final messagesByConversationId = <String, List<_StorageV2MessageRow>>{};
    for (final item in json['messages'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      try {
        final raw = Map<String, dynamic>.from(item);
        final conversationId = raw['conversationId'] as String?;
        if (conversationId == null) continue;
        final messageId = raw['id'] as String;
        final timestamp = DateTime.tryParse(raw['timestamp'] as String? ?? '');
        if (timestamp == null) throw const FormatException('Invalid timestamp');
        (messagesByConversationId[conversationId] ??= []).add(
          _StorageV2MessageRow(
            message: Message(
              id: messageId,
              role: raw['role'] as String,
              content: raw['content'] as String? ?? '',
              images: attachmentsByMessageId[messageId] ?? const [],
              thinkingContent: raw['thinkingContent'] as String?,
              timestamp: timestamp,
            ),
            sortOrder: (raw['sortOrder'] as num?)?.toInt(),
          ),
        );
      } catch (e) {
        debugPrint('跳过损坏的新版消息记录: $e');
      }
    }
    final conversations = <Conversation>[];
    for (final item in json['conversations'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final raw = Map<String, dynamic>.from(item);
      final id = raw['id'] as String;
      final messageRows = List<_StorageV2MessageRow>.from(
        messagesByConversationId[id] ?? const [],
      );
      messageRows.sort((a, b) {
        final orderA = a.sortOrder;
        final orderB = b.sortOrder;
        if (orderA != null && orderB != null) return orderA.compareTo(orderB);
        if (orderA != null) return -1;
        if (orderB != null) return 1;
        return a.message.timestamp.compareTo(b.message.timestamp);
      });
      final messages = messageRows.map((row) => row.message).toList();
      conversations.add(
        Conversation(
          id: id,
          title: raw['title'] as String? ?? '',
          messages: messages,
          modelId: raw['modelId'] as String? ?? '',
          settings: raw['settings'] is Map
              ? ConversationSettings.fromJson(
                  Map<String, dynamic>.from(raw['settings'] as Map),
                  fallbackModelId: raw['modelId'] as String? ?? '',
                )
              : null,
          roleId: raw['roleId'] as String? ?? 'default',
          createdAt: DateTime.parse(raw['createdAt'] as String),
          updatedAt: DateTime.parse(raw['updatedAt'] as String),
        ),
      );
    }
    _usingStorageV2 = true;
    _conversations = conversations
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> _saveStorageV2Conversations(List<Conversation> snapshot) async {
    final conversations = <Map<String, dynamic>>[];
    final messages = <Map<String, dynamic>>[];
    final attachments = <Map<String, dynamic>>[];
    for (final conversation in snapshot) {
      conversations.add({
        'id': conversation.id,
        'title': conversation.title,
        'modelId': conversation.modelId,
        'settings': conversation.settings.toJson(),
        'roleId': conversation.roleId,
        'createdAt': conversation.createdAt.toIso8601String(),
        'updatedAt': conversation.updatedAt.toIso8601String(),
      });
      for (var i = 0; i < conversation.messages.length; i++) {
        final message = conversation.messages[i];
        messages.add({
          'id': message.id,
          'conversationId': conversation.id,
          'role': message.role,
          'content': message.content,
          if (message.thinkingContent != null &&
              message.thinkingContent!.isNotEmpty)
            'thinkingContent': message.thinkingContent,
          'timestamp': message.timestamp.toIso8601String(),
          'sortOrder': i,
        });
        for (var j = 0; j < message.images.length; j++) {
          final image = message.images[j];
          final role = image.isImage ? 'message_image' : 'message_attachment';
          final resource = await _storageV2.importResourceFile(
            image.path,
            originalName: image.name,
            mimeType: image.mimeType,
            role: role,
          );
          attachments.add({
            'id': '${message.id}_attachment_$j',
            'messageId': message.id,
            'resourceId': resource.id,
            'displayName': image.name,
            'mimeType': image.mimeType,
            'size': image.size,
            'sortOrder': j,
          });
        }
      }
    }
    await _storageV2.writeDataFile('conversations.json', {
      'conversations': conversations,
      'messages': messages,
      'messageAttachments': attachments,
    });
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

  /// 向指定对话添加一条消息。
  void addMessage(
    String conversationId,
    String role,
    String content, {
    List<MessageImage> images = const [],
    String? thinkingContent,
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
        timestamp: DateTime.now(),
      );

      final updatedMessages = List<Message>.from(_conversations[index].messages)
        ..add(message);
      final now = DateTime.now();

      String title = _conversations[index].title;
      if (_conversations[index].messages.isEmpty && role == 'user') {
        // 附带附件但没有文字时，用附件名兜底，避免历史列表出现空标题。
        final clean = content.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
        final titleSource = clean.isNotEmpty
            ? clean
            : (images.isNotEmpty ? '[附件] ${images.first.name}' : '新对话');
        title = titleSource.length > 20
            ? '${titleSource.substring(0, 20)}...'
            : titleSource;
      }

      _conversations[index] = Conversation(
        id: _conversations[index].id,
        title: title,
        messages: updatedMessages,
        modelId: _conversations[index].modelId,
        settings: _conversations[index].settings,
        roleId: _conversations[index].roleId,
        createdAt: _conversations[index].createdAt,
        updatedAt: now,
      );

      // 将更新的对话移到列表顶部
      final conv = _conversations.removeAt(index);
      _conversations.insert(0, conv);

      _queueSaveConversations();
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
      roleId: _conversations[index].roleId,
      createdAt: _conversations[index].createdAt,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index, _conversations[index]);
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
      settings: _conversations[index].settings.copyWith(modelId: modelId),
      roleId: _conversations[index].roleId,
      createdAt: _conversations[index].createdAt,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index, _conversations[index]);
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
        timestamp: lastMsg.timestamp,
      );

      _conversations[index] = Conversation(
        id: _conversations[index].id,
        title: _conversations[index].title,
        messages: messages,
        modelId: _conversations[index].modelId,
        settings: _conversations[index].settings,
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
      roleId: _conversations[index].roleId,
      createdAt: _conversations[index].createdAt,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index, _conversations[index]);
    _queueSaveConversations();
    notifyListeners();
  }

  /// 删除对话
  void deleteConversation(String conversationId) {
    final before = _conversations.length;
    _conversations.removeWhere((c) => c.id == conversationId);
    if (_conversations.length == before) return;
    _queueSaveConversations();
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
      roleId: _conversations[index].roleId,
      createdAt: _conversations[index].createdAt,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index, _conversations[index]);
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
      timestamp: old.timestamp,
    );
    _conversations[index] = Conversation(
      id: _conversations[index].id,
      title: _conversations[index].title,
      messages: messages,
      modelId: _conversations[index].modelId,
      settings: _conversations[index].settings,
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
      timestamp: old.timestamp,
    );
    _conversations[index] = Conversation(
      id: _conversations[index].id,
      title: _conversations[index].title,
      messages: messages,
      modelId: _conversations[index].modelId,
      settings: _conversations[index].settings,
      roleId: _conversations[index].roleId,
      createdAt: _conversations[index].createdAt,
      updatedAt: DateTime.now(),
    );
    _touchConversation(index, _conversations[index]);
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

class _StorageV2MessageRow {
  final Message message;
  final int? sortOrder;

  const _StorageV2MessageRow({required this.message, required this.sortOrder});
}
