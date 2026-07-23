package com.github.lynyugiri.lynai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class GenerationForegroundService : Service() {
    private var foregroundStarted = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (commandForAction(intent?.action)) {
            GenerationServiceCommand.START -> startForegroundIfNeeded()
            GenerationServiceCommand.STOP -> stopForegroundAndSelf(startId)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopForegroundAndSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        removeForegroundNotification()
        super.onDestroy()
    }

    private fun startForegroundIfNeeded() {
        if (foregroundStarted) return
        createChannel()
        startForeground(NOTIFICATION_ID, notification())
        foregroundStarted = true
    }

    private fun stopForegroundAndSelf(startId: Int? = null) {
        removeForegroundNotification()
        if (startId == null) {
            stopSelf()
        } else {
            stopSelfResult(startId)
        }
    }

    @Suppress("DEPRECATION")
    private fun removeForegroundNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            stopForeground(true)
        }
        getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        foregroundStarted = false
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "AI 回复生成",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "保持后台生成回复时的网络连接"
        }
        manager.createNotificationChannel(channel)
    }

    private fun notification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("LynAI 正在生成回复")
            .setContentText("保持后台网络连接")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    companion object {
        internal const val ACTION_START =
            "com.github.lynyugiri.lynai.action.START_GENERATION_FOREGROUND"
        internal const val ACTION_STOP =
            "com.github.lynyugiri.lynai.action.STOP_GENERATION_FOREGROUND"
        private const val CHANNEL_ID = "lynai_generation"
        private const val NOTIFICATION_ID = 1201

        internal fun commandForAction(action: String?): GenerationServiceCommand =
            if (action == ACTION_START) GenerationServiceCommand.START else GenerationServiceCommand.STOP
    }
}

internal enum class GenerationServiceCommand {
    START,
    STOP
}
