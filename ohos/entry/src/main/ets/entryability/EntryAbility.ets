
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { LynaiNativeTools } from '../lynai/LynaiNativeTools';
import { LynaiSecureStorage } from '../lynai/LynaiSecureStorage';
import { LynaiFilePicker } from '../lynai/LynaiFilePicker';
import { LynaiBackgroundService } from '../lynai/LynaiBackgroundService';
import { LynaiCalendarPlatform } from '../lynai/LynaiCalendarPlatform';
import { LynaiClipboard } from '../lynai/LynaiClipboard';
import { LynaiBarcode } from '../lynai/LynaiBarcode';
import { LynaiSpeech } from '../lynai/LynaiSpeech';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // LynAI 自有的原生通道（Android 侧在 MainActivity.kt 注册）。
    LynaiNativeTools.register(flutterEngine, this.context)
    LynaiSecureStorage.register(flutterEngine)
    LynaiFilePicker.register(flutterEngine, this.context)
    LynaiBackgroundService.register(flutterEngine, this.context)
    LynaiCalendarPlatform.register(flutterEngine, this.context)
    LynaiClipboard.register(flutterEngine)
    LynaiBarcode.register(flutterEngine, this.context)
    LynaiSpeech.register(flutterEngine)
  }
}
