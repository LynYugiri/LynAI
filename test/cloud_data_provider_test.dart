import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/account.dart';
import 'package:lynai/models/cloud_data.dart';
import 'package:lynai/providers/cloud_data_provider.dart';
import 'package:lynai/repositories/cloud_data_repository.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/cloud_data_service.dart';

void main() {
  test('refresh failure keeps the last successful cache', () async {
    final backend = BackendClient()..configure('https://example.com');
    addTearDown(backend.close);
    backend.setTokens('token', 'refresh');
    final repository = _MemoryCloudRepository();
    final service = _FakeCloudService();
    final provider = CloudDataProvider(
      backend: backend,
      repository: repository,
      service: service,
    );
    await provider.bind(_user);
    await provider.refresh();
    expect(provider.snapshot.objects.single.objectId, 'task-1');

    service.failStatus = true;
    await provider.refresh();

    expect(provider.error, isNotNull);
    expect(provider.snapshot.objects.single.objectId, 'task-1');
    expect(
      (await repository.load(
        'https://example.com|user-1',
      )).objects.single.objectId,
      'task-1',
    );
  });

  test('manual sync persists operation, requires reseed, then ACKs', () async {
    final backend = BackendClient()..configure('https://example.com');
    addTearDown(backend.close);
    backend.setTokens('token', 'refresh');
    final repository = _MemoryCloudRepository();
    final service = _FakeCloudService()
      ..operations = [
        CloudManagementOperation(
          id: 'op-1',
          kind: 'full',
          selectorType: 'all',
          generation: 4,
          indexRevision: 7,
          createdAt: DateTime.utc(2026, 7, 24),
        ),
      ];
    final provider = CloudDataProvider(
      backend: backend,
      repository: repository,
      service: service,
    );
    await provider.bind(_user);
    var synced = false;

    await provider.syncNow(() async {
      synced = true;
      return true;
    }, (_, _) async => true);

    expect(synced, isTrue);
    expect(repository.requiredGeneration, 4);
    expect(service.acked, ['op-1']);
    expect(provider.operations, isEmpty);
  });

  test('stale refresh cannot overwrite a newly bound account', () async {
    final backend = BackendClient()..configure('https://example.com');
    addTearDown(backend.close);
    backend.setTokens('token', 'refresh');
    final service = _FakeCloudService();
    final provider = CloudDataProvider(
      backend: backend,
      repository: _MemoryCloudRepository(),
      service: service,
    );
    await provider.bind(_user);
    final gate = service.blockStatus();
    final refresh = provider.refresh();
    await Future<void>.delayed(Duration.zero);
    await provider.bind(
      const AccountUser(
        id: 'user-2',
        phone: '13200000000',
        displayName: 'Other',
      ),
    );
    gate.complete();
    await refresh;

    expect(provider.user?.id, 'user-2');
    expect(provider.snapshot.status, isNull);
  });

  test('lost ACK retry reuses durable request id', () async {
    final backend = BackendClient()..configure('https://example.com');
    addTearDown(backend.close);
    backend.setTokens('token', 'refresh');
    final operation = CloudManagementOperation(
      id: 'op-lost-ack',
      kind: 'full',
      selectorType: 'all',
      generation: 2,
      indexRevision: 3,
      createdAt: DateTime.utc(2026, 7, 24),
    );
    final service = _FakeCloudService()
      ..operations = [operation]
      ..loseFirstAck = true;
    final provider = CloudDataProvider(
      backend: backend,
      repository: _MemoryCloudRepository(),
      service: service,
    );
    await provider.bind(_user);

    await provider.syncNow(() async => true, (_, _) async => true);
    await provider.syncNow(() async => true, (_, _) async => true);

    expect(service.ackRequestIds, hasLength(2));
    expect(service.ackRequestIds.toSet(), hasLength(1));
    expect(provider.operations, isEmpty);
  });
}

const _user = AccountUser(
  id: 'user-1',
  phone: '13100000000',
  displayName: 'Tester',
);

class _MemoryCloudRepository implements CloudDataRepository {
  final snapshots = <String, CloudDataSnapshot>{};
  final tasks = <String, List<CloudManagementOperation>>{};
  int? requiredGeneration;

  @override
  Future<CloudDataSnapshot> load(String scope) async =>
      snapshots[scope] ?? const CloudDataSnapshot();

  @override
  Future<List<CloudManagementOperation>> loadOperations(String scope) async =>
      List.of(tasks[scope] ?? const []);

  @override
  Future<void> removeOperation(String scope, String operationId) async {
    tasks[scope]?.removeWhere((item) => item.id == operationId);
  }

  @override
  Future<void> reconcileOperations(
    String scope,
    Iterable<CloudManagementOperation> operations,
  ) async {
    tasks[scope] = List.of(operations);
  }

  final requestIds = <String, String>{};

  @override
  Future<String?> loadRequestId(String scope, String requestKey) async =>
      requestIds['$scope|$requestKey'];

  @override
  Future<void> saveRequestId(
    String scope,
    String requestKey,
    String requestId,
  ) async => requestIds['$scope|$requestKey'] = requestId;

  @override
  Future<void> removeRequestId(String scope, String requestKey) async =>
      requestIds.remove('$scope|$requestKey');

  @override
  Future<void> replace(
    String scope,
    CloudIndexStatus status,
    List<CloudIndexObject> objects,
  ) async {
    snapshots[scope] = CloudDataSnapshot(
      status: status,
      objects: List.of(objects),
      categoryCounts: {
        for (final category in cloudDataCategories)
          category: objects.where((item) => item.category == category).length,
      },
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> requireFullReseed(String scope, int generation) async {
    requiredGeneration = generation;
  }

  @override
  Future<void> saveOperations(
    String scope,
    Iterable<CloudManagementOperation> operations,
  ) async {
    final byId = {
      for (final item in tasks[scope] ?? const <CloudManagementOperation>[])
        item.id: item,
    };
    for (final operation in operations) {
      byId[operation.id] = operation;
    }
    tasks[scope] = byId.values.toList();
  }
}

class _FakeCloudService implements CloudDataService {
  bool failStatus = false;
  List<CloudManagementOperation> operations = const [];
  final acked = <String>[];
  final ackRequestIds = <String>[];
  bool loseFirstAck = false;
  Completer<void>? _statusGate;

  Completer<void> blockStatus() => _statusGate = Completer<void>();

  @override
  Future<void> acknowledgeOperation(
    String operationId,
    int generation,
    String requestId,
  ) async {
    ackRequestIds.add(requestId);
    if (loseFirstAck && ackRequestIds.length == 1) {
      throw StateError('response lost');
    }
    acked.add(operationId);
  }

  @override
  Future<CloudObjectDetail> getObject(String category, String objectId) async =>
      throw UnimplementedError();

  @override
  Future<List<CloudManagementOperation>> getOperations() async =>
      operations.where((item) => !acked.contains(item.id)).toList();

  @override
  Future<CloudIndexStatus> getStatus() async {
    await _statusGate?.future;
    if (failStatus) throw StateError('offline');
    return const CloudIndexStatus(
      lastSeq: 1,
      generation: 1,
      indexRevision: 1,
      minAvailableSeq: 0,
      usage: CloudUsage(
        recordCount: 1,
        blobCount: 0,
        blobBytes: 0,
        blobRefCount: 0,
      ),
    );
  }

  @override
  Future<List<CloudIndexObject>> listObjects(
    String category,
    int revision,
  ) async => category == 'tasks'
      ? [
          CloudIndexObject(
            category: 'tasks',
            objectId: 'task-1',
            recordCount: 1,
            blobRefCount: 0,
            latestSeq: 1,
            updatedAt: DateTime.utc(2026, 7, 24),
          ),
        ]
      : const [];

  @override
  Future<CloudPurgePreview> previewPurge(
    CloudPurgeSelector selector,
    int revision,
  ) async => throw UnimplementedError();

  @override
  Future<CloudManagementOperation> purge(
    CloudPurgePreview preview,
    String requestId,
  ) async => throw UnimplementedError();
}
