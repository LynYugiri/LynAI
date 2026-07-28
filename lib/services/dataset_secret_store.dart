import 'secret_store.dart';
import 'storage_v2_service.dart';

class DatasetSecretStore implements SecretStore {
  DatasetSecretStore(this._storage, this._delegate);

  final StorageV2Service _storage;
  final SecretStore _delegate;

  String _key(String key) =>
      'dataset.${_storage.activeDatasetId}.${Uri.encodeComponent(key)}';

  @override
  Future<String?> read(String key) async {
    final scopedKey = _key(key);
    final value = await _delegate.read(scopedKey);
    if (value != null || _storage.activeDatasetId != 'local') return value;
    final legacy = await _delegate.read(key);
    if (legacy != null) await _delegate.write(scopedKey, legacy);
    return legacy;
  }

  @override
  Future<void> write(String key, String value) =>
      _delegate.write(_key(key), value);

  @override
  Future<void> delete(String key) async {
    await _delegate.delete(_key(key));
    if (_storage.activeDatasetId == 'local') await _delegate.delete(key);
  }
}
