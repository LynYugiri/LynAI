import 'composer_reference.dart';

/// 对话页输入框草稿的载荷：正文片段 + 暂存附件。
///
/// 同一份形状用于 `composer_drafts` 行的 `draft_json`、云/LAN 同步记录里的
/// `draft` 字段和备份里的草稿列表，因此 JSON 读写只在这里定义一次。
class ComposerDraft {
  final List<ComposerSegment> segments;
  final List<ComposerDraftAttachment> attachments;

  const ComposerDraft({this.segments = const [], this.attachments = const []});

  /// 正文与附件都为空时草稿不再需要保留（对应行会被删除）。
  bool get isEmpty => segments.isEmpty && attachments.isEmpty;

  Map<String, dynamic> toJson() => {
    'segments': composerSegmentsToJson(segments),
    'attachments': attachments.map((item) => item.toJson()).toList(),
  };

  factory ComposerDraft.fromJson(Map<String, dynamic> json) {
    final attachments = <ComposerDraftAttachment>[];
    for (final item in json['attachments'] as List? ?? const []) {
      if (item is! Map) continue;
      attachments.add(
        ComposerDraftAttachment.fromJson(Map<String, dynamic>.from(item)),
      );
    }
    return ComposerDraft(
      segments: composerSegmentsFromJson(json['segments']),
      attachments: attachments,
    );
  }
}

/// 草稿里的暂存附件。
///
/// 与消息附件不同，草稿附件以 storage_v2 的 resource 为准：[resourceId] 是另一台
/// 设备认回内容的依据，[path] 只是本机缓存（远端恢复或资源尚未下载时可能为空）。
class ComposerDraftAttachment {
  final String? resourceId;
  final String path;
  final String name;
  final int size;
  final String mimeType;

  const ComposerDraftAttachment({
    this.resourceId,
    this.path = '',
    required this.name,
    required this.size,
    this.mimeType = 'application/octet-stream',
  });

  Map<String, dynamic> toJson() => {
    if (resourceId != null && resourceId!.isNotEmpty) 'resourceId': resourceId,
    'path': path,
    'name': name,
    'size': size,
    'mimeType': mimeType,
  };

  factory ComposerDraftAttachment.fromJson(Map<String, dynamic> json) {
    final resourceId = json['resourceId'] as String?;
    return ComposerDraftAttachment(
      resourceId: resourceId == null || resourceId.isEmpty ? null : resourceId,
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
    );
  }
}
