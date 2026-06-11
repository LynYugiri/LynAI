enum DeviceRunStatus {
  idle,
  running,
  paused,
  stopping,
  stopped,
  completed,
  failed,
}

class DeviceBounds {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const DeviceBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  factory DeviceBounds.fromJson(Map<String, dynamic> json) {
    return DeviceBounds(
      left: _doubleValue(json['left']),
      top: _doubleValue(json['top']),
      right: _doubleValue(json['right']),
      bottom: _doubleValue(json['bottom']),
    );
  }

  Map<String, dynamic> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };

  static double _doubleValue(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}

class DeviceNode {
  final String id;
  final String text;
  final String description;
  final String className;
  final String packageName;
  final String viewId;
  final DeviceBounds bounds;
  final bool clickable;
  final bool scrollable;
  final bool editable;
  final bool enabled;
  final bool focused;
  final List<DeviceNode> children;

  const DeviceNode({
    required this.id,
    this.text = '',
    this.description = '',
    this.className = '',
    this.packageName = '',
    this.viewId = '',
    required this.bounds,
    this.clickable = false,
    this.scrollable = false,
    this.editable = false,
    this.enabled = true,
    this.focused = false,
    this.children = const [],
  });

  factory DeviceNode.fromJson(Map<String, dynamic> json) {
    final children = json['children'];
    return DeviceNode(
      id: json['id']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      className: json['className']?.toString() ?? '',
      packageName: json['packageName']?.toString() ?? '',
      viewId: json['viewId']?.toString() ?? '',
      bounds: DeviceBounds.fromJson(
        Map<String, dynamic>.from(json['bounds'] as Map? ?? const {}),
      ),
      clickable: json['clickable'] == true,
      scrollable: json['scrollable'] == true,
      editable: json['editable'] == true,
      enabled: json['enabled'] != false,
      focused: json['focused'] == true,
      children: children is List
          ? children
                .whereType<Map>()
                .map(
                  (item) =>
                      DeviceNode.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    if (text.isNotEmpty) 'text': text,
    if (description.isNotEmpty) 'description': description,
    if (className.isNotEmpty) 'className': className,
    if (packageName.isNotEmpty) 'packageName': packageName,
    if (viewId.isNotEmpty) 'viewId': viewId,
    'bounds': bounds.toJson(),
    'clickable': clickable,
    'scrollable': scrollable,
    'editable': editable,
    'enabled': enabled,
    'focused': focused,
    if (children.isNotEmpty)
      'children': children.map((item) => item.toJson()).toList(growable: false),
  };

  Iterable<DeviceNode> flatten() sync* {
    yield this;
    for (final child in children) {
      yield* child.flatten();
    }
  }
}

class DeviceScreenSnapshot {
  final String platform;
  final String packageName;
  final String windowTitle;
  final DateTime timestamp;
  final List<DeviceNode> roots;

  const DeviceScreenSnapshot({
    required this.platform,
    this.packageName = '',
    this.windowTitle = '',
    required this.timestamp,
    this.roots = const [],
  });

  factory DeviceScreenSnapshot.fromJson(Map<String, dynamic> json) {
    final roots = json['roots'];
    return DeviceScreenSnapshot(
      platform: json['platform']?.toString() ?? '',
      packageName: json['packageName']?.toString() ?? '',
      windowTitle: json['windowTitle']?.toString() ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      roots: roots is List
          ? roots
                .whereType<Map>()
                .map(
                  (item) =>
                      DeviceNode.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'platform': platform,
    if (packageName.isNotEmpty) 'packageName': packageName,
    if (windowTitle.isNotEmpty) 'windowTitle': windowTitle,
    'timestamp': timestamp.toIso8601String(),
    'roots': roots.map((item) => item.toJson()).toList(growable: false),
  };

  Iterable<DeviceNode> flatten() sync* {
    for (final root in roots) {
      yield* root.flatten();
    }
  }
}

class DeviceNodeQuery {
  final String text;
  final String description;
  final String className;
  final String packageName;
  final String viewId;
  final bool? clickable;
  final bool? scrollable;
  final bool? editable;

  const DeviceNodeQuery({
    this.text = '',
    this.description = '',
    this.className = '',
    this.packageName = '',
    this.viewId = '',
    this.clickable,
    this.scrollable,
    this.editable,
  });

  factory DeviceNodeQuery.fromJson(Map<String, dynamic> json) {
    return DeviceNodeQuery(
      text: json['text']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      className: json['className']?.toString() ?? '',
      packageName: json['packageName']?.toString() ?? '',
      viewId: json['viewId']?.toString() ?? '',
      clickable: _boolArg(json['clickable']),
      scrollable: _boolArg(json['scrollable']),
      editable: _boolArg(json['editable']),
    );
  }

  bool matches(DeviceNode node) {
    return _contains(node.text, text) &&
        _contains(node.description, description) &&
        _contains(node.className, className) &&
        _contains(node.packageName, packageName) &&
        _contains(node.viewId, viewId) &&
        (clickable == null || node.clickable == clickable) &&
        (scrollable == null || node.scrollable == scrollable) &&
        (editable == null || node.editable == editable);
  }

  static bool _contains(String value, String query) {
    if (query.trim().isEmpty) return true;
    return value.toLowerCase().contains(query.trim().toLowerCase());
  }

  static bool? _boolArg(Object? raw) {
    if (raw is bool) return raw;
    if (raw is String) {
      final value = raw.trim().toLowerCase();
      if (value == 'true') return true;
      if (value == 'false') return false;
    }
    return null;
  }
}
