-- manifest 兜底任务脚本：每天 23:00 运行。
--
-- 职责：
-- 1. 若 config.json 的 time 不是 23:00，创建/更新「每日总结（自定义时间）」
--    任务，并把本次运行标记为 schedule_configured（不重复生成）；
-- 2. 若 config.json 的 time 仍是 23:00，则停用自定义任务并生成当天总结。

function run(ctx)
  ctx = ctx or {}
  ctx.config = read_config()
  ctx.mode = ctx.mode or 'scheduled'
  ctx.target_date = ctx.targetDate
  if ctx.target_date == nil or ctx.target_date == '' then
    local scheduled_at = first_non_empty(ctx.scheduledAt, '')
    if scheduled_at ~= '' then
      ctx.target_date = string.sub(scheduled_at, 1, 10)
    else
      ctx.target_date = today_text()
    end
  end

  local ensure = ensure_schedule_command(ctx)
  if ensure ~= nil then
    ensure.__lynai_next = 'after_ensure_schedule'
    ensure.args.__ctx = ctx
    ensure.args.__skip_generation = ctx.config.time ~= MANIFEST_TIME
    return ensure
  end

  if ctx.config.time ~= MANIFEST_TIME then
    return {ok = true, generated = false, reason = 'schedule_configured'}
  end

  return request_summary(ctx)
end
