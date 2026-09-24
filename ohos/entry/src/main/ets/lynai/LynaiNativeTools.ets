/*
 * LynAI 鸿蒙（HarmonyOS / OpenHarmony）原生能力插件。
 *
 * 对应 Android 侧 MainActivity.kt 中注册的 `lynai/native_tools` 通道，
 * 通道名与方法名、返回结构（`{ ok: bool, error?: string }`）都与 Android 保持一致，
 * Dart 侧无需按平台分支解析。
 *
 * 已实现：
 * - saveImageToGallery：把 Dart 传入的 PNG 字节写入系统图库。
 *   使用 Media Library Kit 的 `showAssetsCreationDialog` 弹窗授权保存，
 *   不申请 ohos.permission.WRITE_IMAGEVIDEO（该权限属于受限开放权限，
 *   普通应用无法直接申请）。用户确认后写入返回的媒体库 URI。
 * - getLocation：通过 Location Kit 读取最近一次已知位置。
 * - openApp / queryApps：鸿蒙没有与 Android 包管理器等价的公开能力，
 *   与 Dart 侧「仅 Android」门控一致，返回显式错误而不是让调用方等待。
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
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import common from '@ohos.app.ability.common';
import { exactBuffer } from './ByteUtils';

const CHANNEL_NAME: string = 'lynai/native_tools';
const DEFAULT_FILE_NAME: string = 'lynai_share';

/** 插件返回值统一为字符串键 Map，与 StandardMessageCodec 的 Map 编码一致。 */
function resultMap(ok: boolean, error?: string): Map<string, Object> {
  const map = new Map<string, Object>();
  map.set('ok', ok);
  if (error !== undefined) {
    map.set('error', error);
  }
  return map;
}

/** 把 Dart 传来的 Uint8List 归一化为 Uint8Array（编码器可能给出 ArrayBuffer 或数组）。 */
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

export class LynaiNativeTools implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  getUniqueClassName(): string {
    return 'LynaiNativeTools';
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
      case 'saveImageToGallery':
        this.saveImageToGallery(call, result);
        break;
      case 'getLocation':
        this.getLocation(result);
        break;
      case 'openApp':
        result.success(resultMap(false, 'device.app.open 仅支持 Android'));
        break;
      case 'queryApps':
        result.success(resultMap(false, 'device.app.list 仅支持 Android'));
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  /**
   * 把 PNG 字节保存到系统图库。
   *
   * 流程：写入应用缓存文件 → 转成 file:// URI → showAssetsCreationDialog 弹窗授权
   * → 打开图库目标 URI 写入 → 清理缓存文件。
   */
  private saveImageToGallery(call: MethodCall, result: MethodResult): void {
    const bytes = toUint8Array(call.argument('bytes') as Object | null);
    if (bytes === null || bytes.byteLength === 0) {
      result.success(resultMap(false, '图片数据为空'));
      return;
    }
    const rawName = call.argument('fileName') as string | null;
    const requested = rawName !== null && rawName.length > 0 ? rawName : '';
    const fileName = requested.length > 0
      ? requested
      : `${DEFAULT_FILE_NAME}_${Date.now()}.png`;
    const extension = fileName.endsWith('.jpg') || fileName.endsWith('.jpeg') ? 'jpg' : 'png';
    const title = fileName.substring(0, fileName.lastIndexOf('.') > 0
      ? fileName.lastIndexOf('.')
      : fileName.length);

    this.writeToGallery(bytes, fileName, title, extension)
      .then(() => {
        result.success(resultMap(true));
      })
      .catch((err: BusinessError) => {
        result.success(resultMap(false, `保存到图库失败: ${err.message}`));
      });
  }

  private async writeToGallery(
    bytes: Uint8Array,
    fileName: string,
    title: string,
    extension: string,
  ): Promise<void> {
    const cachePath = `${this.context.cacheDir}/${fileName}`;
    const cacheFile = fileIo.openSync(
      cachePath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
    );
    try {
      fileIo.writeSync(cacheFile.fd, exactBuffer(bytes));
    } finally {
      fileIo.closeSync(cacheFile);
    }

    const accessHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
    const config: photoAccessHelper.PhotoCreationConfig = {
      title: title,
      fileNameExtension: extension,
      photoType: photoAccessHelper.PhotoType.IMAGE,
    };
    const sourceUri = fileUri.getUriFromPath(cachePath);
    let targetUris: Array<string> = [];
    try {
      targetUris = await accessHelper.showAssetsCreationDialog([sourceUri], [config]);
      if (targetUris.length === 0) {
        throw new Error('用户未授权保存到图库');
      }
      const source = fileIo.openSync(sourceUri, fileIo.OpenMode.READ_ONLY);
      try {
        const target = fileIo.openSync(targetUris[0], fileIo.OpenMode.WRITE_ONLY);
        try {
          fileIo.copyFileSync(source.fd, target.fd);
        } finally {
          fileIo.closeSync(target);
        }
      } finally {
        fileIo.closeSync(source);
      }
    } finally {
      // 无论成功、取消还是失败都不在沙箱里残留临时文件。
      fileIo.unlinkSync(cachePath);
    }
  }

  /** 读取最近一次已知位置，字段与 Android 侧 `readLastLocation` 保持一致。 */
  private getLocation(result: MethodResult): void {
    try {
      // Location Kit 提供的是同步的 getLastLocation()（旧文档里的
      // getLastKnownLocation 在当前 SDK 上已不存在）。
      const location: geoLocationManager.Location =
        geoLocationManager.getLastLocation();
      const map = resultMap(true);
      map.set('latitude', location.latitude);
      map.set('longitude', location.longitude);
      map.set('accuracy', location.accuracy);
      map.set('provider', 'ohos');
      map.set('time', location.timeStamp);
      result.success(map);
    } catch (err) {
      const error = err as BusinessError;
      result.success(resultMap(
        false,
        `没有可用的最近位置，请确认定位服务已开启 (${error.message})`,
      ));
    }
  }

  /** 在 EntryAbility 中注册插件，传入 UIAbilityContext 供图库弹窗授权使用。 */
  static register(flutterEngine: FlutterEngine, context: common.UIAbilityContext): void {
    flutterEngine.getPlugins()?.add(new LynaiNativeTools(context));
  }
}
