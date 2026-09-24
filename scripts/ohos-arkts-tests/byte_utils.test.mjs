/*
 * ByteUtils.ts 的单元测试：验证字节视图折算不会带出多余数据。
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import { exactBuffer } from '../../ohos/entry/src/main/ets/lynai/ByteUtils.ts';

test('完整视图直接复用底层 buffer', () => {
  const bytes = new Uint8Array([1, 2, 3]);
  const buffer = exactBuffer(bytes);
  assert.equal(buffer, bytes.buffer);
  assert.equal(buffer.byteLength, 3);
});

test('子视图只取自己的那一段', () => {
  const backing = new Uint8Array([0, 1, 2, 3, 4, 5]);
  const view = backing.subarray(2, 5);

  const buffer = exactBuffer(view);

  assert.notEqual(buffer, backing.buffer);
  assert.deepEqual(Array.from(new Uint8Array(buffer)), [2, 3, 4]);
});

test('空视图返回空 buffer', () => {
  const buffer = exactBuffer(new Uint8Array(0));
  assert.equal(buffer.byteLength, 0);
});

test('折算结果是副本，后续修改原视图不影响它', () => {
  const backing = new Uint8Array([9, 9, 9, 9]);
  const view = backing.subarray(1, 3);
  const buffer = exactBuffer(view);

  view[0] = 7;

  assert.deepEqual(Array.from(new Uint8Array(buffer)), [9, 9]);
});
