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
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString != null) {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      _conversations = jsonList
          .map((j) => Conversation.fromJson(j as Map<String, dynamic>))
          .toList();
      // 按更新时间倒序排列
      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      notifyListeners();
    }
  }

  /// 将对话数据保存到 SharedPreferences
  Future<void> _saveConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString =
        jsonEncode(_conversations.map((c) => c.toJson()).toList());
    await prefs.setString(_storageKey, jsonString);
  }

  /// 创建新对话，返回对话ID
  String createConversation(String modelId) {
    final now = DateTime.now();
    final conversation = Conversation(
      id: _uuid.v4(),
      title: '新对话 ${_conversations.length + 1}',
      messages: [],
      modelId: modelId,
      createdAt: now,
      updatedAt: now,
    );
    _conversations.insert(0, conversation);
    _saveConversations();
    notifyListeners();
    return conversation.id;
  }

  /// 向指定对话添加消息
  void addMessage(String conversationId, String role, String content) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;

    final message = Message(
      id: _uuid.v4(),
      role: role,
      content: content,
      timestamp: DateTime.now(),
    );

    final updatedMessages = List<Message>.from(_conversations[index].messages)
      ..add(message);
    final now = DateTime.now();

    // 如果是第一条用户消息，自动用其内容作为对话标题
    String title = _conversations[index].title;
    if (_conversations[index].messages.isEmpty && role == 'user') {
      title = content.length > 20
          ? '${content.substring(0, 20)}...'
          : content;
    }

    _conversations[index] = Conversation(
      id: _conversations[index].id,
      title: title,
      messages: updatedMessages,
      modelId: _conversations[index].modelId,
      createdAt: _conversations[index].createdAt,
      updatedAt: now,
    );

    // 将更新的对话移到列表顶部
    final conv = _conversations.removeAt(index);
    _conversations.insert(0, conv);

    _saveConversations();
    notifyListeners();
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
      createdAt: _conversations[index].createdAt,
      updatedAt: DateTime.now(),
    );
    _saveConversations();
    notifyListeners();
  }

  /// 删除对话
  void deleteConversation(String conversationId) {
    _conversations.removeWhere((c) => c.id == conversationId);
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
}

