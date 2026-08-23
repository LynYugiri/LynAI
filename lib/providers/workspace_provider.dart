import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/plugin.dart';
import '../models/workspace.dart';
import '../repositories/workspace_repository.dart';
import '../services/attachment_storage_service.dart';
import '../services/storage_v2_service.dart';
import '../services/workspace_file_service.dart';
import '../utils/file_name_utils.dart';
import '../utils/file_picker_io_utils.dart';
import 'serialized_save_queue.dart';

/// 管理工作区列表、当前工作区和工作区文件引用。
///
/// 约定与其余 Provider 一致：先更新内存并通知 UI，再经串行保存队列落盘。
/// 工作区元数据保存在 `workspaces.json`（本机数据，不参与同步/备份）；
/// 添加到工作区的文件本体走 storage_v2 Resource。
class WorkspaceProvider extends ChangeNotifier with SerializedSaveQueue {
  final WorkspaceRepository _repository;
  final StorageV2Service _storageV2;
  final WorkspaceFileService _fileService;
  final _uuid = const Uuid();

  List<Workspace> _workspaces = [];
  String? _activeWorkspaceId;
  String? _lastWorkspaceId;
  bool _loaded = false;
  Timer? _saveDebounce;
  WorkspaceStoreState? _pendingSaveSnapshot;

  factory WorkspaceProvider({
    StorageV2Service? storageV2,
    WorkspaceRepository? repository,
    WorkspaceFileService? fileService,
  }) {
    final storage = storageV2 ?? StorageV2Service();
    return WorkspaceProvider._(
      storage,
      repository ?? WorkspaceRepository(storageV2: storage),
      fileService ?? const WorkspaceFileService(),
    );
  }

  WorkspaceProvider._(this._storageV2, this._repository, this._fileService);

  static const _saveDebounceDuration = Duration(milliseconds: 300);

  List<Workspace> get workspaces => List.unmodifiable(_workspaces);
  bool get loaded => _loaded;
  String? get activeWorkspaceId => _activeWorkspaceId;
  String? get lastWorkspaceId => _lastWorkspaceId;

  Workspace? get activeWorkspace => _workspaceById(_activeWorkspaceId);

  Workspace? workspaceById(String? id) => _workspaceById(id);

  Workspace? _workspaceById(String? id) {
    final normalized = id?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    for (final workspace in _workspaces) {
      if (workspace.id == normalized) return workspace;
    }
    return null;
  }

  Future<void> loadWorkspaces() async {
    final state = await _repository.load();
    _workspaces = List<Workspace>.from(state.workspaces);
    _activeWorkspaceId = _normalizedId(state.activeWorkspaceId);
    if (_activeWorkspaceId != null &&
        _workspaceById(_activeWorkspaceId) == null) {
      _activeWorkspaceId = null;
    }
    _lastWorkspaceId = _normalizedId(state.lastWorkspaceId);
    _loaded = true;
    notifyListeners();
  }

  Workspace createWorkspace({
    required String name,
    Iterable<String> featureIds = const [],
    WorkspacePluginPolicyMode pluginPolicyMode =
        WorkspacePluginPolicyMode.followGlobal,
    Iterable<String> enabledPluginIds = const [],
    Iterable<String> devPluginIds = const [],
    String? mountedFolderPath,
  }) {
    final now = DateTime.now();
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('工作区名称不能为空');
    }
    final workspace = Workspace(
      id: _uuid.v4(),
      name: normalizedName,
      featureIds: Workspace.normalizeFeatureIds(featureIds),
      pluginPolicyMode: pluginPolicyMode,
      enabledPluginIds: _uniqueNonEmpty(enabledPluginIds),
      devPluginIds: _uniqueNonEmpty(devPluginIds),
      mountedFolderPath: mountedFolderPath?.trim().isEmpty == true
          ? null
          : mountedFolderPath?.trim(),
      createdAt: now,
      updatedAt: now,
    );
    _workspaces = [workspace, ..._workspaces];
    _activeWorkspaceId = workspace.id;
    _lastWorkspaceId = workspace.id;
    _queueSave();
    notifyListeners();
    return workspace;
  }

  void updateWorkspace(String id, Workspace Function(Workspace) transform) {
    final index = _workspaces.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final next = transform(
      _workspaces[index],
    ).copyWith(updatedAt: DateTime.now());
    _workspaces = List<Workspace>.from(_workspaces);
    _workspaces[index] = next;
    _queueSave();
    notifyListeners();
  }

  /// 删除工作区并清空指向它的 active/last 状态。
  ///
  /// 不删除会话、不删除 Resource 与挂载目录；会话迁移由调用方（页面或
  /// Agent 编排）在删除前调用 ConversationProvider 完成。
  void deleteWorkspace(String id) {
    _workspaces = _workspaces.where((item) => item.id != id).toList();
    if (_activeWorkspaceId == id) _activeWorkspaceId = null;
    if (_lastWorkspaceId == id) _lastWorkspaceId = null;
    _queueSave();
    notifyListeners();
  }

  void selectWorkspace(String id) {
    final workspace = workspaceById(id);
    if (workspace == null) return;
    _activeWorkspaceId = workspace.id;
    _lastWorkspaceId = workspace.id;
    _queueSave();
    notifyListeners();
  }

  void exitWorkspace() {
    if (_activeWorkspaceId == null) return;
    _activeWorkspaceId = null;
    _queueSave();
    notifyListeners();
  }

  /// 幂等把插件加入工作区开发插件列表。
  void addDevPlugin(String workspaceId, String pluginId) {
    final normalized = pluginId.trim();
    if (normalized.isEmpty) return;
    updateWorkspace(workspaceId, (workspace) {
      if (workspace.devPluginIds.contains(normalized)) return workspace;
      return workspace.copyWith(
        devPluginIds: [...workspace.devPluginIds, normalized],
      );
    });
  }

  void setMountedFolderPath(String workspaceId, String? path) {
    updateWorkspace(workspaceId, (workspace) {
      final normalized = path?.trim();
      return workspace.copyWith(
        mountedFolderPath: normalized == null || normalized.isEmpty
            ? null
            : normalized,
      );
    });
  }

  /// 导入用户选择的工作区文件（Resource + 引用快照）。
  Future<WorkspaceFileRef> importWorkspaceFile(
    String workspaceId,
    PickedFilePayload payload,
  ) async {
    final tempDir = await Directory.systemTemp.createTemp('lynai_workspace_');
    final safeName = safeStorageFileName(payload.name, fallback: 'file');
    final tempFile = File('${tempDir.path}/$safeName');
    try {
      await payload.copyTo(tempFile);
      final mimeType = AttachmentStorageService.inferMimeType(safeName);
      final resource = await _storageV2.importResourceFile(
        tempFile.path,
        originalName: safeName,
        mimeType: mimeType,
        role: 'workspace_file',
      );
      final ref = WorkspaceFileRef(
        resourceId: resource.id,
        originalName: safeName,
        mimeType: mimeType,
        size: await tempFile.length(),
      );
      updateWorkspace(workspaceId, (workspace) {
        final files = workspace.files
            .where((item) => item.originalName != ref.originalName)
            .toList();
        files.add(ref);
        return workspace.copyWith(files: files);
      });
      await flushPendingSaves();
      return ref;
    } finally {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    }
  }

  /// 读取添加到工作区的文件正文。
  Future<String> readWorkspaceFile(WorkspaceFileRef ref) async {
    final resource = await _storageV2.findResourceById(ref.resourceId);
    if (resource == null) throw Exception('工作区文件资源不存在');
    final file = await _storageV2.resourceFile(resource);
    if (file == null) throw Exception('工作区文件已丢失');
    final limit = WorkspaceFileService.maxReadChars * 4 + 8192;
    final bytes = <int>[];
    await for (final chunk in file.openRead(0, limit)) {
      bytes.addAll(chunk);
      if (bytes.length >= limit) {
        throw Exception('工作区文件过大，暂不支持编辑');
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 保存工作区文件：新内容导入新 Resource，替换引用快照。
  Future<WorkspaceFileRef> writeWorkspaceFile(
    String workspaceId,
    WorkspaceFileRef ref,
    String content,
  ) async {
    if (content.length > WorkspaceFileService.maxWriteChars) {
      throw Exception('工作区文件超过单文件写入上限');
    }
    final bytes = utf8.encode(content);
    final resource = await _storageV2.importResourceBytes(
      bytes,
      originalName: ref.originalName,
      mimeType: ref.mimeType,
      role: 'workspace_file',
    );
    final next = ref.copyWith(resourceId: resource.id, size: bytes.length);
    updateWorkspace(workspaceId, (workspace) {
      final files = workspace.files
          .where((item) => item.resourceId != ref.resourceId)
          .toList();
      files.add(next);
      return workspace.copyWith(files: files);
    });
    await flushPendingSaves();
    return next;
  }

  /// 直接以文本内容创建（或按名称替换）工作区添加文件。
  Future<WorkspaceFileRef> createWorkspaceFile(
    String workspaceId,
    String name,
    String content,
  ) async {
    if (content.length > WorkspaceFileService.maxWriteChars) {
      throw Exception('工作区文件超过单文件写入上限');
    }
    final bytes = utf8.encode(content);
    final resource = await _storageV2.importResourceBytes(
      bytes,
      originalName: name,
      mimeType: AttachmentStorageService.inferMimeType(name),
      role: 'workspace_file',
    );
    final ref = WorkspaceFileRef(
      resourceId: resource.id,
      originalName: name,
      mimeType: resource.mimeType,
      size: bytes.length,
    );
    updateWorkspace(workspaceId, (workspace) {
      final files = workspace.files
          .where((item) => item.originalName != name)
          .toList();
      files.add(ref);
      return workspace.copyWith(files: files);
    });
    await flushPendingSaves();
    return ref;
  }

  void removeWorkspaceFile(String workspaceId, String resourceId) {
    updateWorkspace(workspaceId, (workspace) {
      return workspace.copyWith(
        files: workspace.files
            .where((item) => item.resourceId != resourceId)
            .toList(),
      );
    });
  }

  Future<List<WorkspaceFileEntry>> listMountedDirectory(
    Workspace workspace,
    String relativeDir,
  ) {
    final root = workspace.mountedFolderPath;
    if (root == null || root.isEmpty) {
      throw Exception('工作区未挂载本地文件夹');
    }
    return _fileService.listDirectory(root, relativeDir);
  }

  Future<String> readMountedFile(Workspace workspace, String relativePath) {
    final root = workspace.mountedFolderPath;
    if (root == null || root.isEmpty) {
      throw Exception('工作区未挂载本地文件夹');
    }
    return _fileService.readTextFile(root, relativePath);
  }

  Future<void> writeMountedFile(
    Workspace workspace,
    String relativePath,
    String content,
  ) {
    final root = workspace.mountedFolderPath;
    if (root == null || root.isEmpty) {
      throw Exception('工作区未挂载本地文件夹');
    }
    return _fileService.writeTextFile(root, relativePath, content);
  }

  /// 解析工作区插件策略下 Agent 可见的插件集合。
  ///
  /// followGlobal 返回全局启用插件；custom 只返回工作区启用列表内且全局
  /// 启用的插件。绑定中的插件创作目标若全局启用则始终保留，避免收窄时
  /// 切断 plugin_file_* 创作链。
  List<InstalledPlugin> effectiveVisiblePlugins(
    String? workspaceId, {
    required Iterable<InstalledPlugin> allPlugins,
    String? boundPluginId,
  }) {
    final workspace = workspaceById(workspaceId);
    final installed = allPlugins.toList(growable: false);
    if (workspace == null ||
        workspace.pluginPolicyMode == WorkspacePluginPolicyMode.followGlobal) {
      return installed
          .where((plugin) => plugin.enabled && !plugin.hasError)
          .toList(growable: false);
    }
    final allowed = workspace.enabledPluginIds.toSet();
    final bound = boundPluginId?.trim();
    return installed
        .where((plugin) {
          if (bound != null && plugin.id == bound && plugin.enabled) {
            return true;
          }
          return allowed.contains(plugin.id) &&
              plugin.enabled &&
              !plugin.hasError;
        })
        .toList(growable: false);
  }

  void _queueSave() {
    _pendingSaveSnapshot = WorkspaceStoreState(
      workspaces: List<Workspace>.from(_workspaces),
      activeWorkspaceId: _activeWorkspaceId,
      lastWorkspaceId: _lastWorkspaceId,
    );
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDebounceDuration, _enqueuePendingSave);
  }

  void _enqueuePendingSave() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    final snapshot = _pendingSaveSnapshot;
    if (snapshot == null) return;
    _pendingSaveSnapshot = null;
    enqueueSave(() => _repository.save(snapshot));
  }

  @override
  Future<void> onBeforeFlush() async {
    _enqueuePendingSave();
  }

  @override
  void dispose() {
    _enqueuePendingSave();
    _saveDebounce?.cancel();
    super.dispose();
  }

  static List<String> _uniqueNonEmpty(Iterable<String> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (value.trim().isNotEmpty && seen.add(value.trim())) value.trim(),
    ];
  }

  static String? _normalizedId(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
