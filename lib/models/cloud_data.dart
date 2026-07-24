class CloudUsage {
  const CloudUsage({
    required this.recordCount,
    required this.blobCount,
    required this.blobBytes,
    required this.blobRefCount,
  });

  final int recordCount;
  final int blobCount;
  final int blobBytes;
  final int blobRefCount;

  factory CloudUsage.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    return CloudUsage(
      recordCount: (json['recordCount'] as num?)?.toInt() ?? 0,
      blobCount: (json['blobCount'] as num?)?.toInt() ?? 0,
      blobBytes: (json['blobBytes'] as num?)?.toInt() ?? 0,
      blobRefCount: (json['blobRefCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'recordCount': recordCount,
    'blobCount': blobCount,
    'blobBytes': blobBytes,
    'blobRefCount': blobRefCount,
  };
}

class CloudIndexStatus {
  const CloudIndexStatus({
    required this.lastSeq,
    required this.generation,
    required this.indexRevision,
    required this.minAvailableSeq,
    required this.usage,
  });

  final int lastSeq;
  final int generation;
  final int indexRevision;
  final int minAvailableSeq;
  final CloudUsage usage;

  factory CloudIndexStatus.fromJson(Map<String, dynamic> json) =>
      CloudIndexStatus(
        lastSeq: (json['lastSeq'] as num?)?.toInt() ?? 0,
        generation: (json['generation'] as num?)?.toInt() ?? 0,
        indexRevision: (json['indexRevision'] as num?)?.toInt() ?? 0,
        minAvailableSeq: (json['minAvailableSeq'] as num?)?.toInt() ?? 0,
        usage: CloudUsage.fromJson(json['usage']),
      );

  Map<String, dynamic> toJson() => {
    'lastSeq': lastSeq,
    'generation': generation,
    'indexRevision': indexRevision,
    'minAvailableSeq': minAvailableSeq,
    'usage': usage.toJson(),
  };
}

class CloudIndexObject {
  const CloudIndexObject({
    required this.category,
    required this.objectId,
    required this.recordCount,
    required this.blobRefCount,
    required this.latestSeq,
    required this.updatedAt,
  });

  final String category;
  final String objectId;
  final int recordCount;
  final int blobRefCount;
  final int latestSeq;
  final DateTime updatedAt;

  factory CloudIndexObject.fromJson(Map<String, dynamic> json) =>
      CloudIndexObject(
        category: json['category'] as String? ?? '',
        objectId: json['objectId'] as String? ?? '',
        recordCount: (json['recordCount'] as num?)?.toInt() ?? 0,
        blobRefCount: (json['blobRefCount'] as num?)?.toInt() ?? 0,
        latestSeq: (json['latestSeq'] as num?)?.toInt() ?? 0,
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  Map<String, dynamic> toJson() => {
    'category': category,
    'objectId': objectId,
    'recordCount': recordCount,
    'blobRefCount': blobRefCount,
    'latestSeq': latestSeq,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

class CloudObjectDetail {
  const CloudObjectDetail({required this.object, required this.records});

  final CloudIndexObject object;
  final List<Map<String, dynamic>> records;

  factory CloudObjectDetail.fromJson(Map<String, dynamic> json) =>
      CloudObjectDetail(
        object: CloudIndexObject.fromJson(json),
        records: (json['records'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false),
      );
}

enum CloudPurgeType { object, category, all }

class CloudPurgeSelector {
  const CloudPurgeSelector._(this.type, this.category, this.objectId);

  const CloudPurgeSelector.object(String category, String objectId)
    : this._(CloudPurgeType.object, category, objectId);
  const CloudPurgeSelector.category(String category)
    : this._(CloudPurgeType.category, category, null);
  const CloudPurgeSelector.all() : this._(CloudPurgeType.all, null, null);

  final CloudPurgeType type;
  final String? category;
  final String? objectId;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    if (category != null) 'category': category,
    if (objectId != null) 'objectId': objectId,
  };
}

class CloudPurgePreview {
  const CloudPurgePreview({
    required this.selector,
    required this.generation,
    required this.indexRevision,
    required this.recordCount,
    required this.changeCount,
    required this.blobRefCount,
    required this.releasedBlobCandidates,
  });

  final CloudPurgeSelector selector;
  final int generation;
  final int indexRevision;
  final int recordCount;
  final int changeCount;
  final int blobRefCount;
  final int releasedBlobCandidates;

  factory CloudPurgePreview.fromJson(
    Map<String, dynamic> json,
    CloudPurgeSelector selector,
  ) => CloudPurgePreview(
    selector: selector,
    generation: (json['generation'] as num?)?.toInt() ?? 0,
    indexRevision: (json['indexRevision'] as num?)?.toInt() ?? 0,
    recordCount: (json['recordCount'] as num?)?.toInt() ?? 0,
    changeCount: (json['changeCount'] as num?)?.toInt() ?? 0,
    blobRefCount: (json['blobRefCount'] as num?)?.toInt() ?? 0,
    releasedBlobCandidates:
        (json['releasedBlobCandidates'] as num?)?.toInt() ?? 0,
  );
}

class CloudManagementOperation {
  const CloudManagementOperation({
    required this.id,
    required this.kind,
    required this.selectorType,
    this.category,
    this.objectId,
    required this.generation,
    required this.indexRevision,
    required this.createdAt,
  });

  final String id;
  final String kind;
  final String selectorType;
  final String? category;
  final String? objectId;
  final int generation;
  final int indexRevision;
  final DateTime createdAt;

  factory CloudManagementOperation.fromJson(Map<String, dynamic> json) =>
      CloudManagementOperation(
        id: json['id'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        selectorType: json['selectorType'] as String? ?? '',
        category: json['category'] as String?,
        objectId: json['objectId'] as String?,
        generation: (json['generation'] as num?)?.toInt() ?? 0,
        indexRevision: (json['indexRevision'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}

class CloudDurableRequest {
  const CloudDurableRequest({required this.key, required this.requestId});

  final String key;
  final String requestId;
}

class CloudDataSnapshot {
  const CloudDataSnapshot({
    this.status,
    this.objects = const [],
    this.categoryCounts = const {},
    this.updatedAt,
  });

  final CloudIndexStatus? status;
  final List<CloudIndexObject> objects;
  final Map<String, int> categoryCounts;
  final DateTime? updatedAt;
}

const cloudDataCategories = <String>[
  'conversations',
  'messages',
  'attachments',
  'resources',
  'notes',
  'tasks',
  'calendar',
  'roleplay',
  'recycle_bin',
  'settings',
  'models',
  'plugins',
];
