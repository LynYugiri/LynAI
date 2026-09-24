/*
 * LynAI 鸿蒙系统语音识别插件。
 *
 * 工程里的「系统语音识别」走 `speech_to_text`（Android/iOS/Windows），它没有鸿蒙
 * 实现；鸿蒙侧改用系统基础语音服务（Core Speech Kit 的 speechRecognizer）：
 * 识别模型在设备侧离线运行，`recognitionMode: 0` 由系统负责录音（需要
 * ohos.permission.MICROPHONE，已在 module.json5 声明），应用只需处理结果回调。
 *
 * 通道约定（`lynai/speech`，双向）：
 * - Dart → 原生：
 *   start({ language })  开始识别；language 形如 'zh-CN'
 *   stop()               结束输入并等待最终结果（对应长按结束）
 *   cancel()             取消本次识别
 * - 原生 → Dart（同一通道回推）：
 *   onPartial({ text })  当前累计文本（已确认句 + 正在识别的临时句）
 *   onComplete({ text }) 会话结束时的累计文本
 *   onError({ message }) 识别失败
 *
 * 设备不支持时 start 返回 { ok: false, error }，Dart 侧按既有的「语音功能初始化
 * 失败」提示处理；这与其它平台 initialize() 失败的表现一致。
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
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { appendSentence, normalizeLanguage } from './SpeechTextUtils';

const CHANNEL_NAME: string = 'lynai/speech';
/** 短语音模式允许的最大音频时长（毫秒，系统上限 60000）。 */
const MAX_AUDIO_DURATION: number = 60000;

/** 回推事件的结果接收器：Dart 侧未监听时静默忽略（不回错误也不重试）。 */
class LynaiSpeechResultSink implements MethodResult {
  success(result?: Object): void {}

  error(code: string, message: string, details?: Object): void {}

  notImplemented(): void {}
}

function resultMap(ok: boolean, error?: string): Map<string, Object> {
  const map = new Map<string, Object>();
  map.set('ok', ok);
  if (error !== undefined) {
    map.set('error', error);
  }
  return map;
}

export class LynaiSpeech implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private engine: speechRecognizer.SpeechRecognitionEngine | null = null;
  private sessionId: string = '';
  /** 已确认句（isFinal=true 的句子）。 */
  private confirmed: string = '';
  /** 正在识别的临时句，会被后续中间结果覆盖。 */
  private partial: string = '';

  getUniqueClassName(): string {
    return 'LynaiSpeech';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.releaseEngine();
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'start':
        this.start(call, result);
        break;
      case 'stop':
        this.stop(result);
        break;
      case 'cancel':
        this.cancel(result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private start(call: MethodCall, result: MethodResult): void {
    if (!canIUse('SystemCapability.AI.SpeechRecognizer')) {
      result.success(resultMap(false, '当前设备不支持系统语音识别'));
      return;
    }
    const rawLanguage = call.argument('language') as string | null;
    const language = normalizeLanguage(rawLanguage === null ? '' : rawLanguage);
    this.ensureEngine(language)
      .then(() => {
        this.beginListening(result);
      })
      .catch((err: BusinessError) => {
        result.success(resultMap(false, `语音识别引擎初始化失败: ${err.message}`));
      });
  }

  /** 创建（或复用）识别引擎。引擎可跨会话复用，避免每次长按都重新初始化。 */
  private async ensureEngine(language: string): Promise<void> {
    if (this.engine !== null) {
      return;
    }
    const engine = await speechRecognizer.createEngine({
      language: language,
      // 当前公开能力为设备侧离线模型（online=1），失败时不做「在线兜底」。
      online: 1,
      extraParams: {
        locate: 'CN',
        recognizerMode: 'short',
      },
    });
    engine.setListener({
      onStart: (sessionId: string, eventMessage: string) => {},
      onEvent: (sessionId: string, eventCode: number, eventMessage: string) => {},
      onResult: (sessionId: string, speechResult: speechRecognizer.SpeechRecognitionResult) => {
        if (sessionId !== this.sessionId) {
          return;
        }
        if (speechResult.isFinal) {
          this.confirmed = appendSentence(this.confirmed, speechResult.result);
          this.partial = '';
        } else {
          this.partial = speechResult.result;
        }
        this.emit('onPartial', 'text', this.currentText());
      },
      onComplete: (sessionId: string, eventMessage: string) => {
        if (sessionId !== this.sessionId) {
          return;
        }
        const text = this.currentText();
        this.sessionId = '';
        this.emit('onComplete', 'text', text);
      },
      onError: (sessionId: string, errorCode: number, errorMessage: string) => {
        if (sessionId !== this.sessionId) {
          return;
        }
        this.sessionId = '';
        this.emit('onError', 'message', `识别失败（${errorCode}）: ${errorMessage}`);
      },
    });
    this.engine = engine;
  }

  private beginListening(result: MethodResult): void {
    const engine = this.engine;
    if (engine === null) {
      result.success(resultMap(false, '语音识别引擎不可用'));
      return;
    }
    if (engine.isBusy()) {
      result.success(resultMap(false, '语音识别正在进行中'));
      return;
    }
    this.confirmed = '';
    this.partial = '';
    this.sessionId = `lynai-${Date.now()}`;
    const params: speechRecognizer.StartParams = {
      sessionId: this.sessionId,
      audioInfo: {
        audioType: 'pcm',
        sampleRate: 16000,
        soundChannel: 1,
        sampleBit: 16,
      },
      extraParams: {
        // 0：由系统负责实时录音（应用不写音频流），只需要麦克风权限。
        recognitionMode: 0,
        vadBegin: 5000,
        vadEnd: 800,
        maxAudioDuration: MAX_AUDIO_DURATION,
        recognizerOption: {
          enablePartialResult: true,
        },
      },
    };
    try {
      engine.startListening(params);
      result.success(resultMap(true));
    } catch (err) {
      const error = err as BusinessError;
      this.sessionId = '';
      result.success(resultMap(false, `语音识别启动失败: ${error.message}`));
    }
  }

  private stop(result: MethodResult): void {
    const engine = this.engine;
    if (engine === null || this.sessionId.length === 0) {
      // 没有进行中的会话按幂等成功处理：最终文本通过 onComplete 回推。
      result.success(resultMap(true));
      return;
    }
    try {
      engine.finish(this.sessionId);
      result.success(resultMap(true));
    } catch (err) {
      const error = err as BusinessError;
      result.success(resultMap(false, `结束语音识别失败: ${error.message}`));
    }
  }

  private cancel(result: MethodResult): void {
    const engine = this.engine;
    if (engine === null || this.sessionId.length === 0) {
      result.success(resultMap(true));
      return;
    }
    const sessionId = this.sessionId;
    this.sessionId = '';
    this.confirmed = '';
    this.partial = '';
    try {
      engine.cancel(sessionId);
      result.success(resultMap(true));
    } catch (err) {
      const error = err as BusinessError;
      result.success(resultMap(false, `取消语音识别失败: ${error.message}`));
    }
  }

  private releaseEngine(): void {
    const engine = this.engine;
    this.engine = null;
    this.sessionId = '';
    if (engine !== null) {
      try {
        engine.shutdown();
      } catch (err) {
        // 释放失败不影响后续逻辑。
      }
    }
  }

  private currentText(): string {
    return appendSentence(this.confirmed, this.partial);
  }

  /**
   * 通过同一通道向 Dart 回推事件（Dart 侧用 setMethodCallHandler 接收）。
   *
   * 注意引擎的 MethodChannel.invokeMethod 返回 void（不是 Promise），
   * 因此这里传入回调处理 Dart 侧未监听的情况，而不是 .catch()。
   */
  private emit(method: string, key: string, value: string): void {
    const channel = this.channel;
    if (channel === null) {
      return;
    }
    const payload = new Map<string, Object>();
    payload.set(key, value);
    channel.invokeMethod(method, payload, new LynaiSpeechResultSink());
  }

  static register(flutterEngine: FlutterEngine): void {
    flutterEngine.getPlugins()?.add(new LynaiSpeech());
  }
}
