package com.github.lynyugiri.lynai

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

class ScheduleWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> refresh(context)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { id ->
            appWidgetManager.updateAppWidget(id, buildViews(context))
        }
    }

    companion object {
        private const val SCHEDULE_KEY = "flutter.schedule_items"
        private val CELL_IDS = intArrayOf(
            R.id.schedule_widget_cell_1,
            R.id.schedule_widget_cell_2,
            R.id.schedule_widget_cell_3,
            R.id.schedule_widget_cell_4,
            R.id.schedule_widget_cell_5,
            R.id.schedule_widget_cell_6,
            R.id.schedule_widget_cell_7,
            R.id.schedule_widget_cell_8,
            R.id.schedule_widget_cell_9,
            R.id.schedule_widget_cell_10,
            R.id.schedule_widget_cell_11,
            R.id.schedule_widget_cell_12,
            R.id.schedule_widget_cell_13,
            R.id.schedule_widget_cell_14,
            R.id.schedule_widget_cell_15,
            R.id.schedule_widget_cell_16,
            R.id.schedule_widget_cell_17,
            R.id.schedule_widget_cell_18,
            R.id.schedule_widget_cell_19,
            R.id.schedule_widget_cell_20,
            R.id.schedule_widget_cell_21,
            R.id.schedule_widget_cell_22,
            R.id.schedule_widget_cell_23,
            R.id.schedule_widget_cell_24,
            R.id.schedule_widget_cell_25,
            R.id.schedule_widget_cell_26,
            R.id.schedule_widget_cell_27,
            R.id.schedule_widget_cell_28,
            R.id.schedule_widget_cell_29,
            R.id.schedule_widget_cell_30,
            R.id.schedule_widget_cell_31,
            R.id.schedule_widget_cell_32,
            R.id.schedule_widget_cell_33,
            R.id.schedule_widget_cell_34,
            R.id.schedule_widget_cell_35,
            R.id.schedule_widget_cell_36,
            R.id.schedule_widget_cell_37,
            R.id.schedule_widget_cell_38,
            R.id.schedule_widget_cell_39,
            R.id.schedule_widget_cell_40,
            R.id.schedule_widget_cell_41,
            R.id.schedule_widget_cell_42
        )
        private val DAY_CELL_IDS = intArrayOf(
            R.id.schedule_widget_day_1,
            R.id.schedule_widget_day_2,
            R.id.schedule_widget_day_3,
            R.id.schedule_widget_day_4,
            R.id.schedule_widget_day_5,
            R.id.schedule_widget_day_6,
            R.id.schedule_widget_day_7,
            R.id.schedule_widget_day_8,
            R.id.schedule_widget_day_9,
            R.id.schedule_widget_day_10,
            R.id.schedule_widget_day_11,
            R.id.schedule_widget_day_12,
            R.id.schedule_widget_day_13,
            R.id.schedule_widget_day_14,
            R.id.schedule_widget_day_15,
            R.id.schedule_widget_day_16,
            R.id.schedule_widget_day_17,
            R.id.schedule_widget_day_18,
            R.id.schedule_widget_day_19,
            R.id.schedule_widget_day_20,
            R.id.schedule_widget_day_21,
            R.id.schedule_widget_day_22,
            R.id.schedule_widget_day_23,
            R.id.schedule_widget_day_24,
            R.id.schedule_widget_day_25,
            R.id.schedule_widget_day_26,
            R.id.schedule_widget_day_27,
            R.id.schedule_widget_day_28,
            R.id.schedule_widget_day_29,
            R.id.schedule_widget_day_30,
            R.id.schedule_widget_day_31,
            R.id.schedule_widget_day_32,
            R.id.schedule_widget_day_33,
            R.id.schedule_widget_day_34,
            R.id.schedule_widget_day_35,
            R.id.schedule_widget_day_36,
            R.id.schedule_widget_day_37,
            R.id.schedule_widget_day_38,
            R.id.schedule_widget_day_39,
            R.id.schedule_widget_day_40,
            R.id.schedule_widget_day_41,
            R.id.schedule_widget_day_42
        )
        private val DOT_IDS = intArrayOf(
            R.id.schedule_widget_dot_1,
            R.id.schedule_widget_dot_2,
            R.id.schedule_widget_dot_3,
            R.id.schedule_widget_dot_4,
            R.id.schedule_widget_dot_5,
            R.id.schedule_widget_dot_6,
            R.id.schedule_widget_dot_7,
            R.id.schedule_widget_dot_8,
            R.id.schedule_widget_dot_9,
            R.id.schedule_widget_dot_10,
            R.id.schedule_widget_dot_11,
            R.id.schedule_widget_dot_12,
            R.id.schedule_widget_dot_13,
            R.id.schedule_widget_dot_14,
            R.id.schedule_widget_dot_15,
            R.id.schedule_widget_dot_16,
            R.id.schedule_widget_dot_17,
            R.id.schedule_widget_dot_18,
            R.id.schedule_widget_dot_19,
            R.id.schedule_widget_dot_20,
            R.id.schedule_widget_dot_21,
            R.id.schedule_widget_dot_22,
            R.id.schedule_widget_dot_23,
            R.id.schedule_widget_dot_24,
            R.id.schedule_widget_dot_25,
            R.id.schedule_widget_dot_26,
            R.id.schedule_widget_dot_27,
            R.id.schedule_widget_dot_28,
            R.id.schedule_widget_dot_29,
            R.id.schedule_widget_dot_30,
            R.id.schedule_widget_dot_31,
            R.id.schedule_widget_dot_32,
            R.id.schedule_widget_dot_33,
            R.id.schedule_widget_dot_34,
            R.id.schedule_widget_dot_35,
            R.id.schedule_widget_dot_36,
            R.id.schedule_widget_dot_37,
            R.id.schedule_widget_dot_38,
            R.id.schedule_widget_dot_39,
            R.id.schedule_widget_dot_40,
            R.id.schedule_widget_dot_41,
            R.id.schedule_widget_dot_42
        )
        private val COUNT_IDS = intArrayOf(
            R.id.schedule_widget_count_1,
            R.id.schedule_widget_count_2,
            R.id.schedule_widget_count_3,
            R.id.schedule_widget_count_4,
            R.id.schedule_widget_count_5,
            R.id.schedule_widget_count_6,
            R.id.schedule_widget_count_7,
            R.id.schedule_widget_count_8,
            R.id.schedule_widget_count_9,
            R.id.schedule_widget_count_10,
            R.id.schedule_widget_count_11,
            R.id.schedule_widget_count_12,
            R.id.schedule_widget_count_13,
            R.id.schedule_widget_count_14,
            R.id.schedule_widget_count_15,
            R.id.schedule_widget_count_16,
            R.id.schedule_widget_count_17,
            R.id.schedule_widget_count_18,
            R.id.schedule_widget_count_19,
            R.id.schedule_widget_count_20,
            R.id.schedule_widget_count_21,
            R.id.schedule_widget_count_22,
            R.id.schedule_widget_count_23,
            R.id.schedule_widget_count_24,
            R.id.schedule_widget_count_25,
            R.id.schedule_widget_count_26,
            R.id.schedule_widget_count_27,
            R.id.schedule_widget_count_28,
            R.id.schedule_widget_count_29,
            R.id.schedule_widget_count_30,
            R.id.schedule_widget_count_31,
            R.id.schedule_widget_count_32,
            R.id.schedule_widget_count_33,
            R.id.schedule_widget_count_34,
            R.id.schedule_widget_count_35,
            R.id.schedule_widget_count_36,
            R.id.schedule_widget_count_37,
            R.id.schedule_widget_count_38,
            R.id.schedule_widget_count_39,
            R.id.schedule_widget_count_40,
            R.id.schedule_widget_count_41,
            R.id.schedule_widget_count_42
        )

        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, ScheduleWidgetProvider::class.java)
            manager.updateAppWidget(component, buildViews(context))
        }

        private fun buildViews(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.schedule_widget)
            val today = Calendar.getInstance()
            val schedules = readSchedules(context)
            val dayCounts = monthDayCounts(schedules, today)
            val nextSchedule = nextScheduleText(schedules, today.time)
            val todayCount = dayCounts[today.get(Calendar.DAY_OF_MONTH)]

            views.setTextViewText(R.id.schedule_widget_day, today.get(Calendar.DAY_OF_MONTH).toString())
            views.setTextViewText(R.id.schedule_widget_month, "${today.get(Calendar.YEAR)}.${today.get(Calendar.MONTH) + 1}")
            views.setTextViewText(R.id.schedule_widget_title, "${today.get(Calendar.YEAR)} 年 ${today.get(Calendar.MONTH) + 1} 月")
            views.setTextViewText(R.id.schedule_widget_weekday, weekdayName(today.get(Calendar.DAY_OF_WEEK)))
            views.setOnClickPendingIntent(R.id.schedule_widget_root, launchIntent(context))
            views.setOnClickPendingIntent(R.id.schedule_widget_next, launchIntent(context))
            views.setTextViewText(
                R.id.schedule_widget_status,
                if (todayCount == 0) "今天无日程" else "今天 ${todayCount} 条"
            )
            views.setTextViewText(R.id.schedule_widget_next, nextSchedule)

            fillCalendar(views, today, dayCounts)
            return views
        }

        private fun fillCalendar(
            views: RemoteViews,
            today: Calendar,
            dayCounts: IntArray
        ) {
            val first = Calendar.getInstance().apply {
                set(Calendar.YEAR, today.get(Calendar.YEAR))
                set(Calendar.MONTH, today.get(Calendar.MONTH))
                set(Calendar.DAY_OF_MONTH, 1)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val daysInMonth = first.getActualMaximum(Calendar.DAY_OF_MONTH)
            val offset = (first.get(Calendar.DAY_OF_WEEK) + 5) % 7
            CELL_IDS.forEachIndexed { index, cellId ->
                val dayId = DAY_CELL_IDS[index]
                val dotId = DOT_IDS[index]
                val countId = COUNT_IDS[index]
                val day = index - offset + 1
                if (day !in 1..daysInMonth) {
                    views.setViewVisibility(cellId, View.INVISIBLE)
                    views.setTextViewText(dayId, "")
                    views.setViewVisibility(dotId, View.GONE)
                    views.setViewVisibility(countId, View.GONE)
                    return@forEachIndexed
                }
                views.setViewVisibility(cellId, View.VISIBLE)
                val isToday = day == today.get(Calendar.DAY_OF_MONTH)
                val count = dayCounts[day]
                views.setTextViewText(dayId, day.toString())
                views.setTextColor(dayId, if (isToday) 0xFFFFFFFF.toInt() else 0xFF0F172A.toInt())
                views.setInt(
                    dayId,
                    "setBackgroundResource",
                    if (isToday) {
                        R.drawable.schedule_widget_day_number_today_bg
                    } else {
                        R.drawable.schedule_widget_day_number_clear_bg
                    }
                )
                views.setViewVisibility(dotId, if (count > 0) View.VISIBLE else View.GONE)
                views.setTextViewText(countId, dayCountText(count))
                views.setViewVisibility(countId, if (count > 0) View.VISIBLE else View.GONE)
                views.setTextColor(countId, if (isToday) 0xFFDBEAFE.toInt() else 0xFF64748B.toInt())
                views.setInt(
                    cellId,
                    "setBackgroundResource",
                    when {
                        isToday -> R.drawable.schedule_widget_day_today_bg
                        count > 0 -> R.drawable.schedule_widget_day_marked_bg
                        else -> R.drawable.schedule_widget_day_clear_bg
                    }
                )
            }
        }

        private fun readSchedules(context: Context): List<ScheduleEntry> {
            val prefsName = "${context.packageName}_preferences"
            val prefs = listOf(
                context.getSharedPreferences(prefsName, Context.MODE_PRIVATE),
                context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            )
            val raw = prefs.firstNotNullOfOrNull { it.getString(SCHEDULE_KEY, null) }
                ?: prefs.firstNotNullOfOrNull { it.getString("schedule_items", null) }
                ?: return emptyList()
            return try {
                val array = JSONArray(raw)
                buildList {
                    for (index in 0 until array.length()) {
                        val item = array.optJSONObject(index) ?: continue
                        val title = item.optString("title").ifBlank { "未命名日程" }
                        val start = parseDate(item.optString("start")) ?: continue
                        val end = parseDate(item.optString("end")) ?: start
                        add(
                            ScheduleEntry(
                                title = title,
                                start = start,
                                end = maxOf(start, end)
                            )
                        )
                    }
                }
            } catch (_: Exception) {
                emptyList()
            }
        }

        private fun parseDate(value: String): Date? {
            if (value.isBlank()) return null
            val normalized = normalizeIsoDate(value)
            val formats = listOf(
                "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
                "yyyy-MM-dd'T'HH:mm:ssXXX",
                "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                "yyyy-MM-dd'T'HH:mm:ss'Z'",
                "yyyy-MM-dd'T'HH:mm:ss.SSS",
                "yyyy-MM-dd'T'HH:mm:ss"
            )
            return formats.firstNotNullOfOrNull { pattern ->
                try {
                    SimpleDateFormat(pattern, Locale.US).parse(normalized)
                } catch (_: Exception) {
                    null
                }
            }
        }

        private fun normalizeIsoDate(value: String): String {
            val dot = value.indexOf('.')
            if (dot == -1) return value
            val suffixStart = (dot + 1 until value.length)
                .firstOrNull { !value[it].isDigit() }
                ?: value.length
            val fraction = value.substring(dot + 1, suffixStart)
            if (fraction.length <= 3) return value
            return value.substring(0, dot + 1) + fraction.take(3) + value.substring(suffixStart)
        }

        private fun dayCountText(count: Int): String = when {
            count <= 0 -> ""
            count > 99 -> "99+"
            else -> count.toString()
        }

        private fun nextScheduleText(items: List<ScheduleEntry>, now: Date): String {
            val next = items
                .asSequence()
                .filter { !it.end.before(now) }
                .sortedWith(compareBy<ScheduleEntry> { it.start }.thenBy { it.end })
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

        private fun launchIntent(context: Context): PendingIntent {
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= 23) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
            return PendingIntent.getActivity(context, 0, intent, flags)
        }

        private fun monthDayCounts(items: List<ScheduleEntry>, month: Calendar): IntArray {
            val monthStart = Calendar.getInstance().apply {
                set(Calendar.YEAR, month.get(Calendar.YEAR))
                set(Calendar.MONTH, month.get(Calendar.MONTH))
                set(Calendar.DAY_OF_MONTH, 1)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val monthEnd = Calendar.getInstance().apply {
                time = monthStart.time
                add(Calendar.MONTH, 1)
            }
            val daysInMonth = monthStart.getActualMaximum(Calendar.DAY_OF_MONTH)
            val counts = IntArray(daysInMonth + 1)
            items.forEach { item ->
                if (!item.start.before(monthEnd.time) || !item.end.after(monthStart.time)) {
                    return@forEach
                }
                val cursor = Calendar.getInstance().apply {
                    time = maxOf(startOfDay(item.start), monthStart.time)
                }
                val end = minOf(item.end, monthEnd.time)
                while (cursor.time.before(end)) {
                    counts[cursor.get(Calendar.DAY_OF_MONTH)] += 1
                    cursor.add(Calendar.DAY_OF_MONTH, 1)
                }
            }
            return counts
        }

        private fun startOfDay(date: Date): Date = Calendar.getInstance().apply {
            time = date
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.time

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

        private fun maxOf(a: Date, b: Date): Date = if (a.after(b)) a else b

        private fun minOf(a: Date, b: Date): Date = if (a.before(b)) a else b

        private fun weekdayName(day: Int): String = when (day) {
            Calendar.MONDAY -> "星期一"
            Calendar.TUESDAY -> "星期二"
            Calendar.WEDNESDAY -> "星期三"
            Calendar.THURSDAY -> "星期四"
            Calendar.FRIDAY -> "星期五"
            Calendar.SATURDAY -> "星期六"
            else -> "星期日"
        }

    }
}

private data class ScheduleEntry(
    val title: String,
    val start: Date,
    val end: Date
)
