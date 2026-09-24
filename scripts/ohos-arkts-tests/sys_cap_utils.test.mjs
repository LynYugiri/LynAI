/*
 * SysCapUtils.ts 的单元测试：系统能力探测的失败兜底语义。
 *
 * 重点是「探测不到能力时绝不冒险调用 API」：probe 缺失、返回 false 或抛异常
 * 都必须被折算成 false，且不能把异常抛给调用方（否则 MethodChannel 回调会中断）。
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  SYSCAP_CONTINUOUS_TASK,
  SYSCAP_SCAN_BARCODE,
  SYSCAP_SCAN_CORE,
  sysCapAvailable,
  sysCapsAvailable,
} from '../../ohos/entry/src/main/ets/lynai/SysCapUtils.ts';

test('syscap 常量与 SDK 注解一致', () => {
  // 依据：<sdk>/hms/ets/api/@hms.core.scan.scanBarcode.d.ts、
  //       <sdk>/openharmony/ets/api/@ohos.resourceschedule.backgroundTaskManager.d.ts
  assert.equal(SYSCAP_SCAN_BARCODE, 'SystemCapability.Multimedia.Scan.ScanBarcode');
  assert.equal(SYSCAP_SCAN_CORE, 'SystemCapability.Multimedia.Scan.Core');
  assert.equal(
    SYSCAP_CONTINUOUS_TASK,
    'SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask',
  );
});

test('probe 返回 true/false 时如实透传', () => {
  assert.equal(sysCapAvailable(() => true, SYSCAP_SCAN_BARCODE), true);
  assert.equal(sysCapAvailable(() => false, SYSCAP_SCAN_BARCODE), false);
});

test('probe 缺失时按不支持处理', () => {
  assert.equal(sysCapAvailable(undefined, SYSCAP_SCAN_BARCODE), false);
});

test('probe 抛异常时按不支持处理且不向外抛', () => {
  assert.equal(
    sysCapAvailable(() => {
      throw new Error('canIUse is not defined');
    }, SYSCAP_SCAN_BARCODE),
    false,
  );
});

test('空能力名不调用 probe，直接按不支持处理', () => {
  let calls = 0;
  const probe = () => {
    calls += 1;
    return true;
  };
  assert.equal(sysCapAvailable(probe, ''), false);
  assert.equal(calls, 0);
});

test('probe 只收到传入的能力名', () => {
  const seen = [];
  sysCapAvailable((name) => {
    seen.push(name);
    return true;
  }, SYSCAP_SCAN_CORE);
  assert.deepEqual(seen, [SYSCAP_SCAN_CORE]);
});

test('sysCapsAvailable 要求全部能力可用', () => {
  const available = new Set([SYSCAP_SCAN_BARCODE, SYSCAP_SCAN_CORE]);
  const probe = (name) => available.has(name);
  assert.equal(sysCapsAvailable(probe, [SYSCAP_SCAN_BARCODE, SYSCAP_SCAN_CORE]), true);

  available.delete(SYSCAP_SCAN_CORE);
  assert.equal(sysCapsAvailable(probe, [SYSCAP_SCAN_BARCODE, SYSCAP_SCAN_CORE]), false);
});

test('sysCapsAvailable 缺少 probe 或能力列表为空时按不支持处理', () => {
  assert.equal(sysCapsAvailable(undefined, [SYSCAP_SCAN_BARCODE]), false);
  assert.equal(sysCapsAvailable(() => true, []), false);
});

test('sysCapsAvailable 在第一个能力不可用时短路，不再探测后续能力', () => {
  const seen = [];
  const probe = (name) => {
    seen.push(name);
    return name === SYSCAP_SCAN_BARCODE;
  };
  assert.equal(sysCapsAvailable(probe, [SYSCAP_SCAN_CORE, SYSCAP_SCAN_BARCODE]), false);
  assert.deepEqual(seen, [SYSCAP_SCAN_CORE]);
});
