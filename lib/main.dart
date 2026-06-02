import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'providers/conversation_provider.dart';
import 'providers/feature_provider.dart';
import 'providers/model_config_provider.dart';
import 'providers/roleplay_provider.dart';
import 'providers/settings_provider.dart';
import 'pages/home_page.dart';
import 'services/storage_migration_service.dart';
import 'utils/changelog_parser.dart';
import 'widgets/changelog_dialog.dart';

/// LynAI 的应用入口。
///
/// 入口只做三件事：注册全局 Provider、启动根组件、把 Flutter 绑定初始化。
/// 数据加载和主题构建留给 [LynAIApp]，避免入口函数承担运行时状态。
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConversationProvider()),
        ChangeNotifierProvider(create: (_) => FeatureProvider()),
        ChangeNotifierProvider(create: (_) => ModelConfigProvider()),
        ChangeNotifierProvider(create: (_) => RoleplayProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
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

class _LynAIAppState extends State<LynAIApp> {
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    // Provider 已在父级注册；延后到 microtask 后再读取 context。
    Future.microtask(() => _loadData());
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
      final roleplayProvider = context.read<RoleplayProvider>();

      await StorageMigrationService(
        settingsProvider: settingsProvider,
        modelConfigProvider: modelProvider,
        conversationProvider: conversationProvider,
        featureProvider: featureProvider,
      ).ensureMigrationReady();

      await Future.wait([
        conversationProvider.loadConversations(),
        featureProvider.load(),
        roleplayProvider.loadSessions(),
        modelProvider.loadModels(),
        settingsProvider.loadSettings(),
      ]);

      settingsProvider.repairMediaModelSelections(modelProvider.models);
      conversationProvider.repairModelReferences(modelProvider.models);
      roleplayProvider.repairModelReferences(modelProvider.models);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = false;
        });
      }

      if (mounted) {
        _checkNewChangelog();
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

      if (!mounted) return;
      await showChangelogDialog(context, entry);

      final updatedSettings = settingsProvider.settings.copyWith(
        lastSeenChangelogVersion: currentVersion,
      );
      await settingsProvider.replaceSettings(updatedSettings);
    } catch (e) {
      debugPrint('检查更新日志失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;

    final settingsProvider = context.read<SettingsProvider>();
    return MaterialApp(
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
      // 加载完成后显示主页面，否则显示启动画面或错误
      home: _isLoading
          ? const _SplashScreen()
          : _hasError
          ? _ErrorScreen(message: _errorMessage)
          : const HomePage(),
    );
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
