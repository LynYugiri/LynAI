import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import 'community_page.dart';
import 'feature_page.dart';
import 'chat_page.dart';
import 'plugin_market_page.dart';
import 'settings_page.dart';

/// 底部导航的五个顶级页面。
///
/// 顺序固定为 功能 → 插件市场 → 对话 → 社区 → 设置，索引即 [AppTab.index]。
/// 把索引从散落的魔法数字抽出来，避免 home_page 内部以及外部调用方
/// （如 deep link、初始化参数）出现 `_currentIndex == 1` 这类难以维护的硬编码。
enum AppTab { feature, market, chat, community, settings }

/// 将 [AppTab] 映射为底部导航 [NavigationDestination] 的展示数据。
class _TabSpec {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _TabSpec(this.icon, this.selectedIcon, this.label);
}

const _tabSpecs = <AppTab, _TabSpec>{
  AppTab.feature: _TabSpec(Icons.widgets_outlined, Icons.widgets, '功能'),
  AppTab.market: _TabSpec(Icons.store_outlined, Icons.store, '插件市场'),
  AppTab.chat: _TabSpec(Icons.chat_bubble_outline, Icons.chat_bubble, '对话'),
  AppTab.community: _TabSpec(Icons.groups_outlined, Icons.groups, '社区'),
  AppTab.settings: _TabSpec(Icons.settings_outlined, Icons.settings, '设置'),
};

/// 应用主页面。
///
/// 底部导航包含五个选项卡：功能、插件市场、对话、社区、设置。支持背景图片与
/// 模糊效果，处理各子页面的返回和新建对话手势。
class HomePage extends StatefulWidget {
  final AppTab initialTab;
  final String? conversationId;

  const HomePage({
    super.key,
    this.initialTab = AppTab.chat,
    this.conversationId,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late AppTab _currentTab;
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
    _currentTab = widget.initialTab;
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
      _currentTab = AppTab.chat;
      _targetConversationId = conversationId;
    });
  }

  void _openSettings() {
    setState(() {
      _currentTab = AppTab.settings;
      _targetConversationId = null;
    });
  }

  void _roleChanged() {
    setState(() {
      _currentTab = AppTab.chat;
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
    final tappedTab = AppTab.values[index];
    final now = DateTime.now();
    final doubleTappedCurrent =
        tappedTab == _currentTab &&
        _lastTappedIndex == index &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!) <= _doubleTapWindow;
    _lastTappedIndex = index;
    _lastTapAt = now;

    if (doubleTappedCurrent) {
      if (tappedTab == AppTab.feature) {
        _featureDashboardHandler?.call();
        return;
      }
      if (tappedTab == AppTab.chat) {
        _chatNewConversationHandler?.call();
        return;
      }
    }

    setState(() {
      _currentTab = tappedTab;
      _targetConversationId = null;
    });
  }

  // 处理系统返回键：优先让对话页或功能页拦截，无拦截时切回对话页。
  void _handleRootBack(bool didPop) {
    if (didPop) return;

    if (_currentTab == AppTab.chat && (_chatBackHandler?.call() ?? false)) {
      return;
    }

    if (_currentTab == AppTab.feature &&
        (_featureBackHandler?.call() ?? false)) {
      return;
    }

    if (_currentTab != AppTab.chat) {
      setState(() {
        _currentTab = AppTab.chat;
        _targetConversationId = null;
      });
    }
  }

  bool get _canExitFromRoot {
    if (_currentTab != AppTab.chat) return false;
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
          index: _currentTab.index,
          children: [
            FeaturePage(
              active: _currentTab == AppTab.feature,
              onConversationTap: _navigateToChat,
              onRoleChanged: _roleChanged,
              onBackHandlerChanged: _setFeatureBackHandler,
              onDashboardHandlerChanged: _setFeatureDashboardHandler,
            ),
            const PluginMarketPage(),
            ChatPage(
              conversationId: _targetConversationId,
              roleChangeSerial: _roleChangeSerial,
              active: _currentTab == AppTab.chat,
              onBackHandlerChanged: _setChatBackHandler,
              onBackAvailabilityChanged: _setChatBackAvailability,
              onNewConversationHandlerChanged: _setChatNewConversationHandler,
              onConversationLoaded: () {
                _targetConversationId = null;
              },
            ),
            CommunityPage(
              active: _currentTab == AppTab.community,
              onOpenSettings: _openSettings,
            ),
            const SettingsPage(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentTab.index,
          onDestinationSelected: _handleNavigationTap,
          backgroundColor: settings.themeColor.withValues(alpha: 0.08),
          indicatorColor: settings.themeColor.withValues(alpha: 0.12),
          destinations: [
            for (final tab in AppTab.values)
              NavigationDestination(
                icon: Icon(_tabSpecs[tab]!.icon),
                selectedIcon: Icon(_tabSpecs[tab]!.selectedIcon),
                label: _tabSpecs[tab]!.label,
              ),
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
