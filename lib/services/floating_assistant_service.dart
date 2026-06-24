import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../providers/settings_provider.dart';
import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
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

  void start({
    required SettingsProvider settings,
    required ConversationProvider conversations,
    required ModelConfigProvider models,
    required FeatureProvider features,
    required PluginProvider plugins,
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
      onChanged: _syncChatState,
    );
    WidgetsBinding.instance.addObserver(this);
    settings.addListener(_sync);
    conversations.addListener(_syncChatState);
    DeviceRunController.instance.addListener(_sync);
    FloatingAssistantBridge.instance.setHandler(_handleCall);
    _sync();
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _settings?.removeListener(_sync);
    _conversations?.removeListener(_syncChatState);
    DeviceRunController.instance.removeListener(_sync);
    FloatingAssistantBridge.instance.setHandler(null);
    unawaited(_chat?.dispose());
    _chat = null;
    _settings = null;
    _conversations = null;
    unawaited(FloatingAssistantBridge.instance.hideBubble());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'attachScreenContext':
        return {'ok': false, 'error': '模型会在聊天中按需读取当前页面'};
      case 'sendMessage':
        final text = _callArgs(call)['text']?.toString() ?? '';
        unawaited(_chat?.send(text));
        return {'ok': true};
      case 'stopGeneration':
        _chat?.stop();
        return {'ok': true};
      case 'toggleMangaTranslation':
        final floating = _settings?.settings.floatingAssistant;
        if (floating?.showMangaTranslationAction != true) {
          return {'ok': false, 'error': '翻译按钮已关闭'};
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
        return {'ok': true};
      case 'clearTranslation':
        _translationRunning = false;
        _chat?.clearTranslation();
        await FloatingAssistantBridge.instance.setTranslationRunning(false);
        return {'ok': true};
      case 'transcribeAudio':
        final path = _callArgs(call)['path']?.toString() ?? '';
        return await _chat?.transcribeAudioPath(path) ??
            {'ok': false, 'error': '悬浮聊天尚未初始化'};
      case 'openConversation':
        // Native side brings the existing Activity to front; HomePage navigation
        // is intentionally left to the in-app affordance for now.
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
      default:
        throw MissingPluginException(
          'Unknown floating assistant call: ${call.method}',
        );
    }
  }

  void _sync() {
    final settings = _settings?.settings.floatingAssistant;
    if (settings == null || !settings.enabled) {
      _translationRunning = false;
      unawaited(FloatingAssistantBridge.instance.hideBubble());
      return;
    }
    if (!settings.showMangaTranslationAction && _translationRunning) {
      _translationRunning = false;
    }
    unawaited(
      FloatingAssistantBridge.instance.configure({
        'allowScreenContext': settings.allowScreenContext,
        'showMangaTranslationAction': settings.showMangaTranslationAction,
        'translationRunning': _translationRunning,
        'voiceInputMode': settings.voiceInputMode,
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

  Map<String, dynamic> _callArgs(MethodCall call) {
    final arguments = call.arguments;
    if (arguments is Map) return Map<String, dynamic>.from(arguments);
    return const {};
  }
}
