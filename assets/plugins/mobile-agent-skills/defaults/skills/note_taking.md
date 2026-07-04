# 做笔记方法论与操作

当用户要求新建笔记、结构化笔记、选笔记模板（康奈尔/大纲/Zettel）、整理已有笔记时使用。本 skill 覆盖"新建/编辑/归档"全流程。

## 适用场景

- 现记现写：会议、读书、课堂、速记。
- 后续整理：把零散草稿归整到结构化模板。
- 归档整理：选文件夹、改标题、补回链。

## 原则

- 笔记类型识别优先：会议/读书/课堂/速记/复盘，类型决定结构模板。
- 模板可选：康奈尔（线索+笔记+总结）、大纲（多级标题）、Zettel（原子卡片+回链）。
- 改旧笔记优先用 `propose_note_edit`（行级乐观锁），由用户确认后再 `edit_note` 落盘；不直接 `save_note` 覆盖。
- 多页笔记用 `list_note_pages` + `save_note_page`，单页用 `save_note`。
- 文件夹化归档用 `list_note_folders` + `save_note_folder`，避免顶层堆放。
- 没用户授权不擅自改旧笔记内容；只读不改用 `read_note`。

## 分流原则

- 用户说"记一下 X"：默认新建单页笔记，标题用主题+日期。
- 用户说"加到 X 笔记里"：`list_notes` 找目标→`propose_note_edit` 提议追加→用户确认。
- 用户说"做康奈尔笔记"：用三段式模板生成，`save_note` 落盘。
- 用户说"整理某文件夹"：`list_note_folders` 看现状，先列建议让用户确认再批量改。
- 用户说"归档 X"：`save_note_folder` 建文件夹→`edit_note` 改 `folderId`。

## 调用流程

```
1. 判断笔记类型（会议/读书/课堂/速记/复盘）
2. 选模板（康奈尔/大纲/Zettel/无）
3. 落盘工具选：
   ├── 新建单页 → save_note
   ├── 加到旧笔记 → propose_note_edit → 确认 → edit_note
   ├── 多页 → list_note_pages + save_note_page
   └── 归档 → save_note_folder + edit_note(folderId)
4. 返回 note_id / 编辑预览
```

## 工具调用示例

`save_note`（新建康奈尔笔记）：

```json
{
  "name": "save_note",
  "arguments": {
    "title": "会议-周会-2025-07-04",
    "content": "## 线索\n- 议题1\n- 议题2\n## 笔记\n- ...\n## 总结\n- 决议1\n- 决议2\n## 待办\n- [ ] xxx",
    "folderId": "会议记录"
  }
}
```

`propose_note_edit`（向旧笔记提议追加）：

```json
{
  "name": "propose_note_edit",
  "arguments": {
    "id": "<目标 note_id>",
    "edits": [
      {
        "startLine": 12,
        "deleteCount": 0,
        "insertLines": ["## 补充要点 - 2025-07-04", "- 新要点"]
      }
    ],
    "baseRevisionId": "<当前 revisionId>"
  }
}
```

`save_note_folder`（建文件夹）：

```json
{
  "name": "save_note_folder",
  "arguments": {
    "title": "读书笔记"
  }
}
```

## 返回约定

- 新建返回 `noteId` + 标题 + 文件夹。
- 编辑提议返回预览 diff + 待用户确认标记。
- 多页操作返回每页 `pageId` 列表。

错误码：

| 码 | 说明 |
|---|---|
| `ok` | 成功 |
| `note_not_found` | 目标笔记不存在 |
| `revision_conflict` | 行级乐观锁冲突 |
| `folder_not_found` | 目标文件夹不存在 |
| `save_failed` | 笔记落盘失败 |

## 失败处理

- `note_not_found`：用 `list_notes` 列候选笔记让用户选。
- `revision_conflict`：重新 `read_note` 拿最新 `revisionId` 后再提议；不强制覆盖。
