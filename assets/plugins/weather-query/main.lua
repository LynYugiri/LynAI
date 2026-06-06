-- 天气查询插件入口。
--
-- 本文件定义 plugin.json 中 query_weather 工具对应的 Lua handler。
-- 模型发起 query_weather tool call 后，ToolCallService 会把调用转交给
-- PluginLuaRuntimeService，并执行这里的 query_weather(args)。
--
-- 设计约定：
-- 1. 用户没有指定地点时，查询 wttr.in 的 IP 定位天气。
-- 2. 用户指定 location 时，按城市、地区或地点查询。
-- 3. Lua 负责构造请求、解析响应、裁剪字段，返回适合 AI 总结的结构。
-- 4. Dart 只提供通用能力：http.fetch、lynai.json.decode 和 __lynai_next。

local DEFAULT_LANGUAGE = "zh"
local USER_AGENT = "LynAI Weather Plugin"

-- 去除字符串首尾空白。插件参数来自模型，可能出现空字符串或只有空格的值。
local function trim(value)
  if value == nil then
    return ""
  end
  return tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalize_language(value)
  local language = trim(value)
  if language == "" then
    return DEFAULT_LANGUAGE
  end
  if language == "zh-CN" or language == "zh_CN" then
    return "zh"
  end
  return language
end

-- 按 RFC 3986 对 URL 组件编码。Lua 字符串按字节处理，中文会被转成 UTF-8
-- 百分号编码，避免城市名、空格或特殊符号破坏 wttr.in URL。
local function url_encode(value)
  local text = trim(value)
  local encoded = ""
  for index = 1, string.len(text) do
    local codepoint = string.byte(text, index)
    local is_unreserved =
      (codepoint >= 48 and codepoint <= 57) or
      (codepoint >= 65 and codepoint <= 90) or
      (codepoint >= 97 and codepoint <= 122) or
      codepoint == 45 or codepoint == 46 or codepoint == 95 or codepoint == 126
    if is_unreserved then
      encoded = encoded .. string.char(codepoint)
    elseif codepoint <= 127 then
      encoded = encoded .. string.format("%%%02X", codepoint)
    elseif codepoint <= 2047 then
      encoded = encoded .. string.format(
        "%%%02X%%%02X",
        192 + math.floor(codepoint / 64),
        128 + (codepoint % 64)
      )
    elseif codepoint <= 65535 then
      encoded = encoded .. string.format(
        "%%%02X%%%02X%%%02X",
        224 + math.floor(codepoint / 4096),
        128 + (math.floor(codepoint / 64) % 64),
        128 + (codepoint % 64)
      )
    else
      encoded = encoded .. string.format(
        "%%%02X%%%02X%%%02X%%%02X",
        240 + math.floor(codepoint / 262144),
        128 + (math.floor(codepoint / 4096) % 64),
        128 + (math.floor(codepoint / 64) % 64),
        128 + (codepoint % 64)
      )
    end
  end
  return encoded
end

-- wttr.in 在无路径时会按请求 IP 推断地点；带路径时按指定地点查询。
-- format=j1 返回 JSON，lang 控制天气描述语言。
local function build_weather_url(args)
  local location = trim(args.location)
  local language = normalize_language(args.language)

  local query = "format=j1&lang=" .. url_encode(language)
  if location == "" then
    return "https://wttr.in?" .. query
  end
  return "https://wttr.in/" .. url_encode(location) .. "?" .. query
end

-- 安全读取 wttr.in 数组字段中的第一个 { value = ... }。
-- wttr.in 的 areaName、country、weatherDesc 等字段都是这种数组结构。
local function first_value(list)
  if type(list) ~= "table" then
    return nil
  end
  local first = list[1]
  if type(first) ~= "table" then
    return nil
  end
  return first.value
end

-- query_weather 是暴露给 AI tool call 的入口函数。
--
-- 参数：
-- args.location 可选。城市、地区或地点名称；为空时按 IP 自动定位。
-- args.language 可选。天气描述语言，默认 zh。
--
-- 返回：
-- 第一步返回 __lynai_function = "http.fetch"，由 Dart 执行网络请求；
-- 请求完成后通过 __lynai_next 回到 parse_weather，由 Lua 解析并压缩结果。
function query_weather(args)
  args = args or {}
  return {
    __lynai_function = "http.fetch",
    __lynai_next = "parse_weather",
    args = {
      url = build_weather_url(args),
      method = "GET",
      headers = {
        ["User-Agent"] = USER_AGENT
      }
    }
  }
end

-- parse_weather 接收 http.fetch 的结果，并把 wttr.in 的大 JSON 压缩成模型
-- 容易使用的结构化结果。第三个参数 request_args 是实际发出的 HTTP 参数，
-- 用于把最终请求 URL 一并返回，方便调试和解释数据来源。
function parse_weather(response, original_args, request_args)
  original_args = original_args or {}
  request_args = request_args or {}

  if type(response) ~= "table" or response.ok ~= true then
    return {
      ok = false,
      error = "天气服务请求失败",
      detail = response and response.error or nil
    }
  end

  if tonumber(response.status) ~= 200 then
    return {
      ok = false,
      error = "天气服务返回非 200 状态码",
      status = response.status,
      source = "wttr.in"
    }
  end

  local data, decode_error = lynai.json.decode(response.body or "")
  if type(data) ~= "table" then
    return {
      ok = false,
      error = "天气服务返回内容无法解析",
      detail = decode_error,
      source = "wttr.in"
    }
  end

  local current = data.current_condition and data.current_condition[1] or {}
  local area = data.nearest_area and data.nearest_area[1] or {}

  return {
    ok = true,
    query = trim(original_args.location),
    location = first_value(area.areaName),
    region = first_value(area.region),
    country = first_value(area.country),
    latitude = area.latitude,
    longitude = area.longitude,
    observationTime = current.observation_time,
    temperatureC = current.temp_C,
    feelsLikeC = current.FeelsLikeC,
    condition = first_value(current.weatherDesc),
    humidity = current.humidity,
    windKmph = current.windspeedKmph,
    windDirection = current.winddir16Point,
    pressureMb = current.pressure,
    visibilityKm = current.visibility,
    uvIndex = current.uvIndex,
    source = "wttr.in",
    url = request_args.url
  }
end

-- 测试辅助函数：只构造请求，不发起网络调用。
-- 该函数不在 plugin.json tools 中暴露给模型，仅用于插件维护测试。
function weather_request_for_test(args)
  return {ok = true, url = build_weather_url(args or {})}
end
