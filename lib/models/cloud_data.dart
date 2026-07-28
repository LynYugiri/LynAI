import 'sync_change.dart';

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
    if (value is! Map) throw const FormatException('cloud usage is invalid');
    final json = Map<String, dynamic>.from(value);
    return CloudUsage(
      recordCount: _nonNegativeInt(json['recordCount'], 'recordCount'),
      blobCount: _nonNegativeInt(json['blobCount'], 'blobCount'),
      blobBytes: _nonNegativeInt(json['blobBytes'], 'blobBytes'),
      blobRefCount: _nonNegativeInt(json['blobRefCount'], 'blobRefCount'),
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
    this.capabilities = const SyncCapabilities(),
  });

  final int lastSeq;
  final int generation;
  final int indexRevision;
  final int minAvailableSeq;
  final CloudUsage usage;
  final SyncCapabilities capabilities;

  factory CloudIndexStatus.fromJson(Map<String, dynamic> json) =>
      CloudIndexStatus(
        lastSeq: _nonNegativeInt(json['lastSeq'], 'lastSeq'),
        generation: _positiveInt(json['generation'], 'generation'),
        indexRevision: _nonNegativeInt(json['indexRevision'], 'indexRevision'),
        minAvailableSeq: _nonNegativeInt(
          json['minAvailableSeq'],
          'minAvailableSeq',
        ),
        usage: CloudUsage.fromJson(json['usage']),
        capabilities: SyncCapabilities.fromJson(json['capabilities']),
      );

  Map<String, dynamic> toJson() => {
    'lastSeq': lastSeq,
    'generation': generation,
    'indexRevision': indexRevision,
    'minAvailableSeq': minAvailableSeq,
    'usage': usage.toJson(),
    if (capabilities.advertised)
      'capabilities': {
        'index': capabilities.index,
        'selectivePurge': capabilities.selectivePurge,
        'fullPurge': capabilities.fullPurge,
        'operationAck': capabilities.operationAck,
      },
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

  factory CloudIndexObject.fromJson(Map<String, dynamic> json) {
    final category = _requiredString(json['category'], 'category');
    final objectId = _requiredString(json['objectId'], 'objectId');
    final updatedAt = _requiredDateTime(json['updatedAt'], 'updatedAt');
    return CloudIndexObject(
      category: category,
      objectId: objectId,
      recordCount: _positiveInt(json['recordCount'], 'recordCount'),
      blobRefCount: _nonNegativeInt(json['blobRefCount'], 'blobRefCount'),
      latestSeq: _positiveInt(json['latestSeq'], 'latestSeq'),
      updatedAt: updatedAt,
    );
  }

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
  const CloudObjectDetail({
    required this.object,
    required this.records,
    required this.indexRevision,
  });

  final CloudIndexObject object;
  final List<Map<String, dynamic>> records;
  final int indexRevision;

  factory CloudObjectDetail.fromJson(Map<String, dynamic> json) {
    final rawRecords = json['records'];
    if (rawRecords is! List) {
      throw const FormatException('cloud object records are invalid');
    }
    final records = rawRecords
        .map((item) {
          if (item is! Map) {
            throw const FormatException('cloud object record is invalid');
          }
          final record = Map<String, dynamic>.from(item);
          final table = _requiredString(record['table'], 'table');
          final op = _requiredString(record['op'], 'op');
          final recordId = _requiredString(record['recordId'], 'recordId');
          if (op != 'upsert' || record['data'] is! Map) {
            throw const FormatException('cloud projection record is invalid');
          }
          final data = Map<String, dynamic>.from(record['data'] as Map);
          if (data['id'] != recordId) {
            throw const FormatException('cloud projection data.id is invalid');
          }
          return <String, dynamic>{
            'table': table,
            'op': op,
            'recordId': recordId,
            'data': data,
          };
        })
        .toList(growable: false);
    final object = CloudIndexObject.fromJson(json);
    if (records.length != object.recordCount) {
      throw const FormatException('cloud object recordCount is inconsistent');
    }
    return CloudObjectDetail(
      object: object,
      records: records,
      indexRevision: _nonNegativeInt(json['indexRevision'], 'indexRevision'),
    );
  }
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
    generation: _positiveInt(json['generation'], 'generation'),
    indexRevision: _nonNegativeInt(json['indexRevision'], 'indexRevision'),
    recordCount: _nonNegativeInt(json['recordCount'], 'recordCount'),
    changeCount: _nonNegativeInt(json['changeCount'], 'changeCount'),
    blobRefCount: _nonNegativeInt(json['blobRefCount'], 'blobRefCount'),
    releasedBlobCandidates: _nonNegativeInt(
      json['releasedBlobCandidates'],
      'releasedBlobCandidates',
    ),
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

  factory CloudManagementOperation.fromJson(Map<String, dynamic> json) {
    final kind = _requiredString(json['kind'], 'kind');
    final selectorType = _requiredString(json['selectorType'], 'selectorType');
    final category = json['category'];
    final objectId = json['objectId'];
    if ((kind != 'selective' && kind != 'full') ||
        !{'object', 'category', 'all'}.contains(selectorType) ||
        (category != null && (category is! String || category.isEmpty)) ||
        (objectId != null && (objectId is! String || objectId.isEmpty)) ||
        (selectorType == 'object' && (category == null || objectId == null)) ||
        (selectorType == 'category' &&
            (category == null || objectId != null)) ||
        (selectorType == 'all' && (category != null || objectId != null))) {
      throw const FormatException('cloud management operation is invalid');
    }
    return CloudManagementOperation(
      id: _requiredString(json['id'], 'id'),
      kind: kind,
      selectorType: selectorType,
      category: category as String?,
      objectId: objectId as String?,
      generation: _positiveInt(json['generation'], 'generation'),
      indexRevision: _nonNegativeInt(json['indexRevision'], 'indexRevision'),
      createdAt: _requiredDateTime(json['createdAt'], 'createdAt'),
    );
  }
}

class CloudCurrentProjection {
  const CloudCurrentProjection({required this.status, required this.records});

  final CloudIndexStatus status;
  final List<Map<String, dynamic>> records;
}

int _nonNegativeInt(Object? value, String field) {
  if (value is! int || value < 0) {
    throw FormatException('cloud $field is invalid');
  }
  return value;
}

int _positiveInt(Object? value, String field) {
  final parsed = _nonNegativeInt(value, field);
  if (parsed == 0) throw FormatException('cloud $field is invalid');
  return parsed;
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('cloud $field is invalid');
  }
  return value;
}

DateTime _requiredDateTime(Object? value, String field) {
  if (value is! String) throw FormatException('cloud $field is invalid');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('cloud $field is invalid');
  return parsed;
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
