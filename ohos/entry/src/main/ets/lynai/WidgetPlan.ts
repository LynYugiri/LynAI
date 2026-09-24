/*
 * 鸿蒙服务卡片的内容规划（纯逻辑）。
 *
 * 与 Android 桌面小组件保持同一套语义（见 ScheduleWidgetLogic.kt /
 * CalendarProjectionStore.kt）：只取「尚未结束」的日程，按开始时间升序，
 * 首条作为标题行，文案按「今天 / 明天 / N 天后 / 进行中」分档，无日程时显示
 * 「近期无日程」。卡片只能接收字符串，因此这里直接产出渲染用文本。
 *
 * 不依赖任何 ArkTS/鸿蒙 API，便于用 Node 单元测试覆盖
 * （scripts/ohos-arkts-tests/）。
 */

/** 投影里的一条日历发生记录（只取本模块需要的字段）。 */
export interface WidgetOccurrenceInput {
  readonly title?: string;
  /** YYYY-MM-DD */
  readonly date?: string;
  /** HH:mm */
  readonly startTime?: string;
  /** YYYY-MM-DDTHH:mm */
  readonly endAtLocal?: string;
  /** YYYY-MM-DD（不含当天） */
  readonly endDateExclusive?: string;
  readonly startAtEpochMillis?: number;
  readonly endAtEpochMillis?: number;
  readonly isCompleted?: boolean;
}

/** 卡片渲染所需的数据（全部为字符串，直接进 formBindingData）。 */
export interface WidgetPlan {
  /** 首个待办行文案；无日程时为「近期无日程」。 */
  readonly headline: string;
  /** 后续若干行文案（已格式化为「时间 · 标题」）。 */
  readonly rows: string[];
  /** 最近一次计算时间 HH:mm。 */
  readonly updatedAt: string;
}

const EMPTY_HEADLINE: string = '近期无日程';
/** 卡片最多再展示两行，避免小组件内容溢出。 */
export const MAX_EXTRA_ROWS: number = 2;

const LOCAL_MINUTE_PATTERN: RegExp =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$/;
const DATE_PATTERN: RegExp = /^(\d{4})-(\d{2})-(\d{2})$/;
const TIME_PATTERN: RegExp = /^(\d{2}):(\d{2})$/;

interface OccurrenceTimes {
  readonly title: string;
  readonly start: number;
  readonly end: number;
}

function parseDateParts(value: string): number[] | null {
  const dateMatch = DATE_PATTERN.exec(value);
  if (dateMatch === null) {
    return null;
  }
  return [
    Number.parseInt(dateMatch[1], 10),
    Number.parseInt(dateMatch[2], 10),
    Number.parseInt(dateMatch[3], 10),
  ];
}

function parseTimeParts(value: string): number[] | null {
  const timeMatch = TIME_PATTERN.exec(value);
  if (timeMatch === null) {
    return null;
  }
  return [Number.parseInt(timeMatch[1], 10), Number.parseInt(timeMatch[2], 10)];
}

function localMillis(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
): number {
  const date = new Date(year, month - 1, day, hour, minute, 0);
  return date.getTime();
}

function parseLocalMinute(value: string): number | null {
  const match = LOCAL_MINUTE_PATTERN.exec(value);
  if (match === null) {
    return null;
  }
  const millis = localMillis(
    Number.parseInt(match[1], 10),
    Number.parseInt(match[2], 10),
    Number.parseInt(match[3], 10),
    Number.parseInt(match[4], 10),
    Number.parseInt(match[5], 10),
  );
  return Number.isNaN(millis) ? null : millis;
}

/**
 * 计算开始/结束时刻，与 Android 侧 `CalendarWidgetOccurrence` 的推导一致：
 * 开始 = startAtEpochMillis ?? 当天 startTime（缺省 00:00）；
 * 结束 = endAtEpochMillis ?? endAtLocal ?? endDateExclusive 的 00:00。
 * 缺少日期时返回 null（该条不参与卡片）。
 */
export function occurrenceTimes(
  input: WidgetOccurrenceInput,
): OccurrenceTimes | null {
  const title = (input.title ?? '').trim();
  const dateParts = parseDateParts((input.date ?? '').trim());
  if (dateParts === null) {
    return null;
  }
  const timeParts = parseTimeParts((input.startTime ?? '').trim()) ?? [0, 0];
  const fallbackStart = localMillis(
    dateParts[0],
    dateParts[1],
    dateParts[2],
    timeParts[0],
    timeParts[1],
  );
  const start =
    typeof input.startAtEpochMillis === 'number' &&
    Number.isFinite(input.startAtEpochMillis)
      ? input.startAtEpochMillis
      : fallbackStart;

  let end: number | null = null;
  if (
    typeof input.endAtEpochMillis === 'number' &&
    Number.isFinite(input.endAtEpochMillis)
  ) {
    end = input.endAtEpochMillis;
  } else if ((input.endAtLocal ?? '').trim().length > 0) {
    end = parseLocalMinute((input.endAtLocal ?? '').trim());
  }
  if (end === null) {
    const endDateParts = parseDateParts((input.endDateExclusive ?? '').trim());
    end =
      endDateParts === null
        ? fallbackStart
        : localMillis(endDateParts[0], endDateParts[1], endDateParts[2], 0, 0);
  }
  return { title: title, start: start, end: end };
}

/** 自然日差值（本地时区），与 Android 的 calendarDayDiff 语义一致。 */
export function dayDiff(fromMillis: number, toMillis: number): number {
  const from = new Date(fromMillis);
  const to = new Date(toMillis);
  const fromDay = localMillis(
    from.getFullYear(),
    from.getMonth() + 1,
    from.getDate(),
    0,
    0,
  );
  const toDay = localMillis(to.getFullYear(), to.getMonth() + 1, to.getDate(), 0, 0);
  return Math.round((toDay - fromDay) / 86400000);
}

/** 文案前缀：进行中 / 今天 / 明天 / N 天后 / M月d日。 */
export function labelPrefix(
  start: number,
  end: number,
  now: number,
): string {
  if (start <= now && end > now) {
    return '进行中';
  }
  const diff = dayDiff(now, start);
  if (diff <= 0) {
    return '今天';
  }
  if (diff === 1) {
    return '明天';
  }
  if (diff < 7) {
    return `${diff} 天后`;
  }
  const date = new Date(start);
  return `${date.getMonth() + 1}月${date.getDate()}日`;
}

function twoDigit(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** 计算卡片内容。`limit` 为附加行上限。 */
export function planWidget(
  occurrences: WidgetOccurrenceInput[],
  now: number,
  limit: number = MAX_EXTRA_ROWS,
): WidgetPlan {
  const updated = new Date(now);
  const updatedAt = `${twoDigit(updated.getHours())}:${twoDigit(updated.getMinutes())}`;
  const upcoming: OccurrenceTimes[] = [];
  for (const occurrence of occurrences) {
    if (occurrence.isCompleted === true) {
      continue;
    }
    const times = occurrenceTimes(occurrence);
    if (times === null || times.end <= now) {
      continue;
    }
    upcoming.push(times);
  }
  upcoming.sort((a: OccurrenceTimes, b: OccurrenceTimes) =>
    a.start === b.start ? a.end - b.end : a.start - b.start);
  if (upcoming.length === 0) {
    return { headline: EMPTY_HEADLINE, rows: [], updatedAt: updatedAt };
  }
  const headline = `${labelPrefix(upcoming[0].start, upcoming[0].end, now)} · ${upcoming[0].title}`;
  const rows: string[] = [];
  const capped = limit < 0 ? upcoming.length : Math.min(limit, upcoming.length - 1);
  for (let index = 1; index <= capped; index++) {
    const item = upcoming[index];
    rows.push(
      `${labelPrefix(item.start, item.end, now)} · ${item.title}`,
    );
  }
  return { headline: headline, rows: rows, updatedAt: updatedAt };
}
