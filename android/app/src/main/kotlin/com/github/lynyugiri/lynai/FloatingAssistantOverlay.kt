package com.github.lynyugiri.lynai

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

object FloatingAssistantOverlay {
    private var activity: Activity? = null
    private var channel: MethodChannel? = null
    private var bubble: TextView? = null
    private var panel: LinearLayout? = null
    private var agentText: TextView? = null
    private var params: WindowManager.LayoutParams? = null
    private var panelParams: WindowManager.LayoutParams? = null
    private var expanded = false
    private var allowScreenContext = false
    private var showMangaTranslationAction = true
    private var translationRunning = false

    fun install(activity: Activity, channel: MethodChannel) {
        this.activity = activity
        this.channel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    configure(arguments(call.arguments))
                    result.success(null)
                }
                "showBubble" -> {
                    showBubble()
                    result.success(null)
                }
                "hideBubble" -> {
                    hideAll()
                    result.success(null)
                }
                "updateAgentPlan" -> {
                    updateAgentPlan(arguments(call.arguments))
                    result.success(null)
                }
                "setTranslationRunning" -> {
                    translationRunning = arguments(call.arguments)["running"] == true
                    if (expanded) {
                        hidePanel()
                        showPanel()
                    }
                    result.success(null)
                }
                "clearTranslationBlocks" -> {
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun configure(args: Map<String, Any?>) {
        val nextAllowScreenContext = args["allowScreenContext"] == true
        val nextShowManga = args["showMangaTranslationAction"] != false
        val nextTranslationRunning = args["translationRunning"] == true
        val changed = allowScreenContext != nextAllowScreenContext ||
            showMangaTranslationAction != nextShowManga ||
            translationRunning != nextTranslationRunning
        allowScreenContext = nextAllowScreenContext
        showMangaTranslationAction = nextShowManga
        translationRunning = nextTranslationRunning
        if (changed && expanded) {
            hidePanel()
            showPanel()
        }
    }

    private fun showBubble() {
        val ctx = activity ?: return
        if (!canDrawOverlays(ctx)) return
        val manager = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        if (bubble != null) return
        val nextParams = bubbleLayoutParams(ctx)
        params = nextParams
        bubble = TextView(ctx).apply {
            text = "L"
            textSize = 18f
            gravity = Gravity.CENTER
            setTextColor(0xFFFFFFFF.toInt())
            setBackgroundColor(0xDD2563EB.toInt())
            setPadding(26, 20, 26, 20)
            setOnTouchListener(DragTouchListener(ctx, nextParams) { togglePanel() })
        }
        manager.addView(bubble, nextParams)
    }

    private fun togglePanel() {
        if (expanded) hidePanel() else showPanel()
    }

    private fun showPanel() {
        val ctx = activity ?: return
        if (!canDrawOverlays(ctx)) return
        val manager = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        if (panel == null) {
            val nextParams = panelLayoutParams(ctx)
            panelParams = nextParams
            panel = buildPanel(ctx)
            manager.addView(panel, nextParams)
        }
        expanded = true
        channel?.invokeMethod("panelOpened", emptyMap<String, Any>())
    }

    private fun hidePanel() {
        val ctx = activity ?: return
        val current = panel ?: return
        val manager = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        try {
            manager.removeView(current)
        } catch (_: Exception) {
        } finally {
            panel = null
            agentText = null
            panelParams = null
            expanded = false
        }
    }

    private fun hideAll() {
        hidePanel()
        val ctx = activity ?: return
        val current = bubble ?: return
        val manager = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        try {
            manager.removeView(current)
        } catch (_: Exception) {
        } finally {
            bubble = null
            params = null
        }
    }

    private fun buildPanel(ctx: Context): LinearLayout {
        return LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xEE111827.toInt())
            setPadding(24, 20, 24, 20)
            addView(TextView(ctx).apply {
                text = "LynAI 悬浮助手"
                textSize = 16f
                setTextColor(0xFFFFFFFF.toInt())
            })
            agentText = TextView(ctx).apply {
                text = "暂无 Agent 任务"
                textSize = 13f
                setTextColor(0xFFE5E7EB.toInt())
                setPadding(0, 14, 0, 10)
                maxLines = 8
            }.also { addView(it) }
            val actions = LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
            }
            if (allowScreenContext) {
                actions.addView(actionButton(ctx, "读取页面") { emit("attachScreenContext") })
            }
            if (showMangaTranslationAction) {
                actions.addView(actionButton(ctx, if (translationRunning) "停止翻译" else "漫画翻译") {
                    emit("toggleMangaTranslation")
                })
            }
            actions.addView(actionButton(ctx, "继续 Agent") { emit("resumeAgent") })
            actions.addView(actionButton(ctx, "停止 Agent") { emit("stopAgent") })
            actions.addView(actionButton(ctx, "打开 LynAI") { openLynAI() })
            actions.addView(actionButton(ctx, "收起") { hidePanel() })
            addView(actions)
        }
    }

    private fun actionButton(ctx: Context, label: String, action: () -> Unit): Button {
        return Button(ctx).apply {
            text = label
            setOnClickListener { action() }
        }
    }

    private fun updateAgentPlan(args: Map<String, Any?>) {
        val text = agentText ?: return
        val status = args["status"]?.toString().orEmpty()
        val purpose = args["purpose"]?.toString().orEmpty()
        val step = args["currentStep"]?.toString().orEmpty()
        val action = args["lastAction"]?.toString().orEmpty()
        text.text = buildString {
            appendLine("Agent 任务")
            if (status.isNotEmpty()) appendLine("状态: $status")
            if (purpose.isNotEmpty()) appendLine("目标: $purpose")
            if (step.isNotEmpty()) appendLine("步骤: $step")
            if (action.isNotEmpty()) appendLine("动作: $action")
        }.trim().ifEmpty { "暂无 Agent 任务" }
    }

    private fun emit(method: String) {
        channel?.invokeMethod(method, emptyMap<String, Any>())
    }

    private fun openLynAI() {
        val ctx = activity ?: return
        val intent = Intent(ctx, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }
        ctx.startActivity(intent)
    }

    private fun bubbleLayoutParams(ctx: Context): WindowManager.LayoutParams {
        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = ctx.resources.displayMetrics.widthPixels - 110
            y = ctx.resources.displayMetrics.heightPixels / 3
        }
    }

    private fun panelLayoutParams(ctx: Context): WindowManager.LayoutParams {
        return WindowManager.LayoutParams(
            (ctx.resources.displayMetrics.widthPixels * 0.82f).toInt(),
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 36
            y = 180
        }
    }

    private fun overlayType(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
    }

    private fun canDrawOverlays(ctx: Context): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(ctx)
    }

    private fun arguments(raw: Any?): Map<String, Any?> {
        @Suppress("UNCHECKED_CAST")
        return raw as? Map<String, Any?> ?: emptyMap()
    }

    private class DragTouchListener(
        private val ctx: Context,
        private val params: WindowManager.LayoutParams,
        private val click: () -> Unit
    ) : View.OnTouchListener {
        private var startX = 0
        private var startY = 0
        private var downX = 0f
        private var downY = 0f

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            val manager = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    downX = event.rawX
                    downY = event.rawY
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = startX + (event.rawX - downX).toInt()
                    params.y = startY + (event.rawY - downY).toInt()
                    manager.updateViewLayout(view, params)
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    val moved = abs(event.rawX - downX) + abs(event.rawY - downY)
                    if (moved < 12) {
                        click()
                    } else {
                        val width = ctx.resources.displayMetrics.widthPixels
                        params.x = if (params.x < width / 2) 12 else width - view.width - 12
                        manager.updateViewLayout(view, params)
                    }
                    return true
                }
            }
            return false
        }
    }
}
