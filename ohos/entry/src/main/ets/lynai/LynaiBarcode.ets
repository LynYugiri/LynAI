/*
 * LynAI 鸿蒙扫码插件（调起系统扫码 UI）。
 *
 * 工程在 Android/iOS 上用 `mobile_scanner` 自绘扫码页，鸿蒙侧的适配分支落后于
 * 当前 SDK，因此这里改用系统「统一扫码」服务（Scan Kit）：
 * `scanBarcode.startScanForResult` 会拉起系统扫码界面，自带相机权限与相册入口
 * （enableAlbum 允许用户直接从图库选一张二维码图片识别）。
 *
 * 通道约定：
 * - scan 无入参；返回
 *   { ok: true, value }        扫描成功，value 为二维码原文
 *   { ok: false, cancelled: true } 用户取消
 *   { ok: false, error }       其它失败（Dart 侧据此回退到「导入配对码图片」）
 *
 * 注意：Scan Kit 的接口要求在有 UI（页面）的上下文里调用；调用失败时 Dart 侧会
 * 自动回退到既有的图片解码路径，因此不会让配对流程卡住。
 */
import {
  FlutterEngine,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { BusinessError } from '@kit.BasicServicesKit';
import common from '@ohos.app.ability.common';
import {
  SYSCAP_SCAN_BARCODE,
  SYSCAP_SCAN_CORE,
  SysCapProbe,
  sysCapsAvailable,
} from './SysCapUtils';

const CHANNEL_NAME: string = 'lynai/barcode';
/** 用户主动取消扫码时 Scan Kit 返回的错误码。 */
const ERROR_USER_CANCELED: number = 1000500002;
/** 设备缺少 Scan Kit 能力时返回的错误文案（Dart 侧据此回退到导入图片）。 */
const ERROR_UNSUPPORTED: string = '当前设备不支持系统扫码能力';

/** 把环境提供的 canIUse 包成 SysCapProbe；canIUse 缺失时返回 undefined。 */
function sysCapProbe(): SysCapProbe | undefined {
  if (typeof canIUse === 'function') {
    return canIUse;
  }
  return undefined;
}

function resultMap(ok: boolean, error?: string, cancelled?: boolean): Map<string, Object> {
  const map = new Map<string, Object>();
  map.set('ok', ok);
  if (error !== undefined) {
    map.set('error', error);
  }
  if (cancelled !== undefined) {
    map.set('cancelled', cancelled);
  }
  return map;
}

export class LynaiBarcode implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  getUniqueClassName(): string {
    return 'LynaiBarcode';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'scan':
        this.scan(result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private scan(result: MethodResult): void {
    // Scan Kit 并非所有设备都具备（编译器会提示 syscap），缺能力时直接回错误，
    // 交给 Dart 侧回退到「导入配对码图片」，避免在设备上抛异常打断通道。
    if (!sysCapsAvailable(sysCapProbe(), [SYSCAP_SCAN_BARCODE, SYSCAP_SCAN_CORE])) {
      result.success(resultMap(false, ERROR_UNSUPPORTED));
      return;
    }
    // 放大拍码/图片识码都走系统 UI：enableAlbum 让用户可以直接从图库选二维码图片。
    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: false,
      enableAlbum: true,
    };
    try {
      scanBarcode.startScanForResult(this.context, options)
        .then((scanResult: scanBarcode.ScanResult) => {
          const value = scanResult.originalValue;
          if (value === undefined || value.length === 0) {
            result.success(resultMap(false, '未识别到二维码内容'));
            return;
          }
          const map = resultMap(true);
          map.set('value', value);
          result.success(map);
        })
        .catch((err: BusinessError) => {
          if (err.code === ERROR_USER_CANCELED) {
            result.success(resultMap(false, undefined, true));
            return;
          }
          // 其它错误（含「必须在页面上下文调用」这类约束）交给 Dart 侧回退。
          result.success(resultMap(false, err.message));
        });
    } catch (err) {
      // 同步抛出的异常同样按「不可用」处理，保证通道一定有回包。
      const error = err as BusinessError;
      const message = error.message !== undefined ? error.message : ERROR_UNSUPPORTED;
      result.success(resultMap(false, message));
    }
  }

  static register(flutterEngine: FlutterEngine, context: common.UIAbilityContext): void {
    flutterEngine.getPlugins()?.add(new LynaiBarcode(context));
  }
}
