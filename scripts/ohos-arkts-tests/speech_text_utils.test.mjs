/*
 * SpeechTextUtils.ts 的单元测试：语言折算与识别结果拼接。
 */
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  DEFAULT_LANGUAGE,
  appendSentence,
  normalizeLanguage,
} from '../../ohos/entry/src/main/ets/lynai/SpeechTextUtils.ts';

test('中文变体统一走 zh-CN', () => {
  for (const locale of ['zh', 'zh_CN', 'zh-Hans-CN', 'ZH_cn']) {
    assert.equal(normalizeLanguage(locale), 'zh-CN', locale);
  }
});

test('英文走 en-US，其它语言保留归一化结果', () => {
  assert.equal(normalizeLanguage('en_US'), 'en-US');
  assert.equal(normalizeLanguage('en-GB'), 'en-US');
  assert.equal(normalizeLanguage('ja_JP'), 'ja-JP');
});

test('空输入回退到默认语言', () => {
  assert.equal(normalizeLanguage(''), DEFAULT_LANGUAGE);
  assert.equal(normalizeLanguage('   '), DEFAULT_LANGUAGE);
});

test('拼接句子时忽略空片段', () => {
  assert.equal(appendSentence('', ''), '');
  assert.equal(appendSentence('', '   '), '');
  assert.equal(appendSentence('第一句', ''), '第一句');
  assert.equal(appendSentence('', '第一句'), '第一句');
});

test('拼接句子用换行分隔并去除首尾空白', () => {
  assert.equal(appendSentence('第一句', '第二句'), '第一句\n第二句');
  assert.equal(appendSentence('第一句', '  第二句  '), '第一句\n第二句');
  assert.equal(
    appendSentence(appendSentence('一', '二'), '三'),
    '一\n二\n三',
  );
});
