package com.github.lynyugiri.lynai

import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

internal object ScheduleWidgetLogic {
    fun nextScheduleText(items: List<CalendarWidgetOccurrence>, now: Date): String {
        val next = items
            .asSequence()
            .filter { it.end.after(now) }
            .sortedWith(compareBy<CalendarWidgetOccurrence> { it.start }.thenBy { it.end })
            .firstOrNull()
            ?: return "近期无日程"
        val prefix = if (next.start.after(now)) {
            val diffDays = calendarDayDiff(now, next.start)
            when {
                diffDays <= 0 -> "今天"
                diffDays == 1 -> "明天"
                diffDays < 7 -> "${diffDays} 天后"
                else -> SimpleDateFormat("M月d日", Locale.CHINA).format(next.start)
            }
        } else {
            "进行中"
        }
        return "$prefix · ${next.title}"
    }

    private fun calendarDayDiff(from: Date, to: Date): Int {
        val start = Calendar.getInstance().apply { time = startOfDay(from) }
        val end = Calendar.getInstance().apply { time = startOfDay(to) }
        var diff = 0
        while (start.before(end)) {
            start.add(Calendar.DAY_OF_MONTH, 1)
            diff += 1
        }
        return diff
    }

    private fun startOfDay(date: Date): Date = Calendar.getInstance().apply {
        time = date
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.time
}
