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
import 'floating_translation_controller.dart';

class FloatingAssistantService with WidgetsBindingObserver {
  FloatingAssistantService._();

  static final FloatingAssistantService instance = FloatingAssistantService._();

  SettingsProvider? _settings;
  ConversationProvider? _conversations;
  FloatingChatSessionController? _chat;
  FloatingTranslationController? _translation;
  bool _started = false;
  bool _foreground = true;
  Timer? _persistPositionTimer;

  FloatingChatSessionController? get chatController => _chat;
  FloatingTranslationController? get translationController => _translation;

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
    _translation = FloatingTranslationController(
      settings: settings,
      models: models,
      backend: backend,
    );
    _chat!.addListener(_syncChatState);
    _translation!.addListener(_syncTranslationState);
    WidgetsBinding.instance.addObserver(this);
    settings.addListener(_sync);
    conversations.addListener(_syncChatState);
    DeviceRunController.instance.addListener(_sync);
    FloatingAssistantBridge.instance.setHandler(_handleCall);
    DeviceControlService.instance.onTranslationScrollSettled = _onScrollSettled;
    DeviceControlService.instance.onTranslationScrollStarted = _onScrollStarted;
    DeviceControlService.instance.onAccessibilityServiceReconnected =
        _onServiceReconnected;
    unawaited(_translation?.loadTranslationHistory());
    _sync();
  }

  void dispose() {
    _persistPositionTimer?.cancel();
    _persistPositionTimer = null;
    _pendingPersist = null;
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _settings?.removeListener(_sync);
    _conversations?.removeListener(_syncChatState);
    _chat?.removeListener(_syncChatState);
    _translation?.removeListener(_syncTranslationState);
    DeviceRunController.instance.removeListener(_sync);
    FloatingAssistantBridge.instance.setHandler(null);
    DeviceControlService.instance.onTranslationScrollSettled = null;
    DeviceControlService.instance.onTranslationScrollStarted = null;
    DeviceControlService.instance.onAccessibilityServiceReconnected = null;
    unawaited(_chat?.dispose());
    unawaited(_translation?.dispose());
    _chat = null;
    _translation = null;
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
    unawaited(_translation?.clear());
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
      case 'requestManualTranslation':
        final floating = _settings?.settings.floatingAssistant;
        if (floating?.showMangaTranslationAction != true) {
          return {'ok': false, 'error': '翻译按钮已关闭'};
        }
        unawaited(_translation?.translateManually());
        return {'ok': true};
      case 'startAutoTranslation':
        final floating = _settings?.settings.floatingAssistant;
        if (floating?.showMangaTranslationAction != true) {
          return {'ok': false, 'error': '翻译模式已关闭'};
        }
        unawaited(_translation?.startAutomatic());
        return {'ok': true};
      case 'stopAutoTranslation':
        await _translation?.stopAutomatic();
        return {'ok': true};
      case 'clearTranslation':
        await _translation?.clear();
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
        unawaited(_translation?.clear());
        return {'ok': true};
      case 'openAccessibilitySettings':
        DeviceControlService.instance.execute('device.service.openSettings', {
          'target': 'accessibility',
        });
        return {'ok': true};
      case 'resumeAgent':
        DeviceRunController.instance.resume();
        return {'ok': true};
      case 'pauseAgent':
        DeviceRunController.instance.pause(reason: 'user_paused');
        return {'ok': true};
      case 'stopAgent':
        DeviceRunController.instance.stop();
        return {'ok': true};
      case 'panelOpened':
        _syncChatState();
        _syncTranslationState();
        return {'ok': true};
      case 'overlayPermissionLost':
        unawaited(_translation?.clear());
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

  @visibleForTesting
  void persistPositionForTest({int? bubbleX, int? bubbleY}) {
    _persistPosition(bubbleX: bubbleX, bubbleY: bubbleY);
  }

  @visibleForTesting
  bool get hasPendingPositionPersistForTest =>
      _pendingPersist != null || (_persistPositionTimer?.isActive ?? false);

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
    if (!settings.showMangaTranslationAction &&
        (_translation?.isAutomatic == true ||
            _translation?.isTranslating == true)) {
      _clearTranslationSession();
    }
    unawaited(
      FloatingAssistantBridge.instance.configure({
        'allowScreenContext': settings.allowScreenContext,
        'showMangaTranslationAction': settings.showMangaTranslationAction,
        'translationRunning': _translation?.isTranslating == true,
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
      final conversation = run.conversationId == null
          ? null
          : _conversations?.getConversation(run.conversationId!);
      unawaited(
        FloatingAssistantBridge.instance.updateAgentPlan({
          'active': true,
          'run': {
            'active': true,
            'runId': run.runId,
            'conversationId': run.conversationId,
            'status': run.status.name,
            'purpose': run.purpose,
            'currentStep': run.currentStep,
            'lastAction': run.lastAction,
            'actionCount': run.actionCount,
            'canResume': run.canResume,
            'canStop': run.canStop,
            if (run.pauseReason != null) 'pauseReason': run.pauseReason,
            if (run.errorMessage != null) 'summary': run.errorMessage,
          },
          if (conversation?.agentPlan != null)
            'plan': conversation!.agentPlan!.toJson(),
        }),
      );
    } else {
      unawaited(
        FloatingAssistantBridge.instance.updateAgentPlan({'active': false}),
      );
    }
    _syncChatState();
    _syncTranslationState();
  }

  void _syncChatState() {
    final chat = _chat;
    if (chat == null) return;
    unawaited(
      FloatingAssistantBridge.instance.updateChatState(chat.stateJson()),
    );
  }

  void _syncTranslationState() {
    final translation = _translation;
    if (translation == null) return;
    unawaited(
      FloatingAssistantBridge.instance.updateTranslationState({
        'automatic': translation.isAutomatic,
        'translating': translation.isTranslating,
        'status': translation.status,
        'error': translation.error,
        'count': translation.translations.length,
      }),
    );
  }

  void _onScrollStarted() {
    unawaited(_translation?.onScrollStarted());
  }

  void _onScrollSettled() {
    unawaited(_translation?.onScrollSettled());
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
