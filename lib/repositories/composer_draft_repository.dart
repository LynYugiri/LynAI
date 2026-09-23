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
    final entries = await _readRows();
    final resourcePaths = await _resourcePathsFor(entries);
    if (resourcePaths.isEmpty) return entries;
    return [
      for (final entry in entries)
        ComposerDraftEntry(
          slot: entry.slot,
          draft: _resolveAttachmentPaths(entry.draft, resourcePaths),
          updatedAt: entry.updatedAt,
        ),
    ];
  }

  /// 读取原始行：附件路径保持存储时的样子，供保存时判断内容是否变化。
  Future<List<ComposerDraftEntry>> _readRows() async {
    final json = await _storageV2.loadDataFile(fileName);
    final entries = <ComposerDraftEntry>[];
    for (final item in json['drafts'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final slot = row['id'] as String?;
      final raw = row['draft'];
      if (slot == null || slot.isEmpty || raw is! Map) continue;
      entries.add(
        ComposerDraftEntry(
          slot: slot,
          draft: ComposerDraft.fromJson(Map<String, dynamic>.from(raw)),
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
    final existing = {for (final entry in await _readRows()) entry.slot: entry};
    final now = _now().toUtc().toIso8601String();
    final rows = <Map<String, dynamic>>[];
    for (final entry in drafts.entries) {
      final draft = await _ensureResourceIds(entry.value);
      final previous = existing[entry.key];
      final unchanged = previous != null && _sameContent(previous.draft, draft);
      rows.add({
        'id': entry.key,
        if (entry.key != newConversationSlot) 'conversationId': entry.key,
        'draft': draft.toJson(),
        'updatedAt': unchanged ? previous.updatedAt.toIso8601String() : now,
      });
    }
    await _storageV2.writeDataFile(fileName, {'drafts': rows});
  }

  /// 只解析草稿实际引用的 Resource 路径，避免每次加载都遍历整张资源表。
  Future<Map<String, String>> _resourcePathsFor(
    List<ComposerDraftEntry> entries,
  ) async {
    final ids = <String>{};
    for (final entry in entries) {
      for (final attachment in entry.draft.attachments) {
        final id = attachment.resourceId;
        if (id != null) ids.add(id);
      }
    }
    if (ids.isEmpty) return const {};
    final paths = <String, String>{};
    try {
      for (final resource in await _storageV2.findResourcesByIds(ids)) {
        final path = await _storageV2.resourcePath(resource);
        if (path != null && path.isNotEmpty) paths[resource.id] = path;
      }
    } catch (_) {
      // Resource 表不可用时保留草稿里原有的路径。
    }
    return paths;
  }

  /// 判断草稿内容是否变化。
  ///
  /// 附件只比较路径与展示元数据：`resourceId` 是补齐出来的派生信息（撤回消息、
  /// 从备份恢复的附件本来没有），把它算进去会让每次保存都刷新 `updatedAt`，产生
  /// 无意义的同步变更。
  static bool _sameContent(ComposerDraft a, ComposerDraft b) {
    final left = a.toJson()..['attachments'] = _attachmentsForCompare(a);
    final right = b.toJson()..['attachments'] = _attachmentsForCompare(b);
    return jsonEncode(left) == jsonEncode(right);
  }

  static List<Map<String, dynamic>> _attachmentsForCompare(
    ComposerDraft draft,
  ) => [
    for (final attachment in draft.attachments)
      {
        'path': attachment.path,
        'name': attachment.name,
        'size': attachment.size,
        'mimeType': attachment.mimeType,
      },
  ];

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
