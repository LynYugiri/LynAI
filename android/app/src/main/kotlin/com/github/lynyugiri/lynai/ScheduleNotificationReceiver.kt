package com.github.lynyugiri.lynai

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs

class ScheduleNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_NOTIFY -> showNotification(context, intent)
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> reschedule(context)
        }
    }

    private fun showNotification(context: Context, intent: Intent) {
        ensureChannel(context)
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val id = intent.getStringExtra(EXTRA_ID).orEmpty()
        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty().ifBlank { "日程提醒" }
        val note = intent.getStringExtra(EXTRA_NOTE).orEmpty()
        val kind = intent.getStringExtra(EXTRA_KIND).orEmpty()
        val start = intent.getStringExtra(EXTRA_START).orEmpty()
        val content = buildString {
            append(if (kind == "task") "任务开始" else "日程开始")
            if (start.isNotBlank()) append(" · ").append(start)
            if (note.isNotBlank()) append("\n").append(note)
        }
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pendingLaunch = PendingIntent.getActivity(
            context,
            19_000 + abs(id.hashCode() % 10_000),
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(content.lines().firstOrNull().orEmpty())
            .setStyle(NotificationCompat.BigTextStyle().bigText(content))
            .setContentIntent(pendingLaunch)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        NotificationManagerCompat.from(context).notify(abs(id.hashCode()), notification)
    }

    companion object {
        const val ACTION_NOTIFY = "com.github.lynyugiri.lynai.SCHEDULE_NOTIFY"
        private const val CHANNEL_ID = "schedule_notifications"
        private const val CHANNEL_NAME = "日程表提醒"
        private const val SCHEDULE_KEY = "flutter.schedule_items"
        private const val EXTRA_ID = "id"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_NOTE = "note"
        private const val EXTRA_KIND = "kind"
        private const val EXTRA_START = "start"
        private const val NOTIFICATION_PREFS = "schedule_notification_state"
        private const val SCHEDULED_IDS = "scheduled_ids"

        fun reschedule(context: Context): Map<String, Any> {
            ensureChannel(context)
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val entries = readSchedules(context)
            val prefs = context.getSharedPreferences(NOTIFICATION_PREFS, Context.MODE_PRIVATE)
            val previousIds = prefs.getStringSet(SCHEDULED_IDS, emptySet()).orEmpty()
            previousIds.forEach { id ->
                alarmManager.cancel(pendingIntent(context, ScheduleNotificationEntry(id, "", Date(0), "schedule", "")))
            }
            val now = System.currentTimeMillis()
            var scheduled = 0
            val scheduledIds = mutableSetOf<String>()
            entries.filter { it.start.time > now }.forEach { entry ->
                val pendingIntent = pendingIntent(context, entry)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, entry.start.time, pendingIntent)
                } else {
                    alarmManager.set(AlarmManager.RTC_WAKEUP, entry.start.time, pendingIntent)
                }
                scheduledIds.add(entry.id)
                scheduled += 1
            }
            prefs.edit().putStringSet(SCHEDULED_IDS, scheduledIds).apply()
            return mapOf("ok" to true, "scheduled" to scheduled)
        }

        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "日程和任务开始时提醒"
                }
            )
        }

        private fun pendingIntent(context: Context, entry: ScheduleNotificationEntry): PendingIntent {
            val intent = Intent(context, ScheduleNotificationReceiver::class.java).apply {
                action = ACTION_NOTIFY
                putExtra(EXTRA_ID, entry.id)
                putExtra(EXTRA_TITLE, entry.title)
                putExtra(EXTRA_NOTE, entry.note)
                putExtra(EXTRA_KIND, entry.kind)
                putExtra(EXTRA_START, SimpleDateFormat("M月d日 HH:mm", Locale.CHINA).format(entry.start))
            }
            return PendingIntent.getBroadcast(
                context,
                abs(entry.id.hashCode()),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
            )
        }

        private fun readSchedules(context: Context): List<ScheduleNotificationEntry> {
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
                        val id = item.optString("id").ifBlank { continue }
                        val title = item.optString("title").ifBlank { "未命名事项" }
                        val start = parseDate(item.optString("start")) ?: continue
                        add(
                            ScheduleNotificationEntry(
                                id = id,
                                title = title,
                                start = start,
                                kind = item.optString("kind").ifBlank { "schedule" },
                                note = item.optString("note")
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

        private fun immutableFlag(): Int {
            return if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
        }
    }
}

private data class ScheduleNotificationEntry(
    val id: String,
    val title: String,
    val start: Date,
    val kind: String,
    val note: String
)
