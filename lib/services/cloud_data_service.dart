import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/cloud_data.dart';
import 'backend_client.dart';
import 'sync_service.dart';

abstract class CloudDataService {
  Future<CloudIndexStatus> getStatus();
  Future<List<CloudIndexObject>> listObjects(String category, int revision);
  Future<CloudObjectDetail> getObject(
    String category,
    String objectId,
    int revision,
  );
  Future<CloudPurgePreview> previewPurge(
    CloudPurgeSelector selector,
    int revision,
  );
  Future<CloudManagementOperation> purge(
    CloudPurgePreview preview,
    String requestId,
  );
  Future<List<CloudManagementOperation>> getOperations();
  Future<CloudCurrentProjection> getCurrentProjection() =>
      throw UnimplementedError();
  Future<void> acknowledgeOperation(
    String operationId,
    int generation,
    String requestId, {
    required bool includeOperationId,
  });
}

class RemoteCloudDataService implements CloudDataService {
  RemoteCloudDataService(this._client, RemoteSyncService syncService)
    : _postSignedJson = syncService.postSignedJson;

  RemoteCloudDataService.withSignedPost(
    this._client,
    Future<dynamic> Function({
      required String path,
      required String target,
      required String requestId,
      required Map<String, dynamic> body,
    })
    postSignedJson,
  ) : _postSignedJson = postSignedJson;

  final BackendClient _client;
  final Future<dynamic> Function({
    required String path,
    required String target,
    required String requestId,
    required Map<String, dynamic> body,
  })
  _postSignedJson;
  static const _uuid = Uuid();

  @override
  Future<CloudIndexStatus> getStatus() async {
    final response = await _client.get('/sync/index/status');
    final json = _jsonObject(response, '获取云端索引状态失败');
    final status = CloudIndexStatus.fromJson(json);
    if (status.minAvailableSeq > status.lastSeq) {
      throw const FormatException('云端索引状态 cursor metadata 无效');
    }
    return status;
  }

  @override
  Future<List<CloudIndexObject>> listObjects(
    String category,
    int revision,
  ) async {
    var after = '';
    final objects = <CloudIndexObject>[];
    while (true) {
      final query = Uri(
        queryParameters: {
          'category': category,
          'expectedIndexRevision': '$revision',
          'limit': '500',
          if (after.isNotEmpty) 'after': after,
        },
      ).query;
      final response = await _client.get('/sync/index/objects?$query');
      final json = _jsonObject(response, '获取云端对象失败');
      if ((json['indexRevision'] as num?)?.toInt() != revision) {
        throw StateError('云端对象分页 indexRevision 不匹配');
      }
      final rawObjects = json['objects'];
      final hasMore = json['hasMore'];
      if (rawObjects is! List || hasMore is! bool) {
        throw const FormatException('云端对象分页格式无效');
      }
      for (final item in rawObjects) {
        if (item is! Map) throw const FormatException('云端对象格式无效');
        final object = CloudIndexObject.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (object.category != category) {
          throw const FormatException('云端对象分类不匹配');
        }
        objects.add(object);
      }
      if (!hasMore) return objects;
      final next = json['nextAfter'];
      if (next is! String) throw const FormatException('云端对象分页游标无效');
      if (next.isEmpty || next == after) throw StateError('云端对象分页游标未前进');
      after = next;
    }
  }

  @override
  Future<CloudObjectDetail> getObject(
    String category,
    String objectId,
    int revision,
  ) async {
    final path =
        '/sync/index/objects/${Uri.encodeComponent(category)}/${Uri.encodeComponent(objectId)}'
        '?expectedIndexRevision=$revision';
    final response = await _client.get(path);
    final detail = CloudObjectDetail.fromJson(
      _jsonObject(response, '获取云端对象详情失败'),
    );
    if (detail.indexRevision != revision) {
      throw StateError('云端对象详情 indexRevision 不匹配');
    }
    return detail;
  }

  @override
  Future<CloudPurgePreview> previewPurge(
    CloudPurgeSelector selector,
    int revision,
  ) async {
    final response = await _client.post(
      '/sync/manage/purge/preview',
      body: {'expectedIndexRevision': revision, 'selector': selector.toJson()},
    );
    final preview = CloudPurgePreview.fromJson(
      _jsonObject(response, '生成清理预览失败'),
      selector,
    );
    if (preview.indexRevision != revision) {
      throw const FormatException('清理预览 indexRevision 不匹配');
    }
    return preview;
  }

  @override
  Future<CloudManagementOperation> purge(
    CloudPurgePreview preview,
    String requestId,
  ) async {
    final response = await _postSignedJson(
      path: '/sync/manage/purge',
      target: '/sync/manage/purge',
      requestId: requestId,
      body: {
        'requestId': requestId,
        'expectedGeneration': preview.generation,
        'expectedIndexRevision': preview.indexRevision,
        'selector': preview.selector.toJson(),
      },
    );
    final json = _jsonObject(response, '清理云端数据失败');
    final raw = json['operation'];
    if (raw is! Map) throw const FormatException('云端清理操作格式无效');
    return CloudManagementOperation.fromJson(Map<String, dynamic>.from(raw));
  }

  @override
  Future<List<CloudManagementOperation>> getOperations() async {
    final response = await _client.get('/sync/manage/operations');
    final json = _jsonObject(response, '获取云端待处理操作失败');
    final raw = json['operations'];
    if (raw is! List) throw const FormatException('云端待处理操作格式无效');
    return raw
        .map((item) {
          if (item is! Map) throw const FormatException('云端待处理操作格式无效');
          return CloudManagementOperation.fromJson(
            Map<String, dynamic>.from(item),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<CloudCurrentProjection> getCurrentProjection() async {
    final status = await getStatus();
    if (!status.capabilities.index) {
      throw StateError('服务端不支持云端索引 reseed');
    }
    final records = <Map<String, dynamic>>[];
    for (final category in cloudDataCategories) {
      final objects = await listObjects(category, status.indexRevision);
      for (final object in objects) {
        final detail = await getObject(
          object.category,
          object.objectId,
          status.indexRevision,
        );
        records.addAll(detail.records);
      }
    }
    return CloudCurrentProjection(status: status, records: records);
  }

  @override
  Future<void> acknowledgeOperation(
    String operationId,
    int generation,
    String requestId, {
    required bool includeOperationId,
  }) async {
    final response = await _postSignedJson(
      path: '/sync/manage/operations/${Uri.encodeComponent(operationId)}/ack',
      target: '/sync/manage/operations/:id/ack',
      requestId: requestId,
      body: {
        'requestId': requestId,
        'expectedGeneration': generation,
        if (includeOperationId) 'operationId': operationId,
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
        BackendClient.extractErrorMessage(response.body) ?? '确认云端操作失败',
      );
    }
  }

  static String newRequestId() => _uuid.v4().replaceAll('-', '');

  Map<String, dynamic> _jsonObject(dynamic response, String fallback) {
    if (response.statusCode != 200) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['code'] == 'index_revision_conflict') {
          throw CloudProjectionRaceException(
            BackendClient.extractErrorMessage(response.body) ?? fallback,
          );
        }
      } on CloudProjectionRaceException {
        rethrow;
      } catch (_) {}
      throw Exception(
        BackendClient.extractErrorMessage(response.body) ?? fallback,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const FormatException('云端数据响应不是 JSON object');
    return Map<String, dynamic>.from(decoded);
  }
}

class CloudProjectionRaceException implements Exception {
  const CloudProjectionRaceException(this.message);

  final String message;

  @override
  String toString() => message;
}
