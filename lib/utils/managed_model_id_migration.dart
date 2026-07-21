import '../providers/conversation_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/roleplay_provider.dart';
import '../providers/settings_provider.dart';
import '../services/backend_client.dart';

Future<bool> syncManagedModelsAndApplyMigrations({
  required ModelConfigProvider models,
  required BackendClient backend,
  required SettingsProvider settings,
  required ConversationProvider conversations,
  required RoleplayProvider roleplay,
  required PluginProvider plugins,
}) async {
  await applyPendingManagedModelIdMigrations(
    models: models,
    settings: settings,
    conversations: conversations,
    roleplay: roleplay,
    plugins: plugins,
  );
  final synced = await models.syncLynaiManagedProvider(backend);
  await applyPendingManagedModelIdMigrations(
    models: models,
    settings: settings,
    conversations: conversations,
    roleplay: roleplay,
    plugins: plugins,
  );
  return synced;
}

Future<void> applyPendingManagedModelIdMigrations({
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
