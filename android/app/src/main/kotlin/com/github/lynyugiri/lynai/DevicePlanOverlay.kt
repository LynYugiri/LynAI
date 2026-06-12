package com.github.lynyugiri.lynai

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodChannel

object DevicePlanOverlay {
    private var activity: Activity? = null
    private var channel: MethodChannel? = null
    private var view: LinearLayout? = null
    private var textView: TextView? = null
    private var resumeButton: Button? = null
    private var stopButton: Button? = null

    fun install(activity: Activity, channel: MethodChannel) {
        this.activity = activity
        this.channel = channel
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
        val panel = view ?: buildView(ctx).also { next ->
            view = next
            manager.addView(next, layoutParams())
        }
        val text = textView ?: return
        val status = args["status"]?.toString().orEmpty()
        val purpose = args["purpose"]?.toString().orEmpty()
        val step = args["currentStep"]?.toString().orEmpty()
        val action = args["lastAction"]?.toString().orEmpty()
        val pauseReason = args["pauseReason"]?.toString().orEmpty()
        val canResume = args["canResume"] == true
        val canStop = args["canStop"] != false
        text.text = buildString {
            appendLine("LynAI Agent")
            if (status.isNotEmpty()) appendLine("状态: $status")
            if (purpose.isNotEmpty()) appendLine("任务: $purpose")
            if (step.isNotEmpty()) appendLine("步骤: $step")
            if (action.isNotEmpty()) appendLine("动作: $action")
            if (pauseReason.isNotEmpty()) appendLine("暂停: $pauseReason")
        }.trim()
        resumeButton?.visibility = if (canResume) View.VISIBLE else View.GONE
        stopButton?.isEnabled = canStop
        panel.bringToFront()
    }

    private fun buildView(ctx: Context): LinearLayout {
        val panel = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xCC111827.toInt())
            setPadding(24, 18, 24, 18)
        }
        textView = TextView(ctx).apply {
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 13f
            maxLines = 8
        }.also { panel.addView(it) }
        val buttons = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
        }
        resumeButton = Button(ctx).apply {
            text = "继续"
            setOnClickListener { channel?.invokeMethod("resume", emptyMap<String, Any>()) }
        }.also { buttons.addView(it) }
        stopButton = Button(ctx).apply {
            text = "停止"
            setOnClickListener { channel?.invokeMethod("stop", emptyMap<String, Any>()) }
        }.also { buttons.addView(it) }
        Button(ctx).apply {
            text = "打开 LynAI"
            setOnClickListener { openLynAI() }
        }.also { buttons.addView(it) }
        panel.addView(buttons)
        return panel
    }

    private fun openLynAI() {
        val ctx = activity ?: return
        val intent = Intent(ctx, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }
        ctx.startActivity(intent)
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
            textView = null
            resumeButton = null
            stopButton = null
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
