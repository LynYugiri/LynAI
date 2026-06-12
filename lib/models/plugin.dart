final _pluginApiNamePattern = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');
final _luaGlobalFunctionPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

String? _validatePluginApiDefinition({
  required String kind,
  required String name,
  required String handler,
}) {
  if (!_pluginApiNamePattern.hasMatch(name)) {
    return '插件 $kind 名称只能包含字母、数字、下划线和横线，且长度不超过 64';
  }
  if (!_luaGlobalFunctionPattern.hasMatch(handler)) {
    return '插件 $kind handler 必须是 Lua 全局函数名';
  }
  return null;
}

/// Lua/WebView 插件清单中的工具定义。
class PluginToolDefinition {
  /// 工具名称，用于在 API 调用时标识该工具。
  final String name;

  /// 工具的描述信息，供模型理解工具用途。
  final String description;

  /// 对应的 Lua 全局函数名，用于执行工具逻辑。
  final String handler;

  /// 工具参数的 JSON Schema 定义。
  final Map<String, dynamic> parameters;

  /// 创建一个插件工具定义实例。
  const PluginToolDefinition({
    required this.name,
    required this.description,
    required this.handler,
    required this.parameters,
  });

  /// 从 JSON 数据创建 [PluginToolDefinition] 实例。
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

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'handler': handler,
    'parameters': parameters,
  };

  /// 校验工具定义的合法性，返回错误信息或 null。
  String? validate() =>
      _validatePluginApiDefinition(kind: 'tool', name: name, handler: handler);
}

/// Lua 插件导出的非模型调用函数。
class PluginFunctionDefinition {
  /// 函数名称，用于在 UI 中标识该函数。
  final String name;

  /// 函数在界面上显示的标题。
  final String title;

  /// 对应的 Lua 全局函数名，用于执行函数逻辑。
  final String handler;

  /// 函数描述，供 Agent 理解用途。
  final String description;

  /// 函数参数 JSON Schema。
  final Map<String, dynamic> parameters;

  /// 创建一个插件函数定义实例。
  const PluginFunctionDefinition({
    required this.name,
    required this.title,
    required this.handler,
    this.description = '',
    this.parameters = const {
      'type': 'object',
      'properties': <String, dynamic>{},
    },
  });

  /// 从 JSON 数据创建 [PluginFunctionDefinition] 实例。
  factory PluginFunctionDefinition.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? '';
    return PluginFunctionDefinition(
      name: name,
      title: json['title'] as String? ?? name,
      handler: json['handler'] as String? ?? name,
      description: json['description'] as String? ?? '',
      parameters: Map<String, dynamic>.from(
        json['parameters'] as Map? ??
            const {'type': 'object', 'properties': <String, dynamic>{}},
      ),
    );
  }

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() => {
    'name': name,
    'title': title,
    'handler': handler,
    if (description.isNotEmpty) 'description': description,
    'parameters': parameters,
  };

  /// 校验函数定义的合法性，返回错误信息或 null。
  String? validate() => _validatePluginApiDefinition(
    kind: 'function',
    name: name,
    handler: handler,
  );
}

/// 插件提供的按需加载 Skill 定义。
class PluginSkillDefinition {
  /// Skill 名称，用于定位 `skills/<name>.md`。
  final String name;

  /// Skill 在界面上显示的标题。
  final String title;

  /// Skill 摘要，供 Agent 判断是否需要加载正文。
  final String description;

  /// 更具体的触发场景说明。
  final String whenToUse;

  /// Skill 标签，用于筛选和搜索。
  final List<String> tags;

  /// 是否允许模型自动按需加载。
  final bool modelInvocable;

  /// 是否允许用户手动调用。
  final bool userInvocable;

  /// 创建一个插件 Skill 定义实例。
  const PluginSkillDefinition({
    required this.name,
    required this.title,
    this.description = '',
    this.whenToUse = '',
    this.tags = const [],
    this.modelInvocable = true,
    this.userInvocable = true,
  });

  /// 从 JSON 数据创建 [PluginSkillDefinition] 实例。
  factory PluginSkillDefinition.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? '';
    return PluginSkillDefinition(
      name: name,
      title: json['title'] as String? ?? name,
      description: json['description'] as String? ?? '',
      whenToUse:
          json['whenToUse'] as String? ?? json['when_to_use'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      modelInvocable:
          json['modelInvocable'] as bool? ??
          !(json['disableModelInvocation'] as bool? ?? false),
      userInvocable: json['userInvocable'] as bool? ?? true,
    );
  }

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() => {
    'name': name,
    if (title.isNotEmpty && title != name) 'title': title,
    if (description.isNotEmpty) 'description': description,
    if (whenToUse.isNotEmpty) 'whenToUse': whenToUse,
    if (tags.isNotEmpty) 'tags': tags,
    if (!modelInvocable) 'modelInvocable': false,
    if (!userInvocable) 'userInvocable': false,
  };

  /// 校验 Skill 定义的合法性，返回错误信息或 null。
  String? validate() {
    if (!_pluginApiNamePattern.hasMatch(name)) {
      return '插件 skill 名称只能包含字母、数字、下划线和横线，且长度不超过 64';
    }
    return null;
  }
}

/// WebView 插件功能页定义。
class PluginFeaturePageDefinition {
  /// 功能页唯一标识符。
  final String id;

  /// 功能页在界面上显示的标题。
  final String title;

  /// 功能页的图标标识符或路径。
  final String icon;

  /// 功能页的入口文件路径（HTML 或 Lua）。
  final String entry;

  /// 是否在设置页面中显示该功能页。
  final bool showInSettings;

  /// 是否在仪表盘页面中显示该功能页。
  final bool showInDashboard;

  /// 创建一个插件功能页定义实例。
  const PluginFeaturePageDefinition({
    required this.id,
    required this.title,
    required this.icon,
    required this.entry,
    this.showInSettings = false,
    this.showInDashboard = true,
  });

  /// 从 JSON 数据创建 [PluginFeaturePageDefinition] 实例。
  factory PluginFeaturePageDefinition.fromJson(Map<String, dynamic> json) {
    return PluginFeaturePageDefinition(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      entry: json['entry'] as String? ?? '',
      showInSettings: json['showInSettings'] as bool? ?? false,
      showInDashboard: json['showInDashboard'] as bool? ?? true,
    );
  }

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'icon': icon,
    'entry': entry,
    if (showInSettings) 'showInSettings': true,
    if (!showInDashboard) 'showInDashboard': false,
  };

  /// 校验功能页定义的合法性，返回错误信息或 null。
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
  /// 设置项的键名，用于存储和读取设置值。
  final String key;

  /// 设置项的类型，如 'string'、'boolean'、'select' 等。
  final String type;

  /// 设置项在界面上显示的标题。
  final String title;

  /// 设置项的默认值。
  final Object? defaultValue;

  /// 当 type 为 'select' 时的选项列表。
  final List<Map<String, dynamic>> options;

  /// 创建一个插件设置项定义实例。
  const PluginSettingDefinition({
    required this.key,
    required this.type,
    required this.title,
    this.defaultValue,
    this.options = const [],
  });

  /// 从 JSON 数据创建 [PluginSettingDefinition] 实例。
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

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() => {
    'key': key,
    'type': type,
    'title': title,
    if (defaultValue != null) 'default': defaultValue,
    if (options.isNotEmpty) 'options': options,
  };
}

/// 插件真实配置文件定义。
///
/// 描述 config.json 和 config.schema.json 的相对路径，用于插件表单渲染和校验。
class PluginConfigDefinition {
  /// 配置文件的默认路径。
  static const defaultPath = 'config.json';

  /// 配置 Schema 的默认路径。
  static const defaultSchemaPath = 'config.schema.json';

  /// 配置文件的相对路径。
  final String path;

  /// 配置 Schema 文件的相对路径。
  final String schema;

  /// 创建一个插件配置文件定义实例。
  const PluginConfigDefinition({
    this.path = defaultPath,
    this.schema = defaultSchemaPath,
  });

  /// 从 JSON 数据创建 [PluginConfigDefinition] 实例。
  factory PluginConfigDefinition.fromJson(Object? value) {
    if (value is! Map) return const PluginConfigDefinition();
    return PluginConfigDefinition(
      path: value['path'] as String? ?? defaultPath,
      schema: value['schema'] as String? ?? defaultSchemaPath,
    );
  }

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() => {'path': path, 'schema': schema};

  /// 校验配置文件路径的安全性，返回错误信息或 null。
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
  /// 可编辑文件的相对路径。
  final String path;

  /// 文件在编辑器中显示的标题。
  final String title;

  /// 文件的类型标识符，用于语法高亮。
  final String type;

  /// 文件内容为空时的默认模板文件路径。
  final String? defaultPath;

  /// 创建一个可编辑插件文件定义实例。
  const PluginEditableFileDefinition({
    required this.path,
    required this.title,
    required this.type,
    this.defaultPath,
  });

  /// 从 JSON 数据创建 [PluginEditableFileDefinition] 实例。
  factory PluginEditableFileDefinition.fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String? ?? '';
    final dp = (json['defaultPath'] as String? ?? '').trim();
    return PluginEditableFileDefinition(
      path: path,
      title: json['title'] as String? ?? path,
      type: json['type'] as String? ?? fileTypeFromPath(path),
      defaultPath: dp.isEmpty ? null : dp,
    );
  }

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() => {
    'path': path,
    if (title.isNotEmpty && title != path) 'title': title,
    if (type.isNotEmpty) 'type': type,
    if (defaultPath != null && defaultPath!.isNotEmpty)
      'defaultPath': defaultPath,
  };

  /// 校验可编辑文件路径的安全性，返回错误信息或 null。
  String? validate() {
    if (!_isSafeRelativePluginPath(path)) {
      return '插件 editableFiles 路径不安全: $path';
    }
    if (defaultPath != null && defaultPath!.isNotEmpty) {
      if (!_isSafeRelativePluginPath(defaultPath!)) {
        return '插件 editableFiles defaultPath 不安全: $defaultPath';
      }
    }
    return null;
  }
}

/// 插件目录中的文件条目。
class PluginFileEntry {
  /// 文件的相对路径。
  final String path;

  /// 文件大小（字节）。
  final int size;

  /// 是否为目录。
  final bool isDirectory;

  /// 是否可在应用内编辑。
  final bool isEditable;

  /// 是否有对应的默认模板文件。
  final bool hasDefault;

  /// 当前是否为默认模板文件内容。
  final bool isDefault;

  /// 文件类型标识符。
  final String type;

  /// 创建一个插件文件条目实例。
  const PluginFileEntry({
    required this.path,
    required this.size,
    required this.isDirectory,
    required this.isEditable,
    required this.type,
    this.hasDefault = false,
    this.isDefault = false,
  });
}

/// 插件 manifest 的规范化表示。
class PluginManifest {
  /// 插件唯一标识符。
  final String id;

  /// 插件显示名称。
  final String name;

  /// 插件版本号，遵循语义化版本规范。
  final String version;

  /// 插件作者名称。
  final String author;

  /// 插件功能描述。
  final String description;

  /// 插件图标路径或标识符。
  final String icon;

  /// 插件入口文件路径（Lua 或 HTML）。
  final String entry;

  /// 插件所需的权限列表。
  final List<String> permissions;

  /// 插件提供的工具定义列表。
  final List<PluginToolDefinition> tools;

  /// 插件导出的非模型调用函数列表。
  final List<PluginFunctionDefinition> functions;

  /// 插件提供的按需加载 Skills。
  final List<PluginSkillDefinition> skills;

  /// 插件提供的功能页列表。
  final List<PluginFeaturePageDefinition> featurePages;

  /// 插件自定义设置项列表。
  final List<PluginSettingDefinition> settings;

  /// 插件配置文件定义。
  final PluginConfigDefinition config;

  /// 插件可编辑文件列表。
  final List<PluginEditableFileDefinition> editableFiles;

  /// LynAI 私有元数据，用于记录快照来源等非插件运行时信息。
  final Map<String, dynamic> lynai;

  /// 创建插件清单实例，必填字段为 id、name、version、entry、permissions 等。
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
    this.skills = const [],
    required this.featurePages,
    required this.settings,
    this.config = const PluginConfigDefinition(),
    this.editableFiles = const [],
    this.lynai = const {},
  });

  /// 从 JSON 数据创建 [PluginManifest] 实例。
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
      skills: (json['skills'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => PluginSkillDefinition.fromJson(Map.from(item)))
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
      lynai: Map<String, dynamic>.from(json['lynai'] as Map? ?? const {}),
    );
  }

  /// 将当前实例序列化为 JSON Map。
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
    if (skills.isNotEmpty) 'skills': skills.map((e) => e.toJson()).toList(),
    if (featurePages.isNotEmpty)
      'ui': {'featurePages': featurePages.map((e) => e.toJson()).toList()},
    if (settings.isNotEmpty)
      'settings': settings.map((e) => e.toJson()).toList(),
    'config': config.toJson(),
    if (editableFiles.isNotEmpty)
      'editableFiles': editableFiles.map((e) => e.toJson()).toList(),
    if (lynai.isNotEmpty) 'lynai': lynai,
  };

  /// 当前 manifest 是否来自 LynAI 插件快照。
  bool get isSnapshot => snapshotOf != null;

  /// 快照来源插件 ID。
  String? get snapshotOf {
    final value = lynai['snapshotOf']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// 创建当前 manifest 的副本，可用于更新快照身份。
  PluginManifest copyWith({
    String? id,
    String? name,
    Map<String, dynamic>? lynai,
  }) {
    return PluginManifest(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version,
      author: author,
      description: description,
      icon: icon,
      entry: entry,
      permissions: permissions,
      tools: tools,
      functions: functions,
      skills: skills,
      featurePages: featurePages,
      settings: settings,
      config: config,
      editableFiles: editableFiles,
      lynai: lynai ?? this.lynai,
    );
  }

  /// 校验插件清单的完整性，返回错误信息或 null。
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
    for (final function in functions) {
      final error = function.validate();
      if (error != null) return error;
    }
    for (final skill in skills) {
      final error = skill.validate();
      if (error != null) return error;
    }
    final toolNames = <String>{};
    for (final tool in tools) {
      if (!toolNames.add(tool.name)) return '插件 tool 名称重复: ${tool.name}';
    }
    final functionNames = <String>{};
    for (final function in functions) {
      if (!functionNames.add(function.name)) {
        return '插件 function 名称重复: ${function.name}';
      }
    }
    final skillNames = <String>{};
    for (final skill in skills) {
      if (!skillNames.add(skill.name)) return '插件 skill 名称重复: ${skill.name}';
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

/// 验证插件路径是否安全：非空、非绝对路径、非 URL、不包含 ".." 路径穿越。
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

/// 根据文件扩展名返回文件类型标识符，供编辑器高亮使用。
String fileTypeFromPath(String path) {
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
  /// 插件清单的规范化表示。
  final PluginManifest manifest;

  /// 插件在本地文件系统中的路径。
  final String path;

  /// 插件是否已启用。
  final bool enabled;

  /// 用户已授权的权限列表。
  final List<String> grantedPermissions;

  /// 用户已启用的功能页 ID 列表。
  final List<String> enabledFeaturePages;

  /// 用户已启用的模型工具名称列表。
  final List<String> enabledTools;

  /// 用户已启用的插件函数名称列表。
  final List<String> enabledFunctions;

  /// 用户已启用的插件 Skill 名称列表。
  final List<String> enabledSkills;

  /// 插件加载失败时的错误信息。
  final String? loadError;

  /// 用户自定义显示名，仅影响 UI，不写回 plugin.json。
  final String? displayNameOverride;

  /// 创建一个已安装插件实例。
  const InstalledPlugin({
    required this.manifest,
    required this.path,
    required this.enabled,
    required this.grantedPermissions,
    required this.enabledFeaturePages,
    this.enabledTools = const [],
    this.enabledFunctions = const [],
    this.enabledSkills = const [],
    this.loadError,
    this.displayNameOverride,
  });

  /// 快捷返回插件 id，等同于 manifest.id。
  String get id => manifest.id;

  /// UI 中显示的插件名称，优先使用用户自定义显示名。
  String get displayName {
    final override = displayNameOverride?.trim();
    return override == null || override.isEmpty ? manifest.name : override;
  }

  /// 当前插件是否是 LynAI 快照插件。
  bool get isSnapshot => manifest.isSnapshot;

  /// 插件是否在加载过程中发生了错误。
  bool get hasError => loadError != null && loadError!.isNotEmpty;

  /// 是否已对所有声明的权限授予访问权。
  bool get hasAllPermissionsGranted {
    final granted = grantedPermissions.toSet();
    return manifest.permissions.every(granted.contains);
  }

  /// 创建当前实例的副本，可选择性更新部分字段。
  InstalledPlugin copyWith({
    PluginManifest? manifest,
    String? path,
    bool? enabled,
    List<String>? grantedPermissions,
    List<String>? enabledFeaturePages,
    List<String>? enabledTools,
    List<String>? enabledFunctions,
    List<String>? enabledSkills,
    Object? loadError = _sentinel,
    Object? displayNameOverride = _sentinel,
  }) {
    return InstalledPlugin(
      manifest: manifest ?? this.manifest,
      path: path ?? this.path,
      enabled: enabled ?? this.enabled,
      grantedPermissions: grantedPermissions ?? this.grantedPermissions,
      enabledFeaturePages: enabledFeaturePages ?? this.enabledFeaturePages,
      enabledTools: enabledTools ?? this.enabledTools,
      enabledFunctions: enabledFunctions ?? this.enabledFunctions,
      enabledSkills: enabledSkills ?? this.enabledSkills,
      loadError: identical(loadError, _sentinel)
          ? this.loadError
          : loadError as String?,
      displayNameOverride: identical(displayNameOverride, _sentinel)
          ? this.displayNameOverride
          : displayNameOverride as String?,
    );
  }

  /// 将当前实例序列化为 JSON Map。
  Map<String, dynamic> toJson() => {
    'manifest': manifest.toJson(),
    'path': path,
    'enabled': enabled,
    'grantedPermissions': grantedPermissions,
    'enabledFeaturePages': enabledFeaturePages,
    'enabledTools': enabledTools,
    'enabledFunctions': enabledFunctions,
    'enabledSkills': enabledSkills,
    if (loadError != null) 'loadError': loadError,
    if (displayNameOverride != null && displayNameOverride!.trim().isNotEmpty)
      'displayNameOverride': displayNameOverride,
  };

  /// 从 JSON 数据创建 [InstalledPlugin] 实例。
  factory InstalledPlugin.fromJson(Map<String, dynamic> json) {
    final manifest = PluginManifest.fromJson(
      Map<String, dynamic>.from(json['manifest'] as Map? ?? const {}),
    );
    return InstalledPlugin(
      manifest: manifest,
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
      enabledTools:
          (json['enabledTools'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          manifest.tools.map((tool) => tool.name).toList(growable: false),
      enabledFunctions:
          (json['enabledFunctions'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          manifest.functions
              .map((function) => function.name)
              .toList(growable: false),
      enabledSkills:
          (json['enabledSkills'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          manifest.skills.map((skill) => skill.name).toList(growable: false),
      loadError: json['loadError'] as String?,
      displayNameOverride: json['displayNameOverride'] as String?,
    );
  }

  static const _sentinel = Object();
}
