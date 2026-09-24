/*
 * ReminderPlan.ts 的单元测试。
 *
 * 直接跑原生实现（ohos/entry/src/main/ets/lynai/ReminderPlan.ts），
 * 不复制逻辑，保证测的就是 ArkTS 构建实际编译的那份源码。
 * 依赖 Node 的类型剥离能力（Node >= 22.6 的 --experimental-strip-types，
 * Node >= 23 默认开启）。
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  MAX_REMINDERS,
  parseLocalMinute,
  planReminders,
  triggerTimeOf,
} from '../../ohos/entry/src/main/ets/lynai/ReminderPlan.ts';

const localTime = (year, month, day, hour, minute, second = 0) =>
  new Date(year, month - 1, day, hour, minute, second).getTime();

test('parseLocalMinute 解析本地墙上时间', () => {
  assert.equal(
    parseLocalMinute('2026-09-24T09:30'),
    localTime(2026, 9, 24, 9, 30),
  );
  assert.equal(
    parseLocalMinute('2026-09-24T09:30:15'),
    localTime(2026, 9, 24, 9, 30, 15),
  );
});

test('parseLocalMinute 拒绝非法输入', () => {
  for (const value of [
    '',
    '2026-09-24',
    '2026-09-24 09:30',
    '2026-13-01T09:30',
    '2026-02-30T09:30',
    '2026-09-24T25:00',
    '2026-09-24T09:70',
    'not-a-time',
  ]) {
    assert.equal(parseLocalMinute(value), null, `应拒绝：${value}`);
  }
});

test('triggerTimeOf 优先使用 epoch，其次本地时间', () => {
  assert.equal(
    triggerTimeOf({ triggerAtEpochMillis: 1700000000000 }),
    1700000000000,
  );
  assert.equal(
    triggerTimeOf({
      triggerAtEpochMillis: undefined,
      triggerAtLocal: '2026-01-02T03:04',
    }),
    localTime(2026, 1, 2, 3, 4),
  );
  assert.equal(triggerTimeOf({ triggerAtLocal: 'bad' }), null);
  assert.equal(triggerTimeOf({}), null);
});

test('planReminders 过滤过去、按时间升序并补默认标题', () => {
  const now = localTime(2026, 9, 24, 8, 0);
  const planned = planReminders(
    [
      { triggerAtLocal: '2026-09-24T07:00', title: '已过期' },
      { triggerAtLocal: '2026-09-24T12:00', title: '午饭', note: '带上饭卡' },
      { triggerAtLocal: '2026-09-24T09:00', title: '   ' },
      { triggerAtLocal: '2026-09-24T08:00', title: '恰好现在' },
    ],
    now,
  );

  assert.deepEqual(
    planned.map((item) => item.title),
    ['LynAI 提醒', '午饭'],
  );
  assert.equal(planned[0].triggerAt, localTime(2026, 9, 24, 9, 0));
  assert.equal(planned[1].content, '带上饭卡');
  // 标题与正文都为空时回退到默认标题，避免通知内容一片空白。
  assert.equal(planned[0].content, 'LynAI 提醒');
});

test('planReminders 保留 epoch 触发点并混排', () => {
  const now = localTime(2026, 9, 24, 8, 0);
  const epoch = localTime(2026, 9, 24, 10, 0);
  const planned = planReminders(
    [
      { triggerAtLocal: '2026-09-24T10:30', title: '本地时间' },
      { triggerAtEpochMillis: epoch, title: 'UTC 锚定' },
    ],
    now,
  );

  assert.deepEqual(
    planned.map((item) => item.title),
    ['UTC 锚定', '本地时间'],
  );
});

test('planReminders 按系统上限截断为最近的若干条', () => {
  const now = localTime(2026, 1, 1, 0, 0);
  const triggers = [];
  for (let index = 0; index < MAX_REMINDERS + 5; index++) {
    const minute = index % 60;
    const hour = 1 + Math.floor(index / 60);
    triggers.push({
      triggerAtLocal: `2026-01-01T${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`,
      title: `提醒 ${index}`,
    });
  }

  const planned = planReminders(triggers, now);
  assert.equal(planned.length, MAX_REMINDERS);
  assert.equal(planned[0].title, '提醒 0');
  assert.equal(planned.at(-1).title, `提醒 ${MAX_REMINDERS - 1}`);
  // 顺序必须严格递增。
  for (let index = 1; index < planned.length; index++) {
    assert.ok(planned[index].triggerAt >= planned[index - 1].triggerAt);
  }
});

test('planReminders 支持自定义上限且不修改入参顺序', () => {
  const now = 0;
  const triggers = [
    { triggerAtEpochMillis: 3000, title: 'b' },
    { triggerAtEpochMillis: 1000, title: 'a' },
  ];
  const planned = planReminders(triggers, now, 1);

  assert.deepEqual(planned.map((item) => item.title), ['a']);
  assert.deepEqual(triggers.map((item) => item.title), ['b', 'a']);
});
