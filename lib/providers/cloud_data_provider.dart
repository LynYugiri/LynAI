import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../models/cloud_data.dart';
import '../repositories/cloud_data_repository.dart';
import '../services/backend_client.dart';
import '../services/cloud_data_service.dart';

class CloudDataProvider extends ChangeNotifier {
  CloudDataProvider({
    required BackendClient backend,
    required CloudDataRepository repository,
    required CloudDataService service,
  }) : _backend = backend,
       _repository = repository,
       _service = service;

  final BackendClient _backend;
  final CloudDataRepository _repository;
  final CloudDataService _service;

  AccountUser? _user;
  String? _scope;
  CloudDataSnapshot _snapshot = const CloudDataSnapshot();
  List<CloudManagementOperation> _operations = const [];
  bool _loading = false;
  String? _error;
  int _generation = 0;

  AccountUser? get user => _user;
  CloudDataSnapshot get snapshot => _snapshot;
  List<CloudManagementOperation> get operations => _operations;
  bool get loading => _loading;
  String? get error => _error;
  bool get canManage =>
      _scope != null && (_backend.accessToken ?? '').isNotEmpty;

  Future<void> bind(AccountUser? user) async {
    final token = ++_generation;
    final scope = user == null ? null : '${_backend.backendOrigin}|${user.id}';
    _user = user;
    _scope = scope;
    _snapshot = const CloudDataSnapshot();
    _operations = const [];
    _error = null;
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

  Future<void> refresh() => _run((token, scope) => _refresh(token, scope));

  Future<void> _refresh(int token, String scope) async {
    final status = await _service.getStatus();
    if (!_isCurrent(token, scope)) return;
    final groups = await Future.wait(
      cloudDataCategories.map(
        (category) => _service.listObjects(category, status.indexRevision),
      ),
    );
    if (!_isCurrent(token, scope)) return;
    final objects = groups.expand((items) => items).toList(growable: false);
    final operations = await _service.getOperations();
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
    if (scope == null) return null;
    try {
      final detail = await _service.getObject(object.category, object.objectId);
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
    if (scope == null || revision == null) return null;
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
    final remote = await _service.getOperations();
    if (!_isCurrent(token, scope)) return;
    await _repository.reconcileOperations(scope, remote);
    if (!_isCurrent(token, scope)) return;
    _operations = await _repository.loadOperations(scope);
    if (!_isCurrent(token, scope)) return;
    if (_operations.isNotEmpty) {
      final generation = _operations
          .map((item) => item.generation)
          .reduce((a, b) => a > b ? a : b);
      await _repository.requireFullReseed(scope, generation);
    }
    if (!_isCurrent(token, scope) || !await synchronize()) {
      throw StateError('云同步未成功完成');
    }
    if (!_isCurrent(token, scope)) return;
    for (final operation in List<CloudManagementOperation>.of(_operations)) {
      if (!await canAcknowledge(scope, operation.generation) ||
          !_isCurrent(token, scope)) {
        throw StateError('同步 scope 或 generation 已变化，未确认云端操作');
      }
      final requestKey = 'ack:${operation.id}';
      var requestId = await _repository.loadRequestId(scope, requestKey);
      if (!_isCurrent(token, scope)) return;
      requestId ??= RemoteCloudDataService.newRequestId();
      await _repository.saveRequestId(scope, requestKey, requestId);
      await _service.acknowledgeOperation(
        operation.id,
        operation.generation,
        requestId,
      );
      if (!_isCurrent(token, scope)) return;
      await _repository.removeOperation(scope, operation.id);
      await _repository.removeRequestId(scope, requestKey);
    }
    if (!_isCurrent(token, scope)) return;
    _operations = const [];
    await _refresh(token, scope);
  });

  Future<void> _run(
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
