import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../models/cloud_data.dart';
import '../repositories/cloud_data_repository.dart';
import '../services/backend_client.dart';
import '../services/cloud_data_service.dart';
import '../services/cloud_management_coordinator.dart';
import '../services/dataset_runtime_barrier.dart';

class CloudDataProvider extends ChangeNotifier {
  CloudDataProvider({
    required BackendClient backend,
    required CloudDataRepository repository,
    required CloudDataService service,
    CloudManagementOperations? management,
    DatasetRuntimeBarrier? datasetBarrier,
  }) : _backend = backend,
       _repository = repository,
       _service = service,
       _management =
           management ??
           CloudManagementCoordinator(repository: repository, service: service),
       _datasetBarrier = datasetBarrier;

  final BackendClient _backend;
  final CloudDataRepository _repository;
  final CloudDataService _service;
  final CloudManagementOperations _management;
  final DatasetRuntimeBarrier? _datasetBarrier;

  AccountUser? _user;
  String? _scope;
  CloudDataSnapshot _snapshot = const CloudDataSnapshot();
  List<CloudManagementOperation> _operations = const [];
  bool _loading = false;
  Future<void>? _activeOperation;
  String? _error;
  int _generation = 0;

  AccountUser? get user => _user;
  CloudDataSnapshot get snapshot => _snapshot;
  List<CloudManagementOperation> get operations => _operations;
  bool get loading => _loading;
  String? get error => _error;
  bool get canManage =>
      _scope != null && (_backend.accessToken ?? '').isNotEmpty;
  bool get canBrowse =>
      canManage && (_snapshot.status?.capabilities.index ?? false);
  bool get canSelectivePurge =>
      canManage && (_snapshot.status?.capabilities.selectivePurge ?? false);
  bool get canFullPurge =>
      canManage && (_snapshot.status?.capabilities.fullPurge ?? false);
  bool get canAcknowledgeOperations =>
      canManage && (_snapshot.status?.capabilities.operationAck ?? false);

  Future<void> bind(AccountUser? user) async {
    final token = ++_generation;
    final scope = user == null ? null : '${_backend.backendOrigin}|${user.id}';
    _user = user;
    _scope = scope;
    _snapshot = const CloudDataSnapshot();
    _operations = const [];
    _error = null;
    _loading = false;
    notifyListeners();
    if (scope == null) return;
    try {
      final values = await Future.wait<Object>([
        _repository.load(scope),
        _repository.loadOperations(scope),
      ]);
      if (!_isCurrent(token, scope)) return;
      _snapshot = values[0] as CloudDataSnapshot;
      _operations = values[1] as List<CloudManagementOperation>;
    } catch (e) {
      if (!_isCurrent(token, scope)) return;
      _snapshot = const CloudDataSnapshot();
      _operations = const [];
      _error = e.toString();
    }
    if (_isCurrent(token, scope)) notifyListeners();
  }

  Future<void> quiesceForDatasetSwitch() async {
    _generation++;
    _loading = false;
    notifyListeners();
    await _activeOperation;
  }

  Future<void> refresh() => _run((token, scope) => _refresh(token, scope));

  Future<void> _refresh(int token, String scope) async {
    final status = await _service.getStatus();
    if (!_isCurrent(token, scope)) return;
    final groups = status.capabilities.index
        ? await Future.wait(
            cloudDataCategories.map(
              (category) =>
                  _service.listObjects(category, status.indexRevision),
            ),
          )
        : const <List<CloudIndexObject>>[];
    if (!_isCurrent(token, scope)) return;
    final objects = groups.expand((items) => items).toList(growable: false);
    final operations = status.capabilities.operationAck
        ? await _service.getOperations()
        : await _repository.loadOperations(scope);
    if (!_isCurrent(token, scope)) return;
    await _repository.replace(scope, status, objects);
    await _repository.reconcileOperations(scope, operations);
    if (!_isCurrent(token, scope)) return;
    _operations = await _repository.loadOperations(scope);
    if (!_isCurrent(token, scope)) return;
    _snapshot = CloudDataSnapshot(
      status: status,
      objects: objects,
      categoryCounts: {
        for (final category in cloudDataCategories)
          category: objects.where((item) => item.category == category).length,
      },
      updatedAt: DateTime.now(),
    );
  }

  Future<CloudObjectDetail?> loadDetail(CloudIndexObject object) async {
    final token = _generation;
    final scope = _scope;
    if (scope == null || !canBrowse) return null;
    try {
      final revision = _snapshot.status?.indexRevision;
      if (revision == null) return null;
      final detail = await _service.getObject(
        object.category,
        object.objectId,
        revision,
      );
      if (!_isCurrent(token, scope)) return null;
      _error = null;
      return detail;
    } catch (e) {
      if (_isCurrent(token, scope)) {
        _error = e.toString();
        notifyListeners();
      }
      return null;
    }
  }

  Future<CloudPurgePreview?> preview(CloudPurgeSelector selector) async {
    final token = _generation;
    final scope = _scope;
    final revision = _snapshot.status?.indexRevision;
    final supported = selector.type == CloudPurgeType.all
        ? canFullPurge
        : canSelectivePurge;
    if (scope == null || revision == null || !supported) return null;
    try {
      final result = await _service.previewPurge(selector, revision);
      if (!_isCurrent(token, scope)) return null;
      _error = null;
      return result;
    } catch (e) {
      if (_isCurrent(token, scope)) {
        _error = e.toString();
        notifyListeners();
      }
      return null;
    }
  }

  Future<bool> purge(CloudPurgePreview preview) async {
    final supported = preview.selector.type == CloudPurgeType.all
        ? canFullPurge
        : canSelectivePurge;
    if (!supported) return false;
    var succeeded = false;
    await _run((token, scope) async {
      final requestKey =
          'purge:${preview.generation}:${preview.indexRevision}:${preview.selector.toJson()}';
      var requestId = await _repository.loadRequestId(scope, requestKey);
      if (!_isCurrent(token, scope)) return;
      requestId ??= RemoteCloudDataService.newRequestId();
      await _repository.saveRequestId(scope, requestKey, requestId);
      if (!_isCurrent(token, scope)) return;
      final operation = await _service.purge(preview, requestId);
      if (!_isCurrent(token, scope)) return;
      await _repository.saveOperations(scope, [operation]);
      await _repository.removeRequestId(scope, requestKey);
      if (!_isCurrent(token, scope)) return;
      _operations = await _repository.loadOperations(scope);
      succeeded = _isCurrent(token, scope);
    });
    return succeeded;
  }

  Future<void> syncNow(
    Future<bool> Function() synchronize,
    Future<bool> Function(String scope, int generation) canAcknowledge,
  ) => _run((token, scope) async {
    final status = await _service.getStatus();
    if (!_isCurrent(token, scope)) return;
    _operations = await _management.discover(
      scope,
      remoteSupported: status.capabilities.operationAck,
    );
    if (!_isCurrent(token, scope) || !await synchronize()) {
      throw StateError('云同步未成功完成');
    }
    if (!_isCurrent(token, scope)) return;
    await _management.acknowledge(
      scope,
      _operations,
      operationAckSupported: status.capabilities.operationAck,
      canAcknowledge: (operation) async =>
          _isCurrent(token, scope) &&
          await canAcknowledge(scope, operation.generation),
    );
    if (!_isCurrent(token, scope)) return;
    _operations = await _repository.loadOperations(scope);
    await _refresh(token, scope);
  });

  Future<void> _run(Future<void> Function(int token, String scope) action) {
    if (_loading) return Future.value();
    final operation =
        _datasetBarrier?.runExisting((_) => _runOpen(action)) ??
        _runOpen(action);
    _activeOperation = operation;
    return operation.whenComplete(() {
      if (identical(_activeOperation, operation)) _activeOperation = null;
    });
  }

  Future<void> _runOpen(
    Future<void> Function(int token, String scope) action,
  ) async {
    if (_loading) return;
    final token = _generation;
    final scope = _scope;
    if (scope == null) {
      _error = '请先登录并连接服务端';
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await action(token, scope);
    } catch (e) {
      if (_isCurrent(token, scope)) _error = e.toString();
    } finally {
      if (_isCurrent(token, scope)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrent(int token, String scope) =>
      token == _generation && scope == _scope;
}
