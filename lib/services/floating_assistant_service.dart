import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../providers/settings_provider.dart';
import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import 'backend_client.dart';
import 'device_control_service.dart';
import 'device_run_controller.dart';
import 'floating_assistant_bridge.dart';
import 'floating_chat_session_controller.dart';

class FloatingAssistantService with WidgetsBindingObserver {
  FloatingAssistantService._();

  static final FloatingAssistantService instance = FloatingAssistantService._();

  SettingsProvider? _settings;
  ConversationProvider? _conversations;
  FloatingChatSessionController? _chat;
  bool _started = false;
  bool _foreground = true;
  bool _translationRunning = false;
  Timer? _persistPositionTimer;

  /// Exposed for pages that need access to the live controller (e.g. the
  /// translation history page reads `_chat.translationHistory`).
  FloatingChatSessionController? get chatController => _chat;

  void start({
    required SettingsProvider settings,
    required ConversationProvider conversations,
    required ModelConfigProvider models,
    required FeatureProvider features,
    required PluginProvider plugins,
    BackendClient? backend,
  }) {
    if (_started || !Platform.isAndroid) return;
    _started = true;
    _settings = settings;
    _conversations = conversations;
    _chat = FloatingChatSessionController(
      settings: settings,
      conversations: conversations,
      models: models,
      features: features,
      plugins: plugins,
      backend: backend,
    );
    _chat!.addListener(_syncChatState);
    WidgetsBinding.instance.addObserver(this);
    settings.addListener(_sync);
    conversations.addListener(_syncChatState);
    DeviceRunController.instance.addListener(_sync);
    FloatingAssistantBridge.instance.setHandler(_handleCall);
    DeviceControlService.instance.onTranslationScrollSettled = _onScrollSettled;
    DeviceControlService.instance.onAccessibilityServiceReconnected =
        _onServiceReconnected;
    unawaited(_chat?.loadTranslationHistory());
    _sync();
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _settings?.removeListener(_sync);
    _conversations?.removeListener(_syncChatState);
    _chat?.removeListener(_syncChatState);
    DeviceRunController.instance.removeListener(_sync);
    FloatingAssistantBridge.instance.setHandler(null);
    DeviceControlService.instance.onTranslationScrollSettled = null;
    DeviceControlService.instance.onAccessibilityServiceReconnected = null;
    unawaited(_chat?.dispose());
    _chat = null;
    _settings = null;
    _conversations = null;
    unawaited(FloatingAssistantBridge.instance.hideBubble());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _foreground;
    _foreground = state == AppLifecycleState.resumed;
    // F2: returning to the LynAI app clears the translation session so stale
    // overlays are not left floating over our own UI; the in-flight stream is
    // cancelled too.
    if (!wasForeground && _foreground) {
      _clearTranslationSession();
    }
    _sync();
  }

  void _clearTranslationSession() {
    _translationRunning = false;
    _chat?.clearTranslation();
    unawaited(FloatingAssistantBridge.instance.setTranslationRunning(false));
    unawaited(FloatingAssistantBridge.instance.clearTranslationOverlay());
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'sendMessage':
        final text = _callArgs(call)['text']?.toString() ?? '';
        unawaited(_chat?.send(text));
        return {'ok': true};
      case 'stopGeneration':
        _chat?.stop();
        return {'ok': true};
      case 'newConversation':
        _chat?.startNewConversation();
        return {'ok': true};
      case 'toggleMangaTranslation':
        final floating = _settings?.settings.floatingAssistant;
        if (floating?.showMangaTranslationAction != true) {
          return {'ok': false, 'error': '翻译按钮已关闭'};
        }
        // A2: real toggle — if translation is in flight, stop it; otherwise start.
        if (_translationRunning || (_chat?.isTranslationStreaming ?? false)) {
          _translationRunning = false;
          await _chat?.stopTranslation();
          await FloatingAssistantBridge.instance.setTranslationRunning(false);
          unawaited(FloatingAssistantBridge.instance.clearTranslationOverlay());
          return {'ok': true, 'action': 'stopped'};
        }
        _translationRunning = true;
        await FloatingAssistantBridge.instance.setTranslationRunning(true);
        unawaited(
          _chat?.translateCurrentScreen().whenComplete(() {
            _translationRunning = false;
            unawaited(
              FloatingAssistantBridge.instance.setTranslationRunning(false),
            );
          }),
        );
        return {'ok': true, 'action': 'started'};
      case 'clearTranslation':
        _translationRunning = false;
        _chat?.clearTranslation();
        await FloatingAssistantBridge.instance.setTranslationRunning(false);
        unawaited(FloatingAssistantBridge.instance.clearTranslationOverlay());
        return {'ok': true};
      case 'transcribeAudio':
        final path = _callArgs(call)['path']?.toString() ?? '';
        return await _chat?.transcribeAudioPath(path) ??
            {'ok': false, 'error': '悬浮聊天尚未初始化'};
      case 'openConversation':
        // F2: user tapped "打开" to return to LynAI — clear translation.
        _clearTranslationSession();
        return {'ok': true};
      case 'screenOff':
        // F3: stop in-flight translation (keep cache so a quick screen-on
        // could resume). The native side already cleared the overlay.
        _translationRunning = false;
        _chat?.stopTranslation();
        unawaited(
          FloatingAssistantBridge.instance.setTranslationRunning(false),
        );
        return {'ok': true};
      case 'openAccessibilitySettings':
        DeviceControlService.instance.execute('device.service.openSettings', {
          'target': 'accessibility',
        });
        return {'ok': true};
      case 'resumeAgent':
        DeviceRunController.instance.resume();
        return {'ok': true};
      case 'stopAgent':
        DeviceRunController.instance.stop();
        return {'ok': true};
      case 'panelOpened':
        _syncChatState();
        return {'ok': true};
      case 'overlayPermissionLost':
        _translationRunning = false;
        _chat?.clearTranslation();
        return {'ok': true};
      case 'bubbleMoved':
        _persistPosition(
          bubbleX: _callArgs(call)['x'] as int?,
          bubbleY: _callArgs(call)['y'] as int?,
        );
        return {'ok': true};
      case 'panelMoved':
        _persistPosition(
          panelX: _callArgs(call)['x'] as int?,
          panelY: _callArgs(call)['y'] as int?,
        );
        return {'ok': true};
      case 'panelResized':
        _persistPosition(
          panelWidth: _callArgs(call)['width'] as int?,
          panelHeight: _callArgs(call)['height'] as int?,
          panelX: _callArgs(call)['x'] as int?,
          panelY: _callArgs(call)['y'] as int?,
        );
        return {'ok': true};
      default:
        throw MissingPluginException(
          'Unknown floating assistant call: ${call.method}',
        );
    }
  }

  void _persistPosition({
    int? bubbleX,
    int? bubbleY,
    int? panelX,
    int? panelY,
    int? panelWidth,
    int? panelHeight,
  }) {
    // A5: debounce persist + settings sync so a live drag does not cascade
    // configure/agentPlan/chatState channel calls every move frame.
    _pendingPersist = (
      bubbleX: bubbleX,
      bubbleY: bubbleY,
      panelX: panelX,
      panelY: panelY,
      panelWidth: panelWidth,
      panelHeight: panelHeight,
    );
    _persistPositionTimer?.cancel();
    _persistPositionTimer = Timer(const Duration(milliseconds: 150), () {
      _persistPositionTimer = null;
      final p = _pendingPersist;
      if (p == null) return;
      _pendingPersist = null;
      final settings = _settings;
      if (settings == null) return;
      final current = settings.settings.floatingAssistant;
      settings.updateFloatingAssistant(
        current.copyWith(
          bubbleX: p.bubbleX,
          bubbleY: p.bubbleY,
          panelX: p.panelX,
          panelY: p.panelY,
          panelWidth: p.panelWidth,
          panelHeight: p.panelHeight,
        ),
      );
    });
  }

  ({
    int? bubbleX,
    int? bubbleY,
    int? panelX,
    int? panelY,
    int? panelWidth,
    int? panelHeight,
  })?
  _pendingPersist;

  void _sync() {
    final settings = _settings?.settings.floatingAssistant;
    if (settings == null || !settings.enabled) {
      // F2: feature disabled — stop any in-flight translation before hiding
      // the bubble so a late stream completion cannot re-add overlays.
      _clearTranslationSession();
      unawaited(FloatingAssistantBridge.instance.hideBubble());
      return;
    }
    if (!settings.showMangaTranslationAction && _translationRunning) {
      // F2: translation action disabled mid-stream — stop + clear overlay.
      _clearTranslationSession();
    }
    unawaited(
      FloatingAssistantBridge.instance.configure({
        'allowScreenContext': settings.allowScreenContext,
        'showMangaTranslationAction': settings.showMangaTranslationAction,
        'translationRunning': _translationRunning,
        'voiceInputMode': settings.voiceInputMode,
        'mangaTargetLanguage': settings.mangaTargetLanguage,
        'mangaLayoutMode': settings.mangaLayoutMode,
        'mangaOverlayStyle': settings.mangaOverlayStyle,
        'mangaOverlayOpacity': settings.mangaOverlayOpacity,
        'bubbleX': settings.bubbleX,
        'bubbleY': settings.bubbleY,
        'panelX': settings.panelX,
        'panelY': settings.panelY,
        'panelWidth': settings.panelWidth,
        'panelHeight': settings.panelHeight,
      }),
    );
    final run = DeviceRunController.instance.snapshot;
    final shouldShow =
        (!_foreground && settings.showBubbleInBackground) ||
        (settings.showAgentPlan && run.isActive);
    if (shouldShow) {
      unawaited(FloatingAssistantBridge.instance.showBubble());
    } else {
      unawaited(FloatingAssistantBridge.instance.hideBubble());
    }
    if (settings.showAgentPlan && run.isActive) {
      unawaited(
        FloatingAssistantBridge.instance.updateAgentPlan({
          'active': true,
          'status': run.status.name,
          'purpose': run.purpose,
          'currentStep': run.currentStep,
          'lastAction': run.lastAction,
          'canResume': run.canResume,
          'canStop': run.canStop,
          if (run.pauseReason != null) 'pauseReason': run.pauseReason,
        }),
      );
    } else {
      unawaited(
        FloatingAssistantBridge.instance.updateAgentPlan({'active': false}),
      );
    }
    _syncChatState();
  }

  void _syncChatState() {
    final chat = _chat;
    if (chat == null) return;
    unawaited(
      FloatingAssistantBridge.instance.updateChatState(chat.stateJson()),
    );
  }

  void _onScrollSettled() {
    unawaited(_chat?.onTranslationScrollSettled());
  }

  void _onServiceReconnected() {
    _sync();
  }

  Map<String, dynamic> _callArgs(MethodCall call) {
    final arguments = call.arguments;
    if (arguments is Map) return Map<String, dynamic>.from(arguments);
    return const {};
  }
}
