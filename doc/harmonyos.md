# 鸿蒙（HarmonyOS / OpenHarmony）适配

LynAI 支持用 OpenHarmony SIG 的 Flutter SDK 分支构建鸿蒙原生应用（`.hap`）。
本文说明适配方式、依赖策略、构建步骤与各能力的支持状态。

适配的硬性前提是**其它平台行为不变**：默认 `pubspec.yaml`、默认 `pubspec.lock`、
各平台既有代码路径都不因鸿蒙适配而改变；所有鸿蒙差异都收敛在
「平台判定 + 依赖覆盖文件 + `ohos/` 工程」三处。

## 1. 平台判定

`lib/utils/platform_info.dart` 是唯一的平台判定入口：

- 鸿蒙用 `Platform.operatingSystem == 'ohos'` 判断，**不写 `Platform.isOhos`**。
  OpenHarmony SDK 分支给 `dart:io` 增加了 `Platform.isOhos`，但上游 Flutter stable
  没有这个 getter，直接引用会让同一份源码在 Android/iOS/桌面/Web 上无法编译。
- 同理，**不引用 `TargetPlatform.ohos`**。该分支给 `TargetPlatform` 增加了 `ohos`，
  在上游引用它同样编译失败；需要「非 Android/iOS 的移动端」语义时使用
  `isMobilePlatform`，需要「未知平台兜底」时使用 `default` 分支 + `platformDisplayName`。
  枚举 switch 必须保留 `default`/`_` 分支，否则在鸿蒙 SDK 上会因不穷尽而编译失败。

能力开关（同一文件）：

| 开关 | 鸿蒙取值 | 原因 |
|------|----------|------|
| `isMobilePlatform` | true | 触屏、软键盘、图库等移动语义 |
| `isDesktopPlatform` | false | 桌面语义（剪贴板写图片、下载目录） |
| `supportsRichClipboard` | false | `super_clipboard`/`super_native_extensions` 没有鸿蒙实现，且在未知平台直接抛 `UnimplementedError` |
| `supportsMdnsDiscovery` | false | `bonsoir` 没有鸿蒙实现，调用会抛 `MissingPluginException` |
| `supportsQrScanner` | false | 鸿蒙版 `mobile_scanner` 落后于当前 SDK，配对码改走图片导入 |
| `supportsVoiceInput` | true | 系统识别走 Core Speech Kit（`lynai/speech`），配置语音转文字模型时改走录音 + 服务端转写 |

被关闭的能力不会让功能「静默失效」：图片粘贴入口直接不展示（「复制图片」走 `lynai/clipboard`，鸿蒙可用）、
局域网同步给出「请使用配对码手动配对」提示，其余路径保持原样。

## 2. `ohos/` 工程

`ohos/` 是 Stage 模型的鸿蒙工程（由 `flutter create --platforms ohos` 生成后定制）：

| 路径 | 说明 |
|------|------|
| `AppScope/app.json5` | 包名 `com.github.lynyugiri.lynai`；版本号在构建时由 flutter_tools 按 `pubspec.yaml` 覆写 |
| `entry/src/main/module.json5` | 权限声明：INTERNET、网络状态、Wi-Fi 信息、VIBRATE、CAMERA、MICROPHONE、APPROXIMATELY_LOCATION、LOCATION（与 Android 清单对应） |
| `entry/src/main/ets/entryability/EntryAbility.ets` | `FlutterAbility`，注册自动生成的插件与 LynAI 自有通道 |
| `entry/src/main/ets/lynai/LynaiNativeTools.ets` | `lynai/native_tools`：保存图片到图库、读取最近位置 |
| `entry/src/main/ets/lynai/LynaiSecureStorage.ets` | `lynai/secure_storage`：基于 Asset Store Kit 的关键资产读写 |
| `entry/src/main/ets/lynai/LynaiFilePicker.ets` | `lynai/file_picker`：系统文件选择器/图库选择器，替代没有鸿蒙实现的 file_picker 11 |
| `entry/src/main/ets/lynai/LynaiBackgroundService.ets` | `lynai/background_service`：生成期间申请长时任务（continuous task，dataTransfer），等价于 Android 的前台服务 |
| `entry/src/main/ets/lynai/LynaiCalendarPlatform.ets` | `lynai/calendar_platform`：把日历投影转成系统后台代理提醒（reminderAgentManager）+ 通知权限请求 |
| `entry/src/main/ets/lynai/LynaiClipboard.ets` | `lynai/clipboard`：把图片写成系统剪贴板的 PixelMap 记录（只写不读） |
| `entry/src/main/ets/lynai/LynaiBarcode.ets` | `lynai/barcode`：调起系统统一扫码界面（Scan Kit），用于扫描局域网配对码 |
| `entry/src/main/ets/lynai/LynaiSpeech.ets` | `lynai/speech`：系统语音识别（Core Speech Kit，设备侧离线），供长按语音输入使用 |
| `entry/src/main/ets/entryformability/EntryFormAbility.ets` | 服务卡片入口（FormExtensionAbility）：添加/刷新卡片时用 `WidgetPlan` 计算文案 |
| `entry/src/main/ets/widget/pages/WidgetCard.ets` | 卡片 ArkUI 页面（标题行 + 两条后续日程 + 更新时间，点击回到主应用） |
| `entry/src/main/ets/lynai/WidgetStore.ets` | 卡片数据交换：发生记录落盘 + 已添加卡片 id（preferences） |
| `entry/src/main/ets/lynai/WidgetPlan.ts` | 卡片内容规划纯逻辑（与 Android 小组件同一套文案），由 Node 测试覆盖 |
| `entry/src/main/resources/base/profile/form_config.json` | 卡片配置（2*2 / 2*4，`uiSyntax: arkts`，定时刷新） |
| `entry/src/main/ets/lynai/ReminderPlan.ts` | 提醒计划的纯逻辑（时间解析、过滤、排序、上限截断），由 Node 单元测试覆盖 |
| `entry/src/main/ets/lynai/SpeechTextUtils.ts` | 语音文本的纯逻辑（语言标签折算、句子拼接），由 Node 单元测试覆盖 |
| `entry/src/main/ets/lynai/ByteUtils.ts` | 字节视图折算：写文件/解码图片前把 `Uint8Array` 折成精确长度的 `ArrayBuffer`，避免带出多余字节 |
| `AppScope/resources/base/media/app_icon.png`、`entry/src/main/resources/base/media/icon.png` | 应用图标，取自工程 `web/icons/Icon-512.png`（与 Android/iOS 图标一致） |
| `build-profile.json5` | `compatibleSdkVersion`/`targetSdkVersion` 为 HarmonyOS 26.0.0（API 26；换 SDK 时用 `scripts/ohos-sync-sdk-version.sh` 校准） |

已实现的原生能力（与 Android 的 `MainActivity.kt` 对应）：

- **保存图片到图库**：写入应用缓存 → `showAssetsCreationDialog` 弹窗授权
  → 写入媒体库 URI → 清理缓存。鸿蒙把 `ohos.permission.WRITE_IMAGEVIDEO` 列为
  受限开放权限，普通应用不能直接申请，因此走系统弹窗授权；用户会看到一次确认弹窗，
  这是平台差异，不是权限缺失。
- **读取最近位置**：`geoLocationManager.getLastLocation()`，返回字段与 Android
  `readLastLocation()` 对齐（`latitude`/`longitude`/`accuracy`/`provider`/`time`）。
- **关键资产存储**：`asset.add/query/remove`，别名 + 密文由 HUKS 保护，等价于
  Android Keystore / iOS Keychain 的角色；`conflictResolution: OVERWRITE` 保持
  「写入即覆盖」语义，删除不存在的键按幂等成功处理。注意系统对单个关键资产的
  Secret 有 **1-1024 字节**上限（其它平台的 `flutter_secure_storage` 没有等价限制），
  超过时返回 `secure_storage_value_too_large`；因此把可变长 JSON 塞进 `SecretStore`
  的调用方（例如 LAN 配对会话列表与历史 ACK 映射）在鸿蒙上可能写失败，见 §6 已知缺口。
- **生成期间的后台存活**：`backgroundTaskManager.startBackgroundRunning` 申请
  `DATA_TRANSFER` 长时任务（需要 `ohos.permission.KEEP_BACKGROUND_RUNNING`，
  已在 `module.json5` 声明），对应 Android 的前台服务；重复 start / 未 start 就 stop
  都按幂等成功返回，失败只通过 `result.error` 上报，Dart 侧记录日志后继续对话。
  注意官方还要求**在 `abilities[].backgroundModes` 里声明任务类型**（已声明
  `dataTransfer`），两者缺一都会让 `startBackgroundRunning` 失败；
  `DATA_TRANSFER` 另有「进度长时间（首次超过 10 分钟）不更新会被系统取消」的约束，
  因此这里只在单次生成期间持有长时任务，不做后台常驻。
- **选择文件 / 另存为**：`DocumentViewPicker` / `PhotoViewPicker`，选择结果复制进
  应用缓存目录后再交给 Dart（系统 URI 无法用 `dart:io` 直接读取）；缓存副本名带批次
  时间戳与批内序号，同一毫秒内的同名文件不会互相覆盖。用户取消「另存为」返回
  `{ok: true, cancelled: true}`，Dart 侧据此返回 `null`，与其它平台
  `file_picker.saveFile` 的取消语义一致（真正的写入失败仍然抛 `PlatformException`）。
- **复制图片到剪贴板**：把图片字节解码成 `PixelMap` 后以 `MIMETYPE_PIXELMAP`
  记录写入系统剪贴板（鸿蒙**写入剪贴板不需要权限**），系统剪贴板面板与其它应用
  都能识别。反向的「从剪贴板读取图片」需要 `ohos.permission.READ_PASTEBOARD`，
  该权限不向普通应用开放（声明后安装会被系统拒绝），因此鸿蒙上仍不提供粘贴图片，
  相关入口由 `supportsRichClipboard` 关闭；`supportsImageClipboardWrite` 单独表示
  「可写」这一能力，用于控制「复制图片」菜单项。
- **扫码读取配对码**：鸿蒙没有可用的 `mobile_scanner` 适配分支，因此改调系统
  「统一扫码」界面（Scan Kit 的 `scanBarcode.startScanForResult`，`scanTypes:
  [ALL]` + `enableAlbum: true`，自带相机权限与相册入口）。Scan Kit 要求在有 UI 的
  上下文里调用，调用失败时 Dart 侧会自动回退到既有的「导入配对码图片」路径，
  用户取消则不再二次弹窗。
- **桌面服务卡片**：对应 Android 桌面小组件。日历插件在同步投影时把
  `widgetOccurrences` 落盘（`WidgetStore`）：StandardMessageCodec 解出的发生记录是
  ArkTS 的 `Map`，必须先经 `ProjectionRecord.ts` 折算成普通对象——`JSON.stringify`
  对 `Map` 只会得到 `{}`，而 `WidgetPlan` 的属性访问也读不到值，两者都会让卡片永远
  显示「近期无日程」。卡片在添加/刷新时读取并用
  `WidgetPlan` 计算文案（「今天 / 明天 / N 天后 / 进行中 · 标题」，无日程时
  「近期无日程」，与 Android `ScheduleWidgetLogic` 同一套语义）；数据变化后
  日历插件按 preferences 里记录的卡片 id 主动 `formProvider.updateForm` 刷新。
  卡片与主应用分属不同上下文，只通过文件 + preferences 交换数据。
- **系统语音识别**：`speechRecognizer`（Core Speech Kit）在设备侧离线识别，
  `recognitionMode: 0` 由系统实时录音（只需 `ohos.permission.MICROPHONE`），
  应用只处理结果回调：中间结果覆盖临时句、`isFinal` 追加确认句，累计文本经同一
  通道回推给 Dart（`onPartial`/`onComplete`/`onError`）。引擎跨会话复用，页面销毁
  时 `shutdown()`；设备不支持（`canIUse` 判定失败）时与其它平台 `initialize()`
  失败一样提示，不静默降级。语言标签折算与句子拼接是纯逻辑，见 `SpeechTextUtils.ts`。
  会话用独立序号标识：只在开始新会话或页面销毁时失效，因此松手后到达的最终结果
  （Core Speech Kit 的 `onComplete`）仍会回填输入框，与长按说话的用户预期一致。
  Dart 侧 `OhosSpeechBridge` 只在开始识别时安装一个静态通道回调，并把事件派发给
  「当前正在识别」的实例：主聊天页在 `HomePage` 的 `IndexedStack` 里常驻，插件
  AI 工作区还能再开一个聊天页，按实例注册/注销会互相抢通道或把回调摘掉。非鸿蒙
  平台上所有方法都是空操作（内部按平台门控），页面 dispose 不会触发
  `MissingPluginException`。
- **日程提醒投递**：普通应用无法自行安排定时通知，因此把 Dart 生成的日历投影
  （`notificationTriggers`）转成系统**后台代理提醒**：
  `getAllValidReminders()` → 逐条 `cancelReminder()` → 按投影 `publishReminder()`
  重建，保证「投影是唯一权威」且可重入；只取未来触发点，并按系统上限
  （普通应用 30 条）截断到最近的若干条。触发时间优先用 `triggerAtEpochMillis`，
  否则按 `YYYY-MM-DDTHH:mm` 的本地墙上时间解析。时间解析/过滤/排序/截断这些纯逻辑
  抽在 `entry/src/main/ets/lynai/ReminderPlan.ts`，由 Node 单元测试直接覆盖
  （见 §7）。权限方面声明 `ohos.permission.PUBLISH_AGENT_REMINDER`
  （normal / system_grant）；通知开关仍只在用户明确保存提醒时通过
  `requestEnableNotification` 申请，投影同步不弹窗。

Android 专有、鸿蒙未实现的能力：悬浮窗助手、屏幕翻译、无障碍设备控制、
系统长截图、本地 OCR、本地 BlueLM、打开/枚举应用（桌面小组件在鸿蒙侧由服务卡片实现）。这些能力在 Dart 侧原本就按
`Platform.isAndroid` 或 `defaultTargetPlatform == TargetPlatform.android` 门控，
鸿蒙上自动不展示或不执行（日程提醒投递已按上面的方式在鸿蒙实现）。

## 3. 依赖策略

鸿蒙侧的插件依赖全部放在 `pubspec_overrides.ohos.yaml`，默认不生效
（Dart 只读取名为 `pubspec_overrides.yaml` 的文件），因此
Android/iOS/桌面/Web 的依赖图与 `pubspec.lock` 完全保持原样。

`scripts/ohos-pub-get.sh` 负责应用/还原：

```bash
bash scripts/ohos-pub-get.sh            # 备份 pubspec.lock → 应用覆盖 → flutter pub get
bash scripts/ohos-pub-get.sh --restore  # 还原锁文件与默认解析
```

覆盖内容：

| 包 | 鸿蒙来源 | 说明 |
|----|----------|------|
| `path_provider` | `flutter_packages@br_path_provider-v2.1.5_ohos` | 应用私有目录，storage_v2 依赖它 |
| `shared_preferences` | `flutter_packages@oh-3.44.9-dev` | 设置项存储 |
| `package_info_plus` | `package_info_plus-9.0.0-ohos-1.0.0` | 版本号展示 |
| `url_launcher` | `flutter_packages@oh-3.44.9-dev` | 打开链接 |
| `permission_handler` | `flutter_permission_handler@12.0.1-ohos-1.0.0` | 权限请求 |
| `image_picker` | `flutter_packages@oh-3.44.9-dev` | 图片选择与拍照 |
| `share_plus` | `br_share_plus-v12.0.1_ohos` | 系统分享 |
| `record` | `fluttertpc_record@br_3.41_dev` | 录音能力（语音输入另受 `supportsVoiceInput` 门控） |
| `webview_all` | pub.dev `^1.4.1` | 1.4.x 起包内声明 `webview_all_ohos`，插件页/Mermaid/MathLive 内嵌 WebView 可用 |
| `sqlite3` | `SageMik/sqlite3-ohos.dart@sqlite3-2.9.4` | 增加 `PlatformUtils.isOhos → DynamicLibrary.open('libsqlite3.so')` |
| `sqlite3_flutter_libs` | 同上 `sqlite3_flutter_libs-0.5.25-ohos` | ohos 插件通过 ohpm 包 `sqlite3-native-library` 把鸿蒙原生库打进 HAP |
| `drift` | `2.31.0` | 鸿蒙侧 sqlite3 只能停在 2.x（3.x 走 native assets，鸿蒙上会取到 Linux/glibc 库），drift 需同步降到仍依赖 sqlite3 2.x 的版本 |
| `fluent_ui`、`flutter_math_fork` | `build/ohos_deps/`（复制后打补丁） | 见下 |

`fluent_ui` 与 `flutter_math_fork` 的平台 switch 没有穷尽匹配，鸿蒙 SDK 新增
`TargetPlatform.ohos` 后会在编译期报 `non_exhaustive_switch_statement`。
`scripts/ohos-pub-get.sh` 会把它们从 pub 缓存复制到 `build/ohos_deps/`，并应用
`scripts/ohos_patches/fluent_ui.patch` 与 `scripts/ohos_patches/flutter_math_fork.patch`
（只增加 `default`/`_` 分支，对其它平台的运行时行为没有影响）。补丁随上游修复合入后可以删除。

鸿蒙依赖集下的验收口径（与默认依赖集不同）：

- `flutter analyze lib`（生产代码）必须零问题——已实测通过；
- 测试代码（`test/**`）使用 `sqlite3 3.x` 的 `Database.close()` 等 API，
  在鸿蒙依赖集下无法编译，因此 **测试只在默认依赖集下运行**（`scripts/ohos-pub-get.sh --restore`
  之后执行 `flutter test`）。测试代码不会进入 HAP。

## 4. 构建

准备鸿蒙 Flutter SDK（`openharmony-sig/flutter_flutter`，分支 `oh-3.44.9-dev`）
与 DevEco command-line-tools：

```bash
export CLT=$HOME/ohos-dev/command-line-tools          # 解压 commandline-tools-linux-x64-*.zip 得到
export DEVECO_SDK_HOME="$CLT/sdk"
export NODE_HOME="$CLT/tool/node"
export PATH="<flutter_flutter>/bin:$CLT/bin:$CLT/ohpm/bin:$CLT/hvigor/bin:$CLT/tool/node/bin:$PATH"

bash scripts/ohos-doctor.sh     # 先确认工具链齐备（会指出 SDK 版本/API 级别是否够）
bash scripts/ohos-sync-sdk-version.sh   # 按本机 SDK 校准 build-profile.json5 的版本号
bash scripts/ohos-pub-get.sh
bash scripts/ohos-build.sh      # 等价于 flutter build hap --debug --no-codesign
```

`ohos-build.sh` 默认用 PATH 里的 `flutter`；没把鸿蒙 SDK 放进 PATH 时用
`FLUTTER_BIN=/path/to/flutter_flutter/bin/flutter bash scripts/ohos-build.sh`。
脚本会先校验用的是不是鸿蒙 Flutter SDK（官方 stable 没有 `hap` target，直接用会
报与鸿蒙无关的 `Could not find an option named "--debug"`），失败时再按报错的
归属（引擎 HAR / 工程自有 ArkTS / 三方依赖）给出结论。

产物在 `build/ohos/hap/entry-default-unsigned.hap`。未签名的 HAP 只能用于
本机调试校验；安装到真机或上架需要华为账号签发证书，此时在 DevEco Studio 中
配置自动签名，并在 `ohos/build-profile.json5` 的 `products[0]` 补回
`"signingConfig": "<配置名>"`。

`ohos/build-profile.json5` 默认使用 HarmonyOS 26.0.0（API 26，点分形式 `"26.0.0"`，
API ≥ 26 不接受 `"26.0.0(26)"` 写法）；`runtimeOS: "HarmonyOS"` 用字符串形式的版本号，
`"OpenHarmony"` 才使用整数 API 号。换用别的 SDK 时用
`bash scripts/ohos-sync-sdk-version.sh` 校准，它会按 API 级别自动选对写法。
产品配置里开启了
`buildOption.strictMode.useNormalizedOHMUrl`——鸿蒙版 sqlite3 的原生库以字节码
HAR 分发，不开这个开关 `GenerateLoaderJson` 会报
`00306046 Specification Limit Violation: Bytecode HARs: [sqlite3-native-library]
not supported when useNormalizedOHMUrl is not true`。

切换 sqlite3 方案（例如从 3.x 的 native assets 换成 2.x 的 ohos 插件）后，必须先删掉
上一轮遗留的 `ohos/entry/libs/**/libsqlite3.so`，否则 `ProcessLibs` 会报
`00306049 ... Duplicated files found in module entry`（native assets 复制进去的
库和插件自带的库同名）。

### 工具链版本要求（实测结论）

| 组件 | 要求 | 依据 |
|------|------|------|
| Flutter SDK | `openharmony-sig/flutter_flutter` 的 `oh-3.44.9-dev`（Flutter 3.44.9 / Dart 3.12.2） | 与工程 `pubspec.yaml` 的 Dart 约束一致 |
| DevEco command-line-tools | **必须是 API ≥ 26 的 HarmonyOS SDK**（HarmonyOS 7 起；5.1.0(18)、6.1.1(24) 都不够），或带系统接口的 Full SDK | 引擎自带 `flutter.har` 的 `module.json` 声明 `compileSdkVersion 6.1.1.125`，其 ArkTS 源码使用 `autoFillManager.AutoFillType`、`KeyEvent.isCapsLockOn`、`CompetitionStrategy` 等较新 API：5.1.0(18) 编译报 32 处可定位错误（28 引擎 + 4 `record_ohos`），6.1.1(24) 只剩 14 处且全在引擎的 `OhosAutoFillHelper.ets`——这些自动填充接口在公开 SDK 里到 API 26 才从系统接口转为公开（见下表） |
| node / ohpm / hvigor | 随 command-line-tools 提供 | 26.0.0 版 CLT：ohpm 26.0.0.630、hvigor 6.26.8、node v24.14.1（5.1.0 版为 ohpm 5.1.3 / hvigor 5.18.5；6.1.1 版为 ohpm 6.1.2.268 / hvigor 6.24.2） |
| JDK | 17 或更高（官方文档推荐 17，实测 21 可用） | hvigor 打包阶段 |

用 API ≥ 26 的 SDK 时 `flutter build hap` 已经能完整跑通（Dart kernel/AOT →
`CompileArkTS` → 打包），产物见 §8；用 5.x/6.x 的 SDK 时会在 Dart 侧通过后、
停在 `CompileArkTS` 阶段报引擎 HAR 的 API 缺失。两种情况都说明
**工程自身的 Dart/ArkTS 代码不是构建阻塞点**。

`ohos-build.sh` 失败时会做这份归属统计（按去重后的 `At File` 路径分类），
所以下面这组数字可以随时用一条命令复核（下表是 5.1.0(18) 的结果，6.1.1(24)
的结果是引擎 14 / 工程 0 / 依赖 0，26.0.0(26) 则是 0 报错、构建成功）：

```bash
CLT=... FLUTTER_BIN=<flutter_flutter>/bin/flutter bash scripts/ohos-build.sh --debug
#   引擎自带 HAR（@ohos/flutter_ohos）：28 处
#   工程自有 ArkTS（ohos/）：0 处
#   三方依赖（pub-cache 里的鸿蒙适配插件，如 record_ohos）：4 处
#   其它：0 处
```

注：引擎 HAR 与三方插件都经软链接落在 `ohos/**/oh_modules/` 下，脚本会先排除
`oh_modules/` 与 `.pub-cache/` 再统计工程自有代码，否则引擎报错会被误算成
「工程自有 ArkTS 错误」。

### 公开 SDK 与引擎要求的差距（实测）

四套公开 SDK 都实测过，报错数逐级下降，直到 API 26 完全编过：

| SDK | API | `flutter build hap` 的 ArkTS 报错 | 结论 |
|-----|-----|-----------------------------------|------|
| HarmonyOS 5.1.0（CLT 5.1.0.840） | 18 | 引擎 28 / 工程 0 / 依赖 4（`record_ohos`），`ERROR:33` | 差得最多，`KeyEvent`、`window`、`AudioSessionManager`、`autoFillManager` 全线缺失 |
| HarmonyOS 6.1.1（CLT 6.1.1.280） | 24 | 引擎 **14** / 工程 0 / 依赖 **0**，`ERROR:15` | 只剩 `OhosAutoFillHelper.ets` 一个文件报错 |
| OpenHarmony 6.1.0.31（`os/6.1-Release`） | 23 | 不适用 | 是 OpenHarmony SDK，不带 `hmscore`，且同样缺自动填充接口 |
| **HarmonyOS 26.0.0（CLT 26.0.0.851）** | **26** | **0（构建成功）** | 产出 `build/ohos/hap/entry-default-unsigned.hap` |

6.1.1(24) 下剩余的 14 处全部落在引擎的
`plugin/editing/OhosAutoFillHelper.ets`，都是 `autoFillManager` 的自动填充接口
（`AutoFillType`、`ViewData`、`FillRequest`、`SaveRequest`、`FillFailureResult`、
`AutoFillTriggerType`、`AutoFillCallback`、`requestAutoFill`）。原因在上游 SDK
声明里写得很清楚（`interface_sdk-js` 的
`api/@ohos.app.ability.autoFillManager.d.ts`）：

- `ViewData`、`PageNodeInfo` 等标着 `@systemapi [since 11 - 24]`——**API ≤ 24 时它们是系统接口**，
  公开 SDK 会把 `@systemapi` 声明裁掉，所以 `.d.ts` 里只剩 `requestAutoSave`；
- `requestAutoFill`、`AutoFillCallback`、`SaveRequest` 等标着 `@since 26.0.0 dynamic&static`——
  **API 26（HarmonyOS 26.0.0 / 7）才转为公开接口**。

引擎自身也有对应的运行时短路：`OhosAutoFillHelper.ets` 导出
`AUTOFILL_SUPPORT_API = 26`，`FlutterPage.ets` / `TextInputPlugin.ets` / `FlutterView.ets`
都用 `deviceInfo.sdkApiVersion < AUTOFILL_SUPPORT_API` 跳过调用。也就是说
**设备 API < 26 时这些代码根本不会执行**，缺的只是编译期声明。

因此有两条可行路线：

1. 用 **API ≥ 26 的 HarmonyOS command-line-tools / DevEco Studio**（已实测通过）——推荐；
2. 用带系统接口的 **Full SDK**（同一份 6.1.1 也能编过，因为系统接口在 Full SDK 里没被裁掉）。

顺带一提：OpenHarmony 6.1.0.31 那套（`repo.huaweicloud.com/harmonyos/os/6.1-Release/`，
sha256 与镜像的 `.sha256` 一致）虽然补上了 `isCapsLockOn`、`getGlobalWindowMode`、
`isInFreeWindowMode`、`getAvailableDevices` 等符号，但**不能替代 HarmonyOS SDK**：
它是 OpenHarmony 的 API 集合，不带 `hmscore`，而本工程的扫码（Scan Kit）与语音识别
（Core Speech Kit）依赖 HMS 套件；它的 `autoFillManager` 同样没有上述接口。

### SDK 版本号的两种写法（API 26 分界）

hvigor 从 **API 26** 起改用「点分」版本号，`ohos-sync-sdk-version.sh` 会按本机 SDK
自动选对写法，手改时不要写错：

| API | 写法 | 依据 |
|-----|------|------|
| < 26 | `"5.1.0(18)"`、`"6.1.1(24)"`（版本 + 括号里的 API 级别） | hvigor `API_VERSION_PATTERN` |
| ≥ 26 | `"26.0.0"`（点分形式，**不能**写 `"26.0.0(26)"`） | hvigor `FIRST_DOT_API_VERSION = 26` + `DOT_API_VERSION_PATTERN`；写成带括号的形式会报 `00308018 api version parameter is illegal! Expected format: <major>[.<minor>][.<patch>]` |

### 手工解压 command-line-tools 的坑

CLT 的 zip 里有 **符号链接**（`tool/node/bin/npm`、`npx`、`corepack`，以及 SDK 里
LLVM 的 `clang`、`clang++`、`ld.lld` 等，26.0.0 版共 128 个）。Python 的
`zipfile.extractall()` 不还原符号链接，会把它们写成「内容是目标路径的普通文件」，
于是 hvigor 在 `Installing pnpm@...` 阶段报
`.../tool/node/bin/npm: 1: ../lib/node_modules/npm/bin/npm-cli.js: not found`
（`00308002 Operation Error`），原生编译阶段也会找不到 `clang`。
解压后需要按 zip 里记录的链接目标重建：

```python
import os, stat, zipfile
with zipfile.ZipFile(zip_path) as z:
    for info in z.infolist():
        if stat.S_ISLNK(info.external_attr >> 16):
            path = os.path.join(dest, info.filename)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            if os.path.islink(path) or os.path.exists(path):
                os.remove(path)
            os.symlink(z.read(info).decode(), path)
```

### 只做代码校验时的最小环境

`flutter pub get` / `flutter analyze` 只需要「能定位到鸿蒙 SDK」，并不会调用 hvigor，
而 `HmosSdk` 的目录校验只要求 `<dir>/hmscore` 与 `<dir>/openharmony` 存在。
因此不装 DevEco 也能跑鸿蒙依赖集下的静态检查：

```bash
mkdir -p /tmp/ohos-sdk-stub/{hmscore,openharmony}
export DEVECO_SDK_HOME=/tmp/ohos-sdk-stub
bash scripts/ohos-pub-get.sh
flutter analyze --no-pub lib
```

鸿蒙静态分析改为本地执行（不再占用 CI）：上面这种方式不需要下载真实 SDK，也不产出 HAP。

### 签名与安装（三条路线）

`flutter build hap --no-codesign` 产出的是未签名包，装到设备前必须签名。三条路线的能力边界
完全不同，别混用：

| 路线 | 做法 | 能装到哪 |
|------|------|----------|
| **本地自签名**（OpenHarmony 演示证书链） | `CLT=/path/to/command-line-tools bash scripts/ohos-sign-local.sh` | 信任 OpenHarmony 根证书的设备/模拟器（一般要开发者模式 + `hdc install`）；**装不到零售 HarmonyOS 手机** |
| **华为调试证书 + 调试 Profile** | 见下方步骤（需要华为账号；Profile 绑定设备 UDID） | 名单内设备的 `hdc install`——真机调试的唯一途径 |
| **华为发布证书 + 发布 Profile** | AGC 申请发布证书与发布 Profile（不绑定设备） | 只能经 AppGallery 分发；**本地 `hdc install` 会报 `INSTALL_FAILED_APP_SOURCE_NOT_TRUSTED`**，官方口径是「AGC 发布的证书不支持本地安装，只能用于上架」 |

#### 本地自签名（`scripts/ohos-sign-local.sh`）

不需要华为账号，材料全部来自 SDK 的 `sdk/default/openharmony/toolchains/lib/`：

- `OpenHarmony.p12`：演示密钥库，口令 `123456`（公开演示口令，见脚本里的 `KEYSTORE_PWD`）；
  应用签名私钥别名 `openharmony application release`，Profile 签名私钥别名
  `openharmony application profile release`；
- `UnsgnedReleasedProfileTemplate.json`：Profile 模板，其 `bundle-info.distribution-certificate`
  就是应用签名证书（脚本会核对它与密钥库里私钥的 bundleName/公钥一致）；
- `OpenHarmonyProfileRelease.pem`：Profile 证书链。注意 SDK 里是 **root 开头**，
  而 `hap-sign-tool` 要求 **leaf → CA → root**，脚本会重排（应用证书链同理）。

脚本做的事：导出 CA/根证书 → 拼证书链 → 按本工程 bundleName 生成 Profile（新 uuid，
有效期到 2049-12-31，`type: release` 不绑定设备）→ `sign-profile` → `sign-app`
→ `verify-app`。产物：

```
build/ohos/hap/entry-default-signed.hap     已签名 HAP
build/ohos/sign-local/                      中间产物与三份日志（sign-profile/sign-app/verify-app）
```

两点实现细节，排障时有用：

- 签名数据写在第 N 个 zip 条目之后、中央目录之前（26.0.0 版 `hap-sign-tool` 的格式），
  因此**不要**再去找旧版的尾部 `Hap Signature Block` 标记——签名后文件尾部仍是
  zip 的中央目录与 EOCD，直接看 EOCD 是自洽的；
- 每次执行都会重新生成 Profile（uuid/有效期不同），所以签名包的 sha256 每次都不一样；
  要固定哈希就把脚本里的 uuid/validity 改成常量。

#### 华为调试证书（手动申请，不需要 DevEco Studio 图形界面）

1. 生成密钥库与 CSR（本仓库当前已生成一份，放在被 `.gitignore` 忽略的 `ohos/signature/`）：

   ```bash
   keytool -genkeypair -alias lynai -keyalg EC -groupname secp256r1 -sigalg SHA256withECDSA \
     -keystore lynai.p12 -storetype PKCS12 -storepass '<密码>' -keypass '<密码>' \
     -validity 9125 -dname "CN=LynAI, OU=LynAI, O=LynAI, C=CN"
   keytool -certreq -alias lynai -keystore lynai.p12 -storetype PKCS12 \
     -storepass '<密码>' -keypass '<密码>' -sigalg SHA256withECDSA -file lynai.csr
   ```

   必须是 EC（`secp256r1`）+ `SHA256withECDSA`，这也是 DevEco「Generate Key and CSR」的算法。
2. AGC → 创建应用（**包名必须等于 `AppScope/app.json5` 里的 `com.github.lynyugiri.lynai`**）
   → 证书 → 新增 → 类型选**调试证书** → 上传 `lynai.csr` → 下载 `.cer`。
3. 取设备 UDID 并在 AGC 登记：`hdc shell bm get --udid`
   （`hdc` 在 `<clt>/sdk/default/openharmony/toolchains/`），AGC → 设备 → 添加设备。
4. AGC → Profile → 新增 → 类型**调试** → 选证书 + 勾选设备 + 填包名 → 下载 `.p7b`。
5. 签名（把材料换成华为签发的那三件）：

   ```bash
   java -jar <clt>/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar sign-app \
     -mode localSign -keyAlias lynai -keyPwd '<密码>' \
     -appCertFile lynai.cer -profileFile lynai.p7b \
     -inFile build/ohos/hap/entry-default-unsigned.hap \
     -outFile build/ohos/hap/entry-default-signed.hap \
     -signAlg SHA256withECDSA -keystoreFile lynai.p12 -keystorePwd '<密码>' \
     -compatibleVersion 26
   ```

   在 DevEco Studio 里则是把这五要素填进 `File > Project Structure > Signing Configs`，
   它会写回 `ohos/build-profile.json5` 的 `signingConfigs` 与 `products[0].signingConfig`。
6. 安装：`hdc install -r build/ohos/hap/entry-default-signed.hap`。

注意：

- 调试 Profile 只对登记过的 UDID 生效，换设备要重新登记并**重新下载 Profile**；
- 覆盖安装要求签名一致（同一份 `.p12`），换签名前先卸载旧包；
- 本工程没有 ACL 受限权限（`WRITE_IMAGEVIDEO` / `WRITE_CONTACTS` / `READ_PASTEBOARD`），
  普通调试证书即可，不需要在 AGC 申请 ACL 白名单；
- 发布证书签名的包**不能**用 `hdc install` 本地安装，这是华为的限制，不是工程配置问题。

## 5. 支持状态

| 能力 | 鸿蒙状态 |
|------|----------|
| 对话、模型配置、Markdown/LaTeX/Mermaid、代码高亮 | 可用 |
| 构建产物（未签名 HAP） | 可用：`bash scripts/ohos-build.sh [--debug|--release]` 在 HarmonyOS 26.0.0(26) SDK 下产出 `build/ohos/hap/entry-default-unsigned.hap`（debug 189 MB / release 55.8 MB，release 含 AOT `libapp.so`） |
| 本地自签名（OpenHarmony 证书链） | 可用：`bash scripts/ohos-sign-local.sh` 产出 `entry-default-signed.hap`，`verify-app` 校验通过；只能装到信任 OpenHarmony 根证书的设备/模拟器 |
| 华为调试证书签名（装机调试） | 待设备：`ohos/signature/` 已备好 EC `lynai.p12` + `lynai.csr`；在 AGC 申请调试证书并登记设备 UDID 后即可签名安装（步骤见 §4「签名与安装」） |
| storage_v2（Drift + 鸿蒙原生 sqlite3） | 依赖已闭环（见 §3 的 sqlite3 覆盖），原生库随 HAP 分发 |
| API key / 凭据 | 可用，走关键资产库 |
| 知识库、笔记、随记、待办、日程 | 可用 |
| 备份/恢复、云同步、局域网同步 | 可用；局域网设备发现需手动配对码 |
| 长图导出、图片保存到图库 | 可用（保存时会有一次系统授权弹窗） |
| 图片选择、拍照、分享、打开链接 | 可用 |
| 选择文件 / 另存为 | 可用，走 `lynai/file_picker` 通道（系统文件选择器与图库选择器） |
| 生成期间保持后台运行 | 可用，走 `lynai/background_service` 通道申请长时任务（dataTransfer） |
| 日程/待办/纪念日提醒 | 可用，投影转成系统后台代理提醒（最多 30 条，超出按最近优先） |
| 应用内 WebView（插件功能页、Mermaid、MathLive） | 可用 |
| 语音输入（系统识别） | 可用，走 Core Speech Kit 离线识别；配置语音转文字模型时改为录音 + 服务端转写 |
| 扫码配对 | 可用，调起系统统一扫码界面（Scan Kit）；不可用时自动回退到导入配对码图片 |
| 复制图片到剪贴板 | 可用（`lynai/clipboard` 写入 PixelMap 记录） |
| 从剪贴板粘贴图片 | 暂不可用：读取剪贴板需要受限权限 `READ_PASTEBOARD`，普通应用无法申请 |
| 悬浮窗助手、屏幕翻译、设备控制、系统长截图、本地 OCR/BlueLM | 暂不可用（Android 专有，Dart 侧已按平台门控不展示） |
| 桌面小组件 | 可用：鸿蒙服务卡片（2*2 / 2*4），显示最近与后续日程 |

## 6. 已知缺口

1. **真机回归**：未签名 HAP 已经能产出（`build/ohos/hap/entry-default-unsigned.hap`，
   见 §8 的验证记录），但本机没有鸿蒙设备/模拟器，因此装机后的实际行为尚未验证；
   首轮真机清单见 §9.4。构建侧的要求是 **API ≥ 26 的 HarmonyOS SDK**
   （HarmonyOS 26.0.0 / 7 起，或带系统接口的 Full SDK），原因见 §4
   「公开 SDK 与引擎要求的差距」。
2. **华为调试证书**：本地自签名已经跑通（OpenHarmony 证书链，`scripts/ohos-sign-local.sh`），
   但那套证书装不到零售 HarmonyOS 手机；要在真机上安装，需要 AGC 签发的**调试证书 +
   绑定设备 UDID 的调试 Profile**（发布证书不行——它不支持本地安装）。密钥库与 CSR
   已经生成好放在 `ohos/signature/`（该目录已 gitignore），只等一台设备来取 UDID。
3. **sqlite3 / drift 的版本策略**：鸿蒙侧固定在 `sqlite3 2.9.4` + `drift 2.31.0`，
   与其它平台的 `sqlite3 3.x` + `drift 2.34` 不同。已实测生产代码在鸿蒙依赖集下
   零分析问题，但测试代码使用 `sqlite3 3.x` 的 API，只在默认依赖集下运行。
   升级 sqlite3 3.x 的鸿蒙适配分支可用后，应把两侧版本重新对齐。
4. **file_picker**：社区鸿蒙分支是 `file_picker 12.x`，与工程当前使用的
   `11.x` API 不兼容，因此鸿蒙改走自有 `lynai/file_picker` 通道
   （`ohos/entry/src/main/ets/lynai/LynaiFilePicker.ets` +
   `lib/utils/ohos_file_picker.dart`）：选择结果先复制进应用缓存目录再交给 Dart，
   保证 `dart:io` 可直接读取；另存为在写入用户所选位置的同时留一份沙箱副本，
   使返回值与其它平台的 `file_picker` 语义一致。其它平台仍走 file_picker。
5. **语音输入**：系统识别已走 Core Speech Kit（`lynai/speech`）；
   「录音 + 服务端转写」这条路径依赖 `record` 的鸿蒙适配
   （`fluttertpc_record@br_3.41_dev`，其 ArkTS 同样需要 6.1 SDK 才能编译通过），
   真机上需要一并回归。
6. **关键资产的 1024 字节上限**：Asset Store Kit 限制单条 Secret 为 1-1024 字节，
   超过时写入失败（Dart 侧收到 `PlatformException`）。`SecretStore` 的多数调用方
   只存 API key 与短 token，但 LAN 相关路径会把 JSON 写进 `SecretStore`
   （`lan_peer_repository.dart` 的配对会话列表与历史 ACK 映射、
   `lan_tls_certificate_service.dart` 的自签证书 PEM：EC P-256 自签证书约 0.6-1 KB，
   已接近上限）。真机回归时必须验证局域网同步的配对与证书写入；若确认超限，
   应把这些值改成按别名分片存储或移出 `SecretStore`（历史 ACK 已有
   `migrateLegacyTransportState` 迁到 storage_v2 的路径）。
7. 上述补丁与覆盖分支都是社区维护的适配分支，需在真机上回归后再进入发布流程。

## 7. 回归要求

- 任何鸿蒙相关改动都必须同时满足：默认依赖集下的 `flutter analyze` + `flutter test`
  （上游 Flutter stable），以及鸿蒙依赖集下的 `flutter analyze lib`。
- `scripts/ohos-pub-get.sh --restore` 之后 `pubspec.lock` 必须与改动前一致。
- 平台判定与能力开关改动需同步更新本文件与 `README.md` 的平台表。

配套的自动化测试（都在默认依赖集下运行，不需要鸿蒙 SDK）：

| 测试 | 覆盖内容 |
|------|----------|
| `test/platform_info_test.dart` | 平台判定与能力开关在非鸿蒙平台上的取值 |
| `test/ohos_file_picker_test.dart` | `lynai/file_picker` 通道的解析、取消、失败语义 |
| `test/ohos_secret_store_test.dart` | `lynai/secure_storage` 通道的方法名、参数与失败语义 |
| `test/ohos_clipboard_test.dart` | `lynai/clipboard` 写入通道的参数、失败透传，以及「可写不可读」的能力边界 |
| `test/ohos_barcode_test.dart` | `lynai/barcode` 扫描通道：成功、用户取消、失败回退语义与扫码能力开关 |
| `test/ohos_speech_test.dart` | `lynai/speech` 双向通道：start 语言参数与失败语义、onPartial/onComplete/onError 回推、dispose 后不再回调 |
| `test/ohos_channel_contract_test.dart` | Dart 侧通道与 ArkTS 实现的对应关系：新增通道必须同时在鸿蒙实现或列入 Android 专有清单，ArkTS 不允许出现孤儿通道，通道方法名与 Dart 调用一致 |
| `test/calendar_platform_bridge_test.dart` | 日历平台桥：桌面平台 no-op，移动端发送完整投影且权限请求单独发送 |
| `test/generation_background_service_test.dart` | 后台存活服务：非移动平台 no-op，Android 发送 start/stop |
| `test/ohos_project_structure_test.dart` | 鸿蒙工程结构：清单引用的源文件/资源/profile 都存在，权限声明成对，卡片配置完整且默认尺寸在支持列表内，每个 `Lynai*` 插件都已注册，鸿蒙包名与 Android applicationId 一致 |

ArkTS 侧的纯逻辑（不依赖任何鸿蒙 API 的部分）放在 `.ts` 模块里，用 Node 直接跑源码：

```bash
bash scripts/ohos-arkts-tests/run.sh   # 需要 Node >= 22.6
```

该脚本暂未纳入 GitHub Actions（发布前本地手动执行一次）。脚本按文件列表调用 `node --test`，Node 22 与 23+ 都能跑；`--test <目录>` 在 Node 22 会被当成模块加载并报 `MODULE_NOT_FOUND`，不要再改回目录写法。

| 测试 | 覆盖内容 |
|------|----------|
| `scripts/ohos-arkts-tests/reminder_plan.test.mjs` | `ReminderPlan.ts`（日程提醒计划）：本地墙上时间解析与非法输入、epoch 优先级、过去触发点过滤、升序排列、标题/正文兜底、30 条上限截断、不修改入参 |
| `scripts/ohos-arkts-tests/byte_utils.test.mjs` | `ByteUtils.ts`（字节视图折算）：完整视图复用底层 buffer、子视图只取自己那一段、空视图、折算结果是副本 |
| `scripts/ohos-arkts-tests/speech_text_utils.test.mjs` | `SpeechTextUtils.ts`（语音文本）：语言标签折算（中文变体、英文、空值）与句子拼接去空白 |
| `scripts/ohos-arkts-tests/widget_plan.test.mjs` | `WidgetPlan.ts`（服务卡片）：起止时间推导（epoch/endAtLocal/缺省）、自然日差、文案分档、过滤已结束与已完成、行数上限 |
| `scripts/ohos-arkts-tests/picker_path_utils.test.mjs` | `PickerPathUtils.ts`（选择器 URI）：沙箱路径与 `file://` URI 取文件名、忽略 query/fragment、百分号解码、恶意与畸形输入、缓存文件名兜底 |
| `scripts/ohos-arkts-tests/projection_record.test.mjs` | `ProjectionRecord.ts`（投影字段折算）：真实 `Map` 与普通对象两种解码形态、字段白名单、`null` 键省略、JSON 序列化后字段完整 |
| `scripts/ohos-arkts-tests/sys_cap_utils.test.mjs` | `SysCapUtils.ts`（系统能力探测）：常量与 SDK 注解一致、probe 缺失/抛异常/空能力名一律按不支持、全部可用才放行、不可用时短路 |

## 8. 本次适配的验证记录

| 验证项 | 命令 | 结果 |
|--------|------|------|
| 现有平台静态检查 | `flutter analyze`（Flutter 3.44.1 stable） | No issues found |
| 现有平台回归测试 | `flutter test`（Flutter 3.44.1 stable） | All tests passed（1507 个用例，含鸿蒙相关测试文件） |
| 默认依赖解析未被污染 | `git diff pubspec.lock` | 无差异（`scripts/ohos-pub-get.sh --restore` 后） |
| 鸿蒙依赖集生产代码检查 | 鸿蒙 SDK（3.44.9-ohos）+ OHOS 覆盖依赖 `flutter analyze lib` | No issues found（真实 CLT 与占位 SDK 两种环境下都通过） |
| 鸿蒙 Dart 编译 | `flutter build hap --debug --no-codesign` 的 Dart kernel 阶段 | 通过（0 个 Dart 错误） |
| 鸿蒙 release 编译 | `flutter build hap --release --no-codesign` 的 Dart AOT 阶段 | 通过（0 个 Dart 错误；失败点同样是引擎 HAR 的 ArkTS 编译） |
| 鸿蒙插件依赖接入 | 同上 hvigor 阶段 | image_picker_ohos、path_provider_ohos、permission_handler_ohos、record_ohos、share_plus、shared_preferences_ohos、sqlite3_flutter_libs、url_launcher_ohos、webview_all_ohos、package_info_plus 全部编译进构建；ohpm 拉取 `sqlite3-native-library-3.53.4.har` |
| 鸿蒙 ArkTS 编译 | 同上 `CompileArkTS` 阶段 | 工程自有 ArkTS（`LynaiNativeTools`/`LynaiSecureStorage`/`LynaiFilePicker`/`LynaiBackgroundService`/`LynaiCalendarPlatform`/`LynaiClipboard`/`LynaiBarcode`/`LynaiSpeech`/`EntryFormAbility`/`WidgetCard` 与六个 `.ts` 模块）零错误；可定位的 32 个错误全部来自引擎 `flutter.har`（28）与 `record_ohos`（4）的 6.x API 缺失，hvigor 汇总 `ERROR:33 WARN:518`（多出的 1 处无 `At File` 行） |
| ArkTS 纯逻辑单测 | `bash scripts/ohos-arkts-tests/run.sh`（Node 直跑 `.ts` 源码） | 39 个用例全部通过（含能力探测兜底 9 个） |
| ArkTS 报错归属诊断 | `CLT=... FLUTTER_BIN=... bash scripts/ohos-build.sh --debug` | 输出「引擎 28 / 工程 0 / 依赖 4 / 其它 0」并给出 6.1 SDK 结论（脚本会先排除 `oh_modules/`、`.pub-cache/` 再统计工程自有代码） |
| 结构测试非空转 | 临时删掉 `LynaiBarcode.ets` 的 `SysCapUtils` 守卫、临时重命名 `SysCapUtils.ts` 的常量 | 对应测试如预期失败；按 md5 还原后重新通过（说明新增断言真的在校验约定，而不是恒真） |
| 公开 OpenHarmony 6.1 SDK 能否顶替 | 下载 `os/6.1-Release/ohos-sdk-windows_linux-public.tar.gz`，校验 sha256 后解出 `ets` 逐符号对照 | 不能：6.1.0.31(API 23) 补上了 `isCapsLockOn`/`getGlobalWindowMode`/`getAvailableDevices` 等，但仍缺 `autoFillManager` 的 8 个成员、`CompetitionStrategy`、`DialogSubWindowApi`（详见 §4） |
| 工具链自检 | `bash scripts/ohos-doctor.sh` | 正确识别版本与 API 级别：5.1.0(18) → 1 项阻塞（版本不够）；6.1.1(24) → 1 项阻塞（API < 26 缺自动填充声明）；26.0.0(26) → **0 项阻塞** |
| SDK 版本校准 | `bash scripts/ohos-sync-sdk-version.sh` | 自动按 API 分界选写法：5.1.0→`5.1.0(18)`、6.1.1→`6.1.1(24)`、26.0.0→`26.0.0`（点分）；重复执行不再改动（幂等） |
| HarmonyOS 6.1.1 SDK 下的构建 | 下载并解压 CLT 6.1.1.280（HarmonyOS SDK 6.1.1.125 / API 24，zip 完整性校验通过），`FLUTTER_BIN=... CLT=... bash scripts/ohos-build.sh --debug` | ArkTS 报错 33 → **15**：工程自有 0 处、`record_ohos` 0 处，剩余 14 处全在引擎 `OhosAutoFillHelper.ets`（API ≤ 24 的系统接口）；Dart kernel 与 11 个鸿蒙插件 HAR 均编译通过 |
| 手工解压 CLT 的符号链接 | 解压 CLT 26.0.0.851（114,666 条目）后首次构建 | hvigor 在 `Installing pnpm@10.28.2` 阶段报 `tool/node/bin/npm: ../lib/node_modules/npm/bin/npm-cli.js: not found`（`00308002`）；按 zip 记录的链接目标重建 128 个符号链接后 pnpm 安装成功（详见 §4） |
| **HarmonyOS 26.0.0 SDK 下的 debug 构建** | `FLUTTER_BIN=... CLT=<clt-26.0.0> bash scripts/ohos-build.sh --debug` | **构建成功**：`✓ Built build/ohos/hap/entry-default-unsigned.hap`（189,303,626 字节，112 个条目）；ArkTS 0 报错，`ets/modules.abc` 2.07 MB、`ets/widgets.abc` 13.9 KB（服务卡片）、`libs/arm64-v8a/libflutter.so` 39.5 MB、`libsqlite3.so`（arm64 + x86_64）、96 个 `resources/rawfile/flutter_assets/*` |
| **HarmonyOS 26.0.0 SDK 下的 release 构建** | `FLUTTER_BIN=... CLT=<clt-26.0.0> bash scripts/ohos-build.sh --release` | **构建成功**：`✓ Built build/ohos/hap/entry-default-unsigned.hap (55.8MB)`（55,849,039 字节，109 个条目）；Dart AOT 产物 `libs/arm64-v8a/libapp.so` 22.7 MB、release 引擎 `libflutter.so` 17.0 MB、`libsqlite3.so`（arm64 + x86_64）、`ets/modules.abc` 1.19 MB；`pack.info` 里 `mainAbility EntryAbility`、`deviceType [phone, tablet, 2in1]`、服务卡片 `lynai_schedule` 均在 |
| HAP 元数据核对 | 解出 debug 与 release 两个 HAP 的 `module.json` 逐字段检查 | 两者一致：`bundleName com.github.lynyugiri.lynai`（与 Android applicationId 一致）、`versionName 4.2.0`（与 pubspec 一致）、`minAPIVersion/targetAPIVersion 260000026`、`compileSdkVersion 26.0.0.105 / compileSdkType HarmonyOS`、`deviceTypes [phone, tablet, 2in1]`、`mainElement EntryAbility`、`virtualMachine ark24.0.0.0`、10 项 `requestPermissions` 与 `module.json5` 一致、`EntryAbility.backgroundModes ["dataTransfer"]`、`EntryFormAbility`（form）都在 |
| 产物指纹 | `sha256sum build/ohos/hap/entry-default-unsigned.hap` | release 包 55,849,039 字节，`32fdbc9eef452bfce3d775a7ba30c034bf66dcb1b45173699ed229958673be92`（产物在 `build/` 下，不入库） |
| 本地自签名 | `CLT=<clt-26.0.0> bash scripts/ohos-sign-local.sh` | 成功：`build/ohos/hap/entry-default-signed.hap` 56,266,422 字节（未签名 55,849,039 + 签名数据 371,339 + 新增 `.pages.info` 条目与 CD 增长）；`verify-app` 报 `Digest verify result: true` / `verify permission sign success` / `Verify success`，导出的 Profile `verifiedPassed=true`、`bundle-name=com.github.lynyugiri.lynai`、`type=release`、无 `debug-info`（不绑定设备） |
| AGC 调试证书材料 | `keytool -genkeypair`（EC secp256r1 + SHA256withECDSA）+ `keytool -certreq` | 生成 `ohos/signature/lynai.p12`（别名 `lynai`，有效期到 2051）与 `lynai.csr`（openssl 校验：`prime256v1` / `ecdsa-with-SHA256`，正是 HarmonyOS 签名要求）；`ohos/signature/` 已加入 `.gitignore` |
| 发布证书能否本地安装 | 官方 FAQ 与问题说明 | 不能：`hdc install` 发布签名包报 `INSTALL_FAILED_APP_SOURCE_NOT_TRUSTED`，「AGC 发布的证书不支持本地安装，只能用于上架」 |
| 自动填充接口的公开版本 | 上游 `interface_sdk-js` 的 `@ohos.app.ability.autoFillManager.d.ts` 注解 | `ViewData`/`PageNodeInfo` 等为 `@systemapi [since 11 - 24]`，`requestAutoFill`/`AutoFillCallback` 为 `@since 26.0.0`——即 API 26 起才公开；引擎侧有 `AUTOFILL_SUPPORT_API = 26` 的运行时短路 |
| API 26 的版本号写法 | hvigor `sdkmanager-common` 的 `FIRST_DOT_API_VERSION = 26` 与 `DOT_API_VERSION_PATTERN` | API ≥ 26 只接受点分形式；`26.0.0(26)` 会被拒（`00308018 api version parameter is illegal`），改成 `26.0.0` 后构建继续 |
| CI 门槛 | 无（鸿蒙静态分析 workflow 已移除，见下） | 鸿蒙相关的分析与单测都由本地按本文档手动执行，不进入 GitHub Actions |

构建侧已经没有未完成项。剩下的是**真机回归**：本机没有鸿蒙设备/模拟器，
装机后的实际行为（关键资产库、图库保存、系统扫码、语音识别、长时任务、
代理提醒、服务卡片等）还没在设备上验证过，清单见 §9.4。

### 逐 API 复核（无法真机验证时的替代手段）

由于本机没有真机，鸿蒙侧的原生实现无法运行时验证，因此对每个用到的
鸿蒙 API 都对照 SDK 的 `.d.ts` 与官方文档做了复核，并据此修掉了四个只会在设备上
暴露的问题：

| 问题 | 复核依据 | 修复 |
|------|----------|------|
| `LynaiSecureStorage` 把 `NOT_FOUND` 当成 24000001 | SDK `asset.ErrorCode` 实际是 `NOT_FOUND = 24000002` / `DUPLICATED = 24000003` | 改用 `asset.ErrorCode.NOT_FOUND` 枚举，不再硬编码数字 |
| 长时任务只声明了权限 | 官方《长时任务》要求同时声明 `ohos.permission.KEEP_BACKGROUND_RUNNING` **与** `abilities[].backgroundModes` | 在 `module.json5` 的 EntryAbility 上补 `"backgroundModes": ["dataTransfer"]`（已对照 SDK 的 `module.json` 校验 schema 与枚举） |
| 直接把 `Uint8Array.buffer` 交给文件/图像 API | 视图可能只是底层 buffer 的一段，会写入多余字节且不报错 | 新增 `ByteUtils.exactBuffer()` 并在三处（图库保存、另存为、剪贴板）使用，配 4 个 Node 用例 |
| 直接调用 syscap 受限 API（长时任务、Scan Kit） | ArkTS 编译器对这两个 API 都给出 `The system capacity of this api '...' is not supported on all devices`；缺能力的设备上调用会抛异常，而异常从 `onMethodCall` 抛出会越过 Dart 侧的回退分支 | 新增 `SysCapUtils.ts`（`sysCapAvailable`/`sysCapsAvailable`，probe 缺失或抛异常都算不支持），扫码与长时任务在调用前先探测，并补 try/catch 保证通道一定有回包 |

其余复核结论：`fileIo.copyFileSync(src: string\|number, dest: string\|number)` 允许
fd/路径混用、`statSync` 接受 fd、`fileSuffixFilters` 支持 `'.pdf'` 形式、
`showAssetsCreationDialog` 签名与 `PhotoCreationConfig` 字段一致、
`pasteboard` 写入无需权限、`PUBLISH_AGENT_REMINDER` 为 normal/system_grant、
普通应用代理提醒上限 30 条。

`pages/Index.ets` 是鸿蒙 Flutter 模板生成的入口页，编译器提示
`LocalStorage.getShared()` 与 `getContext(this)` 已废弃。这里**刻意保留模板写法**：
替代 API（`getUIContext().getSharedLocalStorage()` / `getHostContext()`）与引擎
加载页面的方式（`windowStage.loadContent('pages/Index', storage)` 与
`@LocalStorageLink('viewId')`）耦合，没有真机时替换属于不可验证的改动；废弃 ≠ 移除，
现有写法仍受支持。真机回归确认两者行为一致后再替换。

## 9. 维护手册

### 9.1 新增一个鸿蒙原生通道

1. **Dart 侧桥接**：在 `lib/utils/` 或 `lib/services/` 下新增小类，通道名统一用
   `lynai/<功能>`，用 `isOhosPlatform` 判断是否走鸿蒙实现；把它接进真正的调用点
   （页面/服务），并保证其它平台走原路径不变。
2. **ArkTS 插件**：在 `ohos/entry/src/main/ets/lynai/` 下新增 `Lynai<功能>.ets`，
   实现 `FlutterPlugin, MethodCallHandler`（`getUniqueClassName` /
   `onAttachedToEngine` / `onDetachedFromEngine` / `onMethodCall`），返回值统一用
   `Map<string, Object>`（`{ok, error}`），字节入参先过 `ByteUtils.exactBuffer()`。
3. **注册**：在 `EntryAbility.configureFlutterEngine` 里
   `Lynai<功能>.register(flutterEngine, this.context)`（不需要 context 的传
   `flutterEngine` 即可）。
4. **权限/清单**：需要的 `ohos.permission.*` 写进 `module.json5` 的
   `requestPermissions`（user_grant 还要 `reason` 与 `usedScene`）；长时任务这类
   能力还要在 `abilities[]` 上补对应字段（见 9.3）。
5. **能力探测**：调用被编译器标为 `The system capacity of this api ... is not
   supported on all devices` 的 API 前，先用 `SysCapUtils.ts` 的
   `sysCapAvailable(probe, SYSCAP_*)` 探测（probe 用 `canIUse`），探测不到就返回
   错误结果让 Dart 侧回退；同时给同步抛异常的调用补 try/catch，避免异常从
   `onMethodCall` 抛出导致通道无回包。syscap 字符串以 SDK 的 `.d.ts` 里的
   `@syscap` 注解为准，不要凭记忆写。
6. **纯逻辑外置**：把可离线验证的部分（解析、过滤、排序、命名、能力判定）放进
   `ohos/entry/src/main/ets/lynai/*.ts`，并在
   `scripts/ohos-arkts-tests/` 加 Node 用例——这是当前唯一能自动验证 ArkTS 逻辑的手段。
7. **测试与文档**：在 `test/ohos_channel_contract_test.dart` 的
   `ohosImplementedChannels` 里登记通道名（否则契约测试会失败），补 Dart 侧的
   通道契约测试，并在本文件 §2/§5 更新说明。

### 9.2 升级鸿蒙 Flutter SDK 或引擎

1. 修改工作目录外的 SDK 分支（例如从 `oh-3.44.9-dev` 换到新的 release 分支），
   重新 `bash scripts/ohos-doctor.sh` 确认工具链，并用
   `bash scripts/ohos-sync-sdk-version.sh` 把 `build-profile.json5` 的
   `compatibleSdkVersion`/`targetSdkVersion` 对齐到本机 SDK。
2. 引擎 HAR 的 `compileSdkVersion` 决定所需 DevEco 版本：
   `unzip -p <flutter.sdk>/bin/cache/artifacts/engine/ohos-arm64/flutter.har \
     package/src/main/module.json` 查看 `compileSdkVersion`。
3. 依赖覆盖里的分支（`pubspec_overrides.ohos.yaml`）按新 SDK 版本挑选对应 ref；
   补丁（`scripts/ohos_patches/*.patch`）需要重新确认能否 `patch -p1` 应用——
   `scripts/ohos-pub-get.sh` 会在失败时报出具体包名。
4. 升级后重跑 §7 的全部验证项。

### 9.3 依赖覆盖的坑（都踩过）

- `pubspec_overrides.yaml` **整体替换** `pubspec.yaml` 的 `dependency_overrides`：
  新增覆盖时必须原样保留 `webview_all_linux` / `webview_all_windows` /
  `lua_dardo` 三条本地 vendored 覆盖，否则 `lua_dardo` 会退回上游版本并直接编译失败。
- 该文件**不支持 `hooks` 段**（只支持 `dependency_overrides` / `resolution` /
  `workspace`），所以「只在鸿蒙上改变某个包的构建方式」做不到，只能改版本或改包。
- 字节码 HAR（如 `sqlite3-native-library`）要求产品配置开启
  `buildOption.strictMode.useNormalizedOHMUrl`，否则 `GenerateLoaderJson` 报
  `00306046`。
- 切换 sqlite3 方案后必须删除上一次构建遗留的 `ohos/entry/libs/**/libsqlite3.so`，
  否则 `ProcessLibs` 报 `00306049` 同名 `.so` 冲突。
- 在鸿蒙依赖集下 `test/**` 可能因 `sqlite3 2.x` API 差异无法编译，因此测试只在
  默认依赖集下运行；鸿蒙依赖集的验收口径是 `flutter analyze lib`。

### 9.4 首轮真机清单

构建与签名链路都已跑通（见 §4「签名与安装」和 §8）：`bash scripts/ohos-doctor.sh`
0 项阻塞，`bash scripts/ohos-build.sh --debug|--release` 产出未签名 HAP，
`bash scripts/ohos-sign-local.sh` 产出 OpenHarmony 证书链的签名 HAP。剩余的步骤：

1. **换华为调试签名**（本地自签名装不进零售机）：把 `ohos/signature/lynai.csr` 上传
   AGC 申请调试证书 → 取设备 UDID（`hdc shell bm get --udid`）并在 AGC 登记 →
   建调试 Profile 并绑定该设备 → 下载 `.cer`/`.p7b` 后按 §4 的第 5 步签名。
2. 安装：`hdc install -r build/ohos/hap/entry-default-signed.hap`
   （注意 HAP 的 `minAPIVersion` 是 API 26，设备系统版本需 ≥ 对应版本）。
3. 安装后重点回归：应用启动与本地库（storage_v2）、API key 读写（关键资产库）、
   选择文件/另存为、保存长图到图库（应出现系统授权弹窗）、复制图片到剪贴板、
   日程提醒（保存提醒时应弹通知授权；到点由系统代理提醒弹出）、生成中退后台
   不被冻结、局域网同步（手动配对码）、系统扫码、语音输入。
4. 服务卡片：添加 2*2 与 2*4 卡片，确认显示最近日程；在应用内增删日程后卡片应自动刷新。
5. 把真机结论回写到 §5 的「支持状态」表（当前表里与构建/签名无关的结论都来自
   API 复核，尚未在设备上验证）。
