/*
 * LynAI 鸿蒙文件选择插件。
 *
 * 工程使用的 `file_picker 11.x` 没有鸿蒙实现，而社区鸿蒙分支是 API 不兼容的
 * `file_picker 12.x`。这里在自有通道 `lynai/file_picker` 上用系统选择器
 * （DocumentViewPicker / PhotoViewPicker）实现等价的「选文件 / 另存为」能力，
 * 由 `lib/utils/ohos_file_picker.dart` 在鸿蒙上调用；其它平台仍走 file_picker。
 *
 * 通道约定：
 * - pickFiles 入参 { type, allowedExtensions, allowMultiple }
 *   返回 { ok: true, files: [{ name, path, size }] }；取消时 files 为空数组。
 *   选择结果会先复制到应用缓存目录（file://docs/... 这类 URI 无法用 dart:io
 *   直接读取），因此返回的 path 一定是沙箱内的真实路径。
 * - saveFile 入参 { fileName, bytes }
 *   返回 { ok: true, path }，path 是缓存目录里的副本路径，调用方可以继续用
 *   dart:io 读取；用户选择的目标文件已经写入。
 *
 * 选择器由系统提供，不需要申请任何存储权限。
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
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import common from '@ohos.app.ability.common';
import { exactBuffer } from './ByteUtils';
import { cacheFileName, fileNameFromUri } from './PickerPathUtils';

const CHANNEL_NAME: string = 'lynai/file_picker';
/** 选择结果复制到缓存目录下的子目录，便于整体清理。 */
const PICK_DIR: string = 'lynai_pick';

/** 与 dart:io 的 FileType 取值保持一致。 */
const TYPE_ANY: string = 'any';
const TYPE_IMAGE: string = 'image';

interface PickedEntry {
  name: string;
  path: string;
  size: number;
}

function okMap(): Map<string, Object> {
  const map = new Map<string, Object>();
  map.set('ok', true);
  return map;
}

function errorMap(message: string): Map<string, Object> {
  const map = new Map<string, Object>();
  map.set('ok', false);
  map.set('error', message);
  return map;
}

export class LynaiFilePicker implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  getUniqueClassName(): string {
    return 'LynaiFilePicker';
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
      case 'pickFiles':
        this.pickFiles(call, result);
        break;
      case 'saveFile':
        this.saveFile(call, result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private pickFiles(call: MethodCall, result: MethodResult): void {
    const type = (call.argument('type') as string | null) ?? TYPE_ANY;
    const allowMultiple = (call.argument('allowMultiple') as boolean | null) ?? false;
    const extensions = this.stringListArgument(call, 'allowedExtensions');
    if (type === TYPE_IMAGE) {
      this.pickImages(allowMultiple, result);
      return;
    }
    this.pickDocuments(extensions, allowMultiple, result);
  }

  /** 图片走图库选择器，其余类型走文件选择器。 */
  private pickImages(allowMultiple: boolean, result: MethodResult): void {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = allowMultiple ? 9 : 1;
    const photoPicker = new photoAccessHelper.PhotoViewPicker();
    photoPicker.select(options)
      .then((selection: photoAccessHelper.PhotoSelectResult) => {
        result.success(this.copyUris(selection.photoUris));
      })
      .catch((err: BusinessError) => {
        result.success(errorMap(`选择图片失败: ${err.message}`));
      });
  }

  private pickDocuments(
    extensions: string[],
    allowMultiple: boolean,
    result: MethodResult,
  ): void {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = allowMultiple ? 9 : 1;
    if (extensions.length > 0) {
      options.fileSuffixFilters = extensions.map((item: string) => `.${item}`);
    }
    const documentPicker = new picker.DocumentViewPicker(this.context);
    documentPicker.select(options)
      .then((uris: string[]) => {
        result.success(this.copyUris(uris));
      })
      .catch((err: BusinessError) => {
        result.success(errorMap(`选择文件失败: ${err.message}`));
      });
  }

  /**
   * 把选择器返回的 URI 逐个复制进应用缓存目录。
   *
   * 系统选择器给的是临时授权的 URI，dart:io 无法直接读取；复制到沙箱后
   * Dart 侧拿到的就是普通路径，与其它平台行为一致。
   */
  private copyUris(uris: string[]): Map<string, Object> {
    const map = okMap();
    const entries: PickedEntry[] = [];
    if (uris.length === 0) {
      map.set('files', entries);
      return map;
    }
    const targetDir = `${this.context.cacheDir}/${PICK_DIR}`;
    try {
      if (!fileIo.accessSync(targetDir)) {
        fileIo.mkdirSync(targetDir, true);
      }
    } catch (err) {
      const error = err as BusinessError;
      return errorMap(`无法创建缓存目录: ${error.message}`);
    }
    const batchStamp = Date.now();
    for (let index = 0; index < uris.length; index++) {
      try {
        // 时间戳按批次取一次，批内序号保证同一毫秒里的同名文件不会互相覆盖。
        const entry = this.copyUriToCache(uris[index], targetDir, batchStamp, index);
        entries.push(entry);
      } catch (err) {
        const error = err as BusinessError;
        // 单个文件失败不影响其它选择结果，但要在返回值里说明。
        return errorMap(`读取所选文件失败: ${error.message}`);
      }
    }
    map.set('files', entries);
    return map;
  }

  private copyUriToCache(
    uri: string,
    targetDir: string,
    batchStamp: number,
    sequence: number,
  ): PickedEntry {
    const name = fileNameFromUri(uri);
    const targetPath = `${targetDir}/${cacheFileName(name, batchStamp, sequence)}`;
    const source = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    let size = 0;
    try {
      const stat = fileIo.statSync(source.fd);
      size = stat.size;
      fileIo.copyFileSync(source.fd, targetPath);
    } finally {
      fileIo.closeSync(source);
    }
    return { name: name, path: targetPath, size: size };
  }

  private saveFile(call: MethodCall, result: MethodResult): void {
    const fileName = (call.argument('fileName') as string | null) ?? '';
    const bytes = this.toUint8Array(call.argument('bytes') as Object | null);
    if (bytes === null || bytes.byteLength === 0) {
      result.success(errorMap('文件内容为空'));
      return;
    }
    const safeName = fileName.length > 0 ? fileName : `lynai_${Date.now()}`;
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [safeName];
    const documentPicker = new picker.DocumentViewPicker(this.context);
    documentPicker.save(options)
      .then((uris: string[]) => {
        if (uris.length === 0) {
          // 用户取消：与其它平台的 file_picker 一致，返回「成功但没有路径」，
          // Dart 侧据此返回 null，不生成「保存失败」错误。
          const cancelled = okMap();
          cancelled.set('cancelled', true);
          result.success(cancelled);
          return;
        }
        try {
          const target = fileIo.openSync(
            uris[0],
            fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
          );
          try {
            fileIo.writeSync(target.fd, exactBuffer(bytes));
          } finally {
            fileIo.closeSync(target);
          }
          // 另外在沙箱里留一份副本，供调用方用 dart:io 继续读取/分享。
          const targetDir = `${this.context.cacheDir}/${PICK_DIR}`;
          if (!fileIo.accessSync(targetDir)) {
            fileIo.mkdirSync(targetDir, true);
          }
          const copyPath = `${targetDir}/${cacheFileName(safeName, Date.now())}`;
          const copy = fileIo.openSync(
            copyPath,
            fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
          );
          try {
            fileIo.writeSync(copy.fd, exactBuffer(bytes));
          } finally {
            fileIo.closeSync(copy);
          }
          const map = okMap();
          map.set('path', copyPath);
          map.set('uri', fileUri.getUriFromPath(copyPath));
          result.success(map);
        } catch (err) {
          const error = err as BusinessError;
          result.success(errorMap(`写入文件失败: ${error.message}`));
        }
      })
      .catch((err: BusinessError) => {
        result.success(errorMap(`保存文件失败: ${err.message}`));
      });
  }

  private stringListArgument(call: MethodCall, key: string): string[] {
    const value = call.argument(key) as Object | null;
    if (value === null || !Array.isArray(value)) {
      return [];
    }
    return (value as Object[]).map((item: Object) => `${item}`);
  }

  private toUint8Array(value: Object | null): Uint8Array | null {
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

  static register(flutterEngine: FlutterEngine, context: common.UIAbilityContext): void {
    flutterEngine.getPlugins()?.add(new LynaiFilePicker(context));
  }
}
