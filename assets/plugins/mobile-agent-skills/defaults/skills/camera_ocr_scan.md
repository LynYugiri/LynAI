# 拍照与文档 OCR 扫描

当用户要求拍照、扫描文档、截图后做文字识别（OCR）或图像理解时使用。

## 应用信息

- 系统相机包名 `com.android.camera` 或 `com.sec.android.app.camera`、`com.huawei.camera` 等，视设备而定；找不到时向用户报告。
- 相册/图库 `com.android.gallery3d`、`com.miui.gallery` 等。
- 也可不打开相机 App，直接 `lynai.device.screenshot()` 截当前屏做 OCR。

## 原则

- OCR 优先走 `model.ocr`（文字识别）；需要物体/场景理解走 `model.recognizeFile`。
- 截图结果只作为 OCR/识图输入，回主模型的是结构化文本/描述，不回 base64。
- 文档扫描多页时，按页收集 OCR 结果再拼接，注明页码和置信度。
- 识图置信度低于 `0.6` 时降置信并建议用户复核。
- 一次能完成的"拍照→OCR→拼接"合并为一次 `execute_lua`。

## 分流原则

- 用户说"识别这张图片里的文字/扫描文档"：走 `model.ocr`。
- 用户说"这张图里有什么/是什么东西"：走 `model.recognizeFile`。
- 用户说"拍一下 X"：先打开相机 App 引导拍照，再读取相册最新一张做识别。
- 多页文档：循环拍照或翻页后逐页处理。

## 流程

1. 确定输入来源：
   - 当前屏截图：`lynai.device.screenshot()`。
   - 相册图片：`openApp` 图库后 `screenshot` 当前预览。
   - 相机拍摄：`openApp` 相机，引导拍照，再回相册取最新一张。
2. 调用 `model.ocr` 提取文字，或 `model.recognizeFile` 做场景理解。
3. 按 `model.ocr` 返回的文本块（`textSpans`/`blocks`）拼成行序，保留大致版式。
4. 多页文档循环次数到上限或翻页失败后停止。
5. 结构化结果回主模型，必要时 `agent.memory.update`。

## 常用 Lua

```lua
local function ocr_shot(shot)
  return lynai.call("model.ocr", {
    files = {{ dataBase64 = shot.result.dataBase64, mimeType = shot.result.mimeType, name = "screen.png" }}
  })
end
```

```lua
local function remember(content, details)
  return lynai.call("agent.memory.update", {
    entries = {{ kind = "fact", source = "lua", content = content, details = details }}
  })
end
```

## 返回约定

- 返回 `ok`、`phase`、`pages`（每页 `text`/`blocks`/`confidence`）、`summary`。
- 不返回截图 base64、不返回完整 snapshot。
- 多页时汇总每页置信度和总字数。

错误码：

| 码 | 说明 |
|---|---|
| `ok` | 成功 |
| `element_not_found` | 相机/图库入口不存在 |
| `ocr_failed` | OCR 返回为空或错误 |
| `permission_denied` | 缺少相机/存储/无障碍权限 |
| `user_stopped` | 用户停止任务 |

## 失败处理

- `ocr_failed`：换 `model.recognizeFile` 兜底但仍标低置信；持续失败时返回原始截图描述让主模型判断。
- 相机黑屏/未对焦：等待 1-2 秒再截，连续 3 次失败放弃。

## 一次 Lua 工作流骨架

```lua
local opened = lynai.device.openApp("com.android.camera")
if not opened.ok then return opened end

-- 提示用户拍摄后返回此屏；或自动化点击快门（视设备支持）
lynai.device.sleep(2000)

local shot = lynai.device.screenshot()
if not shot.ok then return shot end

local ocr_result = lynai.call("model.ocr", {
  files = {{ dataBase64 = shot.result.dataBase64, mimeType = shot.result.mimeType, name = "capture.png" }}
})
if not ocr_result.ok then return ocr_result end

return {
  ok = true,
  phase = "camera_ocr_scan",
  pages = {{ text = ocr_result.result.text, confidence = ocr_result.result.confidence or 0.7 }},
  summary = "已拍照并 OCR 提取文本"
}
```

## 禁止行为

- 不自动删除原片。
- 不把截图 base64 返回给模型。