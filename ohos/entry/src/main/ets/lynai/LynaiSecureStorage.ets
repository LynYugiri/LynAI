/*
 * LynAI 鸿蒙关键资产存储插件。
 *
 * 对应 Dart 侧 `OhosAssetSecretStore`（lib/services/secret_store.dart）使用的
 * `lynai/secure_storage` 通道。底层是 Asset Store Kit：写入的关键资产由 HUKS
 * 加密后保存在系统资产库，按「业务身份 + 别名」唯一索引，替代 Android Keystore /
 * iOS Keychain 的角色。
 *
 * 与通道约定的返回：
 * - read   入参 { key }，返回 String?（不存在时为 null）
 * - write  入参 { key, value }
 * - delete 入参 { key }
 *
 * 约束：Secret 长度 1-1024 字节、别名 1-256 字节（系统限制），超长时返回
 * 明确错误而不是静默截断。
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
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

const CHANNEL_NAME: string = 'lynai/secure_storage';
const MAX_SECRET_BYTES: number = 1024;
const MAX_ALIAS_BYTES: number = 256;
/**
 * 关键资产未找到。
 *
 * 直接用 SDK 的枚举而不是硬编码数字：Asset Store Kit 的错误码是
 * `NOT_FOUND = 24000002` / `DUPLICATED = 24000003`（不是从 24000001 开始）。
 */
const ERROR_NOT_FOUND: number = asset.ErrorCode.NOT_FOUND;

function encode(value: string): Uint8Array {
  return new util.TextEncoder().encodeInto(value);
}

function decode(value: Uint8Array): string {
  return new util.TextDecoder().decodeToString(value);
}

export class LynaiSecureStorage implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return 'LynaiSecureStorage';
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
      case 'read':
        this.read(call, result);
        break;
      case 'write':
        this.write(call, result);
        break;
      case 'delete':
        this.delete(call, result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private read(call: MethodCall, result: MethodResult): void {
    const key = this.requireKey(call, result);
    if (key === null) {
      return;
    }
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, encode(key));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    asset.query(query)
      .then((entries: asset.AssetMap[]) => {
        if (entries.length === 0) {
          result.success(null);
          return;
        }
        const secret = entries[0].get(asset.Tag.SECRET) as Uint8Array;
        result.success(decode(secret));
      })
      .catch((err: BusinessError) => {
        if (err.code === ERROR_NOT_FOUND) {
          result.success(null);
          return;
        }
        result.error(`secure_storage_read_failed`, err.message, err.code);
      });
  }

  private write(call: MethodCall, result: MethodResult): void {
    const key = this.requireKey(call, result);
    if (key === null) {
      return;
    }
    const value = call.argument('value') as string | null;
    if (value === null) {
      result.error('secure_storage_invalid_argument', '缺少 value', null);
      return;
    }
    const secret = encode(value);
    if (secret.byteLength > MAX_SECRET_BYTES) {
      result.error(
        'secure_storage_value_too_large',
        `关键资产长度上限 ${MAX_SECRET_BYTES} 字节`,
        null,
      );
      return;
    }
    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, encode(key));
    attributes.set(asset.Tag.SECRET, secret);
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    // 同别名重复写入时直接覆盖，等价于 Android/iOS 实现的「写入即覆盖」语义。
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    asset.add(attributes)
      .then(() => {
        result.success(null);
      })
      .catch((err: BusinessError) => {
        result.error('secure_storage_write_failed', err.message, err.code);
      });
  }

  private delete(call: MethodCall, result: MethodResult): void {
    const key = this.requireKey(call, result);
    if (key === null) {
      return;
    }
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, encode(key));
    asset.remove(query)
      .then(() => {
        result.success(null);
      })
      .catch((err: BusinessError) => {
        // 删除不存在的关键资产视为成功，与 Android/iOS 的 delete 幂等语义一致。
        if (err.code === ERROR_NOT_FOUND) {
          result.success(null);
          return;
        }
        result.error('secure_storage_delete_failed', err.message, err.code);
      });
  }

  private requireKey(call: MethodCall, result: MethodResult): string | null {
    const key = call.argument('key') as string | null;
    if (key === null || key.length === 0) {
      result.error('secure_storage_invalid_argument', '缺少 key', null);
      return null;
    }
    if (encode(key).byteLength > MAX_ALIAS_BYTES) {
      result.error(
        'secure_storage_invalid_argument',
        `关键资产别名上限 ${MAX_ALIAS_BYTES} 字节`,
        null,
      );
      return null;
    }
    return key;
  }

  static register(flutterEngine: FlutterEngine): void {
    flutterEngine.getPlugins()?.add(new LynaiSecureStorage());
  }
}
