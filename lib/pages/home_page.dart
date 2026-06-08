import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import 'feature_page.dart';
import 'chat_page.dart';
import 'settings_page.dart';

/// 应用主页面。
///
/// 包含底部导航栏的三个选项卡：功能、对话、设置。支持背景图片与模糊效果，
/// 处理各子页面的返回和新建对话手势。
class HomePage extends StatefulWidget {
  final int initialIndex;
  final String? conversationId;

  const HomePage({super.key, this.initialIndex = 1, this.conversationId});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int _currentIndex;
  String? _targetConversationId;
  int _roleChangeSerial = 0;
  String? _cachedImagePath;
  bool _cachedImageExists = false;
  bool Function()? _featureBackHandler;
  bool Function()? _chatBackHandler;
  Future<void> Function()? _featureDashboardHandler;
  VoidCallback? _chatNewConversationHandler;
  bool _chatCanHandleBack = false;
  int? _lastTappedIndex;
  DateTime? _lastTapAt;
  static const _doubleTapWindow = Duration(milliseconds: 360);

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _targetConversationId = widget.conversationId;
  }

  // 双重检查背景图片文件是否仍存在，避免无效路径导致异常。
  bool _checkImageExists(String path) {
    if (path == _cachedImagePath) return _cachedImageExists;
    _cachedImagePath = path;
    _cachedImageExists = File(path).existsSync();
    return _cachedImageExists;
  }

  void _navigateToChat(String conversationId) {
    setState(() {
      _currentIndex = 1;
      _targetConversationId = conversationId;
    });
  }

  void _roleChanged() {
    setState(() {
      _currentIndex = 1;
      _targetConversationId = null;
      _roleChangeSerial++;
    });
  }

  void _setFeatureBackHandler(bool Function() handler) {
    _featureBackHandler = handler;
  }

  void _setChatBackHandler(bool Function() handler) {
    _chatBackHandler = handler;
  }

  void _setChatBackAvailability(bool canHandleBack) {
    if (_chatCanHandleBack == canHandleBack) return;
    setState(() => _chatCanHandleBack = canHandleBack);
  }

  void _setFeatureDashboardHandler(Future<void> Function() handler) {
    _featureDashboardHandler = handler;
  }

  void _setChatNewConversationHandler(VoidCallback handler) {
    _chatNewConversationHandler = handler;
  }

  // 处理底部导航栏点击：当前页双击则回到仪表盘或新建对话，单击则切换页面。
  void _handleNavigationTap(int index) {
    final now = DateTime.now();
    final doubleTappedCurrent =
        index == _currentIndex &&
        _lastTappedIndex == index &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) <= _doubleTapWindow;
    _lastTappedIndex = index;
    _lastTapAt = now;

    if (doubleTappedCurrent) {
      if (index == 0) {
        _featureDashboardHandler?.call();
        return;
      }
      if (index == 1) {
        _chatNewConversationHandler?.call();
        return;
      }
    }

    setState(() {
      _currentIndex = index;
      _targetConversationId = null;
    });
  }

  // 处理系统返回键：优先让对话页或功能页拦截，无拦截时切回对话页。
  void _handleRootBack(bool didPop) {
    if (didPop) return;

    if (_currentIndex == 1 && (_chatBackHandler?.call() ?? false)) {
      return;
    }

    if (_currentIndex == 0 && (_featureBackHandler?.call() ?? false)) {
      return;
    }

    if (_currentIndex != 1) {
      setState(() {
        _currentIndex = 1;
        _targetConversationId = null;
      });
    }
  }

  bool get _canExitFromRoot {
    if (_currentIndex != 1) return false;
    return !_chatCanHandleBack;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final hasImage =
        settings.backgroundImagePath != null &&
        _checkImageExists(settings.backgroundImagePath!);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final scaffold = PopScope(
      canPop: _canExitFromRoot,
      onPopInvokedWithResult: (didPop, _) => _handleRootBack(didPop),
      child: Scaffold(
        backgroundColor: hasImage ? Colors.transparent : null,
        extendBodyBehindAppBar: hasImage,
        body: IndexedStack(
          index: _currentIndex,
          children: [
            FeaturePage(
              active: _currentIndex == 0,
              onConversationTap: _navigateToChat,
              onRoleChanged: _roleChanged,
              onBackHandlerChanged: _setFeatureBackHandler,
              onDashboardHandlerChanged: _setFeatureDashboardHandler,
            ),
            ChatPage(
              conversationId: _targetConversationId,
              roleChangeSerial: _roleChangeSerial,
              active: _currentIndex == 1,
              onBackHandlerChanged: _setChatBackHandler,
              onBackAvailabilityChanged: _setChatBackAvailability,
              onNewConversationHandlerChanged: _setChatNewConversationHandler,
              onConversationLoaded: () {
                _targetConversationId = null;
              },
            ),
            const SettingsPage(),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _handleNavigationTap,
          selectedItemColor: settings.themeColor,
          unselectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.widgets_outlined),
              label: '功能',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              label: '对话',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置'),
          ],
        ),
      ),
    );

    if (!hasImage) return scaffold;

    final transparentScaffold = Theme(
      data: Theme.of(
        context,
      ).copyWith(scaffoldBackgroundColor: Colors.transparent),
      child: scaffold,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(settings.backgroundImagePath!),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        if (settings.blurEnabled)
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: settings.blurAmount,
                sigmaY: settings.blurAmount,
              ),
              child: Container(
                color: (isDark ? Colors.black : Colors.white).withValues(
                  alpha: 0.3,
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: Container(
            color: (isDark ? Colors.black : Colors.white).withValues(
              alpha: settings.blurEnabled ? 0.2 : 0.55,
            ),
          ),
        ),
        transparentScaffold,
      ],
    );
  }
}
