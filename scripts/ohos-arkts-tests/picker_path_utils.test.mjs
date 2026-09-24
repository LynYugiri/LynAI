/*
 * PickerPathUtils.ts 的单元测试：覆盖选择器 URI 的常见形态与恶意/异常输入。
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  FALLBACK_PREFIX,
  cacheFileName,
  fileNameFromUri,
} from '../../ohos/entry/src/main/ets/lynai/PickerPathUtils.ts';

test('从沙箱路径与 file:// URI 取文件名', () => {
  assert.equal(
    fileNameFromUri('file://docs/storage/Users/currentUser/Download/report.pdf'),
    'report.pdf',
  );
  assert.equal(
    fileNameFromUri('/data/storage/el2/base/haps/entry/cache/lynai_pick/a.png'),
    'a.png',
  );
});

test('忽略 query 与 fragment', () => {
  assert.equal(
    fileNameFromUri('file://docs/a/b/photo.jpg?networkid=1'),
    'photo.jpg',
  );
  assert.equal(fileNameFromUri('file://docs/a/b/photo.jpg#preview'), 'photo.jpg');
});

test('百分号编码会被解码', () => {
  assert.equal(
    fileNameFromUri('file://docs/%E6%8A%A5%E5%91%8A.pdf'),
    '报告.pdf',
  );
  assert.equal(fileNameFromUri('file://docs/a%20b.txt'), 'a b.txt');
});

test('非法百分号编码不抛错，保留原样', () => {
  assert.equal(fileNameFromUri('file://docs/100%.txt'), '100%.txt');
});

test('目录形式与空串回退到兜底前缀', () => {
  assert.equal(fileNameFromUri('file://docs/a/b/'), FALLBACK_PREFIX);
  assert.equal(fileNameFromUri(''), FALLBACK_PREFIX);
  assert.equal(fileNameFromUri('file://docs/%20'), ' ');
});

test('缓存文件名带时间戳且不含路径分隔符', () => {
  assert.equal(cacheFileName('report.pdf', 1700000000000), '1700000000000_report.pdf');
  assert.equal(
    cacheFileName('../../etc/passwd', 1),
    '1_.._.._etc_passwd',
  );
  assert.equal(cacheFileName('a\\b.txt', 2), '2_a_b.txt');
  assert.equal(cacheFileName('', 3), `3_${FALLBACK_PREFIX}`);
});
