/*
 * LynAI 鸿蒙后台任务插件。
 *
 * 对应 Dart 侧 `GenerationBackgroundService`（lib/services/generation_background_service.dart）
 * 使用的 `lynai/background_service` 通道：Android 侧是
 * GenerationForegroundService（前台服务 + 常驻通知），鸿蒙侧的等价物是
 * 「长时任务」（continuous task）——申请后系统不会在应用退到后台时冻结进程，
 * 生成过程可以跑完。
 *
 * 通道约定（与 Android 一致）：
 * - startGeneration 启动长时任务
 * - stopGeneration  结束长时任务
 * 失败时通过 result.error 返回，Dart 侧只记录日志、不影响对话流程。
 *
 * 需要在 module.json5 声明 ohos.permission.KEEP_BACKGROUND_RUNNING（system_grant）。
 * 任务类型选 dataTransfer：本应用在后台做的是模型流式响应的网络收发，
 * 不涉及音频播放/录音/定位等专用类型。
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
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { WantAgent, wantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import common from '@ohos.app.ability.common';
import { SYSCAP_CONTINUOUS_TASK, SysCapProbe, sysCapAvailable } from './SysCapUtils';

const CHANNEL_NAME: string = 'lynai/background_service';
/** 设备不支持长时任务时返回的错误文案（Dart 侧只记日志，不影响对话流程）。 */
const ERROR_UNSUPPORTED: string = '当前设备不支持长时任务，生成期间可能被系统冻结';

/** 把环境提供的 canIUse 包成 SysCapProbe；canIUse 缺失时返回 undefined。 */
function sysCapProbe(): SysCapProbe | undefined {
  if (typeof canIUse === 'function') {
    return canIUse;
  }
  return undefined;
}

export class LynaiBackgroundService implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext;
  private running: boolean = false;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  getUniqueClassName(): string {
    return 'LynaiBackgroundService';
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
      case 'startGeneration':
        this.start(result);
        break;
      case 'stopGeneration':
        this.stop(result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private start(result: MethodResult): void {
    // 重复 start 直接视为成功，避免 Dart 侧频繁切换时产生无意义的错误。
    if (this.running) {
      result.success(null);
      return;
    }
    // 长时任务并非所有设备都具备（编译器会提示 syscap），缺能力时明确回错误，
    // 不进入下面的调用；Dart 侧只记日志，生成流程照常进行。
    if (!sysCapAvailable(sysCapProbe(), SYSCAP_CONTINUOUS_TASK)) {
      result.error('background_task_unsupported', ERROR_UNSUPPORTED, null);
      return;
    }
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: this.context.abilityInfo.bundleName,
            abilityName: this.context.abilityInfo.name,
          },
        ],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      };
      wantAgent.getWantAgent(info)
        .then((agent: WantAgent) => {
          return backgroundTaskManager.startBackgroundRunning(
            this.context,
            backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
            agent,
          );
        })
        .then(() => {
          this.running = true;
          result.success(null);
        })
        .catch((err: BusinessError) => {
          result.error(
            'background_task_start_failed',
            err.message,
            err.code,
          );
        });
    } catch (err) {
      const error = err as BusinessError;
      result.error('background_task_start_failed', error.message, error.code);
    }
  }

  private stop(result: MethodResult): void {
    if (!this.running) {
      result.success(null);
      return;
    }
    try {
      backgroundTaskManager.stopBackgroundRunning(this.context)
        .then(() => {
          this.running = false;
          result.success(null);
        })
        .catch((err: BusinessError) => {
          // 结束失败也要复位状态，否则后续 start 会被误判为「已在运行」。
          this.running = false;
          result.error('background_task_stop_failed', err.message, err.code);
        });
    } catch (err) {
      this.running = false;
      const error = err as BusinessError;
      result.error('background_task_stop_failed', error.message, error.code);
    }
  }

  static register(flutterEngine: FlutterEngine, context: common.UIAbilityContext): void {
    flutterEngine.getPlugins()?.add(new LynaiBackgroundService(context));
  }
}
