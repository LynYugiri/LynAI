package com.github.lynyugiri.lynai

import android.app.Activity
import android.content.Context
import android.graphics.PixelFormat
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.WindowManager
import android.widget.TextView
import io.flutter.plugin.common.MethodChannel

object DevicePlanOverlay {
    private var activity: Activity? = null
    private var view: TextView? = null

    fun install(activity: Activity, channel: MethodChannel) {
        this.activity = activity
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    show(arguments(call.arguments))
                    result.success(null)
                }
                "hide" -> {
                    hide()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun show(args: Map<String, Any?>) {
        val ctx = activity ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(ctx)) {
            return
        }
        val manager = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val text = view ?: TextView(ctx).apply {
            setTextColor(0xFFFFFFFF.toInt())
            setBackgroundColor(0xCC111827.toInt())
            setPadding(24, 18, 24, 18)
            textSize = 13f
            maxLines = 8
        }.also { next ->
            view = next
            manager.addView(next, layoutParams())
        }
        val status = args["status"]?.toString().orEmpty()
        val purpose = args["purpose"]?.toString().orEmpty()
        val step = args["currentStep"]?.toString().orEmpty()
        val action = args["lastAction"]?.toString().orEmpty()
        text.text = buildString {
            appendLine("LynAI Agent")
            if (status.isNotEmpty()) appendLine("状态: $status")
            if (purpose.isNotEmpty()) appendLine("任务: $purpose")
            if (step.isNotEmpty()) appendLine("步骤: $step")
            if (action.isNotEmpty()) appendLine("动作: $action")
        }.trim()
    }

    private fun hide() {
        val ctx = activity ?: return
        val current = view ?: return
        val manager = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        try {
            manager.removeView(current)
        } catch (_: Exception) {
        } finally {
            view = null
        }
    }

    private fun layoutParams(): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = 24
            y = 160
        }
    }

    private fun arguments(raw: Any?): Map<String, Any?> {
        @Suppress("UNCHECKED_CAST")
        return raw as? Map<String, Any?> ?: emptyMap()
    }
}
