import '../models/conversation.dart';
import '../models/message.dart';
import '../providers/model_config_provider.dart';
import 'agent_resource_service.dart';
import 'storage_v2_service.dart';

typedef ConversationLookup =
    Future<Conversation?> Function(String conversationId);

/// Resolves persisted message attachments by stable conversation/message IDs
/// and attachment index. Callers never provide or receive filesystem paths.
class AttachmentReadService {
  AttachmentReadService({
    required StorageV2Service storage,
    required ConversationLookup findConversation,
    AgentResourceService? resources,
  }) : _storage = storage,
       _findConversation = findConversation,
       _resources = resources;

  final StorageV2Service _storage;
  final ConversationLookup _findConversation;
  final AgentResourceService? _resources;

  Future<AgentResourceMetadata> metadata({
    required String conversationId,
    required String messageId,
    required int attachmentIndex,
  }) async {
    final attachment = await _resolve(
      conversationId: conversationId,
      messageId: messageId,
      attachmentIndex: attachmentIndex,
    );
    final resources = _resourcesFor(conversationId);
    try {
      return await resources.metadata(attachment.resource.id);
    } finally {
      if (_resources == null) resources.dispose();
    }
  }

  Future<AgentResourceText> readText({
    required String conversationId,
    required String messageId,
    required int attachmentIndex,
    int maxBytes = AgentResourceService.maxReadBytes,
    int maxChars = AgentResourceService.maxReadChars,
  }) async {
    final attachment = await _resolve(
      conversationId: conversationId,
      messageId: messageId,
      attachmentIndex: attachmentIndex,
    );
    final resources = _resourcesFor(conversationId);
    try {
      return await resources.readText(
        attachment.resource.id,
        maxBytes: maxBytes,
        maxChars: maxChars,
      );
    } finally {
      if (_resources == null) resources.dispose();
    }
  }

  Future<AgentResourceText> recognizeImageText({
    required String conversationId,
    required String messageId,
    required int attachmentIndex,
    required ModelConfigProvider modelConfigs,
    required String? modelId,
    int maxBytes = AgentResourceService.maxReadBytes,
    int maxChars = AgentResourceService.maxReadChars,
  }) async {
    final attachment = await _resolve(
      conversationId: conversationId,
      messageId: messageId,
      attachmentIndex: attachmentIndex,
    );
    final resources = _resourcesFor(conversationId);
    try {
      return await resources.recognizeImageText(
        attachment.resource.id,
        modelConfigs: modelConfigs,
        modelId: modelId,
        maxBytes: maxBytes,
        maxChars: maxChars,
      );
    } finally {
      if (_resources == null) resources.dispose();
    }
  }

  Future<AgentResourceText> recognizeFileText({
    required String conversationId,
    required String messageId,
    required int attachmentIndex,
    required ModelConfigProvider modelConfigs,
    required String? modelId,
    required String prompt,
    int maxBytes = AgentResourceService.maxReadBytes,
    int maxChars = AgentResourceService.maxReadChars,
  }) async {
    final attachment = await _resolve(
      conversationId: conversationId,
      messageId: messageId,
      attachmentIndex: attachmentIndex,
    );
    final resources = _resourcesFor(conversationId);
    try {
      return await resources.recognizeFileText(
        attachment.resource.id,
        modelConfigs: modelConfigs,
        modelId: modelId,
        prompt: prompt,
        maxBytes: maxBytes,
        maxChars: maxChars,
      );
    } finally {
      if (_resources == null) resources.dispose();
    }
  }

  Future<_ResolvedAttachment> _resolve({
    required String conversationId,
    required String messageId,
    required int attachmentIndex,
  }) async {
    if (conversationId.trim().isEmpty || messageId.trim().isEmpty) {
      throw const AgentResourceException(
        'invalid_id',
        'Conversation and message IDs must not be empty',
      );
    }
    final conversation = await _findConversation(conversationId);
    if (conversation == null || conversation.id != conversationId) {
      throw const AgentResourceException(
        'conversation_not_found',
        'Conversation was not found',
      );
    }
    Message? message;
    for (final candidate in conversation.messages) {
      if (candidate.id == messageId) {
        message = candidate;
        break;
      }
    }
    if (message == null) {
      throw const AgentResourceException(
        'message_not_found',
        'Message was not found in the conversation',
      );
    }
    if (message.role != 'user' && message.role != 'assistant') {
      throw const AgentResourceException(
        'forbidden_message_role',
        'Message role does not allow attachment reading',
      );
    }
    if (attachmentIndex < 0 || attachmentIndex >= message.images.length) {
      throw const AgentResourceException(
        'attachment_not_found',
        'Attachment index is out of range',
      );
    }
    final image = message.images[attachmentIndex];
    final resource = image.path.isEmpty
        ? null
        : await _storage.findResourceByPath(image.path);
    if (resource == null) {
      throw const AgentResourceException(
        'resource_not_found',
        'Attachment resource was not found',
      );
    }
    final expectedRole = image.isImage ? 'message_image' : 'message_attachment';
    if (resource.role != expectedRole) {
      throw const AgentResourceException(
        'role_mismatch',
        'Attachment and resource roles do not match',
      );
    }
    if (_normalizedMime(image.mimeType) != _normalizedMime(resource.mimeType)) {
      throw const AgentResourceException(
        'mime_mismatch',
        'Attachment and resource MIME types do not match',
      );
    }
    return _ResolvedAttachment(resource);
  }

  AgentResourceService _resourcesFor(String conversationId) =>
      _resources ??
      AgentResourceService(
        storage: _storage,
        conversationId: conversationId,
        findConversation: _findConversation,
      );

  String _normalizedMime(String mimeType) {
    return mimeType.split(';').first.trim().toLowerCase();
  }
}

class _ResolvedAttachment {
  final StorageV2Resource resource;

  const _ResolvedAttachment(this.resource);
}
