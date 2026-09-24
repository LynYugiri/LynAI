/*
 * WidgetPlan.ts 的单元测试：与 Android 小组件保持同一套语义。
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  MAX_EXTRA_ROWS,
  dayDiff,
  labelPrefix,
  occurrenceTimes,
  planWidget,
} from '../../ohos/entry/src/main/ets/lynai/WidgetPlan.ts';

const local = (y, m, d, h = 0, min = 0) => new Date(y, m - 1, d, h, min).getTime();

test('occurrenceTimes 与 Android 推导一致：epoch 优先，缺省补 00:00', () => {
  assert.deepEqual(
    occurrenceTimes({
      title: '会议',
      date: '2026-09-24',
      startTime: '09:30',
      endDateExclusive: '2026-09-25',
    }),
    { title: '会议', start: local(2026, 9, 24, 9, 30), end: local(2026, 9, 25, 0, 0) },
  );

  assert.deepEqual(
    occurrenceTimes({
      title: '全天',
      date: '2026-09-24',
      endDateExclusive: '2026-09-25',
    }),
    { title: '全天', start: local(2026, 9, 24, 0, 0), end: local(2026, 9, 25, 0, 0) },
  );

  const epoch = local(2026, 9, 24, 9, 30);
  assert.deepEqual(
    occurrenceTimes({
      title: 'UTC 锚定',
      date: '2026-09-24',
      startAtEpochMillis: epoch,
      endAtEpochMillis: epoch + 3600000,
    }),
    { title: 'UTC 锚定', start: epoch, end: epoch + 3600000 },
  );
});

test('occurrenceTimes 优先 endAtLocal，缺日期返回 null', () => {
  assert.deepEqual(
    occurrenceTimes({
      title: '跨天',
      date: '2026-09-24',
      startTime: '22:00',
      endAtLocal: '2026-09-25T02:00',
      endDateExclusive: '2026-09-26',
    }),
    { title: '跨天', start: local(2026, 9, 24, 22, 0), end: local(2026, 9, 25, 2, 0) },
  );
  assert.equal(occurrenceTimes({ title: '无日期' }), null);
  assert.equal(occurrenceTimes({ title: '坏日期', date: '2026/09/24' }), null);
});

test('dayDiff 按自然日计算', () => {
  assert.equal(dayDiff(local(2026, 9, 24, 23, 59), local(2026, 9, 25, 0, 1)), 1);
  assert.equal(dayDiff(local(2026, 9, 24, 0, 1), local(2026, 9, 24, 23, 59)), 0);
  assert.equal(dayDiff(local(2026, 9, 24), local(2026, 10, 1)), 7);
});

test('labelPrefix 输出 进行中/今天/明天/N 天后/M月d日', () => {
  const now = local(2026, 9, 24, 10, 0);
  assert.equal(labelPrefix(local(2026, 9, 24, 9, 0), local(2026, 9, 24, 11, 0), now), '进行中');
  assert.equal(labelPrefix(local(2026, 9, 24, 15, 0), local(2026, 9, 24, 16, 0), now), '今天');
  assert.equal(labelPrefix(local(2026, 9, 25, 9, 0), local(2026, 9, 25, 10, 0), now), '明天');
  assert.equal(labelPrefix(local(2026, 9, 27, 9, 0), local(2026, 9, 27, 10, 0), now), '3 天后');
  assert.equal(labelPrefix(local(2026, 10, 2, 9, 0), local(2026, 10, 2, 10, 0), now), '10月2日');
});

test('planWidget 过滤已结束与已完成，按开始时间升序', () => {
  const now = local(2026, 9, 24, 10, 0);
  const plan = planWidget(
    [
      { title: '已结束', date: '2026-09-24', startTime: '08:00', endAtLocal: '2026-09-24T09:00' },
      { title: '已完成', date: '2026-09-24', startTime: '11:00', endAtLocal: '2026-09-24T12:00', isCompleted: true },
      { title: '下午会', date: '2026-09-24', startTime: '15:00', endAtLocal: '2026-09-24T16:00' },
      { title: '上午会', date: '2026-09-24', startTime: '11:00', endAtLocal: '2026-09-24T12:00' },
      { title: '明天事', date: '2026-09-25', startTime: '09:00', endAtLocal: '2026-09-25T10:00' },
    ],
    now,
  );

  assert.equal(plan.headline, '今天 · 上午会');
  assert.deepEqual(plan.rows, ['今天 · 下午会', '明天 · 明天事']);
  assert.equal(plan.updatedAt, '10:00');
});

test('planWidget 无日程时给出与 Android 一致的文案', () => {
  const now = local(2026, 9, 24, 10, 0);
  const plan = planWidget([], now);

  assert.equal(plan.headline, '近期无日程');
  assert.deepEqual(plan.rows, []);
  assert.equal(plan.updatedAt, '10:00');
});

test('planWidget 附加行受上限约束且可调整', () => {
  const now = local(2026, 9, 24, 8, 0);
  const occurrences = [];
  for (let hour = 9; hour < 15; hour++) {
    occurrences.push({
      title: `${hour} 点`,
      date: '2026-09-24',
      startTime: `${hour < 10 ? '0' : ''}${hour}:00`,
      endAtLocal: `2026-09-24T${hour < 10 ? '0' : ''}${hour}:30`,
    });
  }

  assert.equal(planWidget(occurrences, now).rows.length, MAX_EXTRA_ROWS);
  assert.equal(planWidget(occurrences, now, 4).rows.length, 4);
  assert.equal(planWidget(occurrences, now, 0).rows.length, 0);
  assert.equal(planWidget(occurrences, now).headline, '今天 · 9 点');
});

test('planWidget 跳过缺少日期的记录', () => {
  const now = local(2026, 9, 24, 8, 0);
  const plan = planWidget(
    [
      { title: '坏记录' },
      { title: '好记录', date: '2026-09-24', startTime: '09:00', endAtLocal: '2026-09-24T10:00' },
    ],
    now,
  );

  assert.equal(plan.headline, '今天 · 好记录');
});
