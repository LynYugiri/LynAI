import 'package:flutter/foundation.dart';

import '../models/agent_trace.dart';
import '../models/agent_plan.dart';
import '../models/agent_working_memory.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/storage_v2_service.dart';

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
class ConversationRepository {
  factory ConversationRepository({StorageV2Service? storageV2}) {
    final storage = storageV2 ?? StorageV2Service();
    return ConversationRepository._(storage);
  }

  ConversationRepository._(this._storageV2);

  final StorageV2Service _storageV2;

  /// 加载所有对话记录，按更新时间降序排列。
  Future<ConversationLoadResult> load() async {
    final conversations = await _loadStorageV2Conversations();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return ConversationLoadResult(
      conversations: conversations,
      usingStorageV2: true,
    );
  }

  /// 保存对话列表到当前激活的存储后端。
  Future<void> save(
    List<Conversation> conversations, {
    required bool usingStorageV2,
  }) async {
    await _saveStorageV2Conversations(conversations);
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
          size: (raw['size'] as num?)?.toInt() ?? 0,
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
              agentTrace: raw['agentTrace'] is Map
                  ? AgentTrace.fromJson(
                      Map<String, dynamic>.from(raw['agentTrace'] as Map),
                    )
                  : null,
              timestamp: timestamp,
              revision: (raw['revision'] as num?)?.toInt() ?? 1,
              updatedAt:
                  DateTime.tryParse(raw['updatedAt']?.toString() ?? '') ??
                  timestamp,
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
      try {
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
            agentPlan: _parseAgentPlan(raw['agentPlan']),
            agentWorkingMemory: _parseAgentWorkingMemory(
              raw['agentWorkingMemory'],
            ),
            roleId: raw['roleId'] as String? ?? 'default',
            createdAt: DateTime.parse(raw['createdAt'] as String),
            updatedAt: DateTime.parse(raw['updatedAt'] as String),
          ),
        );
      } catch (e) {
        debugPrint('跳过损坏的新版对话记录: $e');
      }
    }
    return conversations;
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
        if (conversation.agentPlan != null)
          'agentPlan': conversation.agentPlan!.toJson(),
        if (conversation.agentWorkingMemory != null &&
            !conversation.agentWorkingMemory!.isEmpty)
          'agentWorkingMemory': conversation.agentWorkingMemory!.toJson(),
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
          if (message.agentTrace != null &&
              message.agentTrace!.events.isNotEmpty)
            'agentTrace': message.agentTrace!.toJson(),
          'timestamp': message.timestamp.toIso8601String(),
          'revision': message.revision,
          'updatedAt': message.updatedAt.toIso8601String(),
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

  AgentPlan? _parseAgentPlan(Object? raw) {
    if (raw is! Map) return null;
    try {
      final parsed = AgentPlan.fromJson(Map<String, dynamic>.from(raw));
      return parsed.id.isNotEmpty && parsed.items.isNotEmpty ? parsed : null;
    } catch (e) {
      debugPrint('跳过损坏的 Agent 计划: $e');
      return null;
    }
  }

  AgentWorkingMemory? _parseAgentWorkingMemory(Object? raw) {
    if (raw is! Map) return null;
    try {
      final parsed = AgentWorkingMemory.fromJson(
        Map<String, dynamic>.from(raw),
      );
      return parsed.isEmpty ? null : parsed;
    } catch (e) {
      debugPrint('跳过损坏的 Agent 工作记忆: $e');
      return null;
    }
  }
}

class _StorageV2MessageRow {
  const _StorageV2MessageRow({required this.message, required this.sortOrder});

  final Message message;
  final int? sortOrder;
}
