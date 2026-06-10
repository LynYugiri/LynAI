import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../models/roleplay.dart';
import '../providers/conversation_provider.dart';
import '../providers/roleplay_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/file_name_utils.dart';
import 'storage_v2_service.dart';

class LegacyResourceMigrationService {
  LegacyResourceMigrationService({Directory? legacyRoot, Directory? targetRoot})
    : _legacyRoot = legacyRoot,
      _targetRoot = targetRoot;

  final Directory? _legacyRoot;
  final Directory? _targetRoot;
  final Map<String, String> _migratedPaths = {};

  Future<int> migrate({
    required SettingsProvider settingsProvider,
    required ConversationProvider conversationProvider,
    required RoleplayProvider roleplayProvider,
  }) async {
    final legacyRoot = _legacyRoot ?? await getApplicationDocumentsDirectory();
    final targetRoot =
        _targetRoot ?? await StorageV2Service.defaultBaseDirectory();
    final legacyRootPath = _normalizePath(legacyRoot.absolute.path);
    final targetRootPath = _normalizePath(targetRoot.absolute.path);
    if (legacyRootPath == targetRootPath) return 0;

    var changed = 0;
    changed += await _migrateSettings(settingsProvider, legacyRoot, targetRoot);
    changed += await _migrateConversations(
      conversationProvider,
      legacyRoot,
      targetRoot,
    );
    changed += await _migrateRoleplay(roleplayProvider, legacyRoot, targetRoot);
    return changed;
  }

  Future<int> _migrateSettings(
    SettingsProvider provider,
    Directory legacyRoot,
    Directory targetRoot,
  ) async {
    final path = provider.settings.backgroundImagePath;
    final migrated = await _migratePath(path, legacyRoot, targetRoot);
    if (migrated == null || migrated == path) return 0;
    await provider.replaceSettings(
      provider.settings.copyWith(backgroundImagePath: migrated),
    );
    return 1;
  }

  Future<int> _migrateConversations(
    ConversationProvider provider,
    Directory legacyRoot,
    Directory targetRoot,
  ) async {
    var changed = 0;
    final conversations = <Conversation>[];
    for (final conversation in provider.conversations) {
      final messages = <Message>[];
      var conversationChanged = false;
      for (final message in conversation.messages) {
        final images = <MessageImage>[];
        var messageChanged = false;
        for (final image in message.images) {
          final migrated = await _migratePath(
            image.path,
            legacyRoot,
            targetRoot,
          );
          if (migrated != null && migrated != image.path) {
            images.add(_copyImageWithPath(image, migrated));
            messageChanged = true;
            changed++;
          } else {
            images.add(image);
          }
        }
        messages.add(
          messageChanged
              ? Message(
                  id: message.id,
                  role: message.role,
                  content: message.content,
                  images: images,
                  thinkingContent: message.thinkingContent,
                  agentTrace: message.agentTrace,
                  timestamp: message.timestamp,
                )
              : message,
        );
        conversationChanged = conversationChanged || messageChanged;
      }
      conversations.add(
        conversationChanged
            ? conversation.copyWith(messages: messages)
            : conversation,
      );
    }
    if (changed > 0) await provider.replaceConversations(conversations);
    return changed;
  }

  Future<int> _migrateRoleplay(
    RoleplayProvider provider,
    Directory legacyRoot,
    Directory targetRoot,
  ) async {
    var changed = 0;
    final threads = <RoleplayThread>[];
    for (final thread in provider.threads) {
      final messages = <RoleplayMessage>[];
      var threadChanged = false;
      for (final message in thread.messages) {
        final attachments = <MessageImage>[];
        var messageChanged = false;
        for (final attachment in message.attachments) {
          final migrated = await _migratePath(
            attachment.path,
            legacyRoot,
            targetRoot,
          );
          if (migrated != null && migrated != attachment.path) {
            attachments.add(_copyImageWithPath(attachment, migrated));
            messageChanged = true;
            changed++;
          } else {
            attachments.add(attachment);
          }
        }
        messages.add(
          messageChanged
              ? RoleplayMessage(
                  id: message.id,
                  speakerId: message.speakerId,
                  speakerName: message.speakerName,
                  content: message.content,
                  kind: message.kind,
                  attachments: attachments,
                  timestamp: message.timestamp,
                )
              : message,
        );
        threadChanged = threadChanged || messageChanged;
      }
      threads.add(threadChanged ? thread.copyWith(messages: messages) : thread);
    }
    if (changed > 0) {
      await provider.replaceData(
        scenarios: provider.scenarios,
        threads: threads,
      );
    }
    return changed;
  }

  Future<String?> _migratePath(
    String? path,
    Directory legacyRoot,
    Directory targetRoot,
  ) async {
    try {
      if (path == null || path.isEmpty) return null;
      final cached = _migratedPaths[path];
      if (cached != null) return cached;

      final source = File(path);
      final sourcePath = _normalizePath(source.absolute.path);
      final legacyRootPath = _normalizePath(legacyRoot.absolute.path);
      final targetRootPath = _normalizePath(targetRoot.absolute.path);
      if (sourcePath == targetRootPath ||
          sourcePath.startsWith('$targetRootPath/')) {
        return path;
      }
      if (sourcePath != legacyRootPath &&
          !sourcePath.startsWith('$legacyRootPath/')) {
        return null;
      }
      if (!await source.exists()) return null;

      final relativePath = sourcePath.substring(legacyRootPath.length + 1);
      final target = await _uniqueTargetFile(targetRoot, relativePath, source);
      final parent = target.parent;
      if (!await parent.exists()) await parent.create(recursive: true);
      if (_normalizePath(target.absolute.path) != sourcePath) {
        await source.copy(target.path);
      }
      _migratedPaths[path] = target.path;
      return target.path;
    } catch (e) {
      debugPrint('迁移旧资源失败: $path, $e');
      return null;
    }
  }

  Future<File> _uniqueTargetFile(
    Directory targetRoot,
    String relativePath,
    File source,
  ) async {
    final sourcePath = _normalizePath(source.absolute.path);
    final safeRelative = _safeRelativePath(relativePath);
    var target = File('${targetRoot.path}/$safeRelative');
    if (!await target.exists()) return target;
    if (_normalizePath(target.absolute.path) == sourcePath ||
        await _sameFileContent(source, target)) {
      return target;
    }

    final directory = target.parent.path;
    final name = target.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final base = dot <= 0 ? name : name.substring(0, dot);
    final extension = dot <= 0 ? '' : name.substring(dot);
    var suffix = 1;
    while (await target.exists()) {
      if (await _sameFileContent(source, target)) return target;
      target = File('$directory/${base}_$suffix$extension');
      suffix++;
    }
    return target;
  }

  Future<bool> _sameFileContent(File a, File b) async {
    if (!await a.exists() || !await b.exists()) return false;
    if (await a.length() != await b.length()) return false;
    final aBytes = await a.readAsBytes();
    final bBytes = await b.readAsBytes();
    if (aBytes.length != bBytes.length) return false;
    for (var i = 0; i < aBytes.length; i++) {
      if (aBytes[i] != bBytes[i]) return false;
    }
    return true;
  }

  String _safeRelativePath(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty && part != '.' && part != '..')
        .map((part) => safeStorageFileName(part, fallback: 'asset'))
        .toList();
    if (parts.isEmpty) return 'migrated_assets/asset';
    return parts.join('/');
  }

  MessageImage _copyImageWithPath(MessageImage image, String path) {
    return MessageImage(
      path: path,
      name: image.name,
      size: image.size,
      mimeType: image.mimeType,
    );
  }

  static String _normalizePath(String path) => path.replaceAll('\\', '/');
}
