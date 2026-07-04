# 解题与问题求解

当用户遇到题目（数学/物理/化学/代码/语言等）需要解答、推导、讲解时使用。本 skill 是"题目→理解→推导→答案→可选沉淀错题本"的端到端流程。

## 适用场景

- 拍题、粘贴题目、口述题目。
- 单题或一组相关题目。
- 需要"先讲思路再给答案"或"直接给答案"由用户明示。

## 原则

- 输入题目时优先通过 `execute_lua` 调 `lynai.call("model.ocr", ...)` 做文本提取；公式/图表/代码可用时要保留原始形式。
- 推导过程用主模型完成；遇到需要分步检查的难题用 `update_plan` 拆解步骤后逐步推进。
- 单步结果写入 `update_agent_memory` 供保持上下文连续。
- 拿不准的环节可通过 `execute_lua` 调 `lynai.call("model.chat", ...)` 做二次校验，置信度低于 `0.6` 时如实标注。
- 答案与思路分离呈现：先答问题、再展开推导；用户问"怎么做"才展开思路。

## 分流原则

- 题目 OCR 失败：让用户口述或粘贴文本兜底，不强行瞎猜。
- 题目不完整/歧义：先问清楚再答，不要基于猜测给答案。
- 多步综合题：先列解题计划（`update_plan`），每完成一步 `update_agent_memory` 一条。
- 用户说"直接给答案"：跳过思路展开，只给最终结果+必要算式。
- 沉淀错题本：用户明确说"记一下这道题"再写笔记（`save_note`），不擅自新建。

## 调用流程

```
1. 输入题目（图片/文本）
   ├── 图片 → execute_lua + lynai.call("model.ocr", ...) 提取题目文本
   └── 文本 → 直接进入第 2 步
2. 拆解（如果是多步综合题）
   └── update_plan 列步骤
3. 推导
   ├── 主模型分步推导
   ├── 单步难判定 → execute_lua + lynai.call("model.chat", ...) 二次校验
   └── 每步结果 → update_agent_memory
4. 给答案
   └── 简短陈述最终答案 + 必要算式
5. 展开思路（仅当用户问"怎么做"或后追问）
6. 沉淀错题本（仅当用户明确要求）
   └── save_note 保存题目+解答+关键思路
```

## 工具调用示例

`execute_lua` + `model.ocr`（拍题识别）：

```json
{
  "name": "execute_lua",
  "arguments": {
    "purpose": "OCR 提取题目文本",
    "code": "local result = lynai.call(\"model.ocr\", { files = {{ dataBase64 = \"<截图 base64>\", mimeType = \"image/png\", name = \"problem.png\" }} }); if not result.ok then return result end; return { ok = true, text = result.result.text, confidence = result.result.confidence or 0.7 }"
  }
}
```

`update_plan`（多步拆解）：

```json
{
  "name": "update_plan",
  "arguments": {
    "items": [
      { "id": "step_1", "status": "in_progress", "summary": "设未知数列方程" },
      { "id": "step_2", "status": "pending", "summary": "求解方程" },
      { "id": "step_3", "status": "pending", "summary": "代入验证" }
    ]
  }
}
```

`save_note`（错题本）：

```json
{
  "name": "save_note",
  "arguments": {
    "title": "错题本-2025-07-04-二元一次方程",
    "content": "## 题目\n...\n## 思路\n...\n## 答案\nx=3, y=4\n## 易错点\n...",
    "folderId": "错题本"
  }
}
```

## 返回约定

- 答案先、推导后；多步题先给最终值再展开。
- 标注每步置信度；低于 `0.6` 的步骤标 `confidence=低` 并说明原因。
- 沉淀成功后返回 `note_id`，方便用户后续管理。

错误码：

| 码 | 说明 |
|---|---|
| `ok` | 成功 |
| `ocr_failed` | OCR 返回为空或乱码 |
| `step_uncertain` | 某步推导置信度低 |
| `save_failed` | 错题本保存失败 |

## 失败处理

- `ocr_failed`：让用户口述或粘贴题目文本。
- `step_uncertain`：标明不明步骤，建议用户重点核对；不直接拿低置信结果继续往下推。
