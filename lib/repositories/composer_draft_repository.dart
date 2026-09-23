import 'dart:convert';
import 'dart:io';

import '../models/composer_draft.dart';
import '../services/attachment_storage_service.dart';
import '../services/storage_v2_service.dart';

/// 一个槽位的草稿：内容与最后修改时间。
class ComposerDraftEntry {
  final String slot;
  final ComposerDraft draft;
  final DateTime updatedAt;

  const ComposerDraftEntry({
    required this.slot,
    required this.draft,
    required this.updatedAt,
  });
}

/// 输入框草稿的本地持久化。
///
/// 草稿存在 `composer_drafts` 表（逻辑文件名 `composer_drafts.json`），跟随对话分区
/// 一起备份与同步；尚未创建对话的 [newConversationSlot] 没有对话可绑定，只留在本机。
///
/// 附件在行里只保存 Resource ID 与展示元数据，本机路径按 Resource 解析：这样另一台
/// 设备（或备份恢复后）拿到同一条草稿时也能定位到本地的附件文件。
class ComposerDraftRepository {
  ComposerDraftRepository({
    StorageV2Service? storageV2,
    DateTime Function()? now,
  }) : _storageV2 = storageV2 ?? StorageV2Service(),
       _now = now ?? DateTime.now;

  static const fileName = 'composer_drafts.json';

  /// 尚未创建对话时使用的槽位。
  static const newConversationSlot = 'new';

  /// 槽位就是对话 ID；没有对话时用 [newConversationSlot]。
  static String slotFor(String? conversationId) =>
      conversationId == null || conversationId.isEmpty
      ? newConversationSlot
      : conversationId;

  final StorageV2Service _storageV2;
  final DateTime Function() _now;

  Future<List<ComposerDraftEntry>> load() async {
    final json = await _storageV2.loadDataFile(fileName);
    final resourcePaths = await _localResourcePaths();
    final entries = <ComposerDraftEntry>[];
    for (final item in json['drafts'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final slot = row['id'] as String?;
      final raw = row['draft'];
      if (slot == null || slot.isEmpty || raw is! Map) continue;
      final draft = ComposerDraft.fromJson(Map<String, dynamic>.from(raw));
      entries.add(
        ComposerDraftEntry(
          slot: slot,
          draft: _resolveAttachmentPaths(draft, resourcePaths),
          updatedAt:
              DateTime.tryParse(row['updatedAt'] as String? ?? '') ??
              _now().toUtc(),
        ),
      );
    }
    return entries;
  }

  /// 覆盖写入全部草稿。
  ///
  /// 内容没变的槽位保留原来的 `updatedAt`，否则整表覆盖会让每条草稿都产生一次
  /// 无意义的同步变更。
  Future<void> save(Map<String, ComposerDraft> drafts) async {
    final existing = {for (final entry in await load()) entry.slot: entry};
    final now = _now().toUtc().toIso8601String();
    final rows = <Map<String, dynamic>>[];
    for (final entry in drafts.entries) {
      final draft = await _ensureResourceIds(entry.value);
      final previous = existing[entry.key];
      final unchanged =
          previous != null &&
          jsonEncode(previous.draft.toJson()) == jsonEncode(draft.toJson());
      rows.add({
        'id': entry.key,
        if (entry.key != newConversationSlot) 'conversationId': entry.key,
        'draft': draft.toJson(),
        'updatedAt': unchanged ? previous.updatedAt.toIso8601String() : now,
      });
    }
    await _storageV2.writeDataFile(fileName, {'drafts': rows});
  }

  /// 本机已有内容的 Resource 路径，用于把草稿附件指向本机文件。
  Future<Map<String, String>> _localResourcePaths() async {
    final paths = <String, String>{};
    try {
      for (final resource in await _storageV2.loadResources()) {
        final path = await _storageV2.resourcePath(resource);
        if (path != null && path.isNotEmpty) paths[resource.id] = path;
      }
    } catch (_) {
      // Resource 表不可用时保留草稿里原有的路径。
    }
    return paths;
  }

  ComposerDraft _resolveAttachmentPaths(
    ComposerDraft draft,
    Map<String, String> resourcePaths,
  ) {
    if (draft.attachments.isEmpty) return draft;
    var changed = false;
    final attachments = draft.attachments
        .map((attachment) {
          final path = resourcePaths[attachment.resourceId];
          if (path == null || path == attachment.path) return attachment;
          changed = true;
          return ComposerDraftAttachment(
            resourceId: attachment.resourceId,
            path: path,
            name: attachment.name,
            size: attachment.size,
            mimeType: attachment.mimeType,
          );
        })
        .toList(growable: false);
    if (!changed) return draft;
    return ComposerDraft(segments: draft.segments, attachments: attachments);
  }

  /// 给还只有本机路径的附件补 Resource。
  ///
  /// 撤回消息、从备份恢复的草稿都只带路径；导入 Resource 是内容哈希去重的，所以补
  /// 一次之后附件就能跟着草稿同步到其他设备。
  Future<ComposerDraft> _ensureResourceIds(ComposerDraft draft) async {
    if (draft.attachments.isEmpty) return draft;
    var changed = false;
    final attachments = <ComposerDraftAttachment>[];
    for (final attachment in draft.attachments) {
      if (attachment.resourceId != null ||
          attachment.path.isEmpty ||
          !File(attachment.path).existsSync()) {
        attachments.add(attachment);
        continue;
      }
      try {
        final resource = await _storageV2.importResourceFile(
          attachment.path,
          originalName: attachment.name,
          mimeType: attachment.mimeType,
          role: AttachmentStorageService.messageResourceRole(
            attachment.mimeType,
          ),
        );
        changed = true;
        attachments.add(
          ComposerDraftAttachment(
            resourceId: resource.id,
            path: attachment.path,
            name: attachment.name,
            size: attachment.size,
            mimeType: attachment.mimeType,
          ),
        );
      } catch (_) {
        attachments.add(attachment);
      }
    }
    if (!changed) return draft;
    return ComposerDraft(segments: draft.segments, attachments: attachments);
  }
}
