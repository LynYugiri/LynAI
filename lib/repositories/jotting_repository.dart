import 'package:flutter/foundation.dart';

import '../models/jotting.dart';
import '../services/storage_v2_service.dart';

/// 从持久化层一次性读取的随记数据快照。
final class JottingLoadResult {
  const JottingLoadResult({required this.jottings});

  final List<Jotting> jottings;
}

/// 负责随记数据与 storage_v2 数据文件之间的转换。
///
/// v1 使用全量快照替换持久化（与笔记数据文件一致）；随记表不进入
/// 云/LAN 同步，待云端分享阶段再切换为增量行操作。
class JottingRepository {
  JottingRepository({StorageV2Service? storageV2})
    : _storageV2 = storageV2 ?? StorageV2Service();

  static const fileName = 'jottings.json';
  final StorageV2Service _storageV2;

  /// 读取随记数据。
  ///
  /// 顶层 `jottings` 缺失或为 null 按空列表处理；存在但不是列表时抛出
  /// [FormatException]；列表内单条损坏记录跳过。
  Future<JottingLoadResult> load() async {
    final data = await _storageV2.loadDataFile(fileName);
    return JottingLoadResult(
      jottings: _decode(data['jottings'], Jotting.fromJson, '随记'),
    );
  }

  /// 使用完整快照替换当前随记数据。
  Future<void> replace(JottingLoadResult value) {
    return _storageV2.writeDataFile(fileName, {
      'jottings': value.jottings.map((item) => item.toJson()).toList(),
    });
  }
}

List<T> _decode<T>(
  Object? raw,
  T Function(Map<String, dynamic>) parser,
  String label,
) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw FormatException('$label集合必须是列表');
  }
  final values = <T>[];
  for (final item in raw) {
    try {
      if (item is Map) values.add(parser(Map<String, dynamic>.from(item)));
    } catch (error) {
      debugPrint('跳过损坏的$label: $error');
    }
  }
  return values;
}
