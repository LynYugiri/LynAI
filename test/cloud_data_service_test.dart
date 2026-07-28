import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lynai/models/cloud_data.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/cloud_data_service.dart';
import 'package:lynai/models/sync_change.dart';

void main() {
  test('loads status and paginated objects', () async {
    final backend = _CloudBackendClient();
    final service = RemoteCloudDataService.withSignedPost(
      backend,
      ({
        required path,
        required target,
        required requestId,
        required body,
      }) async => http.Response('{}', 200),
    );

    final status = await service.getStatus();
    final objects = await service.listObjects('notes', status.indexRevision);
    final detail = await service.getObject(
      'notes',
      'note-1',
      status.indexRevision,
    );

    expect(status.usage.blobBytes, 1024);
    expect(objects.map((item) => item.objectId), ['note-1', 'note-2']);
    expect(detail.indexRevision, status.indexRevision);
    expect(
      backend.getPaths.where((path) => path.startsWith('/sync/index/objects?')),
      hasLength(2),
    );
  });

  test('signed purge and ACK use canonical management targets', () async {
    final calls = <({String path, String target, Map<String, dynamic> body})>[];
    final service = RemoteCloudDataService.withSignedPost(
      _CloudBackendClient(),
      ({
        required path,
        required target,
        required requestId,
        required body,
      }) async {
        calls.add((path: path, target: target, body: body));
        return http.Response(
          path.endsWith('/ack')
              ? '{}'
              : '{"operation":{"id":"op-1","kind":"selective","selectorType":"category","category":"notes","generation":1,"indexRevision":3,"createdAt":"2026-07-24T00:00:00Z"}}',
          200,
        );
      },
    );

    final operation = await service.purge(
      const CloudPurgePreview(
        selector: CloudPurgeSelector.category('notes'),
        generation: 1,
        indexRevision: 2,
        recordCount: 1,
        changeCount: 1,
        blobRefCount: 0,
        releasedBlobCandidates: 0,
      ),
      'purge-request-id-00000000000000',
    );
    await service.acknowledgeOperation(
      operation.id,
      operation.generation,
      'ack-request-id-000000000000000',
      includeOperationId: true,
    );

    expect(calls[0].target, '/sync/manage/purge');
    expect(calls[0].body['requestId'], isNotEmpty);
    expect(calls[1].target, '/sync/manage/operations/:id/ack');
    expect(calls[1].path, '/sync/manage/operations/op-1/ack');
    expect(calls[1].body['operationId'], 'op-1');
  });

  test('rejects malformed advertised capability values', () async {
    final service = RemoteCloudDataService.withSignedPost(
      _MalformedCapabilityBackendClient(),
      ({
        required path,
        required target,
        required requestId,
        required body,
      }) async => http.Response('{}', 200),
    );

    await expectLater(service.getStatus(), throwsFormatException);
    expect(
      () => SyncCapabilities.fromJson({'index': 1}),
      throwsFormatException,
    );
  });
}

class _CloudBackendClient extends BackendClient {
  final getPaths = <String>[];

  @override
  Future<http.Response> get(String path, {Map<String, String>? headers}) async {
    getPaths.add(path);
    if (path == '/sync/index/status') {
      return http.Response(
        '{"lastSeq":2,"generation":1,"indexRevision":2,"minAvailableSeq":0,"usage":{"recordCount":2,"blobCount":1,"blobBytes":1024,"blobRefCount":1}}',
        200,
      );
    }
    if (path.startsWith('/sync/index/objects/notes/note-1?')) {
      return http.Response(
        '{"category":"notes","objectId":"note-1","recordCount":1,'
        '"blobRefCount":0,"latestSeq":1,"updatedAt":"2026-07-24T00:00:00Z",'
        '"indexRevision":2,"records":[{"table":"notes","op":"upsert",'
        '"recordId":"note-1","data":{"id":"note-1"}}]}',
        200,
      );
    }
    if (path.contains('after=')) {
      return http.Response(
        '{"objects":[{"category":"notes","objectId":"note-2","recordCount":1,"blobRefCount":0,"latestSeq":2,"updatedAt":"2026-07-24T00:00:00Z"}],"indexRevision":2,"hasMore":false}',
        200,
      );
    }
    return http.Response(
      '{"objects":[{"category":"notes","objectId":"note-1","recordCount":1,"blobRefCount":1,"latestSeq":1,"updatedAt":"2026-07-24T00:00:00Z"}],"indexRevision":2,"nextAfter":"cursor","hasMore":true}',
      200,
    );
  }
}

class _MalformedCapabilityBackendClient extends BackendClient {
  @override
  Future<http.Response> get(
    String path, {
    Map<String, String>? headers,
  }) async => http.Response(
    '{"lastSeq":0,"generation":1,"indexRevision":0,'
    '"minAvailableSeq":0,"usage":{"recordCount":0,"blobCount":0,'
    '"blobBytes":0,"blobRefCount":0},"capabilities":{"index":1}}',
    200,
  );
}
