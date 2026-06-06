# 天气查询插件

## 用途

天气查询插件是内置 AI tool 插件，用于查询当前网络位置或用户指定地点的实时天气。

用户没有指定地点时，插件请求 `wttr.in` 的默认入口，由服务端按请求 IP 推断位置。用户指定城市、地区或地点时，插件把 `location` 写入 URL 路径，按该地点查询。

## 调用链

模型发起 `query_weather` tool call 后，调用链如下：

```text
模型 tool_call query_weather
-> ToolCallService._executePluginTool
-> PluginLuaRuntimeService.executeTool
-> Lua query_weather(args)
-> LynAI http.fetch
-> Lua parse_weather(response, original_args, request_args)
-> 返回精简天气 JSON
```

## 参数

`location` 可选。城市、地区或地点名称，例如 `北京`、`上海`、`Tokyo`。省略或为空时按当前网络 IP 自动定位。

`language` 可选。天气描述语言，默认 `zh`。

## 返回结构

Lua 会把 `wttr.in` 的大 JSON 裁剪为适合 AI 总结的结构：

```json
{
  "ok": true,
  "query": "北京",
  "location": "Beijing",
  "region": "Beijing",
  "country": "China",
  "temperatureC": "18",
  "feelsLikeC": "17",
  "condition": "Partly cloudy",
  "humidity": "42",
  "windKmph": "11",
  "source": "wttr.in"
}
```

## 权限

插件需要 `network:access`，因为它通过 `http.fetch` 请求外部天气服务。

## 维护注意

天气业务逻辑保留在 Lua 中。Dart 端只提供通用插件运行时能力，例如 `http.fetch`、`lynai.json.decode` 和 `__lynai_next` continuation。

不要新增天气专用 Dart function，例如 `weather.query`。如果需要调整字段裁剪、URL 策略或错误处理，应优先修改 `main.lua`。
