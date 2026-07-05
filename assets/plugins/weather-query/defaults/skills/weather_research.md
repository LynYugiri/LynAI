# 天气查询工作流

当用户询问天气、温度、下雨、出门、旅行天气、穿衣建议或户外活动安排时使用。

## 流程

1. 判断用户是否指定地点；没有地点时不要追问，直接按当前位置或网络位置查询。
2. 调用 `weather-query__query_weather`，把用户指定的城市、地区或地点传入 `location`。
3. 工具调用成功不等于天气业务成功；必须检查返回的 `phase`、`business_ok`、`temperatureC` 或 `condition`。
4. 只有 `ok=true`、`phase=weather_data_verified`、`business_ok=true` 时，才根据温度、体感温度、天气描述、湿度和风速给出建议。
5. 不要编造天气数据；工具失败或 `business_ok=false` 时说明无法获取实时天气，并询问是否换一个地点重试。

## Phase

成功 phase：

```text
weather_data_verified
```

失败 phase：

```text
weather_request_failed
weather_response_unreadable
weather_data_not_verified
```

## 返回检查

- `action_ok=false` 表示请求动作失败，例如网络错误。
- `action_ok=true` 且 `business_ok=false` 表示请求动作完成，但天气数据不可用或未验证。
- `weather_data_not_verified` 时不要给出穿衣、出行或活动建议，只能说明天气数据缺失。

## 输出

- 先给出天气概况。
- 再给出穿衣、出行或活动建议。
- 如果用户有具体计划，优先围绕计划给建议。
- 在天气数据未验证时，不要把工具调用成功当成实时天气成功。
