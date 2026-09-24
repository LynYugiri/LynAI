/*
 * 鸿蒙系统能力（syscap）探测工具。
 *
 * 背景：ArkTS 编译器会对「并非所有设备都具备」的 API 给出提示
 * （The system capacity of this api '...' is not supported on all devices），
 * 例如长时任务与 Scan Kit。这类 API 在缺少对应能力的设备上直接调用会抛异常，
 * 而异常若从 MethodChannel 的 onMethodCall 里抛出，会越过 Dart 侧的
 * 「失败就回退」分支，直接表现成崩溃或通道无响应。
 *
 * 因此统一在调用前用 canIUse() 探测一次，探测不到就当作「不支持」，
 * 由调用方返回错误结果，让 Dart 侧走既有回退路径（例如扫码回退到导入图片）。
 *
 * 这个文件不引入任何鸿蒙 API，canIUse 由调用方以 probe 形式注入，
 * 便于在 Node 里直接跑单元测试（见 scripts/ohos-arkts-tests/）。
 */

/** canIUse 的最小签名；注入形式让纯逻辑可以被测试。 */
export type SysCapProbe = (name: string) => boolean;

/** Scan Kit 统一扫码界面的系统能力。 */
export const SYSCAP_SCAN_BARCODE: string = 'SystemCapability.Multimedia.Scan.ScanBarcode';

/** Scan Kit 基础类型（ScanType 等枚举）的系统能力。 */
export const SYSCAP_SCAN_CORE: string = 'SystemCapability.Multimedia.Scan.Core';

/** 长时任务（continuous task）的系统能力。 */
export const SYSCAP_CONTINUOUS_TASK: string =
  'SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask';

/**
 * 探测某个系统能力是否可用。
 *
 * probe 缺失（运行环境没有 canIUse）或探测本身抛异常时一律返回 false：
 * 宁可走「不支持」分支，也不要在缺少能力的设备上直接调用 API。
 */
export function sysCapAvailable(probe: SysCapProbe | undefined, name: string): boolean {
  if (probe === undefined || name.length === 0) {
    return false;
  }
  try {
    return probe(name) === true;
  } catch (err) {
    return false;
  }
}

/**
 * 判断一组系统能力是否全部可用（用于同时依赖 Core + ScanBarcode 的扫码调用）。
 */
export function sysCapsAvailable(probe: SysCapProbe | undefined, names: string[]): boolean {
  if (names.length === 0) {
    return false;
  }
  for (const name of names) {
    if (!sysCapAvailable(probe, name)) {
      return false;
    }
  }
  return true;
}
