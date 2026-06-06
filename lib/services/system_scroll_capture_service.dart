import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 跨平台长截图采集服务。
///
/// 通过 MethodChannel 与原生端协作用于 Android 系统的滚动截图功能。核心流程：
/// 1. 原生端发起截图请求，调用 `getMetrics` 获取滚动区域位置和尺寸
/// 2. 原生端循环调用 `scrollTo` 逐步滚动，每次截取可视区域
/// 3. 采集完成后调用 `restore` 将滚动位置恢复到初始状态
///
/// 非 Android 平台不执行任何操作。
class SystemScrollCaptureService {
  SystemScrollCaptureService._() {
    _channel.setMethodCallHandler(_handleCall);
  }

  static final SystemScrollCaptureService instance =
      SystemScrollCaptureService._();
  static const _channel = MethodChannel('lynai/scroll_capture');

  _SystemScrollCaptureRegistration? _target;
  double? _restoreOffset;
  bool _capturing = false;

  /// 是否正在进行截图采集。
  bool get isCapturing => _capturing;

  void _register(_SystemScrollCaptureRegistration target) {
    if (!Platform.isAndroid) return;
    _target = target;
  }

  void _unregister(_SystemScrollCaptureRegistration target) {
    if (_target == target) {
      _target = null;
      _restoreOffset = null;
      _capturing = false;
    }
  }

  /// 处理来自原生端的 MethodChannel 调用。
  Future<dynamic> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'getMetrics':
        return _metrics();
      case 'begin':
        _capturing = true;
        return {'ok': true};
      case 'scrollTo':
        final offset = (call.arguments as num?)?.toDouble();
        if (offset == null) return {'ok': false};
        return _scrollTo(offset);
      case 'restore':
        return _restore();
      default:
        throw PlatformException(
          code: 'not_implemented',
          message: 'Unknown scroll capture method ${call.method}',
        );
    }
  }

  /// 返回当前滚动目标的度量信息，供原生端计算截图区域和滚动步长。
  Map<String, Object?> _metrics() {
    final target = _target;
    if (target == null || !target.isAvailable) return {'ok': false};
    final rect = target.globalRect;
    if (rect == null || rect.isEmpty) return {'ok': false};
    final metrics = target.controller.position;
    // 首次调用时记录当前滚动位置，供 restore 使用
    _restoreOffset ??= metrics.pixels;
    return {
      'ok': true,
      'left': rect.left,
      'top': rect.top,
      'right': rect.right,
      'bottom': rect.bottom,
      'devicePixelRatio': target.devicePixelRatio,
      'offset': metrics.pixels,
      'maxOffset': metrics.maxScrollExtent,
      'viewportHeight': metrics.viewportDimension,
      'contentHeight': metrics.maxScrollExtent + metrics.viewportDimension,
    };
  }

  /// 将滚动目标移动到指定偏移位置。
  Future<Map<String, Object?>> _scrollTo(double offset) async {
    final target = _target;
    if (target == null || !target.isAvailable) return {'ok': false};
    final position = target.controller.position;
    final next = offset.clamp(0.0, position.maxScrollExtent);
    target.controller.jumpTo(next);
    await _endOfFrame();
    return {'ok': true, 'offset': target.controller.position.pixels};
  }

  /// 将滚动位置恢复到截图开始前的状态。
  Future<Map<String, Object?>> _restore() async {
    final target = _target;
    final restoreOffset = _restoreOffset;
    _restoreOffset = null;
    _capturing = false;
    if (target == null || restoreOffset == null || !target.isAvailable) {
      return {'ok': false};
    }
    final position = target.controller.position;
    target.controller.jumpTo(
      restoreOffset.clamp(0.0, position.maxScrollExtent),
    );
    await _endOfFrame();
    return {'ok': true};
  }

  /// 等待当前帧渲染完成后额外延迟一帧，确保原生端能截取到最新画面。
  Future<void> _endOfFrame() async {
    final binding = WidgetsBinding.instance;
    await binding.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
}

/// 标记一个可滚动区域作为系统截图的采集目标。
///
/// 包裹在任意 `ScrollController` 驱动的滚动组件外层即可启用系统截图功能。
/// [enabled] 为 false 时取消注册。
class SystemScrollCaptureTarget extends StatefulWidget {
  /// 目标区域的滚动控制器。
  final ScrollController controller;

  /// 被包裹的子组件。
  final Widget child;

  /// 是否启用截图采集注册。
  final bool enabled;

  const SystemScrollCaptureTarget({
    super.key,
    required this.controller,
    required this.child,
    this.enabled = true,
  });

  @override
  State<SystemScrollCaptureTarget> createState() =>
      _SystemScrollCaptureTargetState();
}

class _SystemScrollCaptureTargetState extends State<SystemScrollCaptureTarget> {
  late final _registration = _SystemScrollCaptureRegistration(this);

  @override
  void initState() {
    super.initState();
    _registerIfEnabled();
  }

  @override
  void didUpdateWidget(SystemScrollCaptureTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled) {
      _registerIfEnabled();
    } else {
      SystemScrollCaptureService.instance._unregister(_registration);
    }
  }

  @override
  void dispose() {
    SystemScrollCaptureService.instance._unregister(_registration);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // build 中注册确保重建后仍被 target 引用
    _registerIfEnabled();
    return widget.child;
  }

  void _registerIfEnabled() {
    if (widget.enabled) {
      SystemScrollCaptureService.instance._register(_registration);
    }
  }
}

/// 滚动截图注册令牌，封装对 target State 的引用和几何信息查询。
class _SystemScrollCaptureRegistration {
  final _SystemScrollCaptureTargetState state;

  const _SystemScrollCaptureRegistration(this.state);

  ScrollController get controller => state.widget.controller;

  /// 目标区域的滚动组件是否处于可用状态。
  bool get isAvailable {
    return state.mounted &&
        state.widget.enabled &&
        controller.hasClients &&
        controller.position.hasContentDimensions &&
        controller.position.maxScrollExtent > 0;
  }

  double get devicePixelRatio => MediaQuery.devicePixelRatioOf(state.context);

  /// 获取目标区域在屏幕上的全局矩形区域。
  Rect? get globalRect {
    final renderObject = state.context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return null;
    final origin = renderObject.localToGlobal(Offset.zero);
    return origin & renderObject.size;
  }
}
