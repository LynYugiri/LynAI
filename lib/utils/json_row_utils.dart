import 'package:flutter/foundation.dart';

/// 持久化 JSON 列表的统一解码。
///
/// 顶层字段缺失或为 `null` 视为空集合，但存在且不是列表属于结构损坏，必须显式
/// 失败；列表内单条记录损坏只跳过该条并打印，不阻断整份数据加载。Repository
/// 各自实现同一段逻辑容易分叉，这里集中一份。
List<T> decodeRowList<T>(
  Object? raw,
  T Function(Map<String, dynamic> row) parser,
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
