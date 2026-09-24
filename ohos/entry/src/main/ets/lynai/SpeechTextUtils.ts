/*
 * 语音识别的纯逻辑：语言标签折算与句子拼接。
 *
 * 与 ArkTS/鸿蒙 API 解耦，便于用 Node 单元测试覆盖
 * （scripts/ohos-arkts-tests/）。设备相关部分在 LynaiSpeech.ets。
 */

/** 识别引擎默认语言标签。 */
export const DEFAULT_LANGUAGE: string = 'zh-CN';

/**
 * 把 Dart 传来的 localeId（`zh_CN` / `en_US` / `zh-Hans-CN` 等）折算成识别引擎
 * 认识的语言标签。
 *
 * 当前公开能力只提供中文离线模型，因此所有中文变体统一走 `zh-CN`；无法识别时
 * 也不返回空串，避免把空语言交给 SDK 触发参数错误。
 */
export function normalizeLanguage(localeId: string): string {
  const normalized = (localeId ?? '').replace(/_/g, '-').trim();
  if (normalized.length === 0) {
    return DEFAULT_LANGUAGE;
  }
  const lower = normalized.toLowerCase();
  if (lower.startsWith('zh')) {
    return 'zh-CN';
  }
  if (lower.startsWith('en')) {
    return 'en-US';
  }
  return normalized;
}

/**
 * 拼接句子：空片段不参与，非空片段之间用换行分隔。
 *
 * 与 Dart 侧 `_fillSpeechText` 的追加语义保持一致，识别结果填入输入框时不会
 * 出现空白行。
 */
export function appendSentence(base: string, next: string): string {
  const trimmed = (next ?? '').trim();
  if (trimmed.length === 0) {
    return base;
  }
  return base.length === 0 ? trimmed : `${base}\n${trimmed}`;
}
