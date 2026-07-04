# 对话沉淀到知识库

当用户希望从当前对话/任务过程中抽出值得长期保存的事实或结论，沉淀进笔记或记忆时使用。本 skill 是被动沉淀，区别于 `note_taking` 的主动新建。

## 适用场景

- 对话中产出有保留价值的事实/结论/数据/计算结果。
- 多轮任务结束后把关键发现收拾成结构化笔记。
- 给主 Agent 做跨会话记忆，下次直接调用。

## 原则

- 只存事实/已验证结论，不存猜测；猜测要显式标 `推测`，并降置信度。
- 一条只存一件事，避免杂糅笔记。
- 既有笔记覆盖范围内的话题走 `edit_note`/`propose_note_edit` 追加；新话题走 `save_note` 草稿。
- 沉淀前先 `read_agent_memory` 看主 Agent 已知什么，不重复写。
- 关键发现同时写 `update_agent_memory`（短时记忆）和笔记（长期知识库）。

## 分流原则

- 用户说"记一下这条/存到笔记"：直接沉淀。
- 用户说"这次聊的整理一下"：列要点 + 给用户确认 + 沉淀综述。
- 主 Agent 自己判断可沉淀：先问用户"是否沉淀进笔记？"再操作，不擅自保存。
- 沉淀目标笔记不确定：`list_notes` 找候选，让用户选。

## 调用流程

```
1. read_agent_memory 看已知
2. 识别可沉淀内容
   └── 事实/结论/数据/计算/引用源
3. 选沉淀位置：
   ├── 已有相关笔记 → propose_note_edit 追加 → 确认 → edit_note 落盘
   └── 无 → save_note 草稿（标记待整理）
4. update_agent_memory 短时记忆一份
5. 返回沉淀位置 + 要点
```

## 工具调用示例

`read_agent_memory`（先读已知）：

```json
{
  "name": "read_agent_memory",
  "arguments": {}
}
```

`propose_note_edit`（追加到既有笔记）：

```json
{
  "name": "propose_note_edit",
  "arguments": {
    "id": "<相关知识库笔记 id>",
    "edits": [
      {
        "startLine": 8,
        "deleteCount": 0,
        "insertLines": ["## 实测数据 - 2025-07-04", "- 指标 A = 12.4", "- 来源：对话内计算"]
      }
    ],
    "baseRevisionId": "<当前 revisionId>"
  }
}
```

`update_agent_memory`（短时记忆）：

```json
{
  "name": "update_agent_memory",
  "arguments": {
    "entries": [
      { "kind": "fact", "source": "conversation", "content": "指标 A 实测 12.4（2025-07-04）" }
    ]
  }
}
```

## 返回约定

- 返回沉淀位置（`noteId` 或新建草稿）+ 已写入要点列表。
- 不直接帮用户定稿长文，只做卡片化整理。

错误码：

| 码 | 说明 |
|---|---|
| `ok` | 成功 |
| `no_valuable_content` | 对话中无可沉淀的稳定事实 |
| `note_not_found` | 目标笔记不存在 |
| `revision_conflict` | 行级乐观锁冲突 |
| `save_failed` | 笔记落盘失败 |

## 失败处理

- `no_valuable_content`：主 Agent 主动告知用户"本次对话暂无明显可沉淀要点"，不强行写空笔记。
- `note_not_found`：让用户选目标笔记列表，或落进新建草稿后再归档。
