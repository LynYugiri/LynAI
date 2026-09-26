/*
 * ProjectionRecord.ts 的单元测试：覆盖 StandardMessageCodec 解出的 Map 与普通对象
 * 两种形态。
 *
 * 这里必须用真实 `Map` 构造输入：鸿蒙服务卡片曾经因为直接
 * `JSON.stringify(Map[])` 落盘成 `[{}]`、并用属性访问读不到 Map 的字段，导致卡片
 * 永远显示「近期无日程」。测试用普通对象会漏掉这个缺陷。
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  WIDGET_OCCURRENCE_KEYS,
  fieldValue,
  occurrenceRecord,
  occurrenceRecords,
} from '../../ohos/entry/src/main/ets/lynai/ProjectionRecord.ts';

/** 模拟 StandardMessageCodec 解出的发生记录。 */
function decodedOccurrence() {
  return new Map([
    ['occurrenceId', 'occ-1'],
    ['sourceType', 'calendar_event'],
    ['sourceId', 'event-1'],
    ['title', '产品评审'],
    ['note', null],
    ['date', '2026-09-24'],
    ['startTime', '10:00'],
    ['endAtLocal', '2026-09-24T11:00'],
    ['startAtEpochMillis', 1790000000000],
    ['endAtEpochMillis', 1790003600000],
    ['endDateExclusive', '2026-09-25'],
    ['isCompleted', false],
  ]);
}

test('fieldValue 同时支持 Map 与普通对象', () => {
  assert.equal(fieldValue(decodedOccurrence(), 'title'), '产品评审');
  assert.equal(fieldValue({ title: '普通对象' }, 'title'), '普通对象');
  assert.equal(fieldValue(decodedOccurrence(), 'missing'), null);
  assert.equal(fieldValue(null, 'title'), null);
});

test('Map 形态的发生记录折算成可 JSON 序列化的普通对象', () => {
  const record = occurrenceRecord(decodedOccurrence());
  assert.equal(record['title'], '产品评审');
  assert.equal(record['date'], '2026-09-24');
  assert.equal(record['startAtEpochMillis'], 1790000000000);

  const encoded = JSON.stringify([record]);
  // 直接 stringify Map 会得到 {}，这正是卡片显示不出日程的根因。
  assert.notEqual(JSON.stringify([decodedOccurrence()]), encoded);
  assert.deepEqual(JSON.parse(encoded), [
    {
      occurrenceId: 'occ-1',
      sourceType: 'calendar_event',
      sourceId: 'event-1',
      title: '产品评审',
      date: '2026-09-24',
      startTime: '10:00',
      endAtLocal: '2026-09-24T11:00',
      startAtEpochMillis: 1790000000000,
      endAtEpochMillis: 1790003600000,
      endDateExclusive: '2026-09-25',
      isCompleted: false,
    },
  ]);
});

test('只保留卡片需要的字段，null 键被省略', () => {
  const record = occurrenceRecord(
    new Map([
      ['title', '会议'],
      ['note', null],
      ['unknownField', '应被丢弃'],
    ]),
  );
  assert.deepEqual(Object.keys(record).sort(), ['title']);
  for (const key of Object.keys(record)) {
    assert.ok(WIDGET_OCCURRENCE_KEYS.includes(key));
  }
});

test('列表折算保持顺序与条数', () => {
  const records = occurrenceRecords([
    new Map([['title', 'A'], ['date', '2026-09-24']]),
    { title: 'B', date: '2026-09-25' },
    new Map(),
  ]);
  assert.equal(records.length, 3);
  assert.equal(fieldValue(records[0], 'title'), 'A');
  assert.equal(fieldValue(records[1], 'title'), 'B');
  assert.deepEqual(records[2], {});
});
