import 'dart:io';

import 'package:flutter/services.dart';

import '../models/device_control.dart';
import 'device_run_controller.dart';

abstract class DeviceControlBackend {
  Future<Map<String, dynamic>> execute(String name, Map<String, dynamic> args);
}

class DeviceControlService {
  DeviceControlService._();

  static final DeviceControlService instance = DeviceControlService._();

  DeviceControlBackend? _backend;

  VoidCallback? onTranslationScrollSettled;
  VoidCallback? onAccessibilityServiceReconnected;

  void setBackendForTesting(DeviceControlBackend? backend) {
    _backend = backend;
  }

  DeviceControlBackend get backend {
    return _backend ??= (Platform.isAndroid
        ? AndroidDeviceControlBackend()
        : UnsupportedDeviceControlBackend());
  }

  Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    final run = DeviceRunController.instance;
    if (name == 'device.service.status') return run.statusJson();
    if (name == 'device.sleep') return _sleep(args);
    if (name == 'device.node.find') return _findNode(args);
    if (name == 'device.node.findAll') return _findNodes(args);
    if (name == 'device.waitForNode') return _waitForNode(args);
    if (name == 'device.screen.query') return _screenQuery(args);
    if (name == 'device.screen.clickText') return _clickText(args);
    if (name == 'device.screen.waitAndClick') return _waitAndClick(args);
    if (name == 'device.screen.inputText') return _inputText(args);
    if (name == 'device.screen.waitText') return _waitText(args);
    if (name == 'device.screen.scrollUntil') return _scrollUntil(args);
    if (name == 'device.screen.readVisibleText') return _readVisibleText(args);
    if (name == 'device.screen.extractMessages') return _extractMessages(args);
    final interrupted = await run.beforeAction(name);
    if (interrupted != null) return interrupted;
    final result = await backend.execute(name, args);
    if (result['ok'] == false) return result;
    return {'ok': true, ...result};
  }

  Future<Map<String, dynamic>> _sleep(Map<String, dynamic> args) async {
    final ms = (_intArg(args['ms']) ?? 0).clamp(0, 600000).toInt();
    final interrupted = await DeviceRunController.instance.delay(
      Duration(milliseconds: ms),
    );
    return interrupted ?? {'ok': true, 'ms': ms};
  }

  Map<String, dynamic> _findNode(Map<String, dynamic> args) {
    final rawSnapshot = args['snapshot'];
    if (rawSnapshot is! Map) {
      return _error('invalid_arguments', 'device.node.find 需要 snapshot');
    }
    final snapshot = DeviceScreenSnapshot.fromJson(
      Map<String, dynamic>.from(rawSnapshot),
    );
    final query = DeviceNodeQuery.fromJson(args);
    for (final root in snapshot.roots) {
      final found = _findInTree(root, query, ancestors: const []);
      if (found != null) {
        return {'ok': true, 'result': found.toJson()};
      }
    }
    return _error('node_not_found', '未找到匹配节点');
  }

  DeviceNode? _findInTree(
    DeviceNode node,
    DeviceNodeQuery query, {
    required List<DeviceNode> ancestors,
  }) {
    if (query.matches(node, ancestors: ancestors)) return node;
    final nextAncestors = [...ancestors, node];
    for (final child in node.children) {
      final found = _findInTree(child, query, ancestors: nextAncestors);
      if (found != null) return found;
    }
    return null;
  }

  Map<String, dynamic> _findNodes(Map<String, dynamic> args) {
    final rawSnapshot = args['snapshot'];
    if (rawSnapshot is! Map) {
      return _error('invalid_arguments', 'device.node.findAll 需要 snapshot');
    }
    final snapshot = DeviceScreenSnapshot.fromJson(
      Map<String, dynamic>.from(rawSnapshot),
    );
    return _querySnapshot(snapshot, args);
  }

  Future<Map<String, dynamic>> _screenQuery(Map<String, dynamic> args) async {
    final interrupted = await DeviceRunController.instance.beforeAction(
      'device.screen.query',
    );
    if (interrupted != null) return interrupted;
    final snapshotResult = await backend.execute(
      'device.screen.snapshot',
      const {},
    );
    final rawResult = snapshotResult['result'];
    if (snapshotResult['ok'] == false || rawResult is! Map) {
      return snapshotResult;
    }
    final snapshot = DeviceScreenSnapshot.fromJson(
      Map<String, dynamic>.from(rawResult),
    );
    return _querySnapshot(snapshot, args);
  }

  Map<String, dynamic> _querySnapshot(
    DeviceScreenSnapshot snapshot,
    Map<String, dynamic> args,
  ) {
    final query = DeviceNodeQuery.fromJson(args);
    final limit = (_intArg(args['limit']) ?? 50).clamp(1, 500).toInt();
    final includeChildren = args['includeChildren'] == true;
    final nodes = <Map<String, dynamic>>[];
    for (final root in snapshot.roots) {
      _collectMatches(
        root,
        query,
        nodes,
        ancestors: const [],
        limit: limit,
        includeChildren: includeChildren,
      );
      if (nodes.length >= limit) break;
    }
    return {
      'ok': true,
      'result': {
        'platform': snapshot.platform,
        if (snapshot.packageName.isNotEmpty)
          'packageName': snapshot.packageName,
        if (snapshot.windowTitle.isNotEmpty)
          'windowTitle': snapshot.windowTitle,
        'timestamp': snapshot.timestamp.toIso8601String(),
        'count': nodes.length,
        'nodes': nodes,
      },
    };
  }

  void _collectMatches(
    DeviceNode node,
    DeviceNodeQuery query,
    List<Map<String, dynamic>> matches, {
    required List<DeviceNode> ancestors,
    required int limit,
    required bool includeChildren,
  }) {
    if (matches.length >= limit) return;
    if (query.matches(node, ancestors: ancestors)) {
      matches.add(_nodeSummary(node, ancestors, includeChildren));
      if (matches.length >= limit) return;
    }
    final nextAncestors = [...ancestors, node];
    for (final child in node.children) {
      _collectMatches(
        child,
        query,
        matches,
        ancestors: nextAncestors,
        limit: limit,
        includeChildren: includeChildren,
      );
      if (matches.length >= limit) return;
    }
  }

  Map<String, dynamic> _nodeSummary(
    DeviceNode node,
    List<DeviceNode> ancestors,
    bool includeChildren,
  ) {
    final target = _targetableNode(node, ancestors);
    return {
      'id': node.id,
      if (node.text.isNotEmpty) 'text': node.text,
      if (node.description.isNotEmpty) 'description': node.description,
      if (node.className.isNotEmpty) 'className': node.className,
      if (node.packageName.isNotEmpty) 'packageName': node.packageName,
      if (node.viewId.isNotEmpty) 'viewId': node.viewId,
      'bounds': node.bounds.toJson(),
      'clickable': node.clickable,
      'scrollable': node.scrollable,
      'editable': node.editable,
      'enabled': node.enabled,
      'focused': node.focused,
      'selected': node.selected,
      'checked': node.checked,
      'checkable': node.checkable,
      'longClickable': node.longClickable,
      'password': node.password,
      'visibleToUser': node.visibleToUser,
      if (node.actions.isNotEmpty) 'actions': node.actions,
      if (target != null && target.id != node.id) 'targetNodeId': target.id,
      if (target != null && target.id != node.id)
        'targetBounds': target.bounds.toJson(),
      if (includeChildren && node.children.isNotEmpty)
        'children': node.children.map((child) => child.toJson()).toList(),
    };
  }

  DeviceNode? _targetableNode(DeviceNode node, List<DeviceNode> ancestors) {
    if (node.clickable || node.longClickable || node.actions.isNotEmpty) {
      return node;
    }
    for (final ancestor in ancestors.reversed) {
      if (ancestor.clickable ||
          ancestor.longClickable ||
          ancestor.actions.isNotEmpty) {
        return ancestor;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _clickText(Map<String, dynamic> args) async {
    final found = await _screenQuery({...args, 'limit': 1});
    final node = _firstResultNode(found);
    if (node == null) return _error('node_not_found', '未找到可点击文本');
    final nodeId = _targetNodeId(node);
    if (nodeId != null) {
      final clicked = await execute('device.node.action', {
        'nodeId': nodeId,
        'action': args['action']?.toString() ?? 'click',
      });
      if (clicked['ok'] != false) return clicked;
      if (args['fallbackTap'] == false) return clicked;
    }
    final center = _centerOf(node);
    if (center == null) return _error('node_not_actionable', '目标节点不可点击');
    return execute('device.tap', {'x': center.$1, 'y': center.$2});
  }

  Future<Map<String, dynamic>> _waitAndClick(Map<String, dynamic> args) async {
    final found = await _waitForNode(args);
    final rawNode = found['result'];
    if (found['ok'] == false || rawNode is! Map) return found;
    final node = Map<String, dynamic>.from(rawNode);
    final nodeId = _targetNodeId(node);
    if (nodeId != null) {
      final clicked = await execute('device.node.action', {
        'nodeId': nodeId,
        'action': args['action']?.toString() ?? 'click',
      });
      if (clicked['ok'] != false) return clicked;
      if (args['fallbackTap'] == false) return clicked;
    }
    final center = _centerOf(node);
    if (center == null) return _error('node_not_actionable', '目标节点不可点击');
    return execute('device.tap', {'x': center.$1, 'y': center.$2});
  }

  Future<Map<String, dynamic>> _inputText(Map<String, dynamic> args) async {
    final text = args['text']?.toString();
    if (text == null) {
      return _error('invalid_arguments', 'device.screen.inputText 缺少 text');
    }
    final queryArgs = {
      ...args,
      'editable': args['editable'] ?? true,
      'limit': 1,
    };
    queryArgs.remove('text');
    queryArgs.remove('textExact');
    queryArgs.remove('textAny');
    final found = await _screenQuery(queryArgs);
    final node = _firstResultNode(found);
    if (node == null) return _error('editable_not_found', '未找到输入框');
    final nodeId = _targetNodeId(node) ?? node['id']?.toString();
    if (nodeId == null || nodeId.isEmpty) {
      return _error('editable_not_found', '输入框节点无效');
    }
    final focused = await execute('device.node.action', {
      'nodeId': nodeId,
      'action': 'focus',
    });
    if (focused['ok'] == false && args['requireFocus'] == true) return focused;
    return execute('device.inputText', {'nodeId': nodeId, 'text': text});
  }

  Future<Map<String, dynamic>> _waitText(Map<String, dynamic> args) async {
    return _waitForNode(args);
  }

  Future<Map<String, dynamic>> _scrollUntil(Map<String, dynamic> args) async {
    final maxScrolls = (_intArg(args['maxScrolls']) ?? 8).clamp(0, 50).toInt();
    final intervalMs = (_intArg(args['intervalMs']) ?? 250)
        .clamp(0, 10000)
        .toInt();
    final queryArgs = Map<String, dynamic>.from(args);
    queryArgs.remove('maxScrolls');
    queryArgs.remove('intervalMs');
    queryArgs.remove('scrollNodeId');
    queryArgs.remove('scrollAction');
    for (var index = 0; index <= maxScrolls; index++) {
      final found = await _screenQuery({
        ...queryArgs,
        'limit': args['limit'] ?? 10,
      });
      final rawNodes = _resultNodes(found);
      if (found['ok'] != false && rawNodes.isNotEmpty) return found;
      if (index == maxScrolls) break;
      final scrollNodeId = args['scrollNodeId']?.toString();
      Map<String, dynamic> scrolled;
      if (scrollNodeId != null && scrollNodeId.isNotEmpty) {
        scrolled = await execute('device.node.action', {
          'nodeId': scrollNodeId,
          'action': args['scrollAction']?.toString() ?? 'scrollForward',
        });
      } else {
        final scrollable = await _screenQuery({'scrollable': true, 'limit': 1});
        final node = _firstResultNode(scrollable);
        final nodeId = node == null
            ? null
            : _targetNodeId(node) ?? node['id']?.toString();
        if (nodeId == null || nodeId.isEmpty) {
          return _error('scrollable_not_found', '未找到可滚动节点');
        }
        scrolled = await execute('device.node.action', {
          'nodeId': nodeId,
          'action': args['scrollAction']?.toString() ?? 'scrollForward',
        });
      }
      if (scrolled['ok'] == false) return scrolled;
      if (intervalMs > 0) {
        final slept = await _sleep({'ms': intervalMs});
        if (slept['ok'] == false) return slept;
      }
    }
    return _error('node_not_found', '滚动后仍未找到目标节点');
  }

  Future<Map<String, dynamic>> _readVisibleText(
    Map<String, dynamic> args,
  ) async {
    final interrupted = await DeviceRunController.instance.beforeAction(
      'device.screen.readVisibleText',
    );
    if (interrupted != null) return interrupted;
    final snapshot = await backend.execute('device.screen.snapshot', const {});
    final rawResult = snapshot['result'];
    if (snapshot['ok'] == false || rawResult is! Map) return snapshot;
    final screen = DeviceScreenSnapshot.fromJson(
      Map<String, dynamic>.from(rawResult),
    );
    final limit = (_intArg(args['limit']) ?? 120).clamp(1, 500).toInt();
    final lines = <String>[];
    for (final root in screen.roots) {
      _collectTextLines(root, lines, limit);
      if (lines.length >= limit) break;
    }
    return {
      'ok': true,
      'result': {
        'platform': screen.platform,
        if (screen.packageName.isNotEmpty) 'packageName': screen.packageName,
        'lines': lines,
        'text': lines.join('\n'),
      },
    };
  }

  Future<Map<String, dynamic>> _extractMessages(
    Map<String, dynamic> args,
  ) async {
    final interrupted = await DeviceRunController.instance.beforeAction(
      'device.screen.extractMessages',
    );
    if (interrupted != null) return interrupted;
    final snapshot = await backend.execute('device.screen.snapshot', const {});
    final rawResult = snapshot['result'];
    if (snapshot['ok'] == false || rawResult is! Map) return snapshot;
    final screen = DeviceScreenSnapshot.fromJson(
      Map<String, dynamic>.from(rawResult),
    );
    final packageName = args['packageName']?.toString() ?? '';
    if (packageName.isNotEmpty && screen.packageName != packageName) {
      return _error('package_mismatch', '当前应用不是目标应用');
    }
    final limit = (_intArg(args['limit']) ?? 12).clamp(1, 80).toInt();
    final candidates = <DeviceNode>[];
    for (final node in screen.flatten()) {
      final text = node.text.trim();
      if (text.isEmpty || node.password || !node.visibleToUser) continue;
      if (_looksLikeChromeText(text)) continue;
      candidates.add(node);
    }
    candidates.sort((a, b) {
      final top = a.bounds.top.compareTo(b.bounds.top);
      return top != 0 ? top : a.bounds.left.compareTo(b.bounds.left);
    });
    final messages = candidates
        .take(limit)
        .map((node) {
          final center = (node.bounds.left + node.bounds.right) / 2;
          final speaker = center > 0
              ? (center > 540 ? 'me' : 'unknown')
              : 'unknown';
          return {
            'speaker': speaker,
            'text': node.text.trim(),
            'confidence': speaker == 'me' ? 0.55 : 0.45,
            'bounds': node.bounds.toJson(),
          };
        })
        .toList(growable: false);
    return {
      'ok': true,
      'result': {
        'platform': screen.platform,
        if (screen.packageName.isNotEmpty) 'packageName': screen.packageName,
        'messages': messages,
        'confidence': messages.isEmpty ? 0.0 : 0.55,
      },
    };
  }

  List<Map<String, dynamic>> _resultNodes(Map<String, dynamic> result) {
    final rawResult = result['result'];
    if (rawResult is! Map) return const [];
    final rawNodes = rawResult['nodes'];
    if (rawNodes is! List) return const [];
    return rawNodes
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Map<String, dynamic>? _firstResultNode(Map<String, dynamic> result) {
    final nodes = _resultNodes(result);
    return nodes.isEmpty ? null : nodes.first;
  }

  String? _targetNodeId(Map<String, dynamic> node) {
    final target = node['targetNodeId']?.toString();
    if (target != null && target.isNotEmpty) return target;
    final id = node['id']?.toString();
    return id != null && id.isNotEmpty ? id : null;
  }

  (double, double)? _centerOf(Map<String, dynamic> node) {
    final rawBounds = node['targetBounds'] ?? node['bounds'];
    if (rawBounds is! Map) return null;
    final bounds = DeviceBounds.fromJson(Map<String, dynamic>.from(rawBounds));
    return ((bounds.left + bounds.right) / 2, (bounds.top + bounds.bottom) / 2);
  }

  void _collectTextLines(DeviceNode node, List<String> lines, int limit) {
    if (lines.length >= limit) return;
    final text = node.text.trim();
    if (text.isNotEmpty && !lines.contains(text)) lines.add(text);
    final description = node.description.trim();
    if (description.isNotEmpty && !lines.contains(description)) {
      lines.add(description);
    }
    for (final child in node.children) {
      _collectTextLines(child, lines, limit);
      if (lines.length >= limit) return;
    }
  }

  bool _looksLikeChromeText(String text) {
    const ignored = {'返回', '更多', '发送', '表情', '图片', '语音', '加号'};
    return ignored.contains(text.trim());
  }

  Future<Map<String, dynamic>> _waitForNode(Map<String, dynamic> args) async {
    final timeoutMs = (_intArg(args['timeoutMs']) ?? 5000)
        .clamp(100, 600000)
        .toInt();
    final intervalMs = (_intArg(args['intervalMs']) ?? 300)
        .clamp(50, 10000)
        .toInt();
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      final interrupted = await DeviceRunController.instance.beforeAction(
        'device.waitForNode',
      );
      if (interrupted != null) return interrupted;
      final snapshot = await backend.execute(
        'device.screen.snapshot',
        const {},
      );
      final rawResult = snapshot['result'];
      if (snapshot['ok'] != false && rawResult is Map) {
        final found = _findNode({
          ...args,
          'snapshot': Map<String, dynamic>.from(rawResult),
        });
        if (found['ok'] == true) return found;
      }
      final sleepInterrupted = await DeviceRunController.instance.delay(
        Duration(milliseconds: intervalMs),
      );
      if (sleepInterrupted != null) return sleepInterrupted;
    }
    return _error('node_timeout', '等待节点超时');
  }

  static int? _intArg(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  static Map<String, dynamic> _error(String code, String message) => {
    'ok': false,
    'error': {'code': code, 'message': message},
  };
}

class AndroidDeviceControlBackend implements DeviceControlBackend {
  static const _channel = MethodChannel('lynai/device_control');
  static const _events = EventChannel('lynai/device_events');

  AndroidDeviceControlBackend() {
    _events.receiveBroadcastStream().listen(_handleEvent);
  }

  @override
  Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        _nativeMethod(name),
        args,
      );
      return result ?? {'ok': false, 'error': '平台无返回'};
    } on PlatformException catch (e) {
      return {
        'ok': false,
        'error': {'code': e.code, 'message': e.message ?? e.toString()},
      };
    }
  }

  void _handleEvent(Object? event) {
    if (event is! Map) return;
    final type = event['type']?.toString();
    if (type == 'user_touch') {
      DeviceRunController.instance.pause(reason: 'user_touch');
    } else if (type == 'translation_scroll_settled') {
      DeviceControlService.instance.onTranslationScrollSettled?.call();
    } else if (type == 'accessibility_service_reconnected') {
      DeviceControlService.instance.onAccessibilityServiceReconnected?.call();
    }
  }

  String _nativeMethod(String name) {
    return switch (name) {
      'device.screen.snapshot' => 'snapshot',
      'device.screen.context' => 'context',
      'device.screen.screenshot' => 'screenshot',
      'device.screen.ocr' => 'ocr',
      'device.tap' => 'tap',
      'device.tapRepeat' => 'tapRepeat',
      'device.swipe' => 'swipe',
      'device.pressBack' => 'pressBack',
      'device.inputText' => 'inputText',
      'device.node.action' => 'nodeAction',
      'device.service.openSettings' => 'openSettings',
      _ => name,
    };
  }
}

class UnsupportedDeviceControlBackend implements DeviceControlBackend {
  @override
  Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    return {
      'ok': false,
      'error': {'code': 'unsupported_platform', 'message': '当前平台暂不支持 $name'},
    };
  }
}
