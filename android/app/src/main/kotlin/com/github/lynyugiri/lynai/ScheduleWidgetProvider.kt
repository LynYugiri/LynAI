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
        private const val MAX_AGENDA_ITEMS = 3

        fun refresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, ScheduleWidgetProvider::class.java)
            manager.updateAppWidget(component, buildViews(context))
        }

        private fun buildViews(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.schedule_widget)
            val today = Calendar.getInstance()
            val schedules = readSchedules(context)
                .sortedWith(compareBy<ScheduleEntry> { it.start }.thenBy { it.end })
            val upcoming = schedules.firstOrNull { sameDay(it.start, today.time) || it.start.after(today.time) }
            val todayItems = schedules
                .filter { occursOn(it, today.time) }
                .take(MAX_AGENDA_ITEMS)

            views.setTextViewText(R.id.schedule_widget_day, today.get(Calendar.DAY_OF_MONTH).toString())
            views.setTextViewText(R.id.schedule_widget_month, "${today.get(Calendar.YEAR)}.${today.get(Calendar.MONTH) + 1}")
            views.setTextViewText(R.id.schedule_widget_title, "${today.get(Calendar.YEAR)} 年 ${today.get(Calendar.MONTH) + 1} 月")
            views.setTextViewText(R.id.schedule_widget_weekday, weekdayName(today.get(Calendar.DAY_OF_WEEK)))
            views.setOnClickPendingIntent(R.id.schedule_widget_root, launchIntent(context))
            views.setTextViewText(
                R.id.schedule_widget_status,
                if (upcoming == null) "暂无待办" else "下一项 ${timeLabel(upcoming.start)}"
            )

            fillCalendar(views, today, schedules)
            fillAgenda(views, todayItems)
            return views
        }

        private fun fillCalendar(
            views: RemoteViews,
            today: Calendar,
            schedules: List<ScheduleEntry>
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
            val markedDays = schedules
                .flatMap { markedDaysInMonth(it, today) }
                .toSet()
            val dayIds = listOf(
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
            dayIds.forEachIndexed { index, viewId ->
                val day = index - offset + 1
                if (day !in 1..daysInMonth) {
                    views.setTextViewText(viewId, "")
                    views.setTextColor(viewId, 0xFF0F172A.toInt())
                    views.setInt(viewId, "setBackgroundResource", R.drawable.schedule_widget_day_clear_bg)
                    return@forEachIndexed
                }
                val isToday = day == today.get(Calendar.DAY_OF_MONTH)
                val hasSchedule = markedDays.contains(day)
                views.setTextViewText(viewId, if (hasSchedule && !isToday) "$day ·" else day.toString())
                views.setTextColor(viewId, if (isToday) 0xFFFFFFFF.toInt() else 0xFF0F172A.toInt())
                views.setInt(
                    viewId,
                    "setBackgroundResource",
                    when {
                        isToday -> R.drawable.schedule_widget_day_today_bg
                        hasSchedule -> R.drawable.schedule_widget_day_marked_bg
                        else -> R.drawable.schedule_widget_day_clear_bg
                    }
                )
            }
        }

        private fun fillAgenda(views: RemoteViews, items: List<ScheduleEntry>) {
            val agendaIds = listOf(
                R.id.schedule_widget_agenda_1,
                R.id.schedule_widget_agenda_2,
                R.id.schedule_widget_agenda_3
            )
            views.setTextViewText(
                R.id.schedule_widget_agenda_title,
                if (items.isEmpty()) "今日日程" else "今日日程 · ${items.size}"
            )
            agendaIds.forEachIndexed { index, viewId ->
                val item = items.getOrNull(index)
                views.setViewVisibility(viewId, if (item == null && index > 0) View.GONE else View.VISIBLE)
                if (item != null) {
                    views.setTextViewText(viewId, "${rangeLabel(item.start, item.end)}  ${item.title.ifBlank { "未命名日程" }}")
                } else if (index == 0) {
                    views.setTextViewText(viewId, "今天没有日程，点击进入应用添加安排")
                }
            }
        }

        private fun readSchedules(context: Context): List<ScheduleEntry> {
            val prefsName = "${context.packageName}_preferences"
            val raw = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .getString(SCHEDULE_KEY, null)
                ?: return emptyList()
            return try {
                val array = JSONArray(raw)
                buildList {
                    for (index in 0 until array.length()) {
                        val item = array.optJSONObject(index) ?: continue
                        val start = parseDate(item.optString("start")) ?: continue
                        val end = parseDate(item.optString("end")) ?: start
                        add(
                            ScheduleEntry(
                                title = item.optString("title"),
                                start = start,
                                end = end,
                                note = item.optString("note").takeIf { it.isNotBlank() }
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
                    SimpleDateFormat(pattern, Locale.US).parse(value)
                } catch (_: Exception) {
                    null
                }
            }
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

        private fun sameDay(date: Date, other: Date): Boolean {
            val a = Calendar.getInstance().apply { time = date }
            val b = Calendar.getInstance().apply { time = other }
            return a.get(Calendar.YEAR) == b.get(Calendar.YEAR) &&
                a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)
        }

        private fun occursOn(item: ScheduleEntry, date: Date): Boolean {
            val dayStart = startOfDay(date)
            val dayEnd = Calendar.getInstance().apply {
                time = dayStart
                add(Calendar.DAY_OF_MONTH, 1)
            }.time
            return item.start.before(dayEnd) && item.end.after(dayStart)
        }

        private fun markedDaysInMonth(item: ScheduleEntry, month: Calendar): List<Int> {
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
            if (!item.start.before(monthEnd.time) || !item.end.after(monthStart.time)) return emptyList()

            val cursor = Calendar.getInstance().apply {
                time = maxOf(startOfDay(item.start), monthStart.time)
            }
            val end = minOf(item.end, monthEnd.time)
            val days = mutableListOf<Int>()
            while (cursor.time.before(end)) {
                days.add(cursor.get(Calendar.DAY_OF_MONTH))
                cursor.add(Calendar.DAY_OF_MONTH, 1)
            }
            return days
        }

        private fun startOfDay(date: Date): Date = Calendar.getInstance().apply {
            time = date
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.time

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

        private fun rangeLabel(start: Date, end: Date): String =
            "${timeLabel(start)}-${timeLabel(end)}"

        private fun timeLabel(date: Date): String =
            SimpleDateFormat("HH:mm", Locale.getDefault()).format(date)
    }
}

private data class ScheduleEntry(
    val title: String,
    val start: Date,
    val end: Date,
    val note: String?
)
