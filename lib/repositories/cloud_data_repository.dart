import '../models/cloud_data.dart';
import '../services/storage_v2_database.dart';
import '../services/storage_v2_service.dart';

abstract class CloudDataRepository {
  Future<CloudDataSnapshot> load(String scope);
  Future<void> replace(
    String scope,
    CloudIndexStatus status,
    List<CloudIndexObject> objects,
  );
  Future<void> saveOperations(
    String scope,
    Iterable<CloudManagementOperation> operations,
  );
  Future<List<CloudManagementOperation>> loadOperations(String scope);
  Future<void> removeOperation(String scope, String operationId);
  Future<void> reconcileOperations(
    String scope,
    Iterable<CloudManagementOperation> operations,
  );
  Future<String?> loadRequestId(String scope, String requestKey);
  Future<void> saveRequestId(String scope, String requestKey, String requestId);
  Future<void> removeRequestId(String scope, String requestKey);
  Future<void> requireFullReseed(String scope, int generation);
}

class StorageV2CloudDataRepository implements CloudDataRepository {
  StorageV2CloudDataRepository(this._storage);

  final StorageV2Service _storage;

  Future<StorageV2Database> get _database => _storage.storageDatabase();

  @override
  Future<CloudDataSnapshot> load(String scope) =>
      _database.then((db) => db.loadCloudData(scope));

  @override
  Future<void> replace(
    String scope,
    CloudIndexStatus status,
    List<CloudIndexObject> objects,
  ) => _database.then((db) => db.replaceCloudData(scope, status, objects));

  @override
  Future<void> saveOperations(
    String scope,
    Iterable<CloudManagementOperation> operations,
  ) => _database.then((db) => db.saveCloudOperations(scope, operations));

  @override
  Future<List<CloudManagementOperation>> loadOperations(String scope) =>
      _database.then((db) => db.loadCloudOperations(scope));

  @override
  Future<void> removeOperation(String scope, String operationId) =>
      _database.then((db) => db.removeCloudOperation(scope, operationId));

  @override
  Future<void> reconcileOperations(
    String scope,
    Iterable<CloudManagementOperation> operations,
  ) => _database.then((db) => db.reconcileCloudOperations(scope, operations));

  @override
  Future<String?> loadRequestId(String scope, String requestKey) =>
      _database.then((db) => db.loadCloudRequestId(scope, requestKey));

  @override
  Future<void> saveRequestId(
    String scope,
    String requestKey,
    String requestId,
  ) => _database.then(
    (db) => db.saveCloudRequestId(scope, requestKey, requestId),
  );

  @override
  Future<void> removeRequestId(String scope, String requestKey) =>
      _database.then((db) => db.removeCloudRequestId(scope, requestKey));

  @override
  Future<void> requireFullReseed(String scope, int generation) =>
      _database.then((db) => db.requireCloudReseed(scope, generation));
}
