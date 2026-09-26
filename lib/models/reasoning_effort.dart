/// 思考强度（reasoning effort）的取值、顺序与预算映射。
///
/// 取值来自模型目录（models.dev 的 `reasoning_options[].values`），这一层只
/// 定义客户端与后端共用的换算规则：
/// - OpenAI 兼容接口直接透传 `reasoning_effort`；
/// - Anthropic 风格接口把强度换算成 `thinking.budget_tokens`；
/// - `none` 表示显式关闭思考，不下发思考参数。
library;

import 'dart:math' as math;

/// 强度的强弱顺序，用于 UI 排序与夹取。
const List<String> reasoningEffortOrder = [
  'none',
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh',
  'max',
];

/// 显式关闭思考的强度取值。
const String reasoningEffortNone = 'none';

/// 强度 → 思考预算（token）的换算阶梯。
///
/// 只用于 Anthropic 风格接口：它没有 effort 概念，只有 `budget_tokens`。
/// 这些数值是保守的工程取值，不是任何厂商的官方推荐值。
const Map<String, int> reasoningEffortBudgets = {
  'minimal': 1024,
  'low': 2048,
  'medium': 8192,
  'high': 24576,
  'xhigh': 32768,
  'max': 49152,
};

/// 归一化强度取值（小写、去空白）。
String normalizeReasoningEffort(String? value) =>
    (value ?? '').trim().toLowerCase();

/// 该强度是否表示"显式关闭思考"。
bool isReasoningEffortDisabled(String? effort) =>
    normalizeReasoningEffort(effort) == reasoningEffortNone;

/// 把强度换算成思考预算。
///
/// [min] 是目录给出的最小预算；[maxTokens] 是本次请求的 max_tokens（Anthropic
/// 要求预算小于它）。未知强度回退到 [min]（再回退 1024）。
int reasoningBudgetForEffort(
  String effort, {
  int? min,
  required int maxTokens,
}) {
  final base =
      reasoningEffortBudgets[normalizeReasoningEffort(effort)] ?? min ?? 1024;
  final floor = math.max(1, min ?? 1);
  var budget = math.max(base, floor);
  final ceiling = math.max(1, maxTokens - 1);
  if (budget > ceiling) budget = ceiling;
  return budget;
}
