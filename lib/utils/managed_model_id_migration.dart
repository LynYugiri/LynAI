import '../providers/conversation_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/roleplay_provider.dart';
import '../providers/settings_provider.dart';
import '../services/backend_client.dart';

Future<void> _managedModelMigrationTail = Future.value();

Future<bool> syncManagedModelsAndApplyMigrations({
  required ModelConfigProvider models,
  required BackendClient backend,
  required SettingsProvider settings,
  required ConversationProvider conversations,
  required RoleplayProvider roleplay,
  required PluginProvider plugins,
}) => _serializeManagedModelMigration(() async {
  await _applyPendingManagedModelIdMigrations(
    models: models,
    settings: settings,
    conversations: conversations,
    roleplay: roleplay,
    plugins: plugins,
  );
  final synced = await models.syncLynaiManagedModels(backend);
  await _applyPendingManagedModelIdMigrations(
    models: models,
    settings: settings,
    conversations: conversations,
    roleplay: roleplay,
    plugins: plugins,
  );
  return synced;
});

Future<void> applyPendingManagedModelIdMigrations({
  required ModelConfigProvider models,
  required SettingsProvider settings,
  required ConversationProvider conversations,
  required RoleplayProvider roleplay,
  required PluginProvider plugins,
}) => _serializeManagedModelMigration(
  () => _applyPendingManagedModelIdMigrations(
    models: models,
    settings: settings,
    conversations: conversations,
    roleplay: roleplay,
    plugins: plugins,
  ),
);

Future<void> _applyPendingManagedModelIdMigrations({
  required ModelConfigProvider models,
  required SettingsProvider settings,
  required ConversationProvider conversations,
  required RoleplayProvider roleplay,
  required PluginProvider plugins,
}) async {
  final migrations = models.peekManagedModelIdMigrations();
  if (migrations.isEmpty) return;
  await settings.migrateModelIds(migrations);
  await conversations.migrateModelIds(migrations);
  await roleplay.migrateModelIds(migrations);
  await plugins.migrateModelIds(migrations);
  await models.ackManagedModelIdMigrations(migrations);
}

Future<T> _serializeManagedModelMigration<T>(Future<T> Function() action) {
  late T value;
  final operation = _managedModelMigrationTail.then((_) async {
    value = await action();
  });
  _managedModelMigrationTail = operation.catchError((Object _) {});
  return operation.then((_) => value);
}
