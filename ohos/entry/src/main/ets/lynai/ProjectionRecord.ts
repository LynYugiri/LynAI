/*
 * 平台投影字段读取与「Map → 普通对象」折算（纯逻辑）。
 *
 * flutter_ohos 的 StandardMessageCodec 把 Dart 的 `Map` 解成 ArkTS 的 `Map`，
 * 而不是普通对象。两者在按字段读取时要区别对待，并且在写 JSON 时必须先折算：
 * `JSON.stringify(new Map([['a', 1]]))` 得到的是 `{}`（Map 的键不是自有可枚举
 * 属性），属性访问 `map.a` 同样读不到值。
 *
 * 这里不依赖任何 ArkTS/鸿蒙 API，便于用 Node 单元测试覆盖
 * （scripts/ohos-arkts-tests/），测试必须用真实 `Map` 构造输入。
 */

/** 服务卡片消费的日历发生记录字段（与 Dart 侧投影 JSON 的键一致）。 */
export const WIDGET_OCCURRENCE_KEYS: string[] = [
  'occurrenceId',
  'sourceType',
  'sourceId',
  'title',
  'note',
  'date',
  'startTime',
  'endAtLocal',
  'startAtEpochMillis',
  'endAtEpochMillis',
  'endDateExclusive',
  'isCompleted',
];

/** 读取 Map 或普通对象上的字段，兼容 StandardMessageCodec 的两种解码形态。 */
export function fieldValue(source: Object | null, key: string): Object | null {
  if (source === null) {
    return null;
  }
  if (source instanceof Map) {
    const value = (source as Map<string, Object>).get(key);
    return value === undefined ? null : value;
  }
  const record = source as Record<string, Object>;
  const value = record[key];
  return value === undefined ? null : value;
}

/**
 * 把一条发生记录折算成可 JSON 序列化的普通对象。
 *
 * 只保留 [WIDGET_OCCURRENCE_KEYS] 里的字段，值为 `null`/`undefined` 的键直接省略，
 * 与 Dart 侧 `toJson()` 的形状保持一致。
 */
export function occurrenceRecord(source: Object | null): Record<string, Object> {
  const record: Record<string, Object> = {};
  for (const key of WIDGET_OCCURRENCE_KEYS) {
    const value = fieldValue(source, key);
    if (value !== null) {
      record[key] = value;
    }
  }
  return record;
}

/**
 * 把发生记录列表折算成普通对象列表。
 *
 * 卡片落盘（JSON）与内容规划（属性访问）都要求普通对象，因此在通道边界统一折算
 * 一次，两个消费方拿到的都是真实字段。返回 `Object[]` 与卡片侧的入参类型一致。
 */
export function occurrenceRecords(sources: Object[]): Object[] {
  const records: Object[] = [];
  for (const source of sources) {
    records.push(occurrenceRecord(source));
  }
  return records;
}
