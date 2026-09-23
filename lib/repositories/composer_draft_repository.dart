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
  Future<List<ComposerDraftEntry>> _readRows() async =>
      (await _readRowsWithRaw()).entries;

  /// 同时给出解析后的行与原始行。
  ///
  /// 原始行用于「本次保存没有提到的槽位原样写回」：重新序列化会丢掉未知字段，
  /// 也会让未改动的行看上去变了一次。
  Future<
    ({List<ComposerDraftEntry> entries, Map<String, Map<String, dynamic>> raw})
  >
  _readRowsWithRaw() async {
    final json = await _storageV2.loadDataFile(fileName);
    final entries = <ComposerDraftEntry>[];
    final raw = <String, Map<String, dynamic>>{};
    for (final item in json['drafts'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final slot = row['id'] as String?;
      if (slot == null || slot.isEmpty) continue;
      raw[slot] = row;
      final draft = row['draft'];
      if (draft is! Map) continue;
      entries.add(
        ComposerDraftEntry(
          slot: slot,
          draft: ComposerDraft.fromJson(Map<String, dynamic>.from(draft)),
          updatedAt:
              DateTime.tryParse(row['updatedAt'] as String? ?? '') ??
              _now().toUtc(),
        ),
      );
    }
    return (entries: entries, raw: raw);
  }

  /// 保存草稿。
  ///
  /// [drafts] 里出现的槽位按内容写入，[removed] 里的槽位删除，**两者都没提到的
  /// 槽位保持数据库里的原样**。合并语义是必须的：内存缓存可能是部分状态（启动时
  /// [ConversationProvider.loadConversations] 因 mutation generation 变化提前返回，
  /// 或草稿读取失败时保留旧缓存），整表覆盖会把没提到的对话草稿一起删掉，并经云/LAN
  /// 同步传播到其他设备。
  Future<void> save(
    Map<String, ComposerDraft> drafts, {
    Set<String> removed = const {},
  }) async {
    final (:entries, :raw) = await _readRowsWithRaw();
    final existing = {for (final entry in entries) entry.slot: entry};
    final now = _now().toUtc().toIso8601String();
    final slots = <String>{...raw.keys, ...drafts.keys}..removeAll(removed);
    final rows = <Map<String, dynamic>>[];
    for (final slot in slots) {
      final incoming = drafts[slot];
      if (incoming == null) {
        // 没有被本次保存提到：原样写回，不重新序列化、不刷新 updatedAt。
        rows.add(raw[slot]!);
        continue;
      }
      final draft = await _ensureResourceIds(incoming);
      final previous = existing[slot];
      final unchanged = previous != null && _sameContent(previous.draft, draft);
      rows.add({
        'id': slot,
        if (slot != newConversationSlot) 'conversationId': slot,
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
  /// 附件按「Resource 身份」比较：读回时 `path` 会被解析成 Resource 的私有路径，
  /// 而存储行里可能还是选择时的暂存路径，按路径比较会让每次启动后的第一次保存都
  /// 刷新 `updatedAt`，推出一条无意义的同步变更。只有还没有 `resourceId` 的附件
  /// （刚撤回或刚从备份恢复，尚未补 Resource）才回退到路径比较；等
  /// [_ensureResourceIds] 补上 Resource 后会再刷新一次 `updatedAt`，之后就收敛。
  static bool _sameContent(ComposerDraft a, ComposerDraft b) {
    final left = a.toJson()..['attachments'] = _attachmentsForCompare(a);
    final right = b.toJson()..['attachments'] = _attachmentsForCompare(b);
    return jsonEncode(left) == jsonEncode(right);
  }

  static List<Map<String, dynamic>> _attachmentsForCompare(
    ComposerDraft draft,
  ) => [
    for (final attachment in draft.attachments)
      if (attachment.resourceId != null)
        {
          'resourceId': attachment.resourceId,
          'name': attachment.name,
          'size': attachment.size,
          'mimeType': attachment.mimeType,
        }
      else
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
