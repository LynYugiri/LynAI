import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../providers/settings_provider.dart';
import 'device_control_service.dart';
import 'device_run_controller.dart';
import 'floating_assistant_bridge.dart';

class FloatingAssistantService with WidgetsBindingObserver {
  FloatingAssistantService._();

  static final FloatingAssistantService instance = FloatingAssistantService._();

  SettingsProvider? _settings;
  bool _started = false;
  bool _foreground = true;
  bool _translationRunning = false;

  void start(SettingsProvider settings) {
    if (_started || !Platform.isAndroid) return;
    _started = true;
    _settings = settings;
    WidgetsBinding.instance.addObserver(this);
    settings.addListener(_sync);
    DeviceRunController.instance.addListener(_sync);
    FloatingAssistantBridge.instance.setHandler(_handleCall);
    _sync();
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _settings?.removeListener(_sync);
    DeviceRunController.instance.removeListener(_sync);
    FloatingAssistantBridge.instance.setHandler(null);
    _settings = null;
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
        final floating = _settings?.settings.floatingAssistant;
        if (floating?.allowScreenContext != true) {
          return {'ok': false, 'error': '悬浮助手未允许读取当前页面'};
        }
        unawaited(
          DeviceControlService.instance.execute(
            'device.screen.context',
            const {},
          ),
        );
        return {'ok': true};
      case 'toggleMangaTranslation':
        final floating = _settings?.settings.floatingAssistant;
        if (floating?.showMangaTranslationAction != true) {
          return {'ok': false, 'error': '漫画翻译按钮已关闭'};
        }
        _translationRunning = !_translationRunning;
        await FloatingAssistantBridge.instance.setTranslationRunning(
          _translationRunning,
        );
        return {'ok': true};
      case 'resumeAgent':
        DeviceRunController.instance.resume();
        return {'ok': true};
      case 'stopAgent':
        DeviceRunController.instance.stop();
        return {'ok': true};
      case 'panelOpened':
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
          'status': run.status.name,
          'purpose': run.purpose,
          'currentStep': run.currentStep,
          'lastAction': run.lastAction,
          'canResume': run.canResume,
          'canStop': run.canStop,
          if (run.pauseReason != null) 'pauseReason': run.pauseReason,
        }),
      );
    }
  }
}
