import 'dart:convert';

import '../models/sync_change.dart';
import 'backend_client.dart';

/// 数据同步服务抽象。
///
/// 定义增量同步的 upload/download/status 以及 blob 同步能力。
/// 前端页面只依赖这个抽象，后端就绪后用 [RemoteSyncService] 实现。
abstract class SyncService {
  /// 获取同步状态（最新 seq + blob 数量）。
  Future<SyncStatus> getStatus();

  /// 批量上传变更记录，返回分配的 seq。
  Future<SyncUploadResult> uploadChanges(List<SyncChangeRecord> changes);

  /// 获取指定 seq 之后的增量变更。
  Future<SyncDownloadResult> getChanges({required int since});

  /// 列出用户已有的 blob。
  Future<List<BlobInfo>> listBlobs();

  /// 上传一个 blob（<1MB）。
  Future<void> uploadBlob(String sha256, List<int> bytes);

  /// 下载一个 blob。
  Future<List<int>> downloadBlob(String sha256);
}

/// 待上传的变更记录（客户端构造，尚未分配 seq）。
class SyncChangeRecord {
  final String table;
  final String op;
  final String recordId;
  final Map<String, dynamic>? data;

  const SyncChangeRecord({
    required this.table,
    required this.op,
    required this.recordId,
    this.data,
  });

  Map<String, dynamic> toJson() => {
    'table': table,
    'op': op,
    'recordId': recordId,
    if (data != null) 'data': data,
  };
}

/// 连接真实后端的 [SyncService] 实现。
class RemoteSyncService implements SyncService {
  final BackendClient _client;

  /// 创建远端同步服务实例。
  RemoteSyncService(this._client);

  @override
  Future<SyncStatus> getStatus() async {
    final resp = await _client.get('/sync/status');
    if (resp.statusCode != 200) {
      throw Exception('获取同步状态失败');
    }
    final json = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
    return SyncStatus(
      lastSeq: (json['lastSeq'] as num?)?.toInt() ?? 0,
      blobCount: (json['blobCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<SyncUploadResult> uploadChanges(List<SyncChangeRecord> changes) async {
    final body = {'changes': changes.map((c) => c.toJson()).toList()};
    final resp = await _client.post('/sync/changes', body: body);
    if (resp.statusCode != 200) {
      throw Exception('上传变更失败');
    }
    final json = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
    return SyncUploadResult(
      latestSeq: (json['latestSeq'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<SyncDownloadResult> getChanges({required int since}) async {
    final resp = await _client.get('/sync/changes?since=$since');
    if (resp.statusCode != 200) {
      throw Exception('获取变更失败');
    }
    final json = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
    final changes = (json['changes'] as List? ?? const [])
        .map(
          (item) => SyncChange.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
    return SyncDownloadResult(
      changes: changes,
      latestSeq: (json['latestSeq'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<List<BlobInfo>> listBlobs() async {
    final resp = await _client.get('/sync/blobs');
    if (resp.statusCode != 200) {
      throw Exception('获取 blob 列表失败');
    }
    final json = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
    return (json['blobs'] as List? ?? const [])
        .map(
          (item) => BlobInfo.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
  }

  @override
  Future<void> uploadBlob(String sha256, List<int> bytes) async {
    final resp = await _client.postRaw(
      '/sync/blobs/$sha256',
      headers: {'Content-Type': 'application/octet-stream'},
      body: bytes,
    );
    if (resp.statusCode != 200) {
      throw Exception('上传 blob 失败');
    }
  }

  @override
  Future<List<int>> downloadBlob(String sha256) async {
    final resp = await _client.get('/sync/blobs/$sha256');
    if (resp.statusCode != 200) {
      throw Exception('下载 blob 失败');
    }
    return resp.bodyBytes;
  }
}
