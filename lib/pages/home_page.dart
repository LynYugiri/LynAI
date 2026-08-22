import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/app_settings.dart';
import '../models/chat_quick_action.dart';
import '../models/onboarding/onboarding_input.dart';
import '../providers/settings_provider.dart';
import '../widgets/chat_composer_keyboard.dart';
import '../widgets/chat_quick_action_wheel.dart';
import '../widgets/coach_mark_overlay.dart';
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

  OverlayEntry? _quickActionOverlay;
  ValueNotifier<ChatQuickActionWheelVisualState>? _quickActionVisual;
  Timer? _quickActionEditTimer;
  ChatQuickActionWheelMode _quickActionMode = ChatQuickActionWheelMode.normal;
  String? _quickSelectedDirection;
  static const _quickActionEditDelay = Duration(seconds: 3);
  static const _quickActionDirectionThreshold = 56.0;

  final Map<AppTab, GlobalKey> _navKeys = {
    for (final tab in AppTab.values) tab: GlobalKey(),
  };
  OverlayEntry? _guideOverlay;
  bool _guideScheduled = false;
  bool _guideSessionStarted = false;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
    _targetConversationId = widget.conversationId;
  }

  @override
  void dispose() {
    _quickActionEditTimer?.cancel();
    _removeQuickActionOverlay();
    _quickActionVisual?.dispose();
    _removeGuideOverlay();
    super.dispose();
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

  // ─── 底部导航 ──────────────────────────────────────────────

  Widget _buildBottomNavigationBar(AppSettings settings) {
    return Material(
      color: settings.themeColor.withValues(alpha: 0.08),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 80,
          child: Row(
            children: [
              for (var index = 0; index < AppTab.values.length; index++)
                Expanded(
                  child: KeyedSubtree(
                    key: _navKeys[AppTab.values[index]],
                    child: KeyedSubtree(
                      key: ValueKey(
                        'nav-${_tabSpecs[AppTab.values[index]]!.label}-'
                        '${_currentTab == AppTab.values[index] ? 'on' : 'off'}',
                      ),
                      child: index == AppTab.chat.index
                          ? _buildChatNavItem(
                              _tabSpecs[AppTab.chat]!.icon,
                              _tabSpecs[AppTab.chat]!.selectedIcon,
                              _tabSpecs[AppTab.chat]!.label,
                              _currentTab == AppTab.chat,
                              settings.themeColor,
                            )
                          : _buildNavItem(
                              index,
                              _tabSpecs[AppTab.values[index]]!.icon,
                              _tabSpecs[AppTab.values[index]]!.selectedIcon,
                              _tabSpecs[AppTab.values[index]]!.label,
                              _currentTab == AppTab.values[index],
                              settings.themeColor,
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData icon,
    IconData selectedIcon,
    String label,
    bool selected,
    Color accent,
  ) {
    final color = selected ? accent : Theme.of(context).colorScheme.outline;
    return InkResponse(
      onTap: () => _handleNavigationTap(index),
      radius: 40,
      child: _NavItemContent(
        icon: selected ? selectedIcon : icon,
        label: label,
        color: color,
        selected: selected,
        accent: accent,
      ),
    );
  }

  Widget _buildChatNavItem(
    IconData icon,
    IconData selectedIcon,
    String label,
    bool selected,
    Color accent,
  ) {
    final color = selected ? accent : Theme.of(context).colorScheme.outline;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleNavigationTap(AppTab.chat.index),
      onLongPressStart: _startQuickAction,
      onLongPressMoveUpdate: _updateQuickAction,
      onLongPressEnd: _endQuickAction,
      onLongPressCancel: _removeQuickActionOverlay,
      child: _NavItemContent(
        icon: selected ? selectedIcon : icon,
        label: label,
        color: color,
        selected: selected,
        accent: accent,
      ),
    );
  }

  // ─── 长按快捷盘 ────────────────────────────────────────────

  void _startQuickAction(LongPressStartDetails details) {
    final settings = context.read<SettingsProvider>();
    _quickActionMode = ChatQuickActionWheelMode.normal;
    _quickSelectedDirection = null;
    HapticFeedback.mediumImpact();
    _quickActionVisual = ValueNotifier(
      ChatQuickActionWheelVisualState(
        mode: _quickActionMode,
        selectedDirection: null,
        actions: settings.chatQuickActions,
      ),
    );
    _quickActionOverlay = OverlayEntry(
      builder: (_) => ValueListenableBuilder<ChatQuickActionWheelVisualState>(
        valueListenable: _quickActionVisual!,
        builder: (context, state, _) =>
            ChatQuickActionWheelOverlay(state: state),
      ),
    );
    Overlay.of(context).insert(_quickActionOverlay!);
    _quickActionEditTimer?.cancel();
    _quickActionEditTimer = Timer(_quickActionEditDelay, () {
      if (!mounted || _quickActionVisual == null) return;
      _quickActionMode = ChatQuickActionWheelMode.edit;
      _quickSelectedDirection = null;
      HapticFeedback.heavyImpact();
      _quickActionVisual!.value = ChatQuickActionWheelVisualState(
        mode: _quickActionMode,
        selectedDirection: null,
        actions: context.read<SettingsProvider>().chatQuickActions,
      );
    });
  }

  void _updateQuickAction(LongPressMoveUpdateDetails details) {
    if (_quickActionVisual == null) return;
    final offset = details.offsetFromOrigin;
    final dx = offset.dx;
    final dy = offset.dy;
    final absX = dx.abs();
    final absY = dy.abs();
    String? direction;
    if (absX > _quickActionDirectionThreshold ||
        absY > _quickActionDirectionThreshold) {
      if (dy <= -_quickActionDirectionThreshold && absY >= absX) {
        direction = 'up';
      } else if (dx <= -_quickActionDirectionThreshold && absX > absY) {
        direction = 'left';
      } else if (dx >= _quickActionDirectionThreshold && absX > absY) {
        direction = 'right';
      }
    }
    if (direction == _quickSelectedDirection) return;
    _quickSelectedDirection = direction;
    if (direction != null) {
      HapticFeedback.selectionClick();
    }
    _quickActionVisual!.value = ChatQuickActionWheelVisualState(
      mode: _quickActionMode,
      selectedDirection: direction,
      actions: context.read<SettingsProvider>().chatQuickActions,
    );
  }

  void _endQuickAction(LongPressEndDetails details) {
    _quickActionEditTimer?.cancel();
    _quickActionEditTimer = null;
    final direction = _quickSelectedDirection;
    final mode = _quickActionMode;
    _removeQuickActionOverlay();
    if (direction == null) return;

    if (mode == ChatQuickActionWheelMode.edit) {
      _showQuickActionPicker(direction);
    } else {
      _runQuickAction(direction);
    }
  }

  void _removeQuickActionOverlay() {
    _quickActionEditTimer?.cancel();
    _quickActionEditTimer = null;
    _quickActionOverlay?.remove();
    _quickActionOverlay = null;
    _quickActionVisual?.dispose();
    _quickActionVisual = null;
    _quickSelectedDirection = null;
  }

  void _runQuickAction(String direction) {
    final action = context
        .read<SettingsProvider>()
        .chatQuickActions
        .forDirection(direction);
    switch (action.type) {
      case ChatQuickAction.typeFeaturePage:
        _openFeatureFromQuickAction(action.featureId ?? 'dashboard');
      case ChatQuickAction.typeNewConversation:
        _openNewConversationFromQuickAction();
      case ChatQuickAction.typeSettings:
        _openSettings();
    }
  }

  void _openFeatureFromQuickAction(String featureId) {
    context.read<SettingsProvider>().setLastFeature(featureId);
    setState(() {
      _currentTab = AppTab.feature;
      _targetConversationId = null;
    });
  }

  void _openNewConversationFromQuickAction() {
    setState(() {
      _currentTab = AppTab.chat;
      _targetConversationId = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chatNewConversationHandler?.call();
    });
  }

  String _quickActionDirectionLabel(String direction) {
    switch (direction) {
      case 'left':
        return '←';
      case 'up':
        return '↑';
      case 'right':
        return '→';
      default:
        return direction;
    }
  }

  Future<void> _showQuickActionPicker(String direction) async {
    final settings = context.read<SettingsProvider>();
    final current = settings.chatQuickActions.forDirection(direction);
    final selected = await showModalBottomSheet<ChatQuickAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '选择「${_quickActionDirectionLabel(direction)}」的动作',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final entry in ChatQuickAction.featurePages.entries)
              ListTile(
                leading: Icon(
                  current.featureId == entry.key &&
                          current.type == ChatQuickAction.typeFeaturePage
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(entry.value),
                onTap: () =>
                    Navigator.pop(ctx, ChatQuickAction.featurePage(entry.key)),
              ),
            const Divider(),
            ListTile(
              leading: Icon(
                current.type == ChatQuickAction.typeNewConversation
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: const Text('新建对话'),
              onTap: () => Navigator.pop(
                ctx,
                const ChatQuickAction(
                  type: ChatQuickAction.typeNewConversation,
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                current.type == ChatQuickAction.typeSettings
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: const Text('设置'),
              onTap: () => Navigator.pop(
                ctx,
                const ChatQuickAction(type: ChatQuickAction.typeSettings),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('恢复默认'),
              onTap: () => Navigator.pop(
                ctx,
                ChatQuickActions.defaults().forDirection(direction),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final updated = switch (direction) {
      'left' => settings.chatQuickActions.copyWith(left: selected),
      'up' => settings.chatQuickActions.copyWith(up: selected),
      'right' => settings.chatQuickActions.copyWith(right: selected),
      _ => settings.chatQuickActions,
    };
    settings.setChatQuickActions(updated);
  }

  // ─── 功能引导 ──────────────────────────────────────────────

  void _scheduleGuidedTourIfNeeded(AppSettings settings) {
    if (_guideSessionStarted || _guideScheduled) return;
    if (settings.hasCompletedGuidedTour) return;
    _guideScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _guideScheduled = false;
      if (!mounted || _guideSessionStarted) return;
      if (context.read<SettingsProvider>().settings.hasCompletedGuidedTour) {
        return;
      }
      _startGuidedTour();
    });
  }

  void _startGuidedTour() {
    _guideSessionStarted = true;
    _removeGuideOverlay();
    if (_currentTab != AppTab.chat) {
      setState(() {
        _currentTab = AppTab.chat;
        _targetConversationId = null;
      });
    }
    _guideOverlay = OverlayEntry(
      builder: (_) => CoachMarkOverlay(
        steps: _buildGuideSteps(),
        onClose: _completeGuidedTour,
      ),
    );
    Overlay.of(context).insert(_guideOverlay!);
  }

  void _completeGuidedTour() {
    _removeGuideOverlay();
    final provider = context.read<SettingsProvider>();
    if (!provider.settings.hasCompletedGuidedTour) {
      provider.completeGuidedTour();
    }
  }

  void _removeGuideOverlay() {
    _guideOverlay?.remove();
    _guideOverlay = null;
  }

  Rect? _navRectForTab(AppTab tab) {
    final renderObject = _navKeys[tab]?.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      return renderObject.localToGlobal(Offset.zero) & renderObject.size;
    }
    return null;
  }

  Rect? _navRectForTabs(AppTab first, AppTab second) {
    final a = _navRectForTab(first);
    final b = _navRectForTab(second);
    if (a == null && b == null) return null;
    if (a == null) return b;
    if (b == null) return a;
    return Rect.fromLTRB(
      math.min(a.left, b.left),
      math.min(a.top, b.top),
      math.max(a.right, b.right),
      math.max(a.bottom, b.bottom),
    );
  }

  List<CoachMarkStep> _buildGuideSteps() {
    final input = _parseOnboardingInput();
    final purposes = input?.purposes.toSet() ?? <String>{};
    final occupation = input?.occupation ?? 'other';

    final steps = <CoachMarkStep>[
      CoachMarkStep(
        title: '这就是对话页',
        message: '以后你打开 LynAI 都会停在这里。直接和 AI 说话，它需要时会自己调用笔记、待办和知识库。',
        icon: Icons.chat_bubble_outline,
        targetRect: () => _navRectForTab(AppTab.chat),
      ),
      CoachMarkStep(
        title: '双击有快捷动作',
        message: '双击底部「功能」回到功能总览；双击「对话」新建一个对话。',
        icon: Icons.touch_app_outlined,
        targetRect: () => _navRectForTabs(AppTab.feature, AppTab.chat),
      ),
      CoachMarkStep(
        title: '长按呼出快捷盘',
        message: '长按底部「对话」，滑向 ←↑→ 快速打开功能；按住 3 秒进入编辑模式，可以改方向。',
        icon: Icons.swipe_up_alt_outlined,
        targetRect: () => _navRectForTab(AppTab.chat),
      ),
    ];

    if (purposes.contains('automation') || occupation == 'developer') {
      steps.add(
        CoachMarkStep(
          title: '去插件市场看看',
          message: '你选择了自动化方向。向导已经生成一个 SKILL，可以到「插件市场」里管理；开发者还能给 Agent 开更多工具权限。',
          icon: Icons.store_outlined,
          targetRect: () => _navRectForTab(AppTab.market),
        ),
      );
    } else if (purposes.contains('knowledge') || purposes.contains('cards')) {
      steps.add(
        CoachMarkStep(
          title: '你创建的模块在这里',
          message: '向导给你建好了知识库和记忆卡。双击「功能」进入功能总览，就能看到它们。',
          icon: Icons.widgets_outlined,
          targetRect: () => _navRectForTab(AppTab.feature),
        ),
      );
    } else if (purposes.contains('todos') || purposes.contains('schedule')) {
      steps.add(
        CoachMarkStep(
          title: '待办和日程',
          message: '长按「对话」向右滑打开待办，向左滑打开日程表；也可以在「功能」页里找到它们。',
          icon: Icons.checklist_outlined,
          targetRect: () => _navRectForTab(AppTab.chat),
        ),
      );
    } else if (purposes.contains('writing') || purposes.contains('notes')) {
      steps.add(
        CoachMarkStep(
          title: '写作与笔记',
          message: 'AI 写完可以直接落笔记。双击「功能」进入总览，点开「笔记」试试。',
          icon: Icons.edit_note_outlined,
          targetRect: () => _navRectForTab(AppTab.feature),
        ),
      );
    } else if (purposes.contains('roleplay')) {
      steps.add(
        CoachMarkStep(
          title: '情景演绎',
          message: '想和角色对话、推进剧情？双击「功能」，在总览里打开「情景演绎」。',
          icon: Icons.theater_comedy_outlined,
          targetRect: () => _navRectForTab(AppTab.feature),
        ),
      );
    } else {
      steps.add(
        CoachMarkStep(
          title: '功能总览',
          message: '双击「功能」回到总览，这里聚合了对话历史、日程、笔记、待办、知识库等所有模块。',
          icon: Icons.widgets_outlined,
          targetRect: () => _navRectForTab(AppTab.feature),
        ),
      );
    }

    steps.add(
      CoachMarkStep(
        title: '角色与 Agent',
        message: '对话页右上角可以切换角色、打开对话设置；「设置」里还有完整的角色管理和 Agent 权限。',
        icon: Icons.person_pin_circle_outlined,
        targetRect: () => _navRectForTab(AppTab.settings),
      ),
    );
    return steps;
  }

  OnboardingInput? _parseOnboardingInput() {
    final raw = context.read<SettingsProvider>().settings.onboardingInputJson;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return OnboardingInput.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // 输入损坏时按普通用户路径引导。
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    _scheduleGuidedTourIfNeeded(settings);
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
              onBackHandlerChanged: _setFeatureBackHandler,
              onDashboardHandlerChanged: _setFeatureDashboardHandler,
            ),
            const PluginMarketPage(),
            ChatPage(
              conversationId: _targetConversationId,
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
        bottomNavigationBar: _buildBottomNavigationBar(settings),
      ),
    );

    final page = !hasImage
        ? scaffold
        : Stack(
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
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(scaffoldBackgroundColor: Colors.transparent),
                child: scaffold,
              ),
            ],
          );
    return DesktopEscapeBackScope(
      onBack: () => _handleRootBack(false),
      child: page,
    );
  }
}

class _NavItemContent extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final Color accent;

  const _NavItemContent({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
