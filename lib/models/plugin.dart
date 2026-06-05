/// Lua/WebView 插件清单中的工具定义。
class PluginToolDefinition {
  final String name;
  final String description;
  final String handler;
  final Map<String, dynamic> parameters;

  const PluginToolDefinition({
    required this.name,
    required this.description,
    required this.handler,
    required this.parameters,
  });

  factory PluginToolDefinition.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? '';
    return PluginToolDefinition(
      name: name,
      description: json['description'] as String? ?? '',
      handler: json['handler'] as String? ?? name,
      parameters: Map<String, dynamic>.from(
        json['parameters'] as Map? ??
            const {'type': 'object', 'properties': <String, dynamic>{}},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'handler': handler,
    'parameters': parameters,
  };

  String? validate() {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(name)) {
      return '插件 tool 名称只能包含字母、数字、下划线和横线，且长度不超过 64';
    }
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(handler)) {
      return '插件 tool handler 必须是 Lua 全局函数名';
    }
    return null;
  }
}

/// Lua 插件导出的非模型调用函数。
class PluginFunctionDefinition {
  final String name;
  final String title;
  final String handler;

  const PluginFunctionDefinition({
    required this.name,
    required this.title,
    required this.handler,
  });

  factory PluginFunctionDefinition.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? '';
    return PluginFunctionDefinition(
      name: name,
      title: json['title'] as String? ?? name,
      handler: json['handler'] as String? ?? name,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'title': title,
    'handler': handler,
  };
}

/// WebView 插件功能页定义。
class PluginFeaturePageDefinition {
  final String id;
  final String title;
  final String icon;
  final String entry;

  const PluginFeaturePageDefinition({
    required this.id,
    required this.title,
    required this.icon,
    required this.entry,
  });

  factory PluginFeaturePageDefinition.fromJson(Map<String, dynamic> json) {
    return PluginFeaturePageDefinition(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      entry: json['entry'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'icon': icon,
    'entry': entry,
  };

  String? validate() {
    if (id.trim().isEmpty) return '插件功能页缺少 id';
    if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(id)) {
      return '插件功能页 id 只能包含字母、数字、下划线、点和横线';
    }
    if (entry.trim().isEmpty) return '插件功能页 $id 缺少 entry';
    return null;
  }
}

/// 插件自定义设置项定义。
class PluginSettingDefinition {
  final String key;
  final String type;
  final String title;
  final Object? defaultValue;
  final List<Map<String, dynamic>> options;

  const PluginSettingDefinition({
    required this.key,
    required this.type,
    required this.title,
    this.defaultValue,
    this.options = const [],
  });

  factory PluginSettingDefinition.fromJson(Map<String, dynamic> json) {
    return PluginSettingDefinition(
      key: json['key'] as String? ?? '',
      type: json['type'] as String? ?? 'string',
      title: json['title'] as String? ?? json['key'] as String? ?? '',
      defaultValue: json['default'],
      options: (json['options'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'type': type,
    'title': title,
    if (defaultValue != null) 'default': defaultValue,
    if (options.isNotEmpty) 'options': options,
  };
}

/// 插件真实配置文件定义。
class PluginConfigDefinition {
  static const defaultPath = 'config.json';
  static const defaultSchemaPath = 'config.schema.json';

  final String path;
  final String schema;

  const PluginConfigDefinition({
    this.path = defaultPath,
    this.schema = defaultSchemaPath,
  });

  factory PluginConfigDefinition.fromJson(Object? value) {
    if (value is! Map) return const PluginConfigDefinition();
    return PluginConfigDefinition(
      path: value['path'] as String? ?? defaultPath,
      schema: value['schema'] as String? ?? defaultSchemaPath,
    );
  }

  Map<String, dynamic> toJson() => {'path': path, 'schema': schema};

  String? validate() {
    if (!_isSafeRelativePluginPath(path)) return '插件 config.path 不安全: $path';
    if (!_isSafeRelativePluginPath(schema)) {
      return '插件 config.schema 不安全: $schema';
    }
    return null;
  }
}

/// 用户可在插件管理页直接编辑的插件文件。
class PluginEditableFileDefinition {
  final String path;
  final String title;
  final String type;

  const PluginEditableFileDefinition({
    required this.path,
    required this.title,
    required this.type,
  });

  factory PluginEditableFileDefinition.fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String? ?? '';
    return PluginEditableFileDefinition(
      path: path,
      title: json['title'] as String? ?? path,
      type: json['type'] as String? ?? _fileTypeFromPath(path),
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    if (title.isNotEmpty && title != path) 'title': title,
    if (type.isNotEmpty) 'type': type,
  };

  String? validate() {
    if (!_isSafeRelativePluginPath(path)) {
      return '插件 editableFiles 路径不安全: $path';
    }
    return null;
  }
}

/// 插件目录中的文件条目。
class PluginFileEntry {
  final String path;
  final int size;
  final bool isDirectory;
  final bool isEditable;
  final String type;

  const PluginFileEntry({
    required this.path,
    required this.size,
    required this.isDirectory,
    required this.isEditable,
    required this.type,
  });
}

/// 插件 manifest 的规范化表示。
class PluginManifest {
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final String icon;
  final String entry;
  final List<String> permissions;
  final List<PluginToolDefinition> tools;
  final List<PluginFunctionDefinition> functions;
  final List<PluginFeaturePageDefinition> featurePages;
  final List<PluginSettingDefinition> settings;
  final PluginConfigDefinition config;
  final List<PluginEditableFileDefinition> editableFiles;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    required this.description,
    required this.icon,
    required this.entry,
    required this.permissions,
    required this.tools,
    required this.functions,
    required this.featurePages,
    required this.settings,
    this.config = const PluginConfigDefinition(),
    this.editableFiles = const [],
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    final ui = json['ui'] as Map?;
    return PluginManifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['id'] as String? ?? '',
      version: json['version'] as String? ?? '0.0.0',
      author: json['author'] as String? ?? '',
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      entry: json['entry'] as String? ?? 'main.lua',
      permissions: (json['permissions'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      tools: (json['tools'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => PluginToolDefinition.fromJson(Map.from(item)))
          .where((item) => item.name.isNotEmpty)
          .toList(growable: false),
      functions: (json['functions'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => PluginFunctionDefinition.fromJson(Map.from(item)))
          .where((item) => item.name.isNotEmpty)
          .toList(growable: false),
      featurePages:
          (ui?['featurePages'] as List<dynamic>? ??
                  json['featurePages'] as List<dynamic>? ??
                  const [])
              .whereType<Map>()
              .map(
                (item) => PluginFeaturePageDefinition.fromJson(Map.from(item)),
              )
              .where((item) => item.id.isNotEmpty)
              .toList(growable: false),
      settings: (json['settings'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => PluginSettingDefinition.fromJson(Map.from(item)))
          .where((item) => item.key.isNotEmpty)
          .toList(growable: false),
      config: PluginConfigDefinition.fromJson(json['config']),
      editableFiles: (json['editableFiles'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => PluginEditableFileDefinition.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((item) => item.path.isNotEmpty)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    if (author.isNotEmpty) 'author': author,
    if (description.isNotEmpty) 'description': description,
    if (icon.isNotEmpty) 'icon': icon,
    'entry': entry,
    if (permissions.isNotEmpty) 'permissions': permissions,
    if (tools.isNotEmpty) 'tools': tools.map((e) => e.toJson()).toList(),
    if (functions.isNotEmpty)
      'functions': functions.map((e) => e.toJson()).toList(),
    if (featurePages.isNotEmpty)
      'ui': {'featurePages': featurePages.map((e) => e.toJson()).toList()},
    if (settings.isNotEmpty)
      'settings': settings.map((e) => e.toJson()).toList(),
    'config': config.toJson(),
    if (editableFiles.isNotEmpty)
      'editableFiles': editableFiles.map((e) => e.toJson()).toList(),
  };

  String? validate() {
    if (id.trim().isEmpty) return '插件缺少 id';
    if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(id)) {
      return '插件 id 只能包含字母、数字、下划线、点和横线';
    }
    if (name.trim().isEmpty) return '插件缺少 name';
    if (entry.trim().isEmpty) return '插件缺少 entry';
    for (final tool in tools) {
      final error = tool.validate();
      if (error != null) return error;
    }
    for (final page in featurePages) {
      final error = page.validate();
      if (error != null) return error;
    }
    final configError = config.validate();
    if (configError != null) return configError;
    for (final file in editableFiles) {
      final error = file.validate();
      if (error != null) return error;
    }
    return null;
  }
}

bool _isSafeRelativePluginPath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) return false;
  final normalized = trimmed.replaceAll('\\', '/');
  if (normalized.startsWith('/') ||
      RegExp(r'^[a-zA-Z]:/').hasMatch(normalized)) {
    return false;
  }
  final parts = normalized
      .split('/')
      .where((part) => part.isNotEmpty && part != '.')
      .toList(growable: false);
  return parts.isNotEmpty && !parts.any((part) => part == '..');
}

String _fileTypeFromPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.json')) return 'json';
  if (lower.endsWith('.md') || lower.endsWith('.markdown')) return 'markdown';
  if (lower.endsWith('.lua')) return 'lua';
  if (lower.endsWith('.js')) return 'javascript';
  if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'html';
  if (lower.endsWith('.css')) return 'css';
  if (lower.endsWith('.yaml') || lower.endsWith('.yml')) return 'yaml';
  if (lower.endsWith('.toml')) return 'toml';
  return 'text';
}

/// 已安装插件的运行时状态。
///
/// [manifest] 来自插件包自身，其他字段来自 LynAI 的本地授权和启用状态。两者
/// 分开保存，避免插件更新时覆盖用户对权限和功能页显示状态的选择。
class InstalledPlugin {
  final PluginManifest manifest;
  final String path;
  final bool enabled;
  final List<String> grantedPermissions;
  final List<String> enabledFeaturePages;
  final String? loadError;

  const InstalledPlugin({
    required this.manifest,
    required this.path,
    required this.enabled,
    required this.grantedPermissions,
    required this.enabledFeaturePages,
    this.loadError,
  });

  String get id => manifest.id;

  bool get hasError => loadError != null && loadError!.isNotEmpty;

  bool get hasAllPermissionsGranted {
    final granted = grantedPermissions.toSet();
    return manifest.permissions.every(granted.contains);
  }

  InstalledPlugin copyWith({
    PluginManifest? manifest,
    String? path,
    bool? enabled,
    List<String>? grantedPermissions,
    List<String>? enabledFeaturePages,
    Object? loadError = _sentinel,
  }) {
    return InstalledPlugin(
      manifest: manifest ?? this.manifest,
      path: path ?? this.path,
      enabled: enabled ?? this.enabled,
      grantedPermissions: grantedPermissions ?? this.grantedPermissions,
      enabledFeaturePages: enabledFeaturePages ?? this.enabledFeaturePages,
      loadError: identical(loadError, _sentinel)
          ? this.loadError
          : loadError as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'manifest': manifest.toJson(),
    'path': path,
    'enabled': enabled,
    'grantedPermissions': grantedPermissions,
    'enabledFeaturePages': enabledFeaturePages,
    if (loadError != null) 'loadError': loadError,
  };

  factory InstalledPlugin.fromJson(Map<String, dynamic> json) {
    return InstalledPlugin(
      manifest: PluginManifest.fromJson(
        Map<String, dynamic>.from(json['manifest'] as Map? ?? const {}),
      ),
      path: json['path'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      grantedPermissions:
          (json['grantedPermissions'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .toList(growable: false),
      enabledFeaturePages:
          (json['enabledFeaturePages'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .toList(growable: false),
      loadError: json['loadError'] as String?,
    );
  }

  static const _sentinel = Object();
}
