import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/sync_change.dart';
import 'backend_client.dart';
import 'device_identity_service.dart';
import 'device_registration_service.dart';

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
  Future<SyncDownloadResult> getChanges({required int since, int limit = 500});

  /// 列出用户已有的 blob。
  Future<List<BlobInfo>> listBlobs({int limit = 1000});

  /// 上传一个 blob（后端默认上限 64 MiB）。
  Future<void> uploadBlob(String sha256, List<int> bytes);

  /// 下载一个 blob。
  Future<List<int>> downloadBlob(String sha256);
}

/// 待上传的变更记录（客户端构造，尚未分配 seq）。
class SyncChangeRecord {
  final String changeId;
  final String deviceId;
  final DateTime clientCreatedAt;
  final int mutationVersion;
  final String table;
  final String op;
  final String recordId;
  final Map<String, dynamic>? data;

  const SyncChangeRecord({
    required this.changeId,
    required this.deviceId,
    required this.clientCreatedAt,
    required this.mutationVersion,
    required this.table,
    required this.op,
    required this.recordId,
    this.data,
  });

  Map<String, dynamic> toJson() => {
    'changeId': changeId,
    'deviceId': deviceId,
    'clientCreatedAt': clientCreatedAt.toUtc().toIso8601String(),
    'table': table,
    'op': op,
    'recordId': recordId,
    if (data != null) 'data': data,
  };
}

/// 连接真实后端的 [SyncService] 实现。
class RemoteSyncService implements SyncService {
  static const blobUploadTimeout = Duration(minutes: 2);
  static const _signatureDomain = 'LynAI/v1/sync-request\x00';

  final BackendClient _client;
  final DeviceIdentityService _identity;
  final DeviceRegistrationService _registration;

  /// 创建远端同步服务实例。
  RemoteSyncService(
    this._client, {
    required DeviceIdentityService identity,
    required DeviceRegistrationService registration,
  }) : _identity = identity,
       _registration = registration;

  @override
  Future<SyncStatus> getStatus() async {
    final resp = await _client.get('/sync/status');
    if (resp.statusCode != 200) {
      throw Exception(_errorMessage(resp.body, '获取同步状态失败'));
    }
    final json = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
    return SyncStatus(
      lastSeq: (json['lastSeq'] as num?)?.toInt() ?? 0,
      blobCount: (json['blobCount'] as num?)?.toInt() ?? 0,
      limits: SyncLimits.fromJson(json['limits']),
    );
  }

  @override
  Future<SyncUploadResult> uploadChanges(List<SyncChangeRecord> changes) async {
    final requestId = requestIdForChanges(changes);
    final body = {
      'requestId': requestId,
      'changes': changes.map((c) => c.toJson()).toList(),
    };
    final bodyBytes = utf8.encode(jsonEncode(body));
    final headers = await _signedHeaders(
      requestId: requestId,
      target: '/sync/changes',
      bodyBytes: bodyBytes,
    );
    final resp = await _client.postJsonBytes(
      '/sync/changes',
      headers: headers,
      bodyBytes: bodyBytes,
    );
    if (resp.statusCode != 200) {
      if (_isExplicitSignatureRejection(resp.body)) {
        throw Exception(_errorMessage(resp.body, '同步签名被拒绝'));
      }
      throw Exception(_errorMessage(resp.body, '上传变更失败'));
    }
    final json = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
    final responseChanges = json['changes'];
    final acknowledgedChangeIds =
        responseChanges is List &&
            responseChanges.every(
              (item) =>
                  item is Map &&
                  item['changeId'] is String &&
                  (item['changeId'] as String).isNotEmpty,
            )
        ? responseChanges
              .map((item) => (item as Map)['changeId'] as String)
              .toSet()
        : null;
    final acknowledgements = acknowledgedChangeIds == null
        ? null
        : changes
              .where(
                (change) => acknowledgedChangeIds.contains(change.changeId),
              )
              .map(
                (change) => SyncAcknowledgement(
                  changeId: change.changeId,
                  mutationVersion: change.mutationVersion,
                ),
              )
              .toList(growable: false);
    return SyncUploadResult(
      latestSeq: (json['latestSeq'] as num?)?.toInt() ?? 0,
      acknowledgements: acknowledgements,
    );
  }

  static String requestIdForChanges(List<SyncChangeRecord> changes) {
    final identity = changes
        .map(
          (change) =>
              '${change.changeId}:${change.clientCreatedAt.toUtc().toIso8601String()}',
        )
        .join('\n');
    return _base64Url(
      sha256.convert(utf8.encode(identity)).bytes.sublist(0, 24),
    );
  }

  static String requestIdForBlob(String hash) => _base64Url(
    sha256.convert(utf8.encode('blob\n$hash')).bytes.sublist(0, 24),
  );

  /// Builds the domain-separated CBE1 request signature input.
  static List<int> buildSyncRequestMessage({
    required int protocolVersion,
    required String userId,
    required String sessionId,
    required String deviceId,
    required String requestId,
    required int timestamp,
    required String method,
    required String target,
    required List<int> bodySha256,
  }) {
    final version = ByteData(2)..setUint16(0, protocolVersion);
    final timestampBytes = ByteData(8)..setUint64(0, timestamp);
    final fields = <List<int>>[
      version.buffer.asUint8List(),
      utf8.encode(userId),
      utf8.encode(sessionId),
      utf8.encode(deviceId),
      timestampBytes.buffer.asUint8List(),
      utf8.encode(requestId),
      utf8.encode(method),
      utf8.encode(target),
      bodySha256,
    ];
    final output = BytesBuilder(copy: false)
      ..add(utf8.encode(_signatureDomain));
    for (var index = 0; index < fields.length; index++) {
      final field = fields[index];
      final header = ByteData(6)
        ..setUint16(0, index + 1)
        ..setUint32(2, field.length);
      output
        ..add(header.buffer.asUint8List())
        ..add(field);
    }
    return output.takeBytes();
  }

  static String _base64Url(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll('=', '');

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  bool _isExplicitSignatureRejection(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return false;
      final values = <Object?>[
        decoded['code'],
        decoded['errorCode'],
        if (decoded['error'] is Map) (decoded['error'] as Map)['code'],
      ];
      if (values.any((value) => value != null)) {
        const codes = {
          'invalid_device_signature',
          'invalid_signature',
          'signature_rejected',
          'signature_required',
          'unknown_device',
          'revoked_device',
          'replayed_request',
        };
        if (values.any((value) => codes.contains(value?.toString()))) {
          return true;
        }
      }
      final message = BackendClient.extractErrorMessageFromDecoded(
        decoded,
      )?.toLowerCase();
      return message == 'device signature is required' ||
          message == 'invalid signed sync request' ||
          message == 'unknown or revoked device' ||
          message == 'request id conflicts with an existing request';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<SyncDownloadResult> getChanges({
    required int since,
    int limit = 500,
  }) async {
    final resp = await _client.get('/sync/changes?since=$since&limit=$limit');
    if (resp.statusCode != 200) {
      throw Exception(_errorMessage(resp.body, '获取变更失败'));
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
      hasMore: json['hasMore'] as bool? ?? false,
      nextSince:
          (json['nextSince'] as num?)?.toInt() ??
          (changes.isEmpty ? since : changes.last.seq),
    );
  }

  @override
  Future<List<BlobInfo>> listBlobs({int limit = 1000}) async {
    var after = 0;
    final blobs = <BlobInfo>[];
    while (true) {
      final path = '/sync/blobs?after=$after&limit=$limit';
      final resp = await _client.get(path);
      if (resp.statusCode != 200) {
        throw Exception(_errorMessage(resp.body, '获取 blob 列表失败'));
      }
      final json = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
      blobs.addAll(
        (json['blobs'] as List? ?? const []).map(
          (item) => BlobInfo.fromJson(Map<String, dynamic>.from(item as Map)),
        ),
      );
      final hasMore = json['hasMore'] as bool? ?? false;
      if (!hasMore) return blobs;
      final next = (json['nextAfter'] as num?)?.toInt();
      if (next == null || next <= after) {
        throw StateError('blob pagination did not advance');
      }
      after = next;
    }
  }

  @override
  Future<void> uploadBlob(String sha256, List<int> bytes) async {
    final requestId = requestIdForBlob(sha256);
    final headers = await _signedHeaders(
      requestId: requestId,
      target: '/sync/blobs/:sha256',
      bodyBytes: bytes,
      contentType: 'application/octet-stream',
    );
    final resp = await _client.postRaw(
      '/sync/blobs/$sha256',
      headers: headers,
      body: bytes,
      timeout: blobUploadTimeout,
    );
    if (resp.statusCode != 200) {
      if (_isExplicitSignatureRejection(resp.body)) {
        throw Exception(_errorMessage(resp.body, '同步签名被拒绝'));
      }
      throw Exception(_errorMessage(resp.body, '上传 blob 失败'));
    }
  }

  Future<Map<String, String>> _signedHeaders({
    required String requestId,
    required String target,
    required List<int> bodyBytes,
    String contentType = 'application/json',
  }) async {
    final claims = DeviceRegistrationService.accessTokenClaims(
      _client.accessToken,
    );
    if (claims == null) {
      throw StateError('access token claims are unavailable');
    }
    if (!await _registration.ensureEnrolled()) {
      throw StateError('device enrollment is required for sync');
    }
    final scope = DeviceIdentityService.accountScope(
      _client.backendUrl,
      claims.userId,
    );
    final identity = await _identity.initialize(scope: scope);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final bodyDigest = sha256.convert(bodyBytes).bytes;
    final message = buildSyncRequestMessage(
      protocolVersion: 1,
      userId: claims.userId,
      sessionId: claims.sessionId,
      deviceId: identity.deviceId,
      requestId: requestId,
      timestamp: timestamp,
      method: 'POST',
      target: target,
      bodySha256: bodyDigest,
    );
    return {
      'Content-Type': contentType,
      'X-LynAI-Protocol': '1',
      'X-LynAI-Device-ID': identity.deviceId,
      'X-LynAI-Request-ID': requestId,
      'X-LynAI-Timestamp': timestamp.toString(),
      'X-LynAI-Body-SHA256': _hex(bodyDigest),
      'X-LynAI-Signature': _base64Url(
        await _identity.sign(message, scope: scope),
      ),
    };
  }

  @override
  Future<List<int>> downloadBlob(String sha256) async {
    final resp = await _client.get('/sync/blobs/$sha256');
    if (resp.statusCode != 200) {
      throw Exception(_errorMessage(resp.body, '下载 blob 失败'));
    }
    return resp.bodyBytes;
  }

  String _errorMessage(String body, String fallback) {
    return BackendClient.extractErrorMessage(body) ?? fallback;
  }
}
