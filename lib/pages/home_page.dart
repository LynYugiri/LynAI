import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_settings.dart';
import '../providers/settings_provider.dart';
import 'history_page.dart';
import 'chat_page.dart';
import 'settings_page.dart';

/// 应用主页面
///
/// 包含底部导航栏，管理三个主要页面：
/// - 左侧：对话历史列表
/// - 中间：新对话页面
/// - 右侧：设置页面
///
/// 使用 IndexedStack 保持页面状态，切换时不会丢失状态。
/// 支持通过参数跳转到指定页面和指定对话。
class HomePage extends StatefulWidget {
  /// 初始选中的导航索引
  final int initialIndex;

  /// 跳转到指定对话ID
  final String? conversationId;

  const HomePage({super.key, this.initialIndex = 1, this.conversationId});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int _currentIndex;
  String? _targetConversationId;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _targetConversationId = widget.conversationId;
  }

  /// 处理从历史列表跳转到聊天页面的导航
  void _navigateToChat(String conversationId) {
    setState(() {
      _currentIndex = 1; // 切换到中间聊天页
      _targetConversationId = conversationId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;

    return Scaffold(
      body: _buildBody(settings),
      bottomNavigationBar: _buildBottomNav(settings),
    );
  }

  /// 构建页面主体，使用 IndexedStack 保持页面状态
  Widget _buildBody(AppSettings settings) {
    return IndexedStack(
      index: _currentIndex,
      children: [
        // 左侧：对话历史列表
        HistoryPage(onConversationTap: _navigateToChat),
        // 中间：新对话 / 继续对话
        ChatPage(
          conversationId: _targetConversationId,
          onConversationLoaded: () {
            // 加载完成后清除目标ID，避免重复加载
            _targetConversationId = null;
          },
        ),
        // 右侧：设置
        const SettingsPage(),
      ],
    );
  }

  /// 构建底部导航栏，使用自定义主题颜色
  Widget _buildBottomNav(AppSettings settings) {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (index) {
        setState(() {
          _currentIndex = index;
          _targetConversationId = null;
        });
      },
      selectedItemColor: settings.themeColor,
      unselectedItemColor: Colors.grey,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.history),
          label: '历史',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.chat_bubble_outline),
          label: '对话',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: '设置',
        ),
      ],
    );
  }
}

