import 'dart:convert';
import 'dart:typed_data';

import '../providers/model_config_provider.dart';
import '../models/conversation.dart';
import 'model_recognition_service.dart';
import 'storage_v2_service.dart';

class AgentResourceMetadata {
  final String id;
  final String name;
  final String mimeType;
  final int size;
  final String role;
  final bool missing;

  const AgentResourceMetadata({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.role,
    required this.missing,
  });
}

class AgentResourceText {
  final AgentResourceMetadata metadata;
  final String text;
  final bool truncated;

  const AgentResourceText({
    required this.metadata,
    required this.text,
    required this.truncated,
  });
}

class AgentResourceException implements Exception {
  final String code;
  final String message;

  const AgentResourceException(this.code, this.message);

  @override
  String toString() => 'AgentResourceException($code): $message';
}

/// Safe, bounded access to agent-readable resources by stable resource ID.
class AgentResourceService {
  AgentResourceService({
    required StorageV2Service storage,
    required String conversationId,
    required Future<Conversation?> Function(String id) findConversation,
    ModelRecognitionService? recognition,
  }) : _storage = storage,
       _conversationId = conversationId,
       _findConversation = findConversation,
       _recognition = recognition ?? ModelRecognitionService(),
       _ownsRecognition = recognition == null;

  static const int maxReadBytes = 1024 * 1024;
  static const int maxReadChars = 100000;
  static const int maxSearchResults = 50;
  static const int maxSearchScan = 1000;
  static const Set<String> readableRoles = {
    'message_attachment',
    'message_image',
  };

  static const Set<String> _textApplicationMimeTypes = {
    'application/json',
    'application/ld+json',
    'application/xml',
    'application/yaml',
    'application/x-yaml',
    'application/javascript',
  };
  static const Set<String> _modelFileMimeTypes = {
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };

  final StorageV2Service _storage;
  final String _conversationId;
  final Future<Conversation?> Function(String id) _findConversation;
  final ModelRecognitionService _recognition;
  final bool _ownsRecognition;

  void dispose() {
    if (_ownsRecognition) _recognition.dispose();
  }

  Future<AgentResourceMetadata> metadata(String resourceId) async {
    return _metadata(await _resolveMetadata(resourceId));
  }

  Future<AgentResourceText> readText(
    String resourceId, {
    int maxBytes = maxReadBytes,
    int maxChars = maxReadChars,
  }) async {
    _validateLimits(maxBytes, maxChars);
    final resource = await _resolve(resourceId);
    if (!_isTextMime(resource.mimeType)) {
      throw AgentResourceException(
        'unsupported_mime',
        'Resource MIME type is not readable as text: ${resource.mimeType}',
      );
    }
    final bytes = await _readBoundedBytes(resource, maxBytes: maxBytes);
    final decoded = utf8.decode(bytes.bytes, allowMalformed: true);
    final charTruncated = decoded.length > maxChars;
    return AgentResourceText(
      metadata: _metadata(resource),
      text: charTruncated ? decoded.substring(0, maxChars) : decoded,
      truncated: bytes.truncated || charTruncated,
    );
  }

  Future<AgentResourceText> recognizeImageText(
    String resourceId, {
    required ModelConfigProvider modelConfigs,
    required String? modelId,
    int maxBytes = maxReadBytes,
    int maxChars = maxReadChars,
  }) async {
    _validateLimits(maxBytes, maxChars);
    final resource = await _resolve(resourceId);
    if (!_normalizedMime(resource.mimeType).startsWith('image/')) {
      throw AgentResourceException(
        'unsupported_mime',
        'Resource MIME type is not an image: ${resource.mimeType}',
      );
    }
    final bytes = await _readCompleteBytes(resource, maxBytes: maxBytes);
    final text = await _recognition.recognizeImagesWithOcr(
      modelConfigs: modelConfigs,
      modelId: modelId,
      files: [_recognitionInput(resource, bytes)],
    );
    return _boundedRecognition(resource, text, maxChars);
  }

  Future<AgentResourceText> recognizeFileText(
    String resourceId, {
    required ModelConfigProvider modelConfigs,
    required String? modelId,
    required String prompt,
    int maxBytes = maxReadBytes,
    int maxChars = maxReadChars,
  }) async {
    _validateLimits(maxBytes, maxChars);
    final resource = await _resolve(resourceId);
    final mime = _normalizedMime(resource.mimeType);
    if (!_modelFileMimeTypes.contains(mime)) {
      throw AgentResourceException(
        'unsupported_mime',
        'Resource MIME type is not supported for model reading: ${resource.mimeType}',
      );
    }
    final bytes = await _readCompleteBytes(resource, maxBytes: maxBytes);
    final text = await _recognition.recognizeFilesWithModel(
      modelConfigs: modelConfigs,
      modelId: modelId,
      prompt: prompt,
      files: [_recognitionInput(resource, bytes)],
    );
    return _boundedRecognition(resource, text, maxChars);
  }

  Future<List<AgentResourceMetadata>> search(
    String query, {
    int limit = 20,
  }) async {
    if (limit <= 0 || limit > maxSearchResults) {
      throw RangeError.range(limit, 1, maxSearchResults, 'limit');
    }
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return const [];

    // TODO: Replace this bounded snapshot scan with an indexed storage query if
    // resource volume grows enough to justify a database API/schema change.
    final resources = await _storage.loadResources();
    final ownedIds = await _ownedResourceIds();
    final matches = <AgentResourceMetadata>[];
    for (final resource in resources.take(maxSearchScan)) {
      if (!ownedIds.contains(resource.id) || !_isReadableRole(resource.role)) {
        continue;
      }
      final haystack = '${resource.originalName}\n${resource.mimeType}'
          .toLowerCase();
      if (!haystack.contains(normalizedQuery)) continue;
      matches.add(_metadata(resource));
      if (matches.length == limit) break;
    }
    return matches;
  }

  Future<StorageV2Resource> _resolve(String resourceId) async {
    final resource = await _resolveMetadata(resourceId);
    if (resource.missing || resource.relativePath == null) {
      throw const AgentResourceException(
        'missing',
        'Resource content is not available locally',
      );
    }
    return resource;
  }

  Future<StorageV2Resource> _resolveMetadata(String resourceId) async {
    final id = resourceId.trim();
    if (id.isEmpty) {
      throw const AgentResourceException(
        'invalid_id',
        'Resource ID must not be empty',
      );
    }
    final resource = await _storage.findResourceById(id);
    if (resource == null) {
      throw const AgentResourceException('not_found', 'Resource was not found');
    }
    if (!_isReadableRole(resource.role)) {
      throw const AgentResourceException(
        'forbidden_role',
        'Resource role is not readable by agents',
      );
    }
    if (!await _owns(resource)) {
      throw const AgentResourceException(
        'not_found',
        'Resource was not found in the active conversation',
      );
    }
    return resource;
  }

  Future<bool> _owns(StorageV2Resource resource) async =>
      (await _ownedResourceIds()).contains(resource.id);

  Future<Set<String>> _ownedResourceIds() async {
    final conversation = await _findConversation(_conversationId);
    if (conversation == null || conversation.id != _conversationId) {
      throw const AgentResourceException(
        'conversation_not_found',
        'Active conversation was not found',
      );
    }
    final ids = <String>{};
    for (final message in conversation.messages) {
      if (message.role != 'user' && message.role != 'assistant') continue;
      for (final attachment in message.images) {
        if (attachment.path.isEmpty) continue;
        final resource = await _storage.findResourceByPath(attachment.path);
        if (resource != null) ids.add(resource.id);
      }
    }
    return ids;
  }

  Future<_BoundedBytes> _readBoundedBytes(
    StorageV2Resource resource, {
    required int maxBytes,
  }) async {
    final file = await _storage.resourceFile(resource);
    if (file == null || !await file.exists()) {
      throw const AgentResourceException(
        'missing',
        'Resource content is not available locally',
      );
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, maxBytes + 1)) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.length <= maxBytes) {
      return _BoundedBytes(bytes, false);
    }
    return _BoundedBytes(Uint8List.sublistView(bytes, 0, maxBytes), true);
  }

  Future<Uint8List> _readCompleteBytes(
    StorageV2Resource resource, {
    required int maxBytes,
  }) async {
    if (resource.size > maxBytes) {
      throw AgentResourceException(
        'byte_limit',
        'Resource exceeds the $maxBytes byte recognition limit',
      );
    }
    final result = await _readBoundedBytes(resource, maxBytes: maxBytes);
    if (result.truncated) {
      throw AgentResourceException(
        'byte_limit',
        'Resource exceeds the $maxBytes byte recognition limit',
      );
    }
    return result.bytes;
  }

  AgentResourceText _boundedRecognition(
    StorageV2Resource resource,
    String text,
    int maxChars,
  ) {
    final truncated = text.length > maxChars;
    return AgentResourceText(
      metadata: _metadata(resource),
      text: truncated ? text.substring(0, maxChars) : text,
      truncated: truncated,
    );
  }

  ModelRecognitionFileInput _recognitionInput(
    StorageV2Resource resource,
    Uint8List bytes,
  ) {
    return ModelRecognitionFileInput(
      name: resource.originalName,
      mimeType: resource.mimeType,
      bytes: bytes,
    );
  }

  AgentResourceMetadata _metadata(StorageV2Resource resource) {
    return AgentResourceMetadata(
      id: resource.id,
      name: _displayName(resource.originalName),
      mimeType: resource.mimeType,
      size: resource.size,
      role: resource.role,
      missing: resource.missing,
    );
  }

  void _validateLimits(int maxBytes, int maxChars) {
    if (maxBytes <= 0 || maxBytes > maxReadBytes) {
      throw RangeError.range(maxBytes, 1, maxReadBytes, 'maxBytes');
    }
    if (maxChars <= 0 || maxChars > maxReadChars) {
      throw RangeError.range(maxChars, 1, maxReadChars, 'maxChars');
    }
  }

  bool _isReadableRole(String role) => readableRoles.contains(role);

  bool _isTextMime(String mimeType) {
    final mime = _normalizedMime(mimeType);
    return mime.startsWith('text/') || _textApplicationMimeTypes.contains(mime);
  }

  String _normalizedMime(String mimeType) {
    return mimeType.split(';').first.trim().toLowerCase();
  }

  String _displayName(String name) {
    final normalized = name.replaceAll('\\', '/');
    final lastSegment = normalized.split('/').last.trim();
    return lastSegment.isEmpty ? 'file' : lastSegment;
  }
}

class _BoundedBytes {
  final Uint8List bytes;
  final bool truncated;

  const _BoundedBytes(this.bytes, this.truncated);
}
