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
import 'providers/model_config_provider.dart';
import 'providers/plugin_provider.dart';
import 'providers/account_provider.dart';
import 'providers/recycle_bin_provider.dart';
import 'providers/roleplay_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/task_provider.dart';
import 'repositories/plugin_repository.dart';
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
import 'services/storage_v2_service.dart';
import 'providers/sync_provider.dart';
import 'providers/lan_sync_provider.dart';
import 'repositories/lan_peer_repository.dart';
import 'services/lan_mdns_service.dart';
import 'services/lan_sync_coordinator.dart';
import 'services/lan_sync_storage.dart';
import 'services/lan_tls_certificate_service.dart';
import 'services/lan_secret_transfer_service.dart';
import 'utils/changelog_parser.dart';
import 'utils/flush_tasks.dart';
import 'utils/managed_model_id_migration.dart';
import 'utils/open_source_licenses.dart';
import 'widgets/changelog_dialog.dart';
import 'widgets/login_dialog.dart';

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
        Provider(
          create: (_) => StorageV2Service(),
          dispose: (_, storage) => unawaited(storage.close()),
        ),
        Provider<SecretStore>(create: (_) => FlutterSecureSecretStore()),
        Provider(
          create: (ctx) =>
              DeviceIdentityService(secretStore: ctx.read<SecretStore>()),
        ),
        Provider(
          create: (ctx) =>
              LanPeerRepository(secretStore: ctx.read<SecretStore>()),
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
              CalendarProvider(storageV2: ctx.read<StorageV2Service>()),
        ),
        ChangeNotifierProvider(
          create: (ctx) => ModelConfigProvider(
            storageV2: ctx.read<StorageV2Service>(),
            secretStore: ctx.read<SecretStore>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (ctx) =>
              PluginProvider(storageV2: ctx.read<StorageV2Service>()),
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
        ChangeNotifierProvider(
          create: (ctx) => SyncProvider(
            backend: ctx.read<BackendClient>(),
            identity: ctx.read<DeviceIdentityService>(),
            registration: ctx.read<DeviceRegistrationService>(),
            readPluginBlob: (hash) =>
                ctx.read<PluginProvider>().readSyncBlob(hash),
            hasPluginBlob: (hash) =>
                ctx.read<PluginProvider>().hasSyncBlob(hash),
            installPluginBlob: (hash, bytes) =>
                ctx.read<PluginProvider>().installSyncBlob(hash, bytes),
            storage: StorageV2SyncStorage(ctx.read<StorageV2Service>()),
            beforeRemoteApply: () async {
              final conversations = ctx.read<ConversationProvider>();
              final features = ctx.read<FeatureProvider>();
              final calendar = ctx.read<CalendarProvider>();
              final roleplay = ctx.read<RoleplayProvider>();
              final tasks = ctx.read<TaskProvider>();
              final settings = ctx.read<SettingsProvider>();
              final models = ctx.read<ModelConfigProvider>();
              final plugins = ctx.read<PluginProvider>();
              await flushAllTasks([
                (name: 'conversations', flush: conversations.flushPendingSaves),
                (name: 'features', flush: features.flushPendingSaves),
                (name: 'calendar', flush: calendar.flushPendingSaves),
                (name: 'roleplay', flush: roleplay.flushPendingSaves),
                (name: 'tasks', flush: tasks.flushPendingSaves),
                (name: 'settings', flush: settings.flushPendingSaves),
                (name: 'models', flush: models.flushPendingSaves),
              ]);
              await plugins.syncAllPlugins();
            },
            onRemoteApplied: () async {
              final projectionCoordinator = ctx
                  .read<CalendarPlatformProjectionCoordinator>();
              final conversations = ctx.read<ConversationProvider>();
              final features = ctx.read<FeatureProvider>();
              final calendar = ctx.read<CalendarProvider>();
              final roleplay = ctx.read<RoleplayProvider>();
              final tasks = ctx.read<TaskProvider>();
              final recycleBin = ctx.read<RecycleBinProvider>();
              final settings = ctx.read<SettingsProvider>();
              final models = ctx.read<ModelConfigProvider>();
              final backend = ctx.read<BackendClient>();
              final plugins = ctx.read<PluginProvider>();
              final scope = ctx.read<SyncProvider>().scope;
              if (scope != null) await plugins.applyRemoteSync(scope);
              await Future.wait([
                conversations.loadConversations(),
                features.load(),
                calendar.load(),
                roleplay.loadSessions(),
                tasks.load(),
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
            },
          ),
        ),
        ChangeNotifierProvider(
          create: (ctx) {
            Future<void> beforeRemoteApply() async {
              final conversations = ctx.read<ConversationProvider>();
              final features = ctx.read<FeatureProvider>();
              final calendar = ctx.read<CalendarProvider>();
              final roleplay = ctx.read<RoleplayProvider>();
              final tasks = ctx.read<TaskProvider>();
              final settings = ctx.read<SettingsProvider>();
              final models = ctx.read<ModelConfigProvider>();
              final plugins = ctx.read<PluginProvider>();
              await flushAllTasks([
                (name: 'conversations', flush: conversations.flushPendingSaves),
                (name: 'features', flush: features.flushPendingSaves),
                (name: 'calendar', flush: calendar.flushPendingSaves),
                (name: 'roleplay', flush: roleplay.flushPendingSaves),
                (name: 'tasks', flush: tasks.flushPendingSaves),
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
              confirmPairing: (_, _) async => false,
              beforeRemoteApply: beforeRemoteApply,
              onRemoteApplied: onRemoteApplied,
            );
            return LanSyncProvider(
              coordinator: coordinator,
              peerRepository: peers,
              mdnsService: mdns,
            );
          },
        ),
        ChangeNotifierProvider(
          create: (ctx) => AccountProvider(
            backend: ctx.read<BackendClient>(),
            secretStore: ctx.read<SecretStore>(),
            afterAuthenticated: () async {
              final enrolled = await ctx
                  .read<DeviceRegistrationService>()
                  .ensureEnrolled();
              if (!enrolled) throw StateError('设备注册失败，云同步不可用');
            },
            onSessionChanged: (user) async {
              final sync = ctx.read<SyncProvider>();
              if (user == null) {
                await sync.unbind();
                return;
              }
              await sync.bindScope(user.id);
              await sync.autoDownload();
            },
          ),
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
  SettingsProvider? _settingsProvider;
  ModelConfigProvider? _modelProvider;
  SyncProvider? _syncProvider;
  CalendarPlatformProjectionCoordinator? _calendarProjectionCoordinator;
  AccountProvider? _accountProvider;
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
    _settingsProvider ??= context.read<SettingsProvider>();
    _modelProvider ??= context.read<ModelConfigProvider>();
    _syncProvider ??= context.read<SyncProvider>();
    _calendarProjectionCoordinator ??= context
        .read<CalendarPlatformProjectionCoordinator>();
    _accountProvider ??= context.read<AccountProvider>();
    if (_settingsProvider != null) {
      FloatingAssistantService.instance.start(
        settings: _settingsProvider!,
        conversations: context.read<ConversationProvider>(),
        models: context.read<ModelConfigProvider>(),
        features: context.read<FeatureProvider>(),
        tasks: context.read<TaskProvider>(),
        calendar: context.read<CalendarProvider>(),
        plugins: context.read<PluginProvider>(),
        backend: context.read<BackendClient>(),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _accountProvider?.retryPendingRevocations();
    }
    if (state
        case AppLifecycleState.inactive ||
            AppLifecycleState.paused ||
            AppLifecycleState.detached) {
      unawaited(_flushCriticalSaves());
    }
  }

  Future<void> _flushCriticalSaves() async {
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
        if (_settingsProvider case final provider?)
          (name: 'settings', flush: provider.flushPendingSaves),
        if (_modelProvider case final provider?)
          (name: 'models', flush: provider.flushPendingSaves),
      ]);
      await _syncProvider?.flushUpload();
    } catch (e) {
      debugPrint('后台保存失败: $e');
    }
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
  Future<void> _loadData() async {
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
      final backendClient = context.read<BackendClient>();
      final deviceIdentityService = context.read<DeviceIdentityService>();
      await StorageV2UpgradeService().ensureReady();

      await Future.wait([
        conversationProvider.loadConversations(),
        featureProvider.load(),
        calendarProvider.load(),
        pluginProvider.load(),
        recycleBinProvider.load(),
        roleplayProvider.loadSessions(),
        taskProvider.load(),
        modelProvider.loadModels(),
        settingsProvider.loadSettings(),
      ]);
      await _calendarProjectionCoordinator?.syncAfterPersistence();

      await settingsProvider.initializeDefaultBackend(
        BackendClient.defaultBackendUrl,
      );

      // Configure backend client from settings. A null URL means the user
      // explicitly disconnected the backend.
      backendClient.configure(settingsProvider.settings.backendUrl ?? '');

      await deviceIdentityService.initialize();
      await accountProvider.load();
      await syncManagedModelsAndApplyMigrations(
        models: modelProvider,
        backend: backendClient,
        settings: settingsProvider,
        conversations: conversationProvider,
        roleplay: roleplayProvider,
        plugins: pluginProvider,
      );

      await _importBuiltInPlugins(pluginProvider);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = false;
        });
      }

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_runStartupDialogs());
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
