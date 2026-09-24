/*
 * LynAI 鸿蒙剪贴板插件（只做写入）。
 *
 * 工程里的图片剪贴板走 `super_clipboard`，它没有鸿蒙实现。鸿蒙侧：
 * - **写入**剪贴板不需要任何权限，用系统的 pasteboard 写入 PixelMap 记录即可，
 *   其它应用与系统剪贴板面板都能正常粘贴；
 * - **读取**剪贴板需要 `ohos.permission.READ_PASTEBOARD`，该权限不向普通应用
 *   开放（声明后安装会被系统拒绝），因此鸿蒙上不提供「从剪贴板粘贴图片」，
 *   Dart 侧继续按能力开关隐藏该行为，只保留从图库/文件选择图片。
 *
 * 通道约定：
 * - copyImage 入参 { bytes, mimeType }（bytes 为 PNG/JPEG 等编码后的图片字节）
 *   返回 { ok: true }；解码失败返回 { ok: false, error }。
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
import { pasteboard } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { exactBuffer } from './ByteUtils';

const CHANNEL_NAME: string = 'lynai/clipboard';

function resultMap(ok: boolean, error?: string): Map<string, Object> {
  const map = new Map<string, Object>();
  map.set('ok', ok);
  if (error !== undefined) {
    map.set('error', error);
  }
  return map;
}

function toUint8Array(value: Object | null): Uint8Array | null {
  if (value instanceof Uint8Array) {
    return value;
  }
  if (value instanceof ArrayBuffer) {
    return new Uint8Array(value);
  }
  if (Array.isArray(value)) {
    return Uint8Array.from(value as number[]);
  }
  return null;
}

export class LynaiClipboard implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return 'LynaiClipboard';
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
      case 'copyImage':
        this.copyImage(call, result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private copyImage(call: MethodCall, result: MethodResult): void {
    const bytes = toUint8Array(call.argument('bytes') as Object | null);
    if (bytes === null || bytes.byteLength === 0) {
      result.success(resultMap(false, '图片数据为空'));
      return;
    }
    this.decodeAndWrite(bytes)
      .then(() => {
        result.success(resultMap(true));
      })
      .catch((err: BusinessError) => {
        result.success(resultMap(false, `复制图片失败: ${err.message}`));
      });
  }

  /**
   * 解码成 PixelMap 后写入系统剪贴板。
   *
   * 用 MIMETYPE_PIXELMAP 而不是自定义 mime：这是鸿蒙剪贴板的标准图片记录类型，
   * 系统剪贴板面板与其它应用都能识别。
   */
  private async decodeAndWrite(bytes: Uint8Array): Promise<void> {
    const source: image.ImageSource = image.createImageSource(exactBuffer(bytes));
    try {
      const pixelMap: image.PixelMap = await source.createPixelMap();
      try {
        const data: pasteboard.PasteData =
          pasteboard.createData(pasteboard.MIMETYPE_PIXELMAP, pixelMap);
        await pasteboard.getSystemPasteboard().setData(data);
      } finally {
        await pixelMap.release();
      }
    } finally {
      await source.release();
    }
  }

  static register(flutterEngine: FlutterEngine): void {
    flutterEngine.getPlugins()?.add(new LynaiClipboard());
  }
}
