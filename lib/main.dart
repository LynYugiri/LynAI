import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/conversation_provider.dart';
import 'providers/model_config_provider.dart';
import 'providers/settings_provider.dart';
import 'pages/home_page.dart';

/// LynAI - AI 对话应用
///
/// 应用入口，负责：
/// 1. 初始化 Provider 状态管理
/// 2. 从 SharedPreferences 加载持久化数据
/// 3. 构建 MaterialApp 并应用自定义主题
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConversationProvider()),
        ChangeNotifierProvider(create: (_) => ModelConfigProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: const LynAIApp(),
    ),
  );
}

/// 应用根 Widget
///
/// 在初始化时加载所有持久化数据（对话、模型配置、设置），
/// 然后根据设置中的主题颜色动态构建 Material Theme。
class LynAIApp extends StatefulWidget {
  const LynAIApp({super.key});

  @override
  State<LynAIApp> createState() => _LynAIAppState();
}

class _LynAIAppState extends State<LynAIApp> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// 加载所有持久化数据
  ///
  /// 从 SharedPreferences 中读取对话列表、模型配置和应用设置。
  Future<void> _loadData() async {
    final conversationProvider = context.read<ConversationProvider>();
    final modelProvider = context.read<ModelConfigProvider>();
    final settingsProvider = context.read<SettingsProvider>();

    await Future.wait([
      conversationProvider.loadConversations(),
      modelProvider.loadModels(),
      settingsProvider.loadSettings(),
    ]);

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 获取设置中的主题颜色
    final settings = context.watch<SettingsProvider>().settings;

    return MaterialApp(
      title: 'LynAI',
      debugShowCheckedModeBanner: false,
      // 动态主题：使用用户自定义的主题颜色作为 seed
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: settings.themeColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
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
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      themeMode: ThemeMode.system,
      // 加载完成后显示主页面，否则显示启动画面
      home: _isLoading
          ? const _SplashScreen()
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
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.1),
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
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
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
