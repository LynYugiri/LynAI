/// 同步变更记录。
///
/// 一条 change record 代表一次行级操作（upsert 或 delete），
/// 对应后端 `sync_changes` 表的一条记录。
class SyncChange {
  /// 序列号（服务端分配，per user 单调递增）。
  final int seq;

  /// Stable client-generated identity for this mutation.
  final String changeId;

  /// Device that created the mutation.
  final String deviceId;

  /// Client creation time retained across upload retries.
  final DateTime clientCreatedAt;

  /// 表名（如 'conversations'、'messages'、'notes' 等）。
  final String table;

  /// 操作类型：'upsert' 或 'delete'。
  final String op;

  /// 被操作的行 ID。
  final String recordId;

  /// upsert 时的完整行 JSON；delete 时为 null。
  final Map<String, dynamic>? data;

  /// Physical dataset lineage used only by additive LAN transport metadata.
  /// It is deliberately omitted from the backend sync wire contract.
  final String? lineage;

  /// 服务端创建时间。
  final DateTime? createdAt;

  /// 创建同步变更实例。
  const SyncChange({
    required this.seq,
    required this.changeId,
    required this.deviceId,
    required this.clientCreatedAt,
    required this.table,
    required this.op,
    required this.recordId,
    this.data,
    this.lineage,
    this.createdAt,
  });

  /// 从后端 JSON 构造。
  factory SyncChange.fromJson(Map<String, dynamic> json) {
    final seq = _positiveInt(json['seq'], 'seq');
    final changeId = _requiredString(json['changeId'], 'changeId');
    final deviceId = _requiredString(json['deviceId'], 'deviceId');
    final table = _requiredString(json['table'], 'table');
    final op = _requiredString(json['op'], 'op');
    final recordId = _requiredString(json['recordId'], 'recordId');
    if (op != 'upsert' && op != 'delete') {
      throw FormatException('invalid sync change op: $op');
    }
    final clientCreatedAtValue = json['clientCreatedAt'];
    if (clientCreatedAtValue is! String) {
      throw const FormatException('sync change clientCreatedAt is invalid');
    }
    final clientCreatedAt = DateTime.tryParse(clientCreatedAtValue);
    if (clientCreatedAt == null) {
      throw const FormatException('sync change clientCreatedAt is invalid');
    }
    final rawData = json['data'];
    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : null;
    if (op == 'upsert' && data?['id'] != recordId) {
      throw FormatException(
        'sync change data.id does not match recordId: $recordId',
      );
    }
    if (op == 'delete' && json.containsKey('data')) {
      throw const FormatException('sync delete must not contain data');
    }
    return SyncChange(
      seq: seq,
      changeId: changeId,
      deviceId: deviceId,
      clientCreatedAt: clientCreatedAt,
      table: table,
      op: op,
      recordId: recordId,
      data: data,
      lineage: json['lineage'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }

  static int _positiveInt(Object? value, String field) {
    if (value is! int || value <= 0) {
      throw FormatException('sync change $field must be a positive integer');
    }
    return value;
  }

  static String _requiredString(Object? value, String field) {
    if (value is! String || value.isEmpty) {
      throw FormatException('sync change $field is empty');
    }
    return value;
  }
}

/// 同步状态。
class SyncStatus {
  /// 用户最新的同步序列号。
  final int lastSeq;

  /// 已上传的 blob 数量。
  final int blobCount;

  final int generation;
  final int indexRevision;
  final int minAvailableSeq;

  final SyncLimits limits;
  final SyncCapabilities capabilities;

  /// 创建同步状态实例。
  const SyncStatus({
    required this.lastSeq,
    required this.blobCount,
    this.generation = 0,
    this.indexRevision = 0,
    this.minAvailableSeq = 0,
    this.limits = const SyncLimits(),
    this.capabilities = const SyncCapabilities(),
  });
}

class SyncCapabilities {
  const SyncCapabilities({
    this.advertised = false,
    this.index = false,
    this.selectivePurge = false,
    this.fullPurge = false,
    this.operationAck = false,
  });

  final bool advertised;
  final bool index;
  final bool selectivePurge;
  final bool fullPurge;
  final bool operationAck;

  factory SyncCapabilities.fromJson(Object? value) {
    if (value == null) return const SyncCapabilities();
    if (value is! Map) {
      throw const FormatException('sync capabilities must be an object');
    }
    bool flag(String key) {
      if (!value.containsKey(key)) return false;
      final parsed = value[key];
      if (parsed is! bool) {
        throw FormatException('sync capability $key must be boolean');
      }
      return parsed;
    }

    return SyncCapabilities(
      advertised: true,
      index: flag('index'),
      selectivePurge: flag('selectivePurge'),
      fullPurge: flag('fullPurge'),
      operationAck: flag('operationAck'),
    );
  }
}

enum SyncCursorErrorCode { generationMismatch, staleCursor, futureCursor }

class SyncCursorException implements Exception {
  const SyncCursorException({
    required this.code,
    required this.message,
    required this.currentGeneration,
    this.expectedGeneration,
    this.latestSeq,
    this.indexRevision,
    this.minAvailableSeq,
  });

  final SyncCursorErrorCode code;
  final String message;
  final int currentGeneration;
  final int? expectedGeneration;
  final int? latestSeq;
  final int? indexRevision;
  final int? minAvailableSeq;

  @override
  String toString() => message;
}

class SyncLimits {
  final int maxBlobBytes;
  final int maxChangesRequestBytes;
  final int maxChangesPerRequest;
  final int maxChangeDataBytes;
  final int maxChangesPageSize;
  final int maxBlobsPageSize;

  const SyncLimits({
    this.maxBlobBytes = 64 * 1024 * 1024,
    this.maxChangesRequestBytes = 2 * 1024 * 1024,
    this.maxChangesPerRequest = 500,
    this.maxChangeDataBytes = 256 * 1024,
    this.maxChangesPageSize = 1000,
    this.maxBlobsPageSize = 1000,
  });

  factory SyncLimits.fromJson(Object? value) {
    if (value is! Map) return const SyncLimits();
    int positive(String key, int fallback) {
      final parsed = (value[key] as num?)?.toInt();
      return parsed != null && parsed > 0 ? parsed : fallback;
    }

    const defaults = SyncLimits();
    return SyncLimits(
      maxBlobBytes: positive('maxBlobBytes', defaults.maxBlobBytes),
      maxChangesRequestBytes: positive(
        'maxChangesRequestBytes',
        defaults.maxChangesRequestBytes,
      ),
      maxChangesPerRequest: positive(
        'maxChangesPerRequest',
        defaults.maxChangesPerRequest,
      ),
      maxChangeDataBytes: positive(
        'maxChangeDataBytes',
        defaults.maxChangeDataBytes,
      ),
      maxChangesPageSize: positive(
        'maxChangesPageSize',
        defaults.maxChangesPageSize,
      ),
      maxBlobsPageSize: positive('maxBlobsPageSize', defaults.maxBlobsPageSize),
    );
  }
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
  final List<SyncAcknowledgement>? acknowledgements;
  final bool legacyWholeBatchAcknowledgement;

  const SyncUploadResult({
    required this.latestSeq,
    this.acknowledgements,
    this.legacyWholeBatchAcknowledgement = false,
  });
}

class SyncAcknowledgement {
  final String changeId;
  final int mutationVersion;

  const SyncAcknowledgement({
    required this.changeId,
    required this.mutationVersion,
  });
}

/// 同步下载结果。
class SyncDownloadResult {
  final List<SyncChange> changes;
  final int latestSeq;
  final bool hasMore;
  final int nextSince;
  final int generation;
  final int indexRevision;
  final int minAvailableSeq;
  final int globalLatestSeq;
  final bool hasGeneration;
  final bool hasIndexRevision;
  final bool hasMinAvailableSeq;

  const SyncDownloadResult({
    required this.changes,
    required this.latestSeq,
    required this.hasMore,
    required this.nextSince,
    this.generation = 0,
    this.indexRevision = 0,
    this.minAvailableSeq = 0,
    int? globalLatestSeq,
    this.hasGeneration = false,
    this.hasIndexRevision = false,
    this.hasMinAvailableSeq = false,
  }) : globalLatestSeq = globalLatestSeq ?? latestSeq;
}
