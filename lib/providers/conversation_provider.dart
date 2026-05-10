import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/conversation.dart';
import '../models/message.dart';

/// 对话状态管理
///
/// 使用 ChangeNotifier 模式管理所有对话的状态。
/// 负责对话的增删改查、持久化存储、搜索等功能。
/// 通过 Provider 在 Widget 树中共享。
class ConversationProvider extends ChangeNotifier {
  List<Conversation> _conversations = [];
  final _uuid = const Uuid();
  static const _storageKey = 'conversations';

  /// 获取所有对话列表（按更新时间倒序排列）
  List<Conversation> get conversations => List.unmodifiable(_conversations);

  /// 从 SharedPreferences 加载对话数据
  Future<void> loadConversations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
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
        // 按更新时间倒序排列
        _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('加载对话失败: $e');
      // 初始化空列表，避免应用崩溃
      _conversations = [];
    }
  }

  /// 将对话数据保存到 SharedPreferences
  Future<void> _saveConversations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(
        _conversations.map((c) => c.toJson()).toList(),
      );
      await prefs.setString(_storageKey, jsonString);
    } catch (e) {
      debugPrint('保存对话失败: $e');
    }
  }

  /// 创建新对话，返回对话ID
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
      _saveConversations();
      notifyListeners();
      return conversation.id;
    } catch (e) {
      debugPrint('创建对话失败: $e');
      rethrow;
    }
  }

  /// 向指定对话添加消息
  void addMessage(
    String conversationId,
    String role,
    String content, {
    List<MessageImage> images = const [],
  }) {
    try {
      final index = _conversations.indexWhere((c) => c.id == conversationId);
      if (index == -1) return;

      final message = Message(
        id: _uuid.v4(),
        role: role,
        content: content,
        images: images,
        timestamp: DateTime.now(),
      );

      final updatedMessages = List<Message>.from(_conversations[index].messages)
        ..add(message);
      final now = DateTime.now();

      String title = _conversations[index].title;
      if (_conversations[index].messages.isEmpty && role == 'user') {
        // 附带图片但没有文字时，用“[图片]”兜底，避免历史列表出现空标题。
        final clean = content.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
        final titleSource = clean.isNotEmpty
            ? clean
            : (images.isNotEmpty ? '[图片]' : '新对话');
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

      _saveConversations();
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
    _saveConversations();
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
    _saveConversations();
    notifyListeners();
  }

  /// 更新最后一条消息的内容（用于流式响应）
  void updateLastMessage(
    String conversationId,
    String content, {
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

      if (save) _saveConversations();
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

    _saveConversations();
    notifyListeners();
  }

  /// 删除对话
  void deleteConversation(String conversationId) {
    final before = _conversations.length;
    _conversations.removeWhere((c) => c.id == conversationId);
    if (_conversations.length == before) return;
    _saveConversations();
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
    _saveConversations();
    notifyListeners();
  }

  /// 更新指定消息的内容
  void updateMessageContent(
    String conversationId,
    String messageId,
    String content,
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
      content: content,
      images: old.images,
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
    _saveConversations();
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

      // 检查消息内容是否匹配
      for (final msg in conv.messages) {
        if (msg.content.toLowerCase().contains(lowerQuery)) {
          results.add({
            'conversation': conv,
            'matchInTitle': false,
            'matchContent': msg.content,
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
