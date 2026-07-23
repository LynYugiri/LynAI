package com.github.lynyugiri.lynai

import android.content.Context
import org.json.JSONObject
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.util.Date

internal object CalendarProjectionStore {
    private const val PREFS_NAME = "calendar_platform_projection"
    private const val PROJECTION_KEY = "projection"
    private const val CURRENT_VERSION = 2

    fun write(context: Context, projection: Map<*, *>): Boolean {
        // 原生 SharedPreferences 只保存 Dart 完整投影，不再旁路读取 Flutter 领域数据。
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(PROJECTION_KEY, JSONObject(projection).toString())
            .commit()
    }

    fun read(context: Context): CalendarNativeProjection {
        val raw = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(PROJECTION_KEY, null)
            ?: return CalendarNativeProjection.EMPTY
        return parse(raw)
    }

    internal fun parse(raw: String): CalendarNativeProjection {
        return try {
            val root = JSONObject(raw)
            if (root.optInt("version") !in 1..CURRENT_VERSION) {
                return CalendarNativeProjection.EMPTY
            }
            val occurrences = buildList {
                val values = root.optJSONArray("widgetOccurrences") ?: return@buildList
                for (index in 0 until values.length()) {
                    val value = values.optJSONObject(index) ?: continue
                    val date = parseDate(value.optString("date")) ?: continue
                    val endDate = parseDate(value.optString("endDateExclusive")) ?: date.plusDays(1)
                    val endAt = parseDateTime(value.optString("endAtLocal"))
                    add(
                        CalendarWidgetOccurrence(
                            occurrenceId = value.optString("occurrenceId"),
                            title = value.optString("title").ifBlank { "未命名事项" },
                            date = date,
                            startTime = parseTime(value.optString("startTime")),
                            endAt = endAt,
                            startAtMillis = optionalLong(value, "startAtEpochMillis"),
                            endAtMillis = optionalLong(value, "endAtEpochMillis"),
                            endDateExclusive = endDate,
                            isCompleted = value.optBoolean("isCompleted")
                        )
                    )
                }
            }
            val triggers = buildList {
                val values = root.optJSONArray("notificationTriggers") ?: return@buildList
                for (index in 0 until values.length()) {
                    val value = values.optJSONObject(index) ?: continue
                    val triggerId = value.optString("triggerId").ifBlank { continue }
                    val triggerAtMillis = optionalLong(value, "triggerAtEpochMillis")
                    val triggerAt = parseDateTime(value.optString("triggerAtLocal"))
                    if (triggerAtMillis == null && triggerAt == null) continue
                    add(
                        CalendarNotificationTrigger(
                            triggerId = triggerId,
                            sourceType = value.optString("sourceType"),
                            title = value.optString("title").ifBlank { "未命名事项" },
                            note = if (value.isNull("note")) "" else value.optString("note"),
                            triggerAt = triggerAt,
                            absoluteTriggerAtMillis = triggerAtMillis
                        )
                    )
                }
            }
            CalendarNativeProjection(occurrences, triggers)
        } catch (_: Exception) {
            CalendarNativeProjection.EMPTY
        }
    }

    private fun parseDate(value: String): LocalDate? = try {
        LocalDate.parse(value)
    } catch (_: Exception) {
        null
    }

    private fun parseTime(value: String): LocalTime? = try {
        LocalTime.parse(value)
    } catch (_: Exception) {
        null
    }

    private fun parseDateTime(value: String): LocalDateTime? = try {
        LocalDateTime.parse(value)
    } catch (_: Exception) {
        null
    }

    private fun optionalLong(value: JSONObject, key: String): Long? {
        return if (value.isNull(key) || !value.has(key)) null else value.optLong(key)
    }
}

internal data class CalendarNativeProjection(
    val widgetOccurrences: List<CalendarWidgetOccurrence>,
    val notificationTriggers: List<CalendarNotificationTrigger>
) {
    companion object {
        val EMPTY = CalendarNativeProjection(emptyList(), emptyList())
    }
}

internal data class CalendarWidgetOccurrence(
    val occurrenceId: String,
    val title: String,
    val date: LocalDate,
    val startTime: LocalTime?,
    val endAt: LocalDateTime?,
    val startAtMillis: Long?,
    val endAtMillis: Long?,
    val endDateExclusive: LocalDate,
    val isCompleted: Boolean
) {
    val start: Date
        get() = startAtMillis?.let(::Date) ?: Date.from(
            date.atTime(startTime ?: LocalTime.MIDNIGHT).atZone(ZoneId.systemDefault()).toInstant()
        )

    val end: Date
        get() = endAtMillis?.let(::Date) ?: Date.from(
            (endAt ?: endDateExclusive.atStartOfDay()).atZone(ZoneId.systemDefault()).toInstant()
        )

    val dateSpanEnd: Date
        get() {
            val absoluteEnd = endAtMillis ?: return Date.from(
                endDateExclusive.atStartOfDay(ZoneId.systemDefault()).toInstant()
            )
            val localEnd = java.time.Instant.ofEpochMilli(absoluteEnd).atZone(ZoneId.systemDefault())
            val exclusiveDate = if (localEnd.toLocalTime() == LocalTime.MIDNIGHT) {
                localEnd.toLocalDate()
            } else {
                localEnd.toLocalDate().plusDays(1)
            }
            return Date.from(exclusiveDate.atStartOfDay(ZoneId.systemDefault()).toInstant())
        }
}

internal data class CalendarNotificationTrigger(
    val triggerId: String,
    val sourceType: String,
    val title: String,
    val note: String,
    val triggerAt: LocalDateTime?,
    val absoluteTriggerAtMillis: Long?
) {
    val triggerAtMillis: Long
        get() = absoluteTriggerAtMillis
            ?: triggerAt!!.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
}
