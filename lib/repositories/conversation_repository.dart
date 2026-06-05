import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../services/storage_v2_service.dart';
import 'app_storage_state.dart';

/// 对话加载结果，包含对话列表与存储版本标识。
class ConversationLoadResult {
  const ConversationLoadResult({
    required this.conversations,
    required this.usingStorageV2,
  });

  final List<Conversation> conversations;
  final bool usingStorageV2;
}

/// 对话数据仓储，负责加载和持久化用户对话记录。
///
/// 支持旧版 SharedPreferences 存储与新版存储 V2 两种模式，
/// 根据当前存储状态自动选择读写路径。
class ConversationRepository {
  factory ConversationRepository({
    StorageV2Service? storageV2,
    AppStorageStateRepository? storageState,
  }) {
    final storage = storageV2 ?? StorageV2Service();
    return ConversationRepository._(
      storage,
      storageState ?? AppStorageStateRepository(storageV2: storage),
    );
  }

  ConversationRepository._(this._storageV2, this._storageState);

  static const _storageKey = 'conversations';

  final StorageV2Service _storageV2;
  final AppStorageStateRepository _storageState;

  /// 加载所有对话记录，按更新时间降序排列。
  ///
  /// 根据当前存储状态选择新版 V2 存储或旧版 SharedPreferences 进行读取。
  Future<ConversationLoadResult> load() async {
    final usingStorageV2 = await _storageState.isStorageV2Active();
    if (usingStorageV2) {
      final conversations = await _loadStorageV2Conversations();
      conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return ConversationLoadResult(
        conversations: conversations,
        usingStorageV2: true,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    if (jsonString == null) {
      return const ConversationLoadResult(
        conversations: [],
        usingStorageV2: false,
      );
    }
    List<dynamic> items;
    try {
      items = jsonDecode(jsonString) as List<dynamic>;
    } catch (e) {
      debugPrint('解析对话数据失败: $e');
      return const ConversationLoadResult(
        conversations: [],
        usingStorageV2: false,
      );
    }
    final conversations = <Conversation>[];
    for (final item in items) {
      try {
        conversations.add(Conversation.fromJson(item as Map<String, dynamic>));
      } catch (e) {
        debugPrint('跳过损坏的对话记录: $e');
      }
    }
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return ConversationLoadResult(
      conversations: conversations,
      usingStorageV2: false,
    );
  }

  /// 保存对话列表到当前激活的存储后端。
  Future<void> save(
    List<Conversation> conversations, {
    required bool usingStorageV2,
  }) async {
    if (usingStorageV2 || await _isStorageV2Active()) {
      await _saveStorageV2Conversations(conversations);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final payload = conversations.map((item) => item.toJson()).toList();
    final encoded = kIsWeb
        ? _encodeJson(payload)
        : await Isolate.run(() => _encodeJson(payload));
    await prefs.setString(_storageKey, encoded);
  }

  Future<List<Conversation>> _loadStorageV2Conversations() async {
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
      conversations.add(
        Conversation(
          id: id,
          title: raw['title'] as String? ?? '',
          messages: messageRows.map((row) => row.message).toList(),
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
    return conversations;
  }

  Future<bool> _isStorageV2Active() async {
    try {
      return await _storageState.isStorageV2Active();
    } catch (_) {
      return false;
    }
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
          final resource = await _storageV2.importResourceFile(
            image.path,
            originalName: image.name,
            mimeType: image.mimeType,
            role: image.isImage ? 'message_image' : 'message_attachment',
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
}

String _encodeJson(Object? value) => jsonEncode(value);

class _StorageV2MessageRow {
  const _StorageV2MessageRow({required this.message, required this.sortOrder});

  final Message message;
  final int? sortOrder;
}
