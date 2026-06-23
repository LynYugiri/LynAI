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
  final bool selected;
  final bool checked;
  final bool checkable;
  final bool longClickable;
  final bool password;
  final bool visibleToUser;
  final List<String> actions;
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
    this.selected = false,
    this.checked = false,
    this.checkable = false,
    this.longClickable = false,
    this.password = false,
    this.visibleToUser = true,
    this.actions = const [],
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
      selected: json['selected'] == true,
      checked: json['checked'] == true,
      checkable: json['checkable'] == true,
      longClickable: json['longClickable'] == true,
      password: json['password'] == true,
      visibleToUser: json['visibleToUser'] != false,
      actions: json['actions'] is List
          ? (json['actions'] as List)
                .map((item) => item?.toString() ?? '')
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const [],
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
    'selected': selected,
    'checked': checked,
    'checkable': checkable,
    'longClickable': longClickable,
    'password': password,
    'visibleToUser': visibleToUser,
    if (actions.isNotEmpty) 'actions': actions,
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
  final String textExact;
  final List<String> textAny;
  final String description;
  final String descriptionExact;
  final List<String> descriptionAny;
  final String className;
  final List<String> classNameAny;
  final String packageName;
  final String viewId;
  final List<String> viewIdAny;
  final bool? clickable;
  final bool? scrollable;
  final bool? editable;
  final bool? enabled;
  final bool? focused;
  final bool? selected;
  final bool? checked;
  final bool? checkable;
  final bool? longClickable;
  final bool? visibleToUser;
  final bool? hasText;
  final bool? hasDescription;
  final bool? targetable;
  final String action;
  final bool regex;

  const DeviceNodeQuery({
    this.text = '',
    this.textExact = '',
    this.textAny = const [],
    this.description = '',
    this.descriptionExact = '',
    this.descriptionAny = const [],
    this.className = '',
    this.classNameAny = const [],
    this.packageName = '',
    this.viewId = '',
    this.viewIdAny = const [],
    this.clickable,
    this.scrollable,
    this.editable,
    this.enabled,
    this.focused,
    this.selected,
    this.checked,
    this.checkable,
    this.longClickable,
    this.visibleToUser,
    this.hasText,
    this.hasDescription,
    this.targetable,
    this.action = '',
    this.regex = false,
  });

  factory DeviceNodeQuery.fromJson(Map<String, dynamic> json) {
    return DeviceNodeQuery(
      text: json['text']?.toString() ?? '',
      textExact: json['textExact']?.toString() ?? '',
      textAny: _stringListArg(json['textAny']),
      description: json['description']?.toString() ?? '',
      descriptionExact: json['descriptionExact']?.toString() ?? '',
      descriptionAny: _stringListArg(json['descriptionAny']),
      className: json['className']?.toString() ?? '',
      classNameAny: _stringListArg(json['classNameAny']),
      packageName: json['packageName']?.toString() ?? '',
      viewId: json['viewId']?.toString() ?? '',
      viewIdAny: _stringListArg(json['viewIdAny']),
      clickable: _boolArg(json['clickable']),
      scrollable: _boolArg(json['scrollable']),
      editable: _boolArg(json['editable']),
      enabled: _boolArg(json['enabled']),
      focused: _boolArg(json['focused']),
      selected: _boolArg(json['selected']),
      checked: _boolArg(json['checked']),
      checkable: _boolArg(json['checkable']),
      longClickable: _boolArg(json['longClickable']),
      visibleToUser: _boolArg(json['visibleToUser']),
      hasText: _boolArg(json['hasText']),
      hasDescription: _boolArg(json['hasDescription']),
      targetable: _boolArg(json['targetable']),
      action: json['action']?.toString() ?? '',
      regex: _boolArg(json['regex']) ?? false,
    );
  }

  bool matches(DeviceNode node, {List<DeviceNode> ancestors = const []}) {
    return _matches(node.text, text) &&
        _matchesExact(node.text, textExact) &&
        _matchesAny(node.text, textAny) &&
        _matches(node.description, description) &&
        _matchesExact(node.description, descriptionExact) &&
        _matchesAny(node.description, descriptionAny) &&
        _matches(node.className, className) &&
        _matchesAny(node.className, classNameAny) &&
        _matches(node.packageName, packageName) &&
        _matches(node.viewId, viewId) &&
        _matchesAny(node.viewId, viewIdAny) &&
        (clickable == null || node.clickable == clickable) &&
        (scrollable == null || node.scrollable == scrollable) &&
        (editable == null || node.editable == editable) &&
        (enabled == null || node.enabled == enabled) &&
        (focused == null || node.focused == focused) &&
        (selected == null || node.selected == selected) &&
        (checked == null || node.checked == checked) &&
        (checkable == null || node.checkable == checkable) &&
        (longClickable == null || node.longClickable == longClickable) &&
        (visibleToUser == null || node.visibleToUser == visibleToUser) &&
        (hasText == null || node.text.trim().isNotEmpty == hasText) &&
        (hasDescription == null ||
            node.description.trim().isNotEmpty == hasDescription) &&
        (targetable == null || _isTargetable(node, ancestors) == targetable) &&
        _hasAction(node, action);
  }

  bool _matches(String value, String query) {
    if (query.trim().isEmpty) return true;
    if (regex) {
      try {
        return RegExp(query, caseSensitive: false).hasMatch(value);
      } catch (_) {
        return false;
      }
    }
    return value.toLowerCase().contains(query.trim().toLowerCase());
  }

  bool _matchesExact(String value, String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return true;
    return value.trim().toLowerCase() == trimmed.toLowerCase();
  }

  bool _matchesAny(String value, List<String> queries) {
    if (queries.isEmpty) return true;
    return queries.any((query) => _matches(value, query));
  }

  bool _isTargetable(DeviceNode node, List<DeviceNode> ancestors) {
    if (node.clickable || node.longClickable || node.actions.isNotEmpty) {
      return true;
    }
    return ancestors.any(
      (item) => item.clickable || item.longClickable || item.actions.isNotEmpty,
    );
  }

  bool _hasAction(DeviceNode node, String action) {
    final trimmed = action.trim();
    if (trimmed.isEmpty) return true;
    final normalized = trimmed.toLowerCase();
    if (normalized == 'click' && node.clickable) return true;
    if (normalized == 'longclick' && node.longClickable) return true;
    if (normalized == 'settext' && node.editable) return true;
    if (normalized == 'scrollforward' && node.scrollable) return true;
    if (normalized == 'scrollbackward' && node.scrollable) return true;
    return node.actions.any((item) => item.toLowerCase() == normalized);
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

  static List<String> _stringListArg(Object? raw) {
    if (raw is String) {
      final value = raw.trim();
      return value.isEmpty ? const [] : [value];
    }
    if (raw is! List) return const [];
    return raw
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
