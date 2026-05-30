import 'package:shared_preferences/shared_preferences.dart';

import '../services/storage_migration_service.dart';
import '../services/storage_v2_service.dart';

class AppStorageStateRepository {
  AppStorageStateRepository({StorageV2Service? storageV2})
    : _storageV2 = storageV2 ?? StorageV2Service();

  final StorageV2Service _storageV2;

  Future<bool> isStorageV2Active() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt('storage_schema_version') ?? 1) >=
            StorageMigrationService.currentSchemaVersion &&
        await _storageV2.exists();
  }
}
