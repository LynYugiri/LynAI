/// 工作区数据模型。
///
/// 工作区是应用级的本地上下文：绑定对话历史域、可挂载的功能页、
/// 开发插件列表与真实本地文件夹。权限表达不属于本模型——Agent 对工作区
/// 的读写能力完全由当前对话设置中的权限快照决定。
library;

import 'package:flutter/foundation.dart';

/// 工作区启用插件策略。
enum WorkspacePluginPolicyMode {
  /// 跟随全局启用插件列表。
  followGlobal('followGlobal'),

  /// 使用工作区自己的启用插件子集（只能从全局已启用插件中收窄）。
  custom('custom');

  const WorkspacePluginPolicyMode(this.wire);

  final String wire;

  static WorkspacePluginPolicyMode fromWire(String? value) {
    for (final mode in values) {
      if (mode.wire == value) return mode;
    }
    return WorkspacePluginPolicyMode.followGlobal;
  }
}

/// 工作区可挂载的功能页 ID（与 `ChatQuickAction.featurePages` 文案对齐）。
///
/// 总览、历史与情景演绎不适合作为工作区节点，不在支持集合内。
const supportedWorkspaceFeatureIds = <String>[
  'notes',
  'schedule',
  'knowledge',
  'todos',
  'jottings',
  'cards',
];

/// 添加到工作区的文件快照。
///
/// 文件本体通过 `StorageV2Service.importResourceFile(role: 'workspace_file')`
/// 导入私有 Resource；这里只保存稳定资源 ID 和展示信息。编辑保存时用新
/// Resource 替换 [resourceId]，旧 Resource 保留（内容寻址）。
class WorkspaceFileRef {
  final String resourceId;
  final String originalName;
  final String mimeType;
  final int size;

  const WorkspaceFileRef({
    required this.resourceId,
    required this.originalName,
    required this.mimeType,
    this.size = 0,
  });

  factory WorkspaceFileRef.fromJson(Map<String, dynamic> json) {
    final resourceId = json['resourceId'] as String? ?? '';
    final originalName = json['originalName'] as String? ?? '';
    final mimeType = json['mimeType'] as String? ?? 'application/octet-stream';
    final size = (json['size'] as num?)?.toInt() ?? 0;
    if (resourceId.isEmpty || originalName.isEmpty) {
      throw const FormatException('WorkspaceFileRef 缺少 resourceId 或名称');
    }
    return WorkspaceFileRef(
      resourceId: resourceId,
      originalName: originalName,
      mimeType: mimeType,
      size: size,
    );
  }

  Map<String, dynamic> toJson() => {
    'resourceId': resourceId,
    'originalName': originalName,
    'mimeType': mimeType,
    'size': size,
  };

  WorkspaceFileRef copyWith({
    String? resourceId,
    String? originalName,
    String? mimeType,
    int? size,
  }) {
    return WorkspaceFileRef(
      resourceId: resourceId ?? this.resourceId,
      originalName: originalName ?? this.originalName,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
    );
  }
}

/// 一个本地工作区。
class Workspace {
  final String id;
  final String name;
  final List<String> featureIds;
  final WorkspacePluginPolicyMode pluginPolicyMode;
  final List<String> enabledPluginIds;
  final List<String> devPluginIds;
  final List<WorkspaceFileRef> files;
  final String? mountedFolderPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Workspace({
    required this.id,
    required this.name,
    this.featureIds = const [],
    this.pluginPolicyMode = WorkspacePluginPolicyMode.followGlobal,
    this.enabledPluginIds = const [],
    this.devPluginIds = const [],
    this.files = const [],
    this.mountedFolderPath,
    required this.createdAt,
    required this.updatedAt,
  });

  static List<String> normalizeFeatureIds(Iterable<String> ids) {
    final seen = <String>{};
    return [
      for (final id in ids)
        if (supportedWorkspaceFeatureIds.contains(id) && seen.add(id)) id,
    ];
  }

  factory Workspace.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    if (id == null ||
        id.isEmpty ||
        name == null ||
        name.trim().isEmpty ||
        createdAt == null ||
        updatedAt == null) {
      throw const FormatException('工作区记录缺少 id/name/时间字段');
    }
    final featureIds = <String>[];
    for (final item in json['featureIds'] as List<dynamic>? ?? const []) {
      final value = item?.toString() ?? '';
      if (supportedWorkspaceFeatureIds.contains(value) &&
          !featureIds.contains(value)) {
        featureIds.add(value);
      }
    }
    final enabledPluginIds = <String>[];
    for (final item in json['enabledPluginIds'] as List<dynamic>? ?? const []) {
      final value = item?.toString().trim() ?? '';
      if (value.isNotEmpty && !enabledPluginIds.contains(value)) {
        enabledPluginIds.add(value);
      }
    }
    final devPluginIds = <String>[];
    for (final item in json['devPluginIds'] as List<dynamic>? ?? const []) {
      final value = item?.toString().trim() ?? '';
      if (value.isNotEmpty && !devPluginIds.contains(value)) {
        devPluginIds.add(value);
      }
    }
    final files = <WorkspaceFileRef>[];
    for (final item in json['files'] as List<dynamic>? ?? const []) {
      if (item is! Map) continue;
      try {
        final ref = WorkspaceFileRef.fromJson(Map<String, dynamic>.from(item));
        if (!files.any((existing) => existing.resourceId == ref.resourceId)) {
          files.add(ref);
        }
      } catch (e) {
        // 单条损坏的文件引用跳过，不影响工作区本身。
        debugPrint('跳过损坏的工作区文件引用: $e');
      }
    }
    final rawPath = json['mountedFolderPath'];
    return Workspace(
      id: id,
      name: name.trim(),
      featureIds: List.unmodifiable(featureIds),
      pluginPolicyMode: WorkspacePluginPolicyMode.fromWire(
        json['pluginPolicyMode'] as String?,
      ),
      enabledPluginIds: List.unmodifiable(enabledPluginIds),
      devPluginIds: List.unmodifiable(devPluginIds),
      files: List.unmodifiable(files),
      mountedFolderPath: rawPath is String && rawPath.isNotEmpty
          ? rawPath
          : null,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (featureIds.isNotEmpty) 'featureIds': featureIds,
    'pluginPolicyMode': pluginPolicyMode.wire,
    if (enabledPluginIds.isNotEmpty) 'enabledPluginIds': enabledPluginIds,
    if (devPluginIds.isNotEmpty) 'devPluginIds': devPluginIds,
    if (files.isNotEmpty) 'files': files.map((item) => item.toJson()).toList(),
    if (mountedFolderPath != null && mountedFolderPath!.isNotEmpty)
      'mountedFolderPath': mountedFolderPath,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  Workspace copyWith({
    String? id,
    String? name,
    List<String>? featureIds,
    WorkspacePluginPolicyMode? pluginPolicyMode,
    List<String>? enabledPluginIds,
    List<String>? devPluginIds,
    Object? files = _sentinel,
    Object? mountedFolderPath = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Workspace(
      id: id ?? this.id,
      name: name ?? this.name,
      featureIds: featureIds ?? this.featureIds,
      pluginPolicyMode: pluginPolicyMode ?? this.pluginPolicyMode,
      enabledPluginIds: enabledPluginIds ?? this.enabledPluginIds,
      devPluginIds: devPluginIds ?? this.devPluginIds,
      files: identical(files, _sentinel)
          ? this.files
          : files as List<WorkspaceFileRef>,
      mountedFolderPath: identical(mountedFolderPath, _sentinel)
          ? this.mountedFolderPath
          : mountedFolderPath as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static const _sentinel = Object();
}
