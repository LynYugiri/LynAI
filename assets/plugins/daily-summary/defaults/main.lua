-- 每日总结内置插件入口。
--
-- 本插件只使用 LynAI 已有的标准插件能力：
--   plugin.config.read / notes.list / todos.list / tasks.list / calendar.list
--   model.chat / plugin.storage.set / scheduledTasks.list|create|update
--
-- 定时计划说明：
--   manifest 中声明了兜底任务「每日总结 · 23:00」。用户通过 config.json
--   修改触发时间后，下一次 23:00 兜底任务运行时会创建/更新一个
--   「每日总结（自定义时间）」任务，并从下一次起按配置时间执行。

MANIFEST_TIME = '23:00'
USER_TASK_NAME = '每日总结（自定义时间）'
USER_TASK_SCRIPT =
  'function run(ctx)\n  return run_daily_summary(ctx)\nend'

local SYSTEM_PROMPT = [[你是 LynAI 的每日总结助手。基于用户当天在本机产生的结构化活动数据，写一篇温暖、克制、条理清晰的个人日报。不得编造数据；数据不足时如实说明。输出纯 Markdown，总长 300-800 字。]]

-- ---------------------------------------------------------------------------
-- 基础工具
-- ---------------------------------------------------------------------------

function first_non_empty(value, fallback)
  if value == nil or value == '' then
    return fallback
  end
  return value
end

function date_starts_with(value, prefix)
  return type(value) == 'string' and string.sub(value, 1, 10) == prefix
end

function short_text(value, max_chars)
  if type(value) ~= 'string' then
    return ''
  end
  local text = value:gsub('%s+', ' ')
  if #text <= max_chars then
    return text
  end
  return string.sub(text, 1, max_chars) .. '...'
end

function next_date(date_text)
  local year = tonumber(string.sub(date_text, 1, 4)) or 0
  local month = tonumber(string.sub(date_text, 6, 7)) or 0
  local day = tonumber(string.sub(date_text, 9, 10)) or 0
  local leap = (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
  local days = {31, leap and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
  day = day + 1
  if day > days[month] then
    day = 1
    month = month + 1
    if month > 12 then
      month = 1
      year = year + 1
    end
  end
  return string.format('%04d-%02d-%02d', year, month, day)
end

function system_now()
  local status = lynai.call('system.status', {})
  if type(status) == 'table' and status.ok == true then
    return first_non_empty(status.timestamp, '')
  end
  return ''
end

function today_text()
  local timestamp = system_now()
  if timestamp == '' then
    return '1970-01-01'
  end
  return string.sub(timestamp, 1, 10)
end

-- ---------------------------------------------------------------------------
-- 配置与素材
-- ---------------------------------------------------------------------------

function read_config()
  local result = lynai.call('plugin.config.read', {})
  local values = {}
  if type(result) == 'table' and result.ok == true and type(result.values) == 'table' then
    values = result.values
  end
  return {
    time = first_non_empty(values.time, MANIFEST_TIME),
    model = type(values.model) == 'table' and values.model or {},
  }
end

function collect_material(target_date)
  local next_day = next_date(target_date)
  local material = {
    date = target_date,
    notes = {},
    todo_lists = {},
    tasks = {},
    calendar = {},
  }

  local notes_result = lynai.call('notes.list', {})
  if type(notes_result) == 'table' and notes_result.ok == true then
    for _, note in ipairs(notes_result.notes or {}) do
      if date_starts_with(note.updatedAt, target_date) then
        table.insert(material.notes, {
          title = note.title or '未命名笔记',
        })
      end
      if #material.notes >= 16 then
        break
      end
    end
  end

  local todos_result = lynai.call('todos.list', {includeItems = true})
  if type(todos_result) == 'table' and todos_result.ok == true then
    for _, list in ipairs(todos_result.todoLists or {}) do
      local done_items = {}
      for _, item in ipairs(list.items or {}) do
        if item.done == true then
          table.insert(done_items, item.text or '')
        end
      end
      table.insert(material.todo_lists, {
        title = list.title or '清单',
        done_count = list.doneCount or list.doneItems or 0,
        total_count = list.totalCount or list.totalItems or 0,
        done_items = done_items,
      })
      if #material.todo_lists >= 10 then
        break
      end
    end
  end

  local tasks_result = lynai.call('tasks.list', {})
  if type(tasks_result) == 'table' and tasks_result.ok == true then
    for _, task in ipairs(tasks_result.tasks or {}) do
      local relevant =
        task.plannedDate == target_date or
        task.dueDate == target_date or
        date_starts_with(task.completedAt, target_date) or
        date_starts_with(task.createdAt, target_date)
      if relevant then
        table.insert(material.tasks, {
          title = task.title or '未命名任务',
          done = task.completed == true,
          planned_today = task.plannedDate == target_date,
          due_today = task.dueDate == target_date,
        })
      end
      if #material.tasks >= 30 then
        break
      end
    end
  end

  local calendar_result = lynai.call('calendar.list', {
    from = target_date,
    to = next_day,
  })
  if type(calendar_result) == 'table' and calendar_result.ok == true then
    for _, event in ipairs(calendar_result.events or {}) do
      table.insert(material.calendar, {
        title = event.title or '未命名日程',
        all_day = event.allDay == true,
        start = event.start or event.startDate or '',
        end_time = event['end'] or event.endDateExclusive or '',
      })
      if #material.calendar >= 20 then
        break
      end
    end
  end

  return material
end

function build_user_prompt(material)
  local encoded = lynai.json.encode(material)
  if encoded == nil then
    encoded = '{}'
  end
  return string.format(
    [[日期：%s
素材（JSON）：
%s

要求：
1. 用一句 8-16 字的话作为标题，概括今天；
2. 第一段用 2-3 句话给出整体印象，数据不足时不要堆砌空话；
3. 按以下小节组织：
   # 标题
   ## 今日概览
   ## 高光时刻
   ## 日程与任务
   ## 笔记与思考
   ## 明日建议
4. 引用具体标题与完成事项，不要出现内部 ID；
5. 「明日建议」不超过 3 条，必须能由已有日程/任务推断；
6. 素材里没有对话数据，不要编造对话内容；数据不足的小节写一句诚实说明。]],
    material.date,
    encoded
  )
end

-- ---------------------------------------------------------------------------
-- 生成与保存
-- ---------------------------------------------------------------------------

function request_summary(ctx)
  local material = collect_material(ctx.target_date)
  local now_text = system_now()

  local chat = {
    system = SYSTEM_PROMPT,
    user = build_user_prompt(material),
  }

  local model = ctx.config and ctx.config.model or {}
  local model_label = '跟随当前对话模型'
  if type(model) == 'table' and first_non_empty(model.modelId, '') ~= '' then
    chat.modelId = model.modelId
    chat.modelName = model.modelName
    model_label = first_non_empty(model.modelName, model.modelId)
  end

  local cmd = lynai.model.chat(chat)
  cmd.__lynai_next = 'save_summary_result'
  cmd.args.__ctx = ctx
  cmd.args.__at = now_text
  cmd.args.__model_label = model_label
  return cmd
end

function save_summary_result(result, original_args, call_args)
  if type(result) ~= 'table' or result.ok ~= true then
    local error_text = type(result) == 'table' and result.error or '模型调用失败'
    return {ok = false, error = error_text}
  end
  local ctx = type(call_args) == 'table' and call_args.__ctx or {}
  local date = ctx.target_date or today_text()
  local markdown = result.content or ''
  if markdown == '' then
    return {ok = false, error = '模型没有返回总结内容'}
  end

  return lynai.call('plugin.storage.set', {
    key = 'summary.' .. date,
    value = {
      date = date,
      markdown = markdown,
      model_label = call_args.__model_label or '跟随当前对话模型',
      generated_at = call_args.__at or '',
      source = ctx.mode or 'scheduled',
    },
  })
end

function generate_now(args)
  args = args or {}
  local ctx = {
    target_date = first_non_empty(args.date, today_text()),
    config = read_config(),
    mode = 'manual',
  }
  return request_summary(ctx)
end

-- ---------------------------------------------------------------------------
-- 调度自举：把 config.json 的 time 同步到自定义 user 任务
-- ---------------------------------------------------------------------------

function find_user_task()
  local result = lynai.call('scheduledTasks.list', {})
  if type(result) ~= 'table' or result.ok ~= true then
    return nil
  end
  for _, task in ipairs(result.tasks or {}) do
    if task.name == USER_TASK_NAME then
      return task
    end
  end
  return nil
end

function ensure_schedule_command(ctx)
  local user_task = find_user_task()
  local config_time = ctx.config.time or MANIFEST_TIME

  if config_time == MANIFEST_TIME then
    if user_task ~= nil then
      return lynai.call('scheduledTasks.update', {
        id = user_task.id,
        enabled = false,
      })
    end
    return nil
  end

  if user_task ~= nil then
    if user_task.time ~= config_time or user_task.enabled ~= true then
      return lynai.call('scheduledTasks.update', {
        id = user_task.id,
        time = config_time,
        enabled = true,
      })
    end
    return nil
  end

  return lynai.call('scheduledTasks.create', {
    name = USER_TASK_NAME,
    time = config_time,
    script = USER_TASK_SCRIPT,
  })
end

function after_ensure_schedule(result, original_args, call_args)
  if type(result) == 'table' and result.ok == false then
    return {ok = false, error = result.error or '同步定时计划失败'}
  end
  local ctx = type(call_args) == 'table' and call_args.__ctx or {}
  if call_args.__skip_generation == true then
    return {ok = true, generated = false, reason = 'schedule_configured'}
  end
  return request_summary(ctx)
end

-- ---------------------------------------------------------------------------
-- 用户任务实际执行入口
-- ---------------------------------------------------------------------------

function run_daily_summary(ctx)
  ctx = ctx or {}
  ctx.target_date = first_non_empty(ctx.targetDate, '')
  if ctx.target_date == '' then
    local scheduled_at = first_non_empty(ctx.scheduledAt, '')
    if scheduled_at ~= '' then
      ctx.target_date = string.sub(scheduled_at, 1, 10)
    else
      ctx.target_date = today_text()
    end
  end
  ctx.config = ctx.config or read_config()
  return request_summary(ctx)
end
