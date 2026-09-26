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

/// 目录只给 `budget_tokens`（预算型，多数 Claude 直连模型）时客户端提供的通用档位。
///
/// 这些档位不是厂商给的取值，而是把"只有预算、没有 effort"的接口用统一的低/中/高
/// 表达出来，再由客户端换算成 `thinking.budget_tokens`；因此只在能忠实换算的配置上
/// 提供（直连 Anthropic，或托管 relay 由后端按上游格式换算）。
const List<String> budgetReasoningEffortLadder = ['low', 'medium', 'high'];

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

/// 档位对应的预算说明（用于 UI 副标题）；没有对应预算时返回 null。
String? reasoningEffortBudgetLabel(String effort) {
  final budget = reasoningEffortBudgets[normalizeReasoningEffort(effort)];
  if (budget == null) return null;
  // 档位是工程取值，展示按 k 取整即可（下发仍是精确值，且会被 max_tokens 夹取）。
  if (budget < 1000) return '思考预算 $budget token';
  return '思考预算约 ${(budget / 1000).round()}k token';
}

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
