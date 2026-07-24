import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/cloud_data.dart';
import 'backend_client.dart';
import 'sync_service.dart';

abstract class CloudDataService {
  Future<CloudIndexStatus> getStatus();
  Future<List<CloudIndexObject>> listObjects(String category, int revision);
  Future<CloudObjectDetail> getObject(String category, String objectId);
  Future<CloudPurgePreview> previewPurge(
    CloudPurgeSelector selector,
    int revision,
  );
  Future<CloudManagementOperation> purge(
    CloudPurgePreview preview,
    String requestId,
  );
  Future<List<CloudManagementOperation>> getOperations();
  Future<void> acknowledgeOperation(
    String operationId,
    int generation,
    String requestId,
  );
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
    return CloudIndexStatus.fromJson(_jsonObject(response, '获取云端索引状态失败'));
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
      objects.addAll(
        (json['objects'] as List? ?? const []).whereType<Map>().map(
          (item) => CloudIndexObject.fromJson(Map<String, dynamic>.from(item)),
        ),
      );
      if (json['hasMore'] != true) return objects;
      final next = json['nextAfter'] as String? ?? '';
      if (next.isEmpty || next == after) throw StateError('云端对象分页游标未前进');
      after = next;
    }
  }

  @override
  Future<CloudObjectDetail> getObject(String category, String objectId) async {
    final path =
        '/sync/index/objects/${Uri.encodeComponent(category)}/${Uri.encodeComponent(objectId)}';
    final response = await _client.get(path);
    return CloudObjectDetail.fromJson(_jsonObject(response, '获取云端对象详情失败'));
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
    return CloudPurgePreview.fromJson(
      _jsonObject(response, '生成清理预览失败'),
      selector,
    );
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
    return CloudManagementOperation.fromJson(
      Map<String, dynamic>.from(json['operation'] as Map),
    );
  }

  @override
  Future<List<CloudManagementOperation>> getOperations() async {
    final response = await _client.get('/sync/manage/operations');
    final json = _jsonObject(response, '获取云端待处理操作失败');
    return (json['operations'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => CloudManagementOperation.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> acknowledgeOperation(
    String operationId,
    int generation,
    String requestId,
  ) async {
    final response = await _postSignedJson(
      path: '/sync/manage/operations/${Uri.encodeComponent(operationId)}/ack',
      target: '/sync/manage/operations/:id/ack',
      requestId: requestId,
      body: {'requestId': requestId, 'expectedGeneration': generation},
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
      throw Exception(
        BackendClient.extractErrorMessage(response.body) ?? fallback,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const FormatException('云端数据响应不是 JSON object');
    return Map<String, dynamic>.from(decoded);
  }
}
