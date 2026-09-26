/*
 * 选择器返回值的纯逻辑：URI → 文件名、缓存副本命名。
 *
 * 系统选择器给的是 `file://docs/...` 这类 URI（可能带 query、经过百分号编码，
 * 也可能是目录形式），而 Dart 侧需要的是可读的文件名与沙箱路径。这里把这段
 * 解析逻辑与 ArkTS API 解耦，便于用 Node 单元测试覆盖
 * （scripts/ohos-arkts-tests/）。
 */

/** URI 解析不出文件名时使用的兜底前缀。 */
export const FALLBACK_PREFIX: string = 'lynai_file';

/** 去掉 query/fragment 后取最后一段，并做百分号解码。 */
export function fileNameFromUri(uri: string): string {
  const withoutQuery = uri.split('?')[0].split('#')[0];
  const segments = withoutQuery.split('/');
  let last = segments[segments.length - 1];
  if (last.length === 0) {
    return FALLBACK_PREFIX;
  }
  try {
    last = decodeURIComponent(last);
  } catch (err) {
    // 非法百分号编码：保留原样，至少不丢文件名。
  }
  return last.length === 0 ? FALLBACK_PREFIX : last;
}

/**
 * 生成缓存副本的文件名：加时间戳与批内序号，避免同批选择里的重名互相覆盖
 * （同一毫秒内选到的两个同名文件必须落成两个不同路径），同时去掉文件名里的
 * 路径分隔符，防止拼出沙箱外的路径。
 */
export function cacheFileName(
  name: string,
  timestamp: number,
  sequence: number = 0,
): string {
  const safe = name.replace(/[\\/]/g, '_');
  return `${timestamp}_${sequence}_${safe.length === 0 ? FALLBACK_PREFIX : safe}`;
}
