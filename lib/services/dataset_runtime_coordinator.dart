import '../models/account.dart';
import '../providers/calendar_provider.dart';
import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/knowledge_provider.dart';
import '../providers/memory_card_provider.dart';
import '../providers/mcp_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/recycle_bin_provider.dart';
import '../providers/roleplay_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/task_provider.dart';
import '../repositories/agent_persistence_repository.dart';
import '../utils/flush_tasks.dart';
import 'backend_client.dart';
import 'storage_v2_service.dart';
import 'storage_v2_upgrade_service.dart';
import 'calendar_platform_projection_coordinator.dart';

class DatasetRuntimeCoordinator {
  DatasetRuntimeCoordinator({
    required this.storage,
    required this.backend,
    required this.conversations,
    required this.features,
    required this.calendar,
    required this.roleplay,
    required this.tasks,
    required this.knowledge,
    required this.memoryCards,
    required this.recycleBin,
    required this.settings,
    required this.models,
    required this.plugins,
    this.mcp,
    this.calendarProjection,
    this.quiesceOperations,
    this.resumeOperations,
  });

  final StorageV2Service storage;
  final BackendClient backend;
  final ConversationProvider conversations;
  final FeatureProvider features;
  final CalendarProvider calendar;
  final RoleplayProvider roleplay;
  final TaskProvider tasks;
  final KnowledgeProvider knowledge;
  final MemoryCardProvider memoryCards;
  final RecycleBinProvider recycleBin;
  final SettingsProvider settings;
  final ModelConfigProvider models;
  final PluginProvider plugins;
  final McpProvider? mcp;
  final CalendarPlatformProjectionCoordinator? calendarProjection;
  final Future<void> Function()? quiesceOperations;
  final Future<void> Function()? resumeOperations;
  Future<void> _tail = Future.value();

  Future<void> activate(AccountUser? user) {
    final operation = _tail.then((_) => _activate(user));
    _tail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _activate(AccountUser? user) async {
    final previous = storage.activeDataset;
    await storage.runtimeBarrier.quiesce();
    try {
      await quiesceOperations?.call();
      await mcp?.quiesceForDatasetSwitch();
      await storage.quiesceResourceMutations();
      await _flush();
      await calendarProjection?.quiesce();
      if (user == null) {
        await storage.activateLocalDataset();
      } else {
        await storage.activateAccountDataset(
          backendUrl: backend.backendOrigin,
          userId: user.id,
        );
      }
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      await _reload();
      await calendarProjection?.syncAfterPersistence();
    } catch (_) {
      await storage.activateDataset(previous);
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      await _reload();
      await calendarProjection?.syncAfterPersistence();
      rethrow;
    } finally {
      storage.runtimeBarrier.reopen();
      await resumeOperations?.call();
    }
  }

  Future<void> _flush() async {
    await flushAllTasks([
      (name: 'conversations', flush: conversations.flushPendingSaves),
      (name: 'features', flush: features.flushPendingSaves),
      (name: 'calendar', flush: calendar.flushPendingSaves),
      (name: 'roleplay', flush: roleplay.flushPendingSaves),
      (name: 'tasks', flush: tasks.flushPendingSaves),
      (name: 'knowledge', flush: knowledge.flushPendingSaves),
      (name: 'memoryCards', flush: memoryCards.flushPendingSaves),
      (name: 'settings', flush: settings.flushPendingSaves),
      (name: 'models', flush: models.flushPendingSaves),
    ]);
    await plugins.syncAllPluginsForDatasetSwitch();
  }

  Future<void> _reload() async {
    await settings.loadSettings();
    await conversations.loadConversations();
    await features.load();
    await calendar.load();
    await roleplay.loadSessions();
    await tasks.load();
    await knowledge.load();
    await memoryCards.load();
    await recycleBin.load();
    await models.loadModels();
    await plugins.loadForDatasetSwitch();
    await mcp?.load();
    await AgentPersistenceRepository(storage).reconcileAfterRestart();
  }
}
