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
import java.text.SimpleDateFormat
import java.util.Locale

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
            append(if (kind.startsWith("task")) "任务提醒" else "日程提醒")
            if (start.isNotBlank()) append(" · ").append(start)
            if (note.isNotBlank()) append("\n").append(note)
        }
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pendingLaunch = PendingIntent.getActivity(
            context,
            19_000 + positiveHash(id) % 10_000,
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
        NotificationManagerCompat.from(context).notify(positiveHash(id), notification)
    }

    companion object {
        const val ACTION_NOTIFY = "com.github.lynyugiri.lynai.SCHEDULE_NOTIFY"
        private const val CHANNEL_ID = "schedule_notifications"
        private const val CHANNEL_NAME = "日程表提醒"
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
            val entries = CalendarProjectionStore.read(context).notificationTriggers
            val prefs = context.getSharedPreferences(NOTIFICATION_PREFS, Context.MODE_PRIVATE)
            val previousIds = prefs.getStringSet(SCHEDULED_IDS, emptySet()).orEmpty()
            previousIds.forEach { id ->
                alarmManager.cancel(
                    pendingIntent(
                        context,
                        CalendarNotificationTrigger(
                            id,
                            "",
                            "",
                            "",
                            java.time.LocalDateTime.MIN,
                            null
                        )
                    )
                )
            }
            val now = System.currentTimeMillis()
            var scheduled = 0
            val scheduledIds = mutableSetOf<String>()
            entries.filter { it.triggerAtMillis > now }.forEach { entry ->
                val pendingIntent = pendingIntent(context, entry)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, entry.triggerAtMillis, pendingIntent)
                } else {
                    alarmManager.set(AlarmManager.RTC_WAKEUP, entry.triggerAtMillis, pendingIntent)
                }
                scheduledIds.add(entry.triggerId)
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

        private fun pendingIntent(context: Context, entry: CalendarNotificationTrigger): PendingIntent {
            val intent = Intent(context, ScheduleNotificationReceiver::class.java).apply {
                action = ACTION_NOTIFY
                putExtra(EXTRA_ID, entry.triggerId)
                putExtra(EXTRA_TITLE, entry.title)
                putExtra(EXTRA_NOTE, entry.note)
                putExtra(EXTRA_KIND, entry.sourceType)
                putExtra(EXTRA_START, SimpleDateFormat("M月d日 HH:mm", Locale.CHINA).format(entry.triggerAtMillis))
            }
            return PendingIntent.getBroadcast(
                context,
                positiveHash(entry.triggerId),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
            )
        }

        private fun positiveHash(value: String): Int = value.hashCode() and Int.MAX_VALUE

        private fun immutableFlag(): Int {
            return if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
        }
    }
}
