import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  Map<String, Object?> _metrics() {
    final target = _target;
    if (target == null || !target.isAvailable) return {'ok': false};
    final rect = target.globalRect;
    if (rect == null || rect.isEmpty) return {'ok': false};
    final metrics = target.controller.position;
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

  Future<Map<String, Object?>> _scrollTo(double offset) async {
    final target = _target;
    if (target == null || !target.isAvailable) return {'ok': false};
    final position = target.controller.position;
    final next = offset.clamp(0.0, position.maxScrollExtent);
    target.controller.jumpTo(next);
    await _endOfFrame();
    return {'ok': true, 'offset': target.controller.position.pixels};
  }

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

  Future<void> _endOfFrame() async {
    final binding = WidgetsBinding.instance;
    await binding.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
}

class SystemScrollCaptureTarget extends StatefulWidget {
  final ScrollController controller;
  final Widget child;
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
    _registerIfEnabled();
    return widget.child;
  }

  void _registerIfEnabled() {
    if (widget.enabled) {
      SystemScrollCaptureService.instance._register(_registration);
    }
  }
}

class _SystemScrollCaptureRegistration {
  final _SystemScrollCaptureTargetState state;

  const _SystemScrollCaptureRegistration(this.state);

  ScrollController get controller => state.widget.controller;

  bool get isAvailable {
    return state.mounted &&
        state.widget.enabled &&
        controller.hasClients &&
        controller.position.hasContentDimensions &&
        controller.position.maxScrollExtent > 0;
  }

  double get devicePixelRatio => MediaQuery.devicePixelRatioOf(state.context);

  Rect? get globalRect {
    final renderObject = state.context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return null;
    final origin = renderObject.localToGlobal(Offset.zero);
    return origin & renderObject.size;
  }
}
