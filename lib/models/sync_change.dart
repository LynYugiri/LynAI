/// 同步变更记录。
///
/// 一条 change record 代表一次行级操作（upsert 或 delete），
/// 对应后端 `sync_changes` 表的一条记录。
class SyncChange {
  /// 序列号（服务端分配，per user 单调递增）。
  final int seq;

  /// 表名（如 'conversations'、'messages'、'notes' 等）。
  final String table;

  /// 操作类型：'upsert' 或 'delete'。
  final String op;

  /// 被操作的行 ID。
  final String recordId;

  /// upsert 时的完整行 JSON；delete 时为 null。
  final Map<String, dynamic>? data;

  /// 服务端创建时间。
  final DateTime? createdAt;

  /// 创建同步变更实例。
  const SyncChange({
    required this.seq,
    required this.table,
    required this.op,
    required this.recordId,
    this.data,
    this.createdAt,
  });

  /// 从后端 JSON 构造。
  factory SyncChange.fromJson(Map<String, dynamic> json) {
    return SyncChange(
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      table: json['table'] as String? ?? '',
      op: json['op'] as String? ?? '',
      recordId: json['recordId'] as String? ?? '',
      data: json['data'] is Map
          ? Map<String, dynamic>.from(json['data'] as Map)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }
}

/// 同步状态。
class SyncStatus {
  /// 用户最新的同步序列号。
  final int lastSeq;

  /// 已上传的 blob 数量。
  final int blobCount;

  /// 创建同步状态实例。
  const SyncStatus({required this.lastSeq, required this.blobCount});
}

/// Blob 元数据。
class BlobInfo {
  final String sha256;
  final int size;

  const BlobInfo({required this.sha256, required this.size});

  factory BlobInfo.fromJson(Map<String, dynamic> json) {
    return BlobInfo(
      sha256: json['sha256'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 同步上传结果。
class SyncUploadResult {
  final int latestSeq;

  const SyncUploadResult({required this.latestSeq});
}

/// 同步下载结果。
class SyncDownloadResult {
  final List<SyncChange> changes;
  final int latestSeq;

  const SyncDownloadResult({required this.changes, required this.latestSeq});
}
