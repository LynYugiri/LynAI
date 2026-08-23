import 'package:flutter/foundation.dart';

import '../models/workspace.dart';
import '../services/storage_v2_service.dart';

/// 工作区仓储状态。
class WorkspaceStoreState {
  final List<Workspace> workspaces;
  final String? activeWorkspaceId;
  final String? lastWorkspaceId;

  const WorkspaceStoreState({
    required this.workspaces,
    this.activeWorkspaceId,
    this.lastWorkspaceId,
  });
}

/// 工作区数据仓储。
///
/// 读写 storage_v2 的 `workspaces.json` generic data file。该文件是本机
/// 上下文，不进入云/LAN 同步 outbox，也不进 v1 备份。
class WorkspaceRepository {
  factory WorkspaceRepository({StorageV2Service? storageV2}) {
    return WorkspaceRepository._(storageV2 ?? StorageV2Service());
  }

  WorkspaceRepository._(this._storageV2);

  final StorageV2Service _storageV2;

  static const _fileName = 'workspaces.json';

  Future<WorkspaceStoreState> load() async {
    final json = await _storageV2.loadDataFile(_fileName);
    final rawWorkspaces = json['workspaces'];
    if (rawWorkspaces == null) {
      return WorkspaceStoreState(workspaces: const []);
    }
    if (rawWorkspaces is! List) {
      throw const FormatException('workspaces.json 的 workspaces 字段不是列表');
    }
    final workspaces = <Workspace>[];
    for (final item in rawWorkspaces) {
      if (item is! Map) continue;
      try {
        workspaces.add(Workspace.fromJson(Map<String, dynamic>.from(item)));
      } catch (e) {
        debugPrint('跳过损坏的工作区记录: $e');
      }
    }
    workspaces.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return WorkspaceStoreState(
      workspaces: List.unmodifiable(workspaces),
      activeWorkspaceId: _nonEmpty(json['activeWorkspaceId']),
      lastWorkspaceId: _nonEmpty(json['lastWorkspaceId']),
    );
  }

  Future<void> save(WorkspaceStoreState state) {
    return _storageV2.writeDataFile(_fileName, {
      'version': 1,
      if (state.activeWorkspaceId != null &&
          state.activeWorkspaceId!.isNotEmpty)
        'activeWorkspaceId': state.activeWorkspaceId,
      if (state.lastWorkspaceId != null && state.lastWorkspaceId!.isNotEmpty)
        'lastWorkspaceId': state.lastWorkspaceId,
      'workspaces': state.workspaces
          .map((workspace) => workspace.toJson())
          .toList(),
    });
  }

  static String? _nonEmpty(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
