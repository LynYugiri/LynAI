import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/model_config.dart';

/// BlueLM 本地推理状态。
enum LocalLlmState {
  unknown,
  notConfigured,
  unsupported,
  permissionRequired,
  modelNotFound,
  invalidModel,
  validated,
  initializing,
  ready,
  error,
}

LocalLlmState _stateFromName(String? name) {
  return switch (name) {
    'not_configured' => LocalLlmState.notConfigured,
    'permission_required' => LocalLlmState.permissionRequired,
    'model_not_found' => LocalLlmState.modelNotFound,
    'invalid_model' => LocalLlmState.invalidModel,
    _ => LocalLlmState.values.firstWhere(
      (value) => value.name == name,
      orElse: () => LocalLlmState.unknown,
    ),
  };
}

/// 原生桥返回的本地模型状态快照。
class LocalLlmStatus {
  const LocalLlmStatus({
    required this.state,
    this.busy = false,
    this.supportedAbi = false,
    this.apiLevel = 0,
    this.storagePermission = false,
    this.modelPath = '',
    this.resolvedConfigPath,
    this.modelVersion,
    this.missingFiles = const [],
    this.lastErrorCode,
    this.lastError,
  });

  final LocalLlmState state;
  final bool busy;
  final bool supportedAbi;
  final int apiLevel;
  final bool storagePermission;
  final String modelPath;
  final String? resolvedConfigPath;
  final String? modelVersion;
  final List<String> missingFiles;
  final int? lastErrorCode;
  final String? lastError;

  /// 是否允许作为普通 Chat 模型出现在模型列表中。
  ///
  /// 未配置、无权限、路径错误、设备不支持或初始化失败时都不显示；
  /// 校验通过、正在初始化或已就绪时显示。
  bool get isVisibleToUser => switch (state) {
    LocalLlmState.validated ||
    LocalLlmState.initializing ||
    LocalLlmState.ready => true,
    _ => false,
  };

  bool get isReady => state == LocalLlmState.ready && !busy;

  factory LocalLlmStatus.fromJson(Map<String, dynamic> json) {
    return LocalLlmStatus(
      state: _stateFromName(json['state']?.toString()),
      busy: json['busy'] as bool? ?? false,
      supportedAbi: json['supportedAbi'] as bool? ?? false,
      apiLevel: (json['apiLevel'] as num?)?.toInt() ?? 0,
      storagePermission: json['storagePermission'] as bool? ?? false,
      modelPath: json['modelPath']?.toString() ?? '',
      resolvedConfigPath: json['resolvedConfigPath']?.toString(),
      modelVersion: json['modelVersion']?.toString(),
      missingFiles: (json['missingFiles'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      lastErrorCode: (json['lastErrorCode'] as num?)?.toInt(),
      lastError: json['lastError']?.toString(),
    );
  }

  LocalLlmStatus copyWith({
    LocalLlmState? state,
    bool? busy,
    bool? supportedAbi,
    int? apiLevel,
    bool? storagePermission,
    String? modelPath,
    Object? resolvedConfigPath = _sentinel,
    Object? modelVersion = _sentinel,
    List<String>? missingFiles,
    Object? lastErrorCode = _sentinel,
    Object? lastError = _sentinel,
  }) {
    return LocalLlmStatus(
      state: state ?? this.state,
      busy: busy ?? this.busy,
      supportedAbi: supportedAbi ?? this.supportedAbi,
      apiLevel: apiLevel ?? this.apiLevel,
      storagePermission: storagePermission ?? this.storagePermission,
      modelPath: modelPath ?? this.modelPath,
      resolvedConfigPath: identical(resolvedConfigPath, _sentinel)
          ? this.resolvedConfigPath
          : resolvedConfigPath as String?,
      modelVersion: identical(modelVersion, _sentinel)
          ? this.modelVersion
          : modelVersion as String?,
      missingFiles: missingFiles ?? this.missingFiles,
      lastErrorCode: identical(lastErrorCode, _sentinel)
          ? this.lastErrorCode
          : lastErrorCode as int?,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as String?,
    );
  }

  static const _sentinel = Object();
}

/// 本地推理流中的标准化增量。
class LocalLlmDelta {
  const LocalLlmDelta({
    this.token,
    this.completed = false,
    this.errorCode,
    this.errorMessage,
  });

  final String? token;
  final bool completed;
  final int? errorCode;
  final String? errorMessage;

  bool get isError => errorCode != null || errorMessage != null;
}

/// 本地模型错误，附带错误码和可直接展示的消息。
class LocalLlmException implements Exception {
  const LocalLlmException(this.code, this.message);

  final String code;
  final String message;

  /// SDK 的 `LLM_PROMPT_TOO_LONG` / 上下文过长错误。
  bool get isContextOverflow =>
      code == '-3070' ||
      message.toLowerCase().contains('context') ||
      message.contains('上下文') ||
      message.contains('过长');

  @override
  String toString() => '$message ($code)';
}

/// 平台后端抽象，便于测试注入。
abstract class OnDeviceLlmBackend {
  Future<Map<String, dynamic>> invoke(
    String method, [
    Map<String, dynamic> arguments = const {},
  ]);

  Stream<Map<String, dynamic>> get events;

  void dispose() {}
}

class MethodChannelOnDeviceLlmBackend implements OnDeviceLlmBackend {
  MethodChannelOnDeviceLlmBackend({
    MethodChannel methodChannel = const MethodChannel('lynai/on_device_llm'),
    EventChannel eventChannel = const EventChannel(
      'lynai/on_device_llm/events',
    ),
  }) : _methodChannel = methodChannel,
       _eventChannel = eventChannel;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  @override
  Future<Map<String, dynamic>> invoke(
    String method, [
    Map<String, dynamic> arguments = const {},
  ]) async {
    final result = await _methodChannel.invokeMethod<dynamic>(
      method,
      arguments,
    );
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return {'ok': true};
  }

  @override
  Stream<Map<String, dynamic>> get events => _eventChannel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => Map<String, dynamic>.from(event as Map));

  @override
  void dispose() {}
}

class UnsupportedOnDeviceLlmBackend implements OnDeviceLlmBackend {
  const UnsupportedOnDeviceLlmBackend();

  @override
  Future<Map<String, dynamic>> invoke(
    String method, [
    Map<String, dynamic> arguments = const {},
  ]) async {
    return {
      'ok': true,
      'state': 'unsupported',
      'busy': false,
      'supportedAbi': false,
      'apiLevel': 0,
      'storagePermission': false,
      'modelPath': '',
    };
  }

  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();

  @override
  void dispose() {}
}

/// 本地 BlueLM 模型的统一服务入口。
///
/// 服务负责与 Android 桥通信、维护状态机和单生成队列；模型本身以普通
/// [ModelConfig]（`apiType = local_bluelm`）形式暴露给 [ModelConfigProvider]
/// 和 ApiService，调用方不需要直接依赖本服务。
class OnDeviceLlmService extends ChangeNotifier {
  OnDeviceLlmService({OnDeviceLlmBackend? backend})
    : _backend =
          backend ??
          (Platform.isAndroid
              ? MethodChannelOnDeviceLlmBackend()
              : const UnsupportedOnDeviceLlmBackend());

  static final OnDeviceLlmService instance = OnDeviceLlmService();

  /// Demo 默认模型路径。
  static const defaultModelPath = '/sdcard/1225';

  final OnDeviceLlmBackend _backend;
  final StreamController<Map<String, dynamic>> _eventsController =
      StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  StreamSubscription<Map<String, dynamic>>? _generationEventSubscription;
  LocalLlmStatus _status = const LocalLlmStatus(state: LocalLlmState.unknown);
  StreamController<LocalLlmDelta>? _activeController;
  String? _activeRequestId;
  bool _activeGenerationStarted = false;
  bool _disposed = false;
  int _requestCounter = 0;

  LocalLlmStatus get status => _status;

  @visibleForTesting
  bool get hasActiveGeneration => _activeController != null;

  /// 刷新原生状态并重新校验模型路径与文件。
  Future<LocalLlmStatus> refreshStatus() async {
    final status = await _applyInvokeStatus('refreshStatus');
    return status;
  }

  Future<LocalLlmStatus> setModelPath(String path) async {
    final result = await _invoke('setModelPath', {'path': path});
    return _applyStatus(result);
  }

  Future<Map<String, dynamic>> requestStoragePermission() async {
    final result = await _invoke('requestStoragePermission');
    if (result['granted'] == true) await refreshStatus();
    return result;
  }

  /// 确保模型文件有效并完成 SDK 初始化。
  ///
  /// 推理参数从 [config] 的生效值派生，缺省值与 Demo 完全一致。
  Future<LocalLlmStatus> ensureReady(ModelConfig config) async {
    if (_status.isReady) return _status;
    var current = await refreshStatus();
    if (current.isReady) return current;
    switch (current.state) {
      case LocalLlmState.unsupported:
        throw const LocalLlmException(
          'unsupported',
          '当前设备不支持 BlueLM APU（需要 arm64 的 MTK 设备）',
        );
      case LocalLlmState.notConfigured:
        throw const LocalLlmException('not_configured', '尚未设置本地模型路径，请先在设置中配置');
      case LocalLlmState.permissionRequired:
        throw const LocalLlmException(
          'permission_required',
          '需要“所有文件访问”权限才能读取模型目录',
        );
      case LocalLlmState.modelNotFound:
        throw const LocalLlmException(
          'model_not_found',
          '未找到 BlueLM 模型配置，请检查模型路径',
        );
      case LocalLlmState.invalidModel:
        throw LocalLlmException(
          'invalid_model',
          current.lastError ?? '模型文件不完整，请检查缺失文件',
        );
      case LocalLlmState.error:
        throw LocalLlmException(
          current.lastErrorCode?.toString() ?? 'error',
          current.lastError ?? '本地模型初始化失败',
        );
      case LocalLlmState.unknown:
      case LocalLlmState.validated:
      case LocalLlmState.initializing:
      case LocalLlmState.ready:
        break;
    }
    final result = await _invoke('init', {'params': _inferenceParams(config)});
    current = _applyStatus(result);
    if (!current.isReady) {
      throw LocalLlmException(
        current.lastErrorCode?.toString() ?? 'init_failed',
        current.lastError ?? '本地模型初始化失败',
      );
    }
    return current;
  }

  Future<void> release() async {
    if (_disposed) return;
    await _invoke('release');
  }

  Future<void> interrupt() async {
    await _invoke('interrupt');
  }

  /// 以与其他模型 API 相同的 [ModelConfig] 触发流式生成。
  ///
  /// 单实例单生成：并发调用会返回错误流。
  Stream<LocalLlmDelta> generate(ModelConfig config, String prompt) {
    if (_activeController != null) {
      return Stream<LocalLlmDelta>.error(
        const LocalLlmException('busy', '本地模型正在生成中，请稍后重试'),
      );
    }
    final requestId =
        'local_${++_requestCounter}_${DateTime.now().microsecondsSinceEpoch}';
    late final StreamController<LocalLlmDelta> controller;
    controller = StreamController<LocalLlmDelta>(
      onListen: () {
        unawaited(_startGeneration(controller, config, prompt, requestId));
      },
      onCancel: () {
        _cancelGeneration(controller, requestId);
      },
    );
    _activeController = controller;
    _activeRequestId = requestId;
    return controller.stream;
  }

  Future<void> _startGeneration(
    StreamController<LocalLlmDelta> controller,
    ModelConfig config,
    String prompt,
    String requestId,
  ) async {
    try {
      await ensureReady(config);
      if (!_isActive(controller, requestId)) return;
      _ensureEventSubscription();
      final result = await _invoke('generate', {
        'requestId': requestId,
        'prompt': prompt,
      });
      if (!_isActive(controller, requestId)) return;
      _activeGenerationStarted = true;
      if (result['ok'] != true) {
        final error = Map<String, dynamic>.from(
          result['error'] as Map? ?? const {},
        );
        throw LocalLlmException(
          error['code']?.toString() ?? 'generate_failed',
          error['message']?.toString() ?? '本地模型启动生成失败',
        );
      }
      _generationEventSubscription = _eventsController.stream
          .where((event) => event['requestId'] == requestId)
          .listen(
            (event) {
              if (!_isActive(controller, requestId)) return;
              switch (event['type']?.toString()) {
                case 'token':
                  final token = event['token']?.toString() ?? '';
                  if (token.isNotEmpty && !controller.isClosed) {
                    controller.add(LocalLlmDelta(token: token));
                  }
                case 'completed':
                  if (!controller.isClosed) {
                    controller.add(const LocalLlmDelta(completed: true));
                  }
                  unawaited(_finishGeneration(controller, requestId));
                case 'error':
                  if (!controller.isClosed) {
                    controller.addError(
                      LocalLlmException(
                        event['code']?.toString() ?? 'inference_failed',
                        event['message']?.toString() ?? '本地模型推理失败',
                      ),
                    );
                  }
                  unawaited(_finishGeneration(controller, requestId));
              }
            },
            onError: (Object error) {
              if (!controller.isClosed) controller.addError(error);
              unawaited(_finishGeneration(controller, requestId));
            },
            onDone: () {
              if (!controller.isClosed) {
                controller.addError(
                  const LocalLlmException('stream_closed', '本地模型输出流意外结束'),
                );
              }
              unawaited(_finishGeneration(controller, requestId));
            },
          );
    } catch (error) {
      if (!controller.isClosed) {
        controller.addError(
          error is LocalLlmException
              ? error
              : LocalLlmException('generate_failed', error.toString()),
        );
      }
      await _finishGeneration(controller, requestId);
    }
  }

  void _cancelGeneration(
    StreamController<LocalLlmDelta> controller,
    String requestId,
  ) {
    if (_activeRequestId == requestId && _activeGenerationStarted) {
      unawaited(
        _invoke('interrupt').then((_) => refreshStatus()).catchError((_) {
          return status;
        }),
      );
    }
    unawaited(_finishGeneration(controller, requestId));
  }

  bool _isActive(StreamController<LocalLlmDelta> controller, String requestId) {
    return !controller.isClosed &&
        _activeRequestId == requestId &&
        identical(_activeController, controller);
  }

  Future<void> _finishGeneration(
    StreamController<LocalLlmDelta> controller,
    String requestId,
  ) async {
    if (_activeRequestId == requestId) {
      _activeRequestId = null;
      _activeController = null;
      _activeGenerationStarted = false;
    }
    final subscription = _generationEventSubscription;
    _generationEventSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    _disposeEventSubscriptionIfIdle();
    if (!controller.isClosed) {
      try {
        await controller.close();
      } on StateError {
        // 取消路径与完成路径可能并发清理。
      }
    }
  }

  Map<String, dynamic> _inferenceParams(ModelConfig config) {
    final maxTokens = config.effectiveMaxTokens;
    final contextWindow = config.effectiveContextWindow;
    return {
      // Demo 默认值：nPredict=200 / nCtx=4096 / nThreads=4 /
      // topK=1 / topP=1.0 / temperature=0.0 / npuPower=100。
      'nPredict': (maxTokens ?? 200).clamp(1, 4096),
      'nCtx': (contextWindow ?? 4096).clamp(2048, 8192),
      'nThreads': 4,
      'topK': 1,
      'topP': config.effectiveTopP ?? 1.0,
      'temperature': config.effectiveTemperature ?? 0.0,
      'npuPower': 100,
      'multimodal': config.supportsVision,
    };
  }

  void _ensureEventSubscription() {
    if (_eventSubscription != null) return;
    _eventSubscription = _backend.events.listen(
      (event) {
        if (!_eventsController.isClosed) _eventsController.add(event);
      },
      onError: (Object error) {
        if (!_eventsController.isClosed) _eventsController.addError(error);
      },
    );
  }

  void _disposeEventSubscriptionIfIdle() {
    if (_activeController != null) return;
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  Future<LocalLlmStatus> _applyInvokeStatus(String method) async {
    final result = await _invoke(method);
    return _applyStatus(result);
  }

  Future<Map<String, dynamic>> _invoke(
    String method, [
    Map<String, dynamic> arguments = const {},
  ]) async {
    final result = await _backend.invoke(method, arguments);
    if (result['ok'] == false) {
      final error = Map<String, dynamic>.from(
        result['error'] as Map? ?? const {},
      );
      throw LocalLlmException(
        error['code']?.toString() ?? 'platform_error',
        error['message']?.toString() ?? '本地模型平台调用失败',
      );
    }
    return result;
  }

  LocalLlmStatus _applyStatus(Map<String, dynamic> json) {
    final next = LocalLlmStatus.fromJson(json);
    if (next.state != _status.state ||
        next.busy != _status.busy ||
        next.modelPath != _status.modelPath ||
        next.lastError != _status.lastError) {
      _status = next;
      if (!_disposed) notifyListeners();
    } else {
      _status = next;
    }
    return next;
  }

  @override
  void dispose() {
    _disposed = true;
    _generationEventSubscription?.cancel();
    _generationEventSubscription = null;
    _eventSubscription?.cancel();
    _eventSubscription = null;
    final activeController = _activeController;
    _activeController = null;
    _activeRequestId = null;
    _activeGenerationStarted = false;
    if (activeController != null && !activeController.isClosed) {
      activeController.close();
    }
    _eventsController.close();
    super.dispose();
  }
}

/// 从 JSON 字符串解析本地模型错误，便于 UI 直接展示。
String localLlmErrorMessage(dynamic error) {
  if (error is LocalLlmException) return error.message;
  return error.toString().replaceFirst('Exception: ', '');
}
