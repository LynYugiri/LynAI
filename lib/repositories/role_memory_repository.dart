import 'package:flutter/foundation.dart';

import '../models/role_memory_entry.dart';
import '../services/storage_v2_service.dart';

/// 从 storage_v2 读取的角色记忆快照。
final class RoleMemoryLoadResult {
  const RoleMemoryLoadResult({required this.entries});

  final List<RoleMemoryEntry> entries;
}

/// 角色记忆与 storage_v2 数据文件之间的转换。
///
/// 数据保存在 `role_memory.json` 数据文件中（由 app.db 的 storage_meta
/// 承载）。记忆量很小，使用整份快照替换而不是行级 upsert；这样写入天然
/// 原子，且不会进入云/LAN 同步表集合。
class RoleMemoryRepository {
  RoleMemoryRepository({StorageV2Service? storageV2})
    : _storageV2 = storageV2 ?? StorageV2Service();

  static const fileName = 'role_memory.json';
  static const currentVersion = 1;

  final StorageV2Service _storageV2;

  /// 读取角色记忆。
  ///
  /// 顶层缺失/为空视为空列表；存在但不是列表时抛出 [FormatException]。
  /// 单条损坏记录跳过，过滤空 roleId/空 entry 和非法 target。
  Future<RoleMemoryLoadResult> load() async {
    final data = await _storageV2.loadDataFile(fileName);
    final raw = data['entries'];
    if (raw == null) return const RoleMemoryLoadResult(entries: []);
    if (raw is! List) {
      throw const FormatException('角色记忆 entries 必须是列表');
    }
    final entries = <RoleMemoryEntry>[];
    for (final item in raw) {
      try {
        if (item is! Map) continue;
        final entry = RoleMemoryEntry.fromJson(Map<String, dynamic>.from(item));
        if (entry.id.isEmpty ||
            entry.roleId.isEmpty ||
            entry.entry.trim().isEmpty) {
          continue;
        }
        entries.add(entry);
      } catch (error) {
        debugPrint('跳过损坏的角色记忆条目: $error');
      }
    }
    return RoleMemoryLoadResult(entries: entries);
  }

  /// 全量替换当前角色记忆。
  Future<void> replace(List<RoleMemoryEntry> entries) {
    return _storageV2.writeDataFile(fileName, {
      'version': currentVersion,
      'entries': entries.map((entry) => entry.toJson()).toList(),
    });
  }
}
