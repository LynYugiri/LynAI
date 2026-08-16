import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'providers/conversation_provider.dart';
import 'providers/calendar_provider.dart';
import 'providers/feature_provider.dart';
import 'providers/knowledge_provider.dart';
import 'providers/memory_card_provider.dart';
import 'providers/model_config_provider.dart';
import 'providers/mcp_provider.dart';
import 'providers/plugin_provider.dart';
import 'providers/account_provider.dart';
import 'providers/cloud_data_provider.dart';
import 'providers/recycle_bin_provider.dart';
import 'providers/roleplay_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/task_provider.dart';
import 'repositories/plugin_repository.dart';
import 'repositories/cloud_data_repository.dart';
import 'repositories/agent_persistence_repository.dart';
import 'repositories/mcp_repository.dart';
import 'pages/home_page.dart';
import 'pages/changelog_page.dart';
import 'services/floating_assistant_service.dart';
import 'services/storage_v2_upgrade_service.dart';
import 'services/backend_client.dart';
import 'services/calendar_platform_bridge.dart';
import 'services/calendar_platform_projection_coordinator.dart';
import 'services/device_identity_service.dart';
import 'services/device_registration_service.dart';
import 'services/secret_store.dart';
import 'services/server_capabilities_service.dart';
import 'services/dataset_secret_store.dart';
import 'services/dataset_runtime_coordinator.dart';
import 'services/dataset_runtime_barrier.dart';
import 'services/device_settings_service.dart';
import 'services/agent_tool_registry.dart';
import 'services/agent_persistence_lifecycle.dart';
import 'services/agent_tool_result_sanitizer.dart';
import 'services/agent_tool_execution_service.dart';
import 'services/web_search_service.dart';
import 'services/mcp/mcp_connection_factory.dart';
import 'services/storage_v2_service.dart';
import 'services/cloud_data_service.dart';
import 'services/cloud_management_coordinator.dart';
import 'services/sync_service.dart';
import 'providers/sync_provider.dart';
import 'providers/lan_sync_provider.dart';
import 'repositories/lan_peer_repository.dart';
import 'services/lan_mdns_service.dart';
import 'services/lan_device_profile_service.dart';
import 'services/lan_sync_coordinator.dart';
import 'services/lan_sync_storage.dart';
import 'services/lan_tls_certificate_service.dart';
import 'services/lan_secret_transfer_service.dart';
import 'services/remote_apply_coordinator.dart';
import 'utils/changelog_parser.dart';
import 'utils/flush_tasks.dart';
import 'utils/managed_model_id_migration.dart';
import 'utils/open_source_licenses.dart';
import 'widgets/changelog_dialog.dart';
import 'widgets/login_dialog.dart';

const _conversationSyncTables = {
  'conversations',
  'messages',
  'message_attachments',
  'resources',
};
const _featureSyncTables = {
  'note_folders',
  'notes',
  'note_pages',
  'note_revisions',
  'note_page_heads',
  'note_page_tombstones',
};
const _calendarSyncTables = {'calendar_events', 'anniversaries'};
const _roleplaySyncTables = {'roleplay_scenarios', 'roleplay_threads'};
const _taskSyncTables = {'tasks', 'task_lists', 'task_list_entries'};
const _knowledgeSyncTables = {
  'knowledge_bases',
  'knowledge_categories',
  'knowledge_entries',
  'knowledge_sources',
  'knowledge_explanations',
};
const _memoryCardSyncTables = {
  'memory_card_decks',
  'memory_cards',
  'memory_card_review_logs',
};
const _settingsSyncTables = {'shared_settings', 'resources'};
const _pluginSyncTables = {'plugin_files', 'plugin_settings', 'plugin_config'};
const _calendarProjectionSyncTables = {
  ..._calendarSyncTables,
  ..._taskSyncTables,
};

/// LynAI 的应用入口。
///
/// 入口只做三件事：注册全局 Provider、启动根组件、把 Flutter 绑定初始化。
/// 数据加载和主题构建留给 [LynAIApp]，避免入口函数承担运行时状态。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await registerOpenSourceLicenses();

  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => DatasetRuntimeBarrier()),
        Provider(
          create: (ctx) => StorageV2Service(
            runtimeBarrier: ctx.read<DatasetRuntimeBarrier>(),
          ),
          dispose: (_, storage) => unawaited(storage.close()),
        ),
        Provider<SecretStore>(create: (_) => FlutterSecureSecretStore()),
        Provider(
          create: (ctx) => DatasetSecretStore(
            ctx.read<StorageV2Service>(),
            ctx.read<SecretStore>(),
          ),
        ),
        Provider(create: (_) => DeviceSettingsService()),
        Provider(create: (_) => AgentToolRegistry()),
        Provider<AgentToolResultProcessor>(
          create: (ctx) => SanitizingAgentToolResultProcessor(
            AgentToolResultSanitizer.storageV2(ctx.read<StorageV2Service>()),
          ),
        ),
        Provider(
          create: (ctx) =>
              AgentPersistenceRepository(ctx.read<StorageV2Service>()),
        ),
        Provider<AgentRunPersistenceLifecycle>(
          create: (ctx) => RepositoryAgentRunPersistenceLifecycle(
            ctx.read<AgentPersistenceRepository>(),
          ),
        ),
        Provider(
          create: (ctx) => PersistentMcpRepository(
            persistence: ctx.read<AgentPersistenceRepository>(),
            secretStore: ctx.read<DatasetSecretStore>(),
          ),
        ),
        Provider<McpConnectionFactory>(
          create: (_) => const DefaultMcpConnectionFactory(),
        ),
        ChangeNotifierProvider(
          create: (ctx) => McpProvider(
            repository: ctx.read<PersistentMcpRepository>(),
            connectionFactory: ctx.read<McpConnectionFactory>(),
            toolRegistry: ctx.read<AgentToolRegistry>(),
            datasetBarrier: ctx.read<DatasetRuntimeBarrier>(),
          ),
        ),
        Provider(
          create: (ctx) =>
              DeviceIdentityService(secretStore: ctx.read<SecretStore>()),
        ),
        Provider(
          create: (ctx) => LanPeerRepository(
            secretStore: ctx.read<SecretStore>(),
            storage: ctx.read<StorageV2Service>(),
          ),
        ),
        Provider(
          create: (ctx) => LanDeviceProfileService(
            secretStore: ctx.read<DatasetSecretStore>(),
            identityService: ctx.read<DeviceIdentityService>(),
          ),
        ),
        Provider(
          create: (_) => LanMdnsService(),
          dispose: (_, service) => unawaited(service.dispose()),
        ),
        Provider(
          create: (ctx) => LanTlsCertificateService(
            secretStore: ctx.read<SecretStore>(),
            identityService: ctx.read<DeviceIdentityService>(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => BackendClient()),
        Provider(create: (_) => RemoteApplyCoordinator()),
        Provider(
          create: (ctx) => DeviceRegistrationService(
            backend: ctx.read<BackendClient>(),
            identity: ctx.read<DeviceIdentityService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (ctx) =>
              ConversationProvider(storageV2: ctx.read<StorageV2Service>()),
        ),
        ChangeNotifierProvider(
          create: (ctx) => FeatureProvider(
            storageV2: ctx.read<StorageV2Service>(),
            authorDeviceId: () async =>
                (await ctx.read<DeviceIdentityService>().initialize()).deviceId,
          ),
        ),
        ChangeNotifierProvider(
          create: (ctx) =>
              KnowledgeProvider(storageV2: ctx.read<StorageV2Service>()),
        ),
        ChangeNotifierProvider(
          create: (ctx) =>
              MemoryCardProvider(storageV2: ctx.read<StorageV2Service>()),
        ),
        ChangeNotifierProvider(
          create: (ctx) =>
              CalendarProvider(storageV2: ctx.read<StorageV2Service>()),
        ),
        ChangeNotifierProvider(
          create: (ctx) => ModelConfigProvider(
            storageV2: ctx.read<StorageV2Service>(),
            secretStore: ctx.read<DatasetSecretStore>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (ctx) => PluginProvider(
            storageV2: ctx.read<StorageV2Service>(),
            datasetBarrier: ctx.read<DatasetRuntimeBarrier>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (ctx) =>
              RecycleBinProvider(storageV2: ctx.read<StorageV2Service>()),
        ),
        ChangeNotifierProvider(
          create: (ctx) =>
              RoleplayProvider(storageV2: ctx.read<StorageV2Service>()),
        ),
        ChangeNotifierProvider(
          create: (ctx) =>
              TaskProvider(storageV2: ctx.read<StorageV2Service>()),
        ),
        Provider(create: (_) => const CalendarPlatformBridge()),
        Provider(
          create: (ctx) {
            final coordinator = CalendarPlatformProjectionCoordinator(
              tasks: ctx.read<TaskProvider>(),
              calendar: ctx.read<CalendarProvider>(),
              bridge: ctx.read<CalendarPlatformBridge>(),
            );
            coordinator.attach();
            return coordinator;
          },
          dispose: (_, coordinator) => coordinator.dispose(),
        ),
        ChangeNotifierProvider(
          create: (ctx) =>
              SettingsProvider(storageV2: ctx.read<StorageV2Service>()),
        ),
        ChangeNotifierProvider(create: (_) => ServerCapabilitiesService()),
        ProxyProvider4<
          SettingsProvider,
          SecretStore,
          BackendClient,
          ServerCapabilitiesService,
          WebSearchService
        >(
          update: (_, settings, secrets, backend, capabilities, previous) =>
              WebSearchService.production(
                settings: settings,
                secretStore: secrets,
                backend: backend,
                serverCapabilities: capabilities,
              ),
        ),
        ChangeNotifierProvider(
          create: (ctx) {
            final backend = ctx.read<BackendClient>();
            final remoteSync = RemoteSyncService(
              backend,
              identity: ctx.read<DeviceIdentityService>(),
              registration: ctx.read<DeviceRegistrationService>(),
            );
            final cloudRepository = StorageV2CloudDataRepository(
              ctx.read<StorageV2Service>(),
            );
            return SyncProvider(
              backend: backend,
              identity: ctx.read<DeviceIdentityService>(),
              registration: ctx.read<DeviceRegistrationService>(),
              capabilitiesService: ctx.read<ServerCapabilitiesService>(),
              readPluginBlob: (hash) =>
                  ctx.read<PluginProvider>().readSyncBlob(hash),
              hasPluginBlob: (hash) =>
                  ctx.read<PluginProvider>().hasSyncBlob(hash),
              installPluginBlob: (hash, bytes) =>
                  ctx.read<PluginProvider>().installSyncBlob(hash, bytes),
              storage: StorageV2SyncStorage(ctx.read<StorageV2Service>()),
              remoteApplyCoordinator: ctx.read<RemoteApplyCoordinator>(),
              cloudManagement: CloudManagementCoordinator(
                repository: cloudRepository,
                service: RemoteCloudDataService(backend, remoteSync),
              ),
              datasetBarrier: ctx.read<DatasetRuntimeBarrier>(),
              beforeLocalSnapshot: () async {
                final conversations = ctx.read<ConversationProvider>();
                final features = ctx.read<FeatureProvider>();
                final calendar = ctx.read<CalendarProvider>();
                final roleplay = ctx.read<RoleplayProvider>();
                final tasks = ctx.read<TaskProvider>();
                final knowledge = ctx.read<KnowledgeProvider>();
                final memoryCards = ctx.read<MemoryCardProvider>();
                final settings = ctx.read<SettingsProvider>();
                final models = ctx.read<ModelConfigProvider>();
                final plugins = ctx.read<PluginProvider>();
                await flushAllTasks([
                  (
                    name: 'conversations',
                    flush: conversations.flushPendingSaves,
                  ),
                  (name: 'features', flush: features.flushPendingSaves),
                  (name: 'calendar', flush: calendar.flushPendingSaves),
                  (name: 'roleplay', flush: roleplay.flushPendingSaves),
                  (name: 'tasks', flush: tasks.flushPendingSaves),
                  (name: 'knowledge', flush: knowledge.flushPendingSaves),
                  (
                    name: 'memoryCards',
                    flush: memoryCards.flushPendingSaves,
                  ),
                  (name: 'settings', flush: settings.flushPendingSaves),
                  (name: 'models', flush: models.flushPendingSaves),
                ]);
                await plugins.syncAllPlugins();
              },
              beforeRemoteApply: (summary) async {
                final conversations = ctx.read<ConversationProvider>();
                final features = ctx.read<FeatureProvider>();
                final calendar = ctx.read<CalendarProvider>();
                final roleplay = ctx.read<RoleplayProvider>();
                final tasks = ctx.read<TaskProvider>();
                final knowledge = ctx.read<KnowledgeProvider>();
                final memoryCards = ctx.read<MemoryCardProvider>();
                final settings = ctx.read<SettingsProvider>();
                final models = ctx.read<ModelConfigProvider>();
                final plugins = ctx.read<PluginProvider>();
                final tables = summary.changedTables;
                final all = tables.isEmpty;
                await flushAllTasks([
                  if (all || tables.any(_conversationSyncTables.contains))
                    (
                      name: 'conversations',
                      flush: conversations.flushPendingSaves,
                    ),
                  if (all || tables.any(_featureSyncTables.contains))
                    (name: 'features', flush: features.flushPendingSaves),
                  if (all || tables.any(_calendarSyncTables.contains))
                    (name: 'calendar', flush: calendar.flushPendingSaves),
                  if (all || tables.any(_roleplaySyncTables.contains))
                    (name: 'roleplay', flush: roleplay.flushPendingSaves),
                  if (all || tables.any(_taskSyncTables.contains))
                    (name: 'tasks', flush: tasks.flushPendingSaves),
                  if (all || tables.any(_knowledgeSyncTables.contains))
                    (name: 'knowledge', flush: knowledge.flushPendingSaves),
                  if (all || tables.any(_memoryCardSyncTables.contains))
                    (
                      name: 'memoryCards',
                      flush: memoryCards.flushPendingSaves,
                    ),
                  if (all || tables.any(_settingsSyncTables.contains))
                    (name: 'settings', flush: settings.flushPendingSaves),
                  if (all || tables.contains('synced_model_configs'))
                    (name: 'models', flush: models.flushPendingSaves),
                ]);
                if (all || tables.any(_pluginSyncTables.contains)) {
                  await plugins.syncAllPlugins();
                }
              },
              onRemoteApplied: (summary) async {
                final projectionCoordinator = ctx
                    .read<CalendarPlatformProjectionCoordinator>();
                final conversations = ctx.read<ConversationProvider>();
                final features = ctx.read<FeatureProvider>();
                final calendar = ctx.read<CalendarProvider>();
                final roleplay = ctx.read<RoleplayProvider>();
                final tasks = ctx.read<TaskProvider>();
                final knowledge = ctx.read<KnowledgeProvider>();
                final memoryCards = ctx.read<MemoryCardProvider>();
                final recycleBin = ctx.read<RecycleBinProvider>();
                final settings = ctx.read<SettingsProvider>();
                final models = ctx.read<ModelConfigProvider>();
                final backend = ctx.read<BackendClient>();
                final plugins = ctx.read<PluginProvider>();
                final tables = summary.changedTables;
                if (tables.any(_pluginSyncTables.contains)) {
                  await plugins.applyRemoteSync(summary.scope);
                }
                await Future.wait([
                  if (tables.any(_conversationSyncTables.contains))
                    conversations.loadConversations(),
                  if (tables.any(_featureSyncTables.contains)) features.load(),
                  if (tables.any(_calendarSyncTables.contains)) calendar.load(),
                  if (tables.any(_roleplaySyncTables.contains))
                    roleplay.loadSessions(),
                  if (tables.any(_taskSyncTables.contains)) tasks.load(),
                  if (tables.any(_knowledgeSyncTables.contains))
                    knowledge.load(),
                  if (tables.any(_memoryCardSyncTables.contains))
                    memoryCards.load(),
                  if (tables.contains('recycle_bin')) recycleBin.load(),
                  if (tables.any(_settingsSyncTables.contains))
                    settings.loadSettings(),
                  if (tables.contains('synced_model_configs'))
                    models.loadModels(),
                ]);
                if (tables.contains('synced_model_configs') ||
                    tables.contains('shared_settings') ||
                    tables.any(_pluginSyncTables.contains)) {
                  await syncManagedModelsAndApplyMigrations(
                    models: models,
                    backend: backend,
                    settings: settings,
                    conversations: conversations,
                    roleplay: roleplay,
                    plugins: plugins,
                  );
                }
                if (tables.any(_calendarProjectionSyncTables.contains)) {
                  await projectionCoordinator.syncAfterPersistence();
                }
              },
            );
          },
        ),
        ChangeNotifierProvider(
          create: (ctx) {
            final backend = ctx.read<BackendClient>();
            final remoteSync = RemoteSyncService(
              backend,
              identity: ctx.read<DeviceIdentityService>(),
              registration: ctx.read<DeviceRegistrationService>(),
            );
            return CloudDataProvider(
              backend: backend,
              repository: StorageV2CloudDataRepository(
                ctx.read<StorageV2Service>(),
              ),
              service: RemoteCloudDataService(backend, remoteSync),
              datasetBarrier: ctx.read<DatasetRuntimeBarrier>(),
            );
          },
        ),
        ChangeNotifierProvider(
          create: (ctx) {
            Future<void> beforeRemoteApply() async {
              final conversations = ctx.read<ConversationProvider>();
              final features = ctx.read<FeatureProvider>();
              final calendar = ctx.read<CalendarProvider>();
              final roleplay = ctx.read<RoleplayProvider>();
              final tasks = ctx.read<TaskProvider>();
              final knowledge = ctx.read<KnowledgeProvider>();
              final memoryCards = ctx.read<MemoryCardProvider>();
              final settings = ctx.read<SettingsProvider>();
              final models = ctx.read<ModelConfigProvider>();
              final plugins = ctx.read<PluginProvider>();
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
              await plugins.syncAllPlugins();
            }

            Future<void> onRemoteApplied() async {
              final projectionCoordinator = ctx
                  .read<CalendarPlatformProjectionCoordinator>();
              final conversations = ctx.read<ConversationProvider>();
              final features = ctx.read<FeatureProvider>();
              final calendar = ctx.read<CalendarProvider>();
              final roleplay = ctx.read<RoleplayProvider>();
              final tasks = ctx.read<TaskProvider>();
              final knowledge = ctx.read<KnowledgeProvider>();
              final memoryCards = ctx.read<MemoryCardProvider>();
              final recycleBin = ctx.read<RecycleBinProvider>();
              final settings = ctx.read<SettingsProvider>();
              final models = ctx.read<ModelConfigProvider>();
              final backend = ctx.read<BackendClient>();
              final plugins = ctx.read<PluginProvider>();
              await plugins.applyRemoteSync(LanSyncStorage.scope);
              await Future.wait([
                conversations.loadConversations(),
                features.load(),
                calendar.load(),
                roleplay.loadSessions(),
                tasks.load(),
                knowledge.load(),
                memoryCards.load(),
                recycleBin.load(),
                settings.loadSettings(),
                models.loadModels(),
              ]);
              await syncManagedModelsAndApplyMigrations(
                models: models,
                backend: backend,
                settings: settings,
                conversations: conversations,
                roleplay: roleplay,
                plugins: plugins,
              );
              await projectionCoordinator.syncAfterPersistence();
            }

            final mdns = ctx.read<LanMdnsService>();
            final peers = ctx.read<LanPeerRepository>();
            final coordinator = LanSyncCoordinator(
              identityService: ctx.read<DeviceIdentityService>(),
              peerRepository: peers,
              certificateService: ctx.read<LanTlsCertificateService>(),
              mdnsService: mdns,
              syncStorage: LanSyncStorage(
                storage: ctx.read<StorageV2Service>(),
                readPluginBlob: (hash) =>
                    ctx.read<PluginProvider>().readSyncBlob(hash),
                hasPluginBlob: (hash) =>
                    ctx.read<PluginProvider>().hasSyncBlob(hash),
                installPluginBlob: (hash, bytes) =>
                    ctx.read<PluginProvider>().installSyncBlob(hash, bytes),
              ),
              secretTransferService: LanSecretTransferService(
                ctx.read<SecretStore>(),
                onImported: () async {
                  final models = ctx.read<ModelConfigProvider>();
                  final backend = ctx.read<BackendClient>();
                  final settings = ctx.read<SettingsProvider>();
                  final conversations = ctx.read<ConversationProvider>();
                  final roleplay = ctx.read<RoleplayProvider>();
                  final plugins = ctx.read<PluginProvider>();
                  await models.flushPendingSaves();
                  await models.loadModels();
                  await syncManagedModelsAndApplyMigrations(
                    models: models,
                    backend: backend,
                    settings: settings,
                    conversations: conversations,
                    roleplay: roleplay,
                    plugins: plugins,
                  );
                },
              ),
              readModels: () => ctx.read<ModelConfigProvider>().models,
              confirmPairing: (_) async => const LanPairingDecision.rejected(),
              confirmPolicyProposal: (_, _, _) async => null,
              beforeLocalSnapshot: beforeRemoteApply,
              beforeRemoteApply: beforeRemoteApply,
              onRemoteApplied: onRemoteApplied,
              remoteApplyCoordinator: ctx.read<RemoteApplyCoordinator>(),
            );
            return LanSyncProvider(
              coordinator: coordinator,
              peerRepository: peers,
              mdnsService: mdns,
              deviceProfileService: ctx.read<LanDeviceProfileService>(),
              datasetBarrier: ctx.read<DatasetRuntimeBarrier>(),
            );
          },
        ),
        ChangeNotifierProvider(
          create: (ctx) {
            final registration = ctx.read<DeviceRegistrationService>();
            final sync = ctx.read<SyncProvider>();
            final cloud = ctx.read<CloudDataProvider>();
            final models = ctx.read<ModelConfigProvider>();
            final backend = ctx.read<BackendClient>();
            final settings = ctx.read<SettingsProvider>();
            final conversations = ctx.read<ConversationProvider>();
            final roleplay = ctx.read<RoleplayProvider>();
            final plugins = ctx.read<PluginProvider>();
            McpProvider? mcp;
            try {
              mcp = ctx.read<McpProvider>();
            } on ProviderNotFoundException {
              mcp = null;
            }
            final datasets = DatasetRuntimeCoordinator(
              storage: ctx.read<StorageV2Service>(),
              backend: backend,
              conversations: conversations,
              features: ctx.read<FeatureProvider>(),
              calendar: ctx.read<CalendarProvider>(),
              roleplay: roleplay,
              tasks: ctx.read<TaskProvider>(),
              knowledge: ctx.read<KnowledgeProvider>(),
              memoryCards: ctx.read<MemoryCardProvider>(),
              recycleBin: ctx.read<RecycleBinProvider>(),
              settings: settings,
              models: models,
              plugins: plugins,
              mcp: mcp,
              calendarProjection: ctx
                  .read<CalendarPlatformProjectionCoordinator>(),
              quiesceOperations: () async {
                await Future.wait([
                  sync.quiesceForDatasetSwitch(),
                  cloud.quiesceForDatasetSwitch(),
                  ctx.read<LanSyncProvider>().quiesceForDatasetSwitch(),
                ]);
              },
              resumeOperations: () =>
                  ctx.read<LanSyncProvider>().resumeAfterDatasetSwitch(),
            );
            return AccountProvider(
              backend: backend,
              secretStore: ctx.read<SecretStore>(),
              onDatasetActivation: datasets.activate,
              onSessionChanged: (user) async {
                final cloudBind = cloud.bind(user);
                if (user == null) {
                  await sync.unbind();
                  await cloudBind;
                  return;
                }
                await sync.bindScope(user.id);
                await cloudBind;
              },
              onRemoteActivation: (user) async {
                await sync.refreshCapabilities();
                final enrolled = await registration.ensureEnrolled();
                if (enrolled) await sync.autoDownload();
                await syncManagedModelsAndApplyMigrations(
                  models: models,
                  backend: backend,
                  settings: settings,
                  conversations: conversations,
                  roleplay: roleplay,
                  plugins: plugins,
                );
              },
            );
          },
        ),
      ],
      child: const LynAIApp(),
    ),
  );
}

/// 应用根组件。
///
/// 负责加载本地持久化数据、修复悬空模型引用，并根据用户设置构建
/// Material 主题。加载失败时停留在可重试错误页，而不是让空状态进入主界面。
class LynAIApp extends StatefulWidget {
  const LynAIApp({super.key});

  @override
  State<LynAIApp> createState() => _LynAIAppState();
}

class _LynAIAppState extends State<LynAIApp> with WidgetsBindingObserver {
  static const List<Locale> _supportedLocales = [
    Locale('zh', 'CN'),
    Locale('en', 'US'),
  ];
  static const List<LocalizationsDelegate<dynamic>>
  _materialLocalizationDelegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];
  static const List<LocalizationsDelegate<dynamic>>
  _windowsLocalizationDelegates = [
    fluent.FluentLocalizations.delegate,
    ..._materialLocalizationDelegates,
  ];

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  ConversationProvider? _conversationProvider;
  FeatureProvider? _featureProvider;
  CalendarProvider? _calendarProvider;
  RoleplayProvider? _roleplayProvider;
  TaskProvider? _taskProvider;
  KnowledgeProvider? _knowledgeProvider;
  MemoryCardProvider? _memoryCardProvider;
  SettingsProvider? _settingsProvider;
  ModelConfigProvider? _modelProvider;
  SyncProvider? _syncProvider;
  LanSyncProvider? _lanSyncProvider;
  CalendarPlatformProjectionCoordinator? _calendarProjectionCoordinator;
  AccountProvider? _accountProvider;
  Future<void>? _criticalSaveFlush;
  Future<void>? _loadDataFuture;
  Future<void>? _backgroundStartupFuture;
  Future<void>? _startupDialogsFuture;
  Future<void>? _accountRestoreFuture;
  bool _isForeground = true;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Provider 已在父级注册；延后到 microtask 后再读取 context。
    Future.microtask(() => _loadData());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _conversationProvider ??= context.read<ConversationProvider>();
    _featureProvider ??= context.read<FeatureProvider>();
    _calendarProvider ??= context.read<CalendarProvider>();
    _roleplayProvider ??= context.read<RoleplayProvider>();
    _taskProvider ??= context.read<TaskProvider>();
    _knowledgeProvider ??= context.read<KnowledgeProvider>();
    _memoryCardProvider ??= context.read<MemoryCardProvider>();
    _settingsProvider ??= context.read<SettingsProvider>();
    _modelProvider ??= context.read<ModelConfigProvider>();
    _syncProvider ??= context.read<SyncProvider>();
    if (_lanSyncProvider == null) {
      try {
        _lanSyncProvider = context.read<LanSyncProvider>();
        unawaited(_lanSyncProvider!.setHostingDesired(_isForeground));
      } on ProviderNotFoundException {
        // Focused widget tests may intentionally provide only the dependencies
        // exercised by the root application shell.
      }
    }
    _calendarProjectionCoordinator ??= context
        .read<CalendarPlatformProjectionCoordinator>();
    _accountProvider ??= context.read<AccountProvider>();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isForeground = true;
      _accountProvider?.retryPendingRevocations();
      unawaited(_lanSyncProvider?.setHostingDesired(true));
    }
    if (state
        case AppLifecycleState.inactive ||
            AppLifecycleState.paused ||
            AppLifecycleState.detached) {
      _isForeground = false;
      unawaited(_lanSyncProvider?.setHostingDesired(false));
      unawaited(_flushCriticalSaves());
    }
  }

  Future<void> _flushCriticalSaves() {
    final active = _criticalSaveFlush;
    if (active != null) return active;

    late final Future<void> flush;
    flush =
        (() async {
          try {
            await flushAllTasks([
              if (_conversationProvider case final provider?)
                (name: 'conversations', flush: provider.flushPendingSaves),
              if (_featureProvider case final provider?)
                (name: 'features', flush: provider.flushPendingSaves),
              if (_calendarProvider case final provider?)
                (name: 'calendar', flush: provider.flushPendingSaves),
              if (_roleplayProvider case final provider?)
                (name: 'roleplay', flush: provider.flushPendingSaves),
              if (_taskProvider case final provider?)
                (name: 'tasks', flush: provider.flushPendingSaves),
              if (_knowledgeProvider case final provider?)
                (name: 'knowledge', flush: provider.flushPendingSaves),
              if (_memoryCardProvider case final provider?)
                (name: 'memoryCards', flush: provider.flushPendingSaves),
              if (_settingsProvider case final provider?)
                (name: 'settings', flush: provider.flushPendingSaves),
              if (_modelProvider case final provider?)
                (name: 'models', flush: provider.flushPendingSaves),
            ]);
            await _syncProvider?.flushUpload();
          } catch (e) {
            debugPrint('后台保存失败: $e');
          }
        })().whenComplete(() {
          if (identical(_criticalSaveFlush, flush)) _criticalSaveFlush = null;
        });
    return _criticalSaveFlush = flush;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_flushCriticalSaves());
    FloatingAssistantService.instance.dispose();
    super.dispose();
  }

  /// 并行加载所有本地数据分区。
  ///
  /// Provider 会自行处理单条坏数据；这里关心的是启动阶段是否完成，以及
  /// 模型配置变更后设置中的模型 ID 是否仍然有效。
  Future<void> _loadData() {
    final active = _loadDataFuture;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _performLoadData().whenComplete(() {
      if (identical(_loadDataFuture, operation)) _loadDataFuture = null;
    });
    return _loadDataFuture = operation;
  }

  Future<void> _performLoadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final conversationProvider = context.read<ConversationProvider>();
      final modelProvider = context.read<ModelConfigProvider>();
      final settingsProvider = context.read<SettingsProvider>();
      final featureProvider = context.read<FeatureProvider>();
      final calendarProvider = context.read<CalendarProvider>();
      final pluginProvider = context.read<PluginProvider>();
      final accountProvider = context.read<AccountProvider>();
      final recycleBinProvider = context.read<RecycleBinProvider>();
      final roleplayProvider = context.read<RoleplayProvider>();
      final taskProvider = context.read<TaskProvider>();
      final knowledgeProvider = context.read<KnowledgeProvider>();
      final memoryCardProvider = context.read<MemoryCardProvider>();
      final backendClient = context.read<BackendClient>();
      final deviceIdentityService = context.read<DeviceIdentityService>();
      final storageV2 = context.read<StorageV2Service>();
      final deviceSettings = context.read<DeviceSettingsService>();
      final webSearch = context.read<WebSearchService>();
      AgentRunPersistenceLifecycle? agentPersistence;
      AgentToolResultProcessor? agentToolResultProcessor;
      try {
        agentPersistence = context.read<AgentRunPersistenceLifecycle>();
        agentToolResultProcessor = context.read<AgentToolResultProcessor>();
      } on ProviderNotFoundException {
        // Focused root widget tests may omit optional Agent persistence.
      }
      AgentToolRegistry? agentToolRegistry;
      try {
        agentToolRegistry = context.read<AgentToolRegistry>();
      } on ProviderNotFoundException {
        // Focused root widget tests may omit optional Agent tool composition.
      }
      McpProvider? mcpProvider;
      try {
        mcpProvider = context.read<McpProvider>();
      } on ProviderNotFoundException {
        // Focused root widget tests may omit optional MCP composition.
      }
      await StorageV2UpgradeService(storageV2: storageV2).ensureDatasetsReady();
      await AgentPersistenceRepository(storageV2).reconcileAfterRestart();

      await settingsProvider.loadSettings();
      await conversationProvider.loadConversations();
      await Future.wait([
        featureProvider.load(),
        calendarProvider.load(),
        pluginProvider.load(),
        recycleBinProvider.load(),
        roleplayProvider.loadSessions(),
        taskProvider.load(),
        knowledgeProvider.load(),
        memoryCardProvider.load(),
        modelProvider.loadModels(),
        if (mcpProvider != null) mcpProvider.load(),
      ]);
      await applyPendingManagedModelIdMigrations(
        models: modelProvider,
        settings: settingsProvider,
        conversations: conversationProvider,
        roleplay: roleplayProvider,
        plugins: pluginProvider,
      );
      final bootstrapBackend = await deviceSettings.loadBackendUrl(
        defaultUrl:
            settingsProvider.settings.backendUrl ??
            BackendClient.defaultBackendUrl,
      );
      backendClient.configure(bootstrapBackend ?? '');

      await deviceIdentityService.initialize();
      _accountRestoreFuture = accountProvider.restoreLocalSession();
      await _accountRestoreFuture;
      FloatingAssistantService.instance.start(
        settings: settingsProvider,
        conversations: conversationProvider,
        models: modelProvider,
        features: featureProvider,
        knowledge: knowledgeProvider,
        memoryCards: memoryCardProvider,
        tasks: taskProvider,
        calendar: calendarProvider,
        plugins: pluginProvider,
        externalToolRegistry: agentToolRegistry,
        persistence: agentPersistence,
        toolResultProcessor: agentToolResultProcessor,
        backend: backendClient,
        storage: storageV2,
        webSearch: webSearch,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = false;
        });
      }

      unawaited(_startBackgroundStartup());

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startupDialogsFuture ??= _runStartupDialogs();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = '加载数据失败: $e';
        });
      }
    }
  }

  Future<void> _startBackgroundStartup() {
    return _backgroundStartupFuture ??= (() async {
      try {
        final plugins = context.read<PluginProvider>();
        final account = context.read<AccountProvider>();
        await _importBuiltInPlugins(plugins);
        await _calendarProjectionCoordinator?.syncAfterPersistence();
        await _lanSyncProvider?.markRuntimeReady();

        await account.refreshCurrentSession();
        if (!mounted) return;
        await account.activateCurrentSession();
      } catch (e) {
        debugPrint('后台启动任务失败: $e');
      }
    })();
  }

  Future<void> _checkNewChangelog() async {
    try {
      final settingsProvider = context.read<SettingsProvider>();
      final lastSeen = settingsProvider.settings.lastSeenChangelogVersion;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      if (lastSeen == currentVersion) return;

      final parser = ChangelogParser();
      final entry = await parser.loadVersion(currentVersion);
      if (entry == null) return;

      final dialogContext = _navigatorKey.currentContext;
      if (!mounted || dialogContext == null || !dialogContext.mounted) return;
      final action = await showChangelogDialog(dialogContext, entry);

      final updatedSettings = settingsProvider.settings.copyWith(
        lastSeenChangelogVersion: currentVersion,
      );
      await settingsProvider.replaceSettings(updatedSettings);

      if (!mounted || action != ChangelogDialogAction.viewAll) return;
      _navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const ChangelogPage()),
      );
    } catch (e) {
      debugPrint('检查更新日志失败: $e');
    }
  }

  Future<void> _runStartupDialogs() async {
    await _accountRestoreFuture;
    if (!mounted) return;
    await _showInitialLoginDialogIfNeeded();
    if (!mounted) return;
    await _checkNewChangelog();
  }

  Future<void> _showInitialLoginDialogIfNeeded() async {
    final dialogContext = _navigatorKey.currentContext;
    if (!mounted || dialogContext == null || !dialogContext.mounted) return;

    final settings = dialogContext.read<SettingsProvider>();
    final backend = dialogContext.read<BackendClient>();
    final account = dialogContext.read<AccountProvider>();
    if (settings.settings.hasSeenLoginGuide ||
        !backend.isConnected ||
        account.isLoggedIn) {
      return;
    }

    await settings.markLoginGuideSeen();
    if (!mounted || !dialogContext.mounted) return;
    await showDialog<void>(
      context: dialogContext,
      builder: (_) => const LoginDialog(initialRegisterMode: true),
    );
  }

  /// 遍历所有内置插件 ID，同步源码，并为首次安装的插件授予其声明权限。
  Future<void> _importBuiltInPlugins(PluginProvider provider) async {
    for (final id in PluginRepository.builtInPluginIds) {
      try {
        final plugin = provider.pluginExistsSync(id)
            ? await provider.syncBuiltIn(id)
            : await provider.installTrustedBuiltIn(id);
        debugPrint('内置插件已同步: ${plugin.manifest.name}');
      } catch (e) {
        debugPrint('内置插件安装失败 $id: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final settingsProvider = context.read<SettingsProvider>();

    final home = _isLoading
        ? const _SplashScreen()
        : _hasError
        ? _ErrorScreen(message: _errorMessage)
        : const HomePage();

    if (Platform.isWindows) {
      return _buildWindowsApp(settings, settingsProvider, home);
    }
    return _buildDefaultApp(settings, settingsProvider, home);
  }

  Widget _buildWindowsApp(
    dynamic settings,
    SettingsProvider settingsProvider,
    Widget home,
  ) {
    final accentColor = _toAccentColor(settings.themeColor);

    final lightMaterialTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: settings.themeColor,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    final darkMaterialTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: settings.themeColor,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    return fluent.FluentApp(
      navigatorKey: _navigatorKey,
      title: 'LynAI',
      debugShowCheckedModeBanner: false,
      theme: fluent.FluentThemeData(
        accentColor: accentColor,
        brightness: Brightness.light,
      ),
      darkTheme: fluent.FluentThemeData(
        accentColor: accentColor,
        brightness: Brightness.dark,
      ),
      themeMode: settingsProvider.themeModeEnum,
      localizationsDelegates: _windowsLocalizationDelegates,
      supportedLocales: _supportedLocales,
      home: home,
      builder: (context, child) {
        final fluentTheme = fluent.FluentTheme.of(context);
        final isDark = fluentTheme.brightness == Brightness.dark;
        return Theme(
          data: isDark ? darkMaterialTheme : lightMaterialTheme,
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              fontFamily: 'Microsoft YaHei',
              fontFamilyFallback: ['Segoe UI', 'Arial'],
            ),
            child: child!,
          ),
        );
      },
    );
  }

  Widget _buildDefaultApp(
    dynamic settings,
    SettingsProvider settingsProvider,
    Widget home,
  ) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'LynAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: settings.themeColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: settings.themeColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      themeMode: settingsProvider.themeModeEnum,
      localizationsDelegates: _materialLocalizationDelegates,
      supportedLocales: _supportedLocales,
      home: home,
    );
  }

  /// 将用户选的主题色转换为 fluent_ui 的 AccentColor。
  static fluent.AccentColor _toAccentColor(Color base) {
    final hsl = HSLColor.fromColor(base);
    return fluent.AccentColor.swatch({
      'darkest': hsl
          .withLightness((hsl.lightness - 0.3).clamp(0.0, 1.0))
          .toColor(),
      'darker': hsl
          .withLightness((hsl.lightness - 0.15).clamp(0.0, 1.0))
          .toColor(),
      'dark': hsl
          .withLightness((hsl.lightness - 0.07).clamp(0.0, 1.0))
          .toColor(),
      'normal': base,
      'light': hsl
          .withLightness((hsl.lightness + 0.1).clamp(0.0, 1.0))
          .toColor(),
      'lighter': hsl
          .withLightness((hsl.lightness + 0.2).clamp(0.0, 1.0))
          .toColor(),
      'lightest': hsl
          .withLightness((hsl.lightness + 0.3).clamp(0.0, 1.0))
          .toColor(),
    });
  }
}

/// 启动画面
///
/// 在数据加载期间显示，包含应用图标和加载指示器。
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 应用图标
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.smart_toy,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            // 应用名称
            Text(
              'LynAI',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            // 加载指示器
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

/// 错误界面
///
/// 在数据加载失败时显示错误信息。
class _ErrorScreen extends StatelessWidget {
  final String message;

  const _ErrorScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text('加载失败', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    final state = context
                        .findAncestorStateOfType<_LynAIAppState>();
                    state?._loadData();
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
