import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'agent_cancellation.dart';
import 'agent_tool_execution_service.dart';
import '../models/agent_runtime.dart';
import 'storage_v2_service.dart';

class AgentToolResultSanitizerLimits {
  final int maxDepth;
  final int maxEntries;
  final int maxStringChars;
  final int maxInlineBytes;
  final int maxOffloadBytes;
  final int previewChars;
  final int binaryDetectionBytes;

  const AgentToolResultSanitizerLimits({
    this.maxDepth = 12,
    this.maxEntries = 2000,
    this.maxStringChars = 100000,
    this.maxInlineBytes = 32 * 1024,
    this.maxOffloadBytes = 8 * 1024 * 1024,
    this.previewChars = 2000,
    this.binaryDetectionBytes = 2 * 1024 * 1024,
  });
}

class AgentToolResultResource {
  final String id;
  final String mimeType;
  final int size;
  final String role;

  const AgentToolResultResource({
    required this.id,
    required this.mimeType,
    required this.size,
    required this.role,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'mimeType': mimeType,
    'size': size,
    'role': role,
  };
}

class AgentToolResultSanitization {
  final Object? value;
  final List<AgentToolResultResource> resources;

  const AgentToolResultSanitization({
    required this.value,
    required this.resources,
  });
}

class AgentToolResultStoredResource {
  final AgentToolResultResource resource;
  final bool created;

  const AgentToolResultStoredResource(this.resource, {required this.created});
}

abstract interface class AgentToolResultResourceStore {
  Future<AgentToolResultStoredResource> store({
    required Uint8List bytes,
    required String mimeType,
    required String name,
  });

  Future<void> discard(AgentToolResultStoredResource stored);
}

class StorageV2AgentToolResultResourceStore
    implements AgentToolResultResourceStore {
  final StorageV2Service storage;

  const StorageV2AgentToolResultResourceStore(this.storage);

  static const role = 'agent_tool_result_local';

  @override
  Future<AgentToolResultStoredResource> store({
    required Uint8List bytes,
    required String mimeType,
    required String name,
  }) async {
    final hash = sha256.convert(bytes).toString();
    final id = 'agent_result_${hash.substring(0, 32)}';
    final existing = await storage.findResourceById(id);
    if (existing != null &&
        !existing.missing &&
        existing.sha256Hash == hash &&
        existing.size == bytes.length &&
        await storage.hasResourceBlob(hash)) {
      return AgentToolResultStoredResource(_metadata(existing), created: false);
    }

    final blobExisted = await storage.hasResourceBlob(hash);
    await storage.installResourceBlob(hash, bytes);
    final location = storageV2ResourceLocation(
      sha256Hash: hash,
      originalName: name,
      mimeType: mimeType,
      role: role,
    );
    final resource = StorageV2Resource(
      id: id,
      kind: location.kind,
      role: role,
      originalPath: '',
      originalName: name,
      relativePath: location.relativePath,
      mimeType: mimeType,
      size: bytes.length,
      sha256Hash: hash,
      missing: false,
    );
    try {
      await (await storage.storageDatabase()).upsertResourceRow(
        resource.toJson(),
      );
    } catch (_) {
      if (!blobExisted) await storage.deleteFile(location.relativePath);
      rethrow;
    }
    return AgentToolResultStoredResource(_metadata(resource), created: true);
  }

  @override
  Future<void> discard(AgentToolResultStoredResource stored) async {
    if (!stored.created) return;
    final resource = await storage.findResourceById(stored.resource.id);
    if (resource == null || resource.role != role) return;
    await (await storage.storageDatabase()).deleteResourceRow(resource.id);
    final hash = resource.sha256Hash;
    if (hash == null) return;
    final stillReferenced = (await storage.loadResources()).any(
      (candidate) => candidate.sha256Hash == hash,
    );
    if (!stillReferenced && resource.relativePath != null) {
      await storage.deleteFile(resource.relativePath!);
    }
  }

  static AgentToolResultResource _metadata(StorageV2Resource resource) {
    return AgentToolResultResource(
      id: resource.id,
      mimeType: resource.mimeType,
      size: resource.size,
      role: resource.role,
    );
  }
}

/// Produces JSON-safe, bounded tool results for persistence and model context.
class AgentToolResultSanitizer {
  AgentToolResultSanitizer({
    required AgentToolResultResourceStore resourceStore,
    this.limits = const AgentToolResultSanitizerLimits(),
  }) : _resourceStore = resourceStore;

  factory AgentToolResultSanitizer.storageV2(
    StorageV2Service storage, {
    AgentToolResultSanitizerLimits limits =
        const AgentToolResultSanitizerLimits(),
  }) {
    return AgentToolResultSanitizer(
      resourceStore: StorageV2AgentToolResultResourceStore(storage),
      limits: limits,
    );
  }

  final AgentToolResultResourceStore _resourceStore;
  final AgentToolResultSanitizerLimits limits;

  Future<AgentToolResultSanitization> sanitize(
    Object? result, {
    AgentCancellationToken? cancellationToken,
  }) async {
    _validateLimits();
    final state = _SanitizationState(cancellationToken, limits.maxEntries);
    try {
      var value = await _sanitizeValue(result, state, 0, key: null);
      state.checkCancellation();
      final encoded = _jsonBytes(value);
      if (encoded.length > limits.maxInlineBytes) {
        final bounded = _boundedBytes(encoded);
        final stored = await _store(
          bounded.bytes,
          mimeType: 'application/json',
          name: 'tool-result.json',
          state: state,
        );
        value = _offloadedValue(
          _preview(utf8.decode(bounded.bytes, allowMalformed: true)),
          stored.resource,
          truncated: bounded.truncated,
        );
      }
      state.checkCancellation();
      return AgentToolResultSanitization(
        value: value,
        resources: List.unmodifiable(state.stored.map((item) => item.resource)),
      );
    } catch (_) {
      await _discardCreated(state.stored);
      rethrow;
    }
  }

  Future<Object?> _sanitizeValue(
    Object? value,
    _SanitizationState state,
    int depth, {
    required String? key,
  }) async {
    state.checkCancellation();
    if (key != null && _isCredentialKey(key)) return '[REDACTED]';
    if (value == null || value is bool || value is int) return value;
    if (value is double) return value.isFinite ? value : value.toString();
    if (value is num) return value.isFinite ? value : value.toString();
    if (value is Uint8List) return _offloadBinary(value, state);
    if (value is String) return _sanitizeString(value, state);
    if (depth >= limits.maxDepth) return '[TRUNCATED: depth limit]';

    if (value is Map) {
      if (!state.enter(value)) return '[REDACTED: cyclic value]';
      try {
        final output = <String, dynamic>{};
        for (final entry in value.entries) {
          state.checkCancellation();
          if (!state.takeEntry()) {
            output['_truncated'] = 'entry limit';
            break;
          }
          final safeKey = _sanitizeKey(entry.key);
          output[safeKey] = await _sanitizeValue(
            entry.value,
            state,
            depth + 1,
            key: safeKey,
          );
        }
        return output;
      } finally {
        state.leave(value);
      }
    }

    if (value is Iterable) {
      if (!state.enter(value)) return '[REDACTED: cyclic value]';
      try {
        final binary = _binaryIterable(value);
        if (binary != null) return _offloadBinary(binary, state);
        final output = <Object?>[];
        for (final item in value) {
          state.checkCancellation();
          if (!state.takeEntry()) {
            output.add('[TRUNCATED: entry limit]');
            break;
          }
          output.add(await _sanitizeValue(item, state, depth + 1, key: null));
        }
        return output;
      } finally {
        state.leave(value);
      }
    }

    return '[UNSUPPORTED: ${value.runtimeType}]';
  }

  Future<Object> _sanitizeString(String value, _SanitizationState state) async {
    final compact = value.trim();
    if (compact.length > limits.binaryDetectionBytes &&
        _looksLikeBase64(compact)) {
      return '[OMITTED: base64 candidate exceeds detection limit]';
    }
    final binary = _decodeBase64(compact);
    if (binary != null) return _offloadBinary(binary, state);
    final redacted = _redactPaths(value);
    final stringTruncated = redacted.length > limits.maxStringChars;
    final boundedText = stringTruncated
        ? redacted.substring(0, limits.maxStringChars)
        : redacted;
    final bytes = utf8.encode(boundedText);
    if (bytes.length > limits.maxInlineBytes) {
      final bounded = _boundedBytes(Uint8List.fromList(bytes));
      final stored = await _store(
        bounded.bytes,
        mimeType: 'text/plain; charset=utf-8',
        name: 'tool-result.txt',
        state: state,
      );
      return _offloadedValue(
        _preview(boundedText),
        stored.resource,
        truncated: bounded.truncated || stringTruncated,
      );
    }
    return stringTruncated ? '$boundedText[TRUNCATED]' : boundedText;
  }

  Future<Object> _offloadBinary(
    Uint8List bytes,
    _SanitizationState state,
  ) async {
    final bounded = _boundedBytes(bytes);
    final mimeType = _binaryMimeType(bounded.bytes);
    final stored = await _store(
      bounded.bytes,
      mimeType: mimeType,
      name: _binaryName(mimeType),
      state: state,
    );
    return _offloadedValue(
      '[binary content omitted]',
      stored.resource,
      truncated: bounded.truncated,
    );
  }

  Future<AgentToolResultStoredResource> _store(
    Uint8List bytes, {
    required String mimeType,
    required String name,
    required _SanitizationState state,
  }) async {
    state.checkCancellation();
    final stored = await _resourceStore.store(
      bytes: bytes,
      mimeType: mimeType,
      name: name,
    );
    state.stored.add(stored);
    state.checkCancellation();
    return stored;
  }

  Map<String, dynamic> _offloadedValue(
    String preview,
    AgentToolResultResource resource, {
    required bool truncated,
  }) {
    return {
      'preview': preview,
      'offloaded': true,
      'truncated': truncated,
      'resource': resource.toJson(),
    };
  }

  Uint8List? _binaryIterable(Iterable<Object?> value) {
    if (value is! List || value.length < 32) return null;
    if (value.length > limits.maxOffloadBytes) return null;
    final bytes = Uint8List(value.length);
    for (var i = 0; i < value.length; i++) {
      final item = value[i];
      if (item is! int || item < 0 || item > 255) return null;
      bytes[i] = item;
    }
    return bytes;
  }

  Uint8List? _decodeBase64(String value) {
    final compact = value.trim();
    if (compact.length < 128 || compact.length > limits.binaryDetectionBytes) {
      return null;
    }
    if (compact.length % 4 != 0 ||
        !RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(compact)) {
      return null;
    }
    try {
      final decoded = base64.decode(compact);
      if (decoded.length < 32 || base64.encode(decoded) != compact) return null;
      return Uint8List.fromList(decoded);
    } on FormatException {
      return null;
    }
  }

  bool _looksLikeBase64(String value) {
    if (value.length < 128 || value.length % 4 != 0) return false;
    final sampleLength = value.length < 4096 ? value.length : 4096;
    for (var i = 0; i < sampleLength; i++) {
      final code = value.codeUnitAt(i);
      final allowed =
          (code >= 0x41 && code <= 0x5a) ||
          (code >= 0x61 && code <= 0x7a) ||
          (code >= 0x30 && code <= 0x39) ||
          code == 0x2b ||
          code == 0x2f;
      if (!allowed) return false;
    }
    return true;
  }

  String _sanitizeKey(Object? key) {
    final raw = key is String ? key : '[${key.runtimeType}]';
    final redacted = _redactPaths(raw);
    return redacted.length <= 200 ? redacted : redacted.substring(0, 200);
  }

  String _redactPaths(String value) {
    var output = value.replaceAll(
      RegExp(r'(?<![:/A-Za-z0-9])(?:/[A-Za-z0-9._~ -]+)+'),
      '[REDACTED_PATH]',
    );
    output = output.replaceAll(
      RegExp(
        r'(?<![A-Za-z0-9])[A-Z]:\\(?:[^\\\r\n]+\\)*[^\\\r\n]*',
        caseSensitive: false,
      ),
      '[REDACTED_PATH]',
    );
    return output.replaceAll(
      RegExp(r'\\\\[^\\\r\n]+\\[^\r\n]+'),
      '[REDACTED_PATH]',
    );
  }

  bool _isCredentialKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized.contains('password') ||
        normalized.contains('passwd') ||
        normalized.contains('secret') ||
        normalized.contains('apikey') ||
        normalized.contains('accesstoken') ||
        normalized.contains('refreshtoken') ||
        normalized == 'token' ||
        normalized == 'authorization' ||
        normalized == 'cookie' ||
        normalized == 'setcookie' ||
        normalized == 'privatekey';
  }

  Uint8List _jsonBytes(Object? value) {
    return Uint8List.fromList(utf8.encode(jsonEncode(value)));
  }

  _BoundedResult _boundedBytes(Uint8List bytes) {
    if (bytes.length <= limits.maxOffloadBytes) {
      return _BoundedResult(bytes, truncated: false);
    }
    return _BoundedResult(
      Uint8List.sublistView(bytes, 0, limits.maxOffloadBytes),
      truncated: true,
    );
  }

  String _preview(String value) {
    final redacted = _redactPaths(value);
    if (redacted.length <= limits.previewChars) return redacted;
    return '${redacted.substring(0, limits.previewChars)}[TRUNCATED]';
  }

  String _binaryMimeType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return 'application/pdf';
    }
    return 'application/octet-stream';
  }

  String _binaryName(String mimeType) => switch (mimeType) {
    'image/png' => 'tool-result.png',
    'image/jpeg' => 'tool-result.jpg',
    'application/pdf' => 'tool-result.pdf',
    _ => 'tool-result.bin',
  };

  Future<void> _discardCreated(
    List<AgentToolResultStoredResource> resources,
  ) async {
    for (final resource in resources.reversed) {
      try {
        await _resourceStore.discard(resource);
      } catch (_) {
        // Preserve the original sanitization or cancellation error.
      }
    }
  }

  void _validateLimits() {
    if (limits.maxDepth <= 0 ||
        limits.maxEntries <= 0 ||
        limits.maxStringChars <= 0 ||
        limits.maxInlineBytes <= 0 ||
        limits.maxOffloadBytes < limits.maxInlineBytes ||
        limits.previewChars <= 0 ||
        limits.binaryDetectionBytes <= 0) {
      throw ArgumentError('Agent tool-result sanitizer limits are invalid');
    }
  }
}

class SanitizingAgentToolResultProcessor implements AgentToolResultProcessor {
  const SanitizingAgentToolResultProcessor(this.sanitizer);

  final AgentToolResultSanitizer sanitizer;

  @override
  Future<List<AgentToolResult>> process(
    List<AgentToolResult> results, {
    required AgentCancellationToken cancellationToken,
  }) async {
    final processed = <AgentToolResult>[];
    for (final result in results) {
      if (result.status == AgentToolResultStatus.cancelled) {
        processed.add(result);
        continue;
      }
      final sanitization = await sanitizer.sanitize(
        result.value,
        cancellationToken: cancellationToken,
      );
      processed.add(
        result.isSuccess
            ? AgentToolResult.success(
                invocationId: result.invocationId,
                toolName: result.toolName,
                value: sanitization.value,
              )
            : AgentToolResult.failure(
                invocationId: result.invocationId,
                toolName: result.toolName,
                code: result.errorCode ?? 'tool_execution_failed',
                message: result.errorMessage ?? 'Tool execution failed',
                value: sanitization.value,
              ),
      );
    }
    return List.unmodifiable(processed);
  }
}

class _SanitizationState {
  final AgentCancellationToken? cancellationToken;
  final int maxEntries;
  final Set<Object> active = Set<Object>.identity();
  final List<AgentToolResultStoredResource> stored = [];
  int entries = 0;

  _SanitizationState(this.cancellationToken, this.maxEntries);

  bool takeEntry() {
    entries++;
    return entries <= maxEntries;
  }

  bool enter(Object value) => active.add(value);

  void leave(Object value) => active.remove(value);

  void checkCancellation() => cancellationToken?.throwIfCancellationRequested();
}

class _BoundedResult {
  final Uint8List bytes;
  final bool truncated;

  const _BoundedResult(this.bytes, {required this.truncated});
}
