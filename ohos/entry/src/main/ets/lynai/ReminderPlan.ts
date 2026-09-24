/*
 * 日程提醒的纯逻辑：把 Dart 侧投影里的触发点折算成要发布的代理提醒。
 *
 * 这里刻意不依赖任何 ArkTS/鸿蒙 API，只做时间解析、过滤、排序与截断，
 * 因此可以直接用 Node 的类型剥离（--experimental-strip-types）跑单元测试：
 *   bash scripts/ohos-arkts-tests/run.sh
 * 设备相关的部分（reminderAgentManager 调用）留在 LynaiCalendarPlatform.ets。
 */

/** 投影里的一条通知触发点（只取本模块需要的字段）。 */
export interface ReminderTriggerInput {
  readonly triggerAtEpochMillis?: number;
  readonly triggerAtLocal?: string;
  readonly title?: string;
  readonly note?: string;
}

/** 计划发布的一条代理提醒。 */
export interface PlannedReminder {
  readonly triggerAt: number;
  readonly title: string;
  readonly content: string;
}

/** 普通应用可发布的有效代理提醒上限（系统约束）。 */
export const MAX_REMINDERS: number = 30;

const DEFAULT_TITLE: string = 'LynAI 提醒';

/** `YYYY-MM-DDTHH:mm[:ss]`（本地墙上时间，无时区后缀）。 */
const LOCAL_MINUTE_PATTERN: RegExp =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$/;

/**
 * 把本地墙上时间解析成 epoch 毫秒。
 *
 * 非法或越界的日期返回 null（例如 2 月 30 日会被 Date 滚动到 3 月，这里显式拒绝），
 * 避免把用户没设置的提醒时间静默改成别的时刻。
 */
export function parseLocalMinute(value: string): number | null {
  const match = LOCAL_MINUTE_PATTERN.exec(value);
  if (match === null) {
    return null;
  }
  const year = Number.parseInt(match[1], 10);
  const month = Number.parseInt(match[2], 10);
  const day = Number.parseInt(match[3], 10);
  const hour = Number.parseInt(match[4], 10);
  const minute = Number.parseInt(match[5], 10);
  const second = match[6] === undefined ? 0 : Number.parseInt(match[6], 10);
  if (month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59) {
    return null;
  }
  const date = new Date(year, month - 1, day, hour, minute, second);
  if (
    date.getFullYear() !== year ||
    date.getMonth() !== month - 1 ||
    date.getDate() !== day
  ) {
    return null;
  }
  const time = date.getTime();
  return Number.isNaN(time) ? null : time;
}

/**
 * 触发时间：优先用 Dart 给出的 epoch（UTC 锚定的定时事件），
 * 否则回退到本地墙上时间。
 */
export function triggerTimeOf(trigger: ReminderTriggerInput): number | null {
  const epoch = trigger.triggerAtEpochMillis;
  if (typeof epoch === 'number' && Number.isFinite(epoch)) {
    return epoch;
  }
  const local = trigger.triggerAtLocal;
  if (typeof local !== 'string' || local.length === 0) {
    return null;
  }
  return parseLocalMinute(local);
}

/**
 * 生成要发布的提醒计划：只保留未来触发点，按时间升序，并截断到系统上限
 * （超出部分会在后续同步中随时间推进重新纳入）。
 */
export function planReminders(
  triggers: ReminderTriggerInput[],
  now: number,
  limit: number = MAX_REMINDERS,
): PlannedReminder[] {
  const planned: PlannedReminder[] = [];
  for (const trigger of triggers) {
    const triggerAt = triggerTimeOf(trigger);
    if (triggerAt === null || triggerAt <= now) {
      continue;
    }
    const rawTitle = (trigger.title ?? '').trim();
    const note = (trigger.note ?? '').trim();
    // 标题与正文都不能为空，否则系统通知里会是一片空白。
    const title = rawTitle.length > 0 ? rawTitle : DEFAULT_TITLE;
    planned.push({
      triggerAt: triggerAt,
      title: title,
      content: note.length > 0 ? note : title,
    });
  }
  planned.sort((a: PlannedReminder, b: PlannedReminder) =>
    a.triggerAt - b.triggerAt);
  return limit >= 0 ? planned.slice(0, limit) : planned;
}
