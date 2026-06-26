package com.github.lynyugiri.lynai

import android.animation.ValueAnimator
import android.app.Activity
import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.abs
import kotlin.math.min

object FloatingAssistantOverlay {
    private var activity: Activity? = null
    private var channel: MethodChannel? = null
    private var bubble: TextView? = null
    private var panel: LinearLayout? = null
    private var messagesContainer: LinearLayout? = null
    private var statusText: TextView? = null
    private var translationCard: TextView? = null
    private var translationButton: TextView? = null
    private var agentCard: LinearLayout? = null
    private var inputEdit: EditText? = null
    private var voiceButton: TextView? = null
    private var params: WindowManager.LayoutParams? = null
    private var panelParams: WindowManager.LayoutParams? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var mediaRecorder: MediaRecorder? = null
    private var recordingPath: String? = null
    private var expanded = false
    private var allowScreenContext = false
    private var showTranslationAction = true
    private var translationRunning = false
    private var voiceInputMode = "system"
    private var chatState: Map<String, Any?> = emptyMap()
    private var agentState: Map<String, Any?> = emptyMap()

    private var mangaLayoutMode = "auto"
    private var mangaOverlayStyle = "auto"
    private var mangaOverlayOpacity = 0.92
    private var persistedBubbleX = -1
    private var persistedBubbleY = -1
    private var persistedPanelX = -1
    private var persistedPanelY = -1
    private var persistedPanelWidth = -1
    private var persistedPanelHeight = -1
    private var pulseAnimator: ValueAnimator? = null
    private var bubbleState: BubbleState = BubbleState.IDLE
    private var scrollMessageHeight = -1
    private var screenOffReceiver: BroadcastReceiver? = null
    private var screenshotBubbleVisible = false
    private var screenshotSavedExpanded = false
    private var screenshotHiding = false

    private enum class BubbleState {
        IDLE, STREAMING, AGENT_RUNNING, TRANSLATING, RECORDING
    }

    private val screenStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    TranslationOverlayManager.clear()
                    stopPulse()
                    // Bug G: let the Dart side stop in-flight translation streams.
                    channel?.invokeMethod("screenOff", emptyMap<String, Any>())
                }
                Intent.ACTION_SCREEN_ON -> {
                    // User needs to re-trigger translation after screen on
                }
            }
        }
    }

    fun install(activity: Activity, channel: MethodChannel) {
        this.activity = activity
        this.channel = channel
        screenOffReceiver = screenStateReceiver
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
        }
        // 用 applicationContext 注册广播接收器，避免持有 Activity 引用导致泄漏。
        val appContext = activity.applicationContext
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(screenOffReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            appContext.registerReceiver(screenOffReceiver, filter)
        }
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
                    agentState = arguments(call.arguments)
                    updatePanelViews()
                    updateBubbleState()
                    result.success(null)
                }
                "updateChatState" -> {
                    chatState = arguments(call.arguments)
                    updatePanelViews()
                    updateBubbleState()
                    result.success(null)
                }
                "setTranslationRunning" -> {
                    translationRunning = arguments(call.arguments)["running"] == true
                    updatePanelViews()
                    updateBubbleState()
                    result.success(null)
                }
                "updateTranslationOverlay" -> {
                    val args = arguments(call.arguments)
                    TranslationOverlayManager.setBlocks(
                        activity!!, args, mangaOverlayStyle, mangaOverlayOpacity, mangaLayoutMode
                    )
                    result.success(null)
                }
                "clearTranslationOverlay" -> {
                    TranslationOverlayManager.clear()
                    result.success(null)
                }
                "hideForScreenshot" -> {
                    hideForScreenshot()
                    result.success(null)
                }
                "restoreAfterScreenshot" -> {
                    restoreAfterScreenshot()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun uninstall() {
        try {
            val ctx = activity?.applicationContext ?: activity
            ctx?.unregisterReceiver(screenOffReceiver)
        } catch (_: Exception) {
            // receiver was not registered or already unregistered
        }
        screenOffReceiver = null
        hideAll()
        stopSpeechRecognition()
        releaseRecorder()
        stopPulse()
        TranslationOverlayManager.dispose()
        activity = null
        channel = null
        screenOffReceiver = null
    }

    private fun configure(args: Map<String, Any?>) {
        allowScreenContext = args["allowScreenContext"] == true
        showTranslationAction = args["showMangaTranslationAction"] != false
        translationRunning = args["translationRunning"] == true
        voiceInputMode = args["voiceInputMode"]?.toString() ?: "system"
        mangaLayoutMode = args["mangaLayoutMode"]?.toString() ?: "auto"
        mangaOverlayStyle = args["mangaOverlayStyle"]?.toString() ?: "auto"
        mangaOverlayOpacity = (args["mangaOverlayOpacity"] as? Number)?.toDouble() ?: 0.92
        persistedBubbleX = (args["bubbleX"] as? Number)?.toInt() ?: -1
        persistedBubbleY = (args["bubbleY"] as? Number)?.toInt() ?: -1
        persistedPanelX = (args["panelX"] as? Number)?.toInt() ?: -1
        persistedPanelY = (args["panelY"] as? Number)?.toInt() ?: -1
        persistedPanelWidth = (args["panelWidth"] as? Number)?.toInt() ?: -1
        persistedPanelHeight = (args["panelHeight"] as? Number)?.toInt() ?: -1
        updatePanelViews()
    }

    private fun showBubble() {
        val ctx = activity ?: return
        if (!canDrawOverlays(ctx)) {
            if (bubble != null || panel != null) {
                hideAll()
                channel?.invokeMethod("overlayPermissionLost", emptyMap<String, Any>())
            }
            return
        }
        val manager = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        if (bubble != null) return
        val nextParams = bubbleLayoutParams(ctx)
        params = nextParams
        bubble = TextView(ctx).apply {
            text = "AI"
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            background = rounded(bubbleColorForState(bubbleState), dp(ctx, 22))
            elevation = dp(ctx, 8).toFloat()
            setPadding(dp(ctx, 14), 0, dp(ctx, 14), 0)
            setOnTouchListener(DragTouchListener(ctx, nextParams, {
                ctx.resources.displayMetrics.heightPixels - nextParams.height
            }, {
                togglePanel()
            }, {
                channel?.invokeMethod(
                    "bubbleMoved",
                    mapOf("x" to nextParams.x, "y" to nextParams.y)
                )
            }))
        }
        manager.addView(bubble, nextParams)
        updateBubbleState()
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
        updatePanelViews()
        channel?.invokeMethod("panelOpened", emptyMap<String, Any>())
    }

    private fun hidePanel() {
        val ctx = activity ?: return
        val current = panel ?: return
        hideKeyboard(ctx)
        val manager = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        try {
            manager.removeView(current)
        } catch (_: Exception) {
        } finally {
            panel = null
            messagesContainer = null
            statusText = null
            translationCard = null
            translationButton = null
            agentCard = null
            inputEdit = null
            voiceButton = null
            panelParams = null
            expanded = false
        }
    }

    private fun hideAll() {
        hidePanel()
        stopSpeechRecognition()
        releaseRecorder()
        stopPulse()
        TranslationOverlayManager.clear()
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

    // E1: temporarily remove bubble/panel/translation overlays from the
    // framebuffer so an accessibility screenshot does not capture them and
    // pollute OCR. Preserves drag position (params) and panel-open state so
    // restoreAfterScreenshot can put everything back exactly where it was.
    private fun hideForScreenshot() {
        if (screenshotHiding) return
        screenshotHiding = true
        screenshotBubbleVisible = bubble != null
        screenshotSavedExpanded = expanded
        TranslationOverlayManager.clear()
        if (panel != null) hidePanel()
        val current = bubble
        if (current != null) {
            val ctx = activity
            if (ctx != null) {
                try {
                    (ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager)
                        .removeView(current)
                } catch (_: Exception) {
                }
            }
            bubble = null
            // Keep `params` (preserved position) for restore.
        }
    }

    private fun restoreAfterScreenshot() {
        if (!screenshotHiding) return
        screenshotHiding = false
        val ctx = activity ?: return
        if (!canDrawOverlays(ctx)) return
        val manager = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        if (screenshotBubbleVisible) {
            val nextParams = params ?: bubbleLayoutParams(ctx).also { params = it }
            params = nextParams
            bubble = TextView(ctx).apply {
                text = "AI"
                textSize = 15f
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                setTextColor(Color.WHITE)
                background = rounded(bubbleColorForState(bubbleState), dp(ctx, 22))
                elevation = dp(ctx, 8).toFloat()
                setPadding(dp(ctx, 14), 0, dp(ctx, 14), 0)
                setOnTouchListener(DragTouchListener(ctx, nextParams, {
                    ctx.resources.displayMetrics.heightPixels - nextParams.height
                }, { togglePanel() }, {
                    channel?.invokeMethod(
                        "bubbleMoved",
                        mapOf("x" to nextParams.x, "y" to nextParams.y)
                    )
                }))
            }
            try {
                manager.addView(bubble, nextParams)
            } catch (_: Exception) {
                bubble = null
            }
            updateBubbleState()
        }
        if (screenshotSavedExpanded && panel == null) {
            showPanel()
        }
        screenshotBubbleVisible = false
        screenshotSavedExpanded = false
    }

    private fun buildPanel(ctx: Context): LinearLayout {
        val root = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(0xF0FFFFFF.toInt(), dp(ctx, 24), 0x1F0F172A, 1)
            elevation = dp(ctx, 18).toFloat()
            setPadding(dp(ctx, 14), dp(ctx, 12), dp(ctx, 14), dp(ctx, 12))
        }

        val header = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        header.addView(TextView(ctx).apply {
            text = "LynAI"
            textSize = 17f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(0xFF0F172A.toInt())
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        header.addView(chip(ctx, "新建", false) {
            channel?.invokeMethod("newConversation", emptyMap<String, Any>())
        })
        header.addView(space(ctx, 8, 1))
        header.addView(chip(ctx, "打开", false) { openLynAI() })
        header.addView(space(ctx, 8, 1))
        header.addView(chip(ctx, "收起", false) { hidePanel() })
        val panelParamRef = panelParams
        if (panelParamRef != null) {
            header.setOnTouchListener(DragTouchListener(ctx, panelParamRef, {
                (ctx.resources.displayMetrics.heightPixels - panelParamRef.height).coerceAtLeast(0)
            }, {
                // tap on header does nothing
            }, {
                channel?.invokeMethod(
                    "panelMoved",
                    mapOf("x" to panelParamRef.x, "y" to panelParamRef.y)
                )
            }, edgeSnap = false))
        }
        root.addView(header)

        statusText = TextView(ctx).apply {
            textSize = 12f
            setTextColor(0xFF64748B.toInt())
            setPadding(0, dp(ctx, 8), 0, 0)
        }.also { root.addView(it) }

        val scroll = ScrollView(ctx).apply {
            isFillViewport = false
            overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS
        }
        messagesContainer = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(ctx, 8), 0, dp(ctx, 4))
        }.also { scroll.addView(it) }
        val scrollHeight = if (persistedPanelHeight > 0) persistedPanelHeight else dp(ctx, 280)
        scrollMessageHeight = scrollHeight
        root.addView(scroll, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            scrollHeight
        ))

        translationCard = TextView(ctx).apply {
            textSize = 13f
            setTextColor(0xFF0F172A.toInt())
            setPadding(dp(ctx, 12), dp(ctx, 10), dp(ctx, 12), dp(ctx, 10))
            background = rounded(0xFFEFF6FF.toInt(), dp(ctx, 16), 0x332563EB, 1)
            setOnClickListener {
                showTranslationCardMenu(ctx)
            }
            setOnLongClickListener {
                val t = text?.toString().orEmpty()
                if (t.isNotEmpty()) {
                    copyToClipboard(ctx, t, "译文已复制")
                }
                true
            }
        }.also { root.addView(it) }

        agentCard = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(ctx, 12), dp(ctx, 10), dp(ctx, 12), dp(ctx, 10))
            background = rounded(0xFFF8FAFC.toInt(), dp(ctx, 16), 0x1F64748B, 1)
        }.also { root.addView(it) }

        val quickRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(ctx, 8), 0, dp(ctx, 8))
        }
        translationButton = chip(ctx, "翻译", translationRunning) {
            channel?.invokeMethod("toggleMangaTranslation", emptyMap<String, Any>())
        }.also { quickRow.addView(it) }
        quickRow.addView(space(ctx, 8, 1))
        val contextChip = chip(ctx, if (allowScreenContext) "可读页面" else "未授权页面", allowScreenContext) {
            channel?.invokeMethod("openAccessibilitySettings", emptyMap<String, Any>())
        }
        quickRow.addView(contextChip)
        root.addView(quickRow)

        val composer = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = rounded(0xFFF8FAFC.toInt(), dp(ctx, 18), 0x1F64748B, 1)
            setPadding(dp(ctx, 8), dp(ctx, 6), dp(ctx, 6), dp(ctx, 6))
        }
        inputEdit = EditText(ctx).apply {
            hint = "问当前页面上的内容..."
            textSize = 14f
            minLines = 1
            maxLines = 4
            setTextColor(0xFF0F172A.toInt())
            setHintTextColor(0xFF94A3B8.toInt())
            background = null
        }.also {
            composer.addView(it, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        }
        voiceButton = chip(ctx, "语音", false) { startVoiceRecognition(ctx) }.also { composer.addView(it) }
        composer.addView(space(ctx, 8, 1))
        composer.addView(chip(ctx, "发送", true) {
            val text = inputEdit?.text?.toString().orEmpty().trim()
            if (text.isEmpty()) return@chip
            channel?.invokeMethod("sendMessage", mapOf("text" to text))
            inputEdit?.setText("")
        })
        root.addView(composer)

        val resizeHandle = View(ctx).apply {
            background = rounded(0xFFCBD5E1.toInt(), dp(ctx, 3))
            setOnTouchListener(ResizeTouchListener(ctx, root, panelParams, scroll, {
                val w = ctx.resources.displayMetrics.widthPixels
                val h = ctx.resources.displayMetrics.heightPixels
                // F2: maxW 受面板当前 x 限制，避免缩放后向右溢出屏幕。
                val maxW = min(w - dp(ctx, 32), dp(ctx, 480))
                (dp(ctx, 240) to maxW) to (dp(ctx, 200) to (h * 7 / 10))
            }) { width, height ->
                scrollMessageHeight = height - dp(ctx, 180)
                val sc = scroll
                if (sc != null && scrollMessageHeight > 0) {
                    val lp = sc.layoutParams
                    lp.height = scrollMessageHeight
                    sc.layoutParams = lp
                }
                channel?.invokeMethod(
                    "panelResized",
                    mapOf(
                        "width" to width,
                        "height" to height,
                        "x" to (panelParams?.x ?: -1),
                        "y" to (panelParams?.y ?: -1)
                    )
                )
            })
        }
        // F3: 居中、更明显的拖拽手柄。
        val handleRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(0, dp(ctx, 6), 0, dp(ctx, 2))
        }
        val handleBar = View(ctx).apply {
            background = rounded(0xCC475569.toInt(), dp(ctx, 3))
        }
        handleRow.addView(handleBar, LinearLayout.LayoutParams(dp(ctx, 44), dp(ctx, 6)))
        handleRow.addView(resizeHandle, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(ctx, 18)
        ))
        root.addView(handleRow, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            topMargin = dp(ctx, 2)
        })

        return root
    }

    private fun updatePanelViews() {
        val ctx = activity ?: return
        if (panel == null) return
        updateStatus()
        updateMessages(ctx)
        updateTranslation()
        updateAgent(ctx)
        voiceButton?.visibility = if (voiceInputMode == "disabled") View.GONE else View.VISIBLE
        if (recordingPath == null && speechRecognizer == null) {
            voiceButton?.text = if (voiceInputMode == "server") "录音" else "语音"
        }
        translationButton?.visibility = if (showTranslationAction) View.VISIBLE else View.GONE
        translationButton?.text = if (translationRunning) "翻译中" else "翻译"
        updateBubbleState()
    }

    private fun updateBubbleState() {
        val newState = when {
            recordingPath != null || speechRecognizer != null -> BubbleState.RECORDING
            translationRunning -> BubbleState.TRANSLATING
            agentState["active"] == true -> BubbleState.AGENT_RUNNING
            chatState["streaming"] == true -> BubbleState.STREAMING
            else -> BubbleState.IDLE
        }
        if (newState != bubbleState) {
            bubbleState = newState
            val ctx = activity ?: return
            val bub = bubble ?: return
            bub.background = rounded(bubbleColorForState(newState), dp(ctx, 22))
            if (newState != BubbleState.IDLE) {
                startPulse(bub)
            } else {
                stopPulse()
            }
        }
    }

    private fun bubbleColorForState(state: BubbleState): Int {
        return when (state) {
            BubbleState.IDLE -> 0xFF2563EB.toInt()
            BubbleState.STREAMING -> 0xFF3B82F6.toInt()
            BubbleState.AGENT_RUNNING -> 0xFFF59E0B.toInt()
            BubbleState.TRANSLATING -> 0xFF22C55E.toInt()
            BubbleState.RECORDING -> 0xFFEF4444.toInt()
        }
    }

    private fun startPulse(view: View) {
        stopPulse()
        pulseAnimator = ValueAnimator.ofFloat(0.8f, 1.2f).apply {
            duration = 800
            repeatMode = ValueAnimator.REVERSE
            repeatCount = ValueAnimator.INFINITE
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animator ->
                val scale = animator.animatedValue as Float
                view.scaleX = scale
                view.scaleY = scale
            }
            start()
        }
    }

    private fun stopPulse() {
        pulseAnimator?.cancel()
        pulseAnimator = null
        bubble?.scaleX = 1f
        bubble?.scaleY = 1f
    }

    private fun updateStatus() {
        val status = chatState["status"]?.toString().orEmpty()
        val error = chatState["error"]?.toString().orEmpty()
        statusText?.apply {
            text = when {
                error.isNotEmpty() -> error
                status.isNotEmpty() -> status
                allowScreenContext -> "模型可按需读取当前页面"
                else -> "悬浮聊天"
            }
            setTextColor(if (error.isNotEmpty()) 0xFFDC2626.toInt() else 0xFF64748B.toInt())
        }
    }

    private fun updateMessages(ctx: Context) {
        val container = messagesContainer ?: return
        container.removeAllViews()
        val messages = listMaps(chatState["messages"])
        if (messages.isEmpty() && chatState["draft"]?.toString().orEmpty().isEmpty()) {
            container.addView(emptyHint(ctx))
            return
        }
        messages.takeLast(24).forEach { message ->
            val content = message["content"]?.toString().orEmpty().trim()
            if (content.isNotEmpty()) {
                container.addView(messageBubble(ctx, message["role"]?.toString() == "user", content))
            }
        }
        val draft = chatState["draft"]?.toString().orEmpty().trim()
        if (draft.isNotEmpty()) container.addView(messageBubble(ctx, false, draft))
    }

    private fun updateTranslation() {
        val text = chatState["translationText"]?.toString().orEmpty().trim()
        translationCard?.apply {
            visibility = if (text.isEmpty()) View.GONE else View.VISIBLE
            this.text = if (text.isEmpty()) "" else "译文\n$text"
            setOnClickListener {
                showTranslationCardMenu(context)
            }
        }
    }

    private fun showTranslationCardMenu(ctx: Context) {
        val card = translationCard ?: return
        val popup = android.widget.PopupMenu(ctx, card)
        popup.menu.add(0, 1, 0, "复制译文")
        popup.menu.add(0, 2, 1, "清空译文")
        popup.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                1 -> {
                    val t = card.text?.toString().orEmpty()
                    if (t.isNotEmpty()) copyToClipboard(ctx, t, "译文已复制")
                    true
                }
                2 -> {
                    channel?.invokeMethod("clearTranslation", emptyMap<String, Any>())
                    true
                }
                else -> false
            }
        }
        popup.show()
    }

    private fun updateAgent(ctx: Context) {
        val card = agentCard ?: return
        val active = agentState["active"] == true
        if (!active) {
            card.visibility = View.GONE
            return
        }
        card.visibility = View.VISIBLE
        card.removeAllViews()
        val status = agentState["status"]?.toString().orEmpty()
        val purpose = agentState["purpose"]?.toString().orEmpty()
        val step = agentState["currentStep"]?.toString().orEmpty()
        val action = agentState["lastAction"]?.toString().orEmpty()
        card.addView(TextView(ctx).apply {
            text = "Agent Plan"
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(0xFF0F172A.toInt())
        })
        card.addView(TextView(ctx).apply {
            text = buildString {
                if (status.isNotEmpty()) appendLine("状态: $status")
                if (purpose.isNotEmpty()) appendLine("目标: $purpose")
                if (step.isNotEmpty()) appendLine("步骤: $step")
                if (action.isNotEmpty()) appendLine("动作: $action")
            }.trim().ifEmpty { "正在执行" }
            textSize = 12f
            setTextColor(0xFF475569.toInt())
            setPadding(0, dp(ctx, 6), 0, 0)
        })
        val canResume = agentState["canResume"] == true
        val canStop = agentState["canStop"] == true
        if (canResume || canStop) {
            val row = LinearLayout(ctx).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.END
                setPadding(0, dp(ctx, 8), 0, 0)
            }
            if (canResume) {
                row.addView(chip(ctx, "继续", true) {
                    channel?.invokeMethod("resumeAgent", emptyMap<String, Any>())
                })
                row.addView(space(ctx, 8, 1))
            }
            if (canStop) {
                row.addView(chip(ctx, "停止", false) {
                    channel?.invokeMethod("stopAgent", emptyMap<String, Any>())
                })
            }
            card.addView(row)
        }
    }

    private fun emptyHint(ctx: Context): TextView {
        return TextView(ctx).apply {
            text = if (allowScreenContext) {
                "问我当前页面上的内容，模型会在需要时读取页面。"
            } else {
                "输入问题开始悬浮对话。"
            }
            textSize = 14f
            setTextColor(0xFF64748B.toInt())
            gravity = Gravity.CENTER
            setPadding(dp(ctx, 18), dp(ctx, 42), dp(ctx, 18), dp(ctx, 42))
        }
    }

    private fun messageBubble(ctx: Context, user: Boolean, content: String): TextView {
        return TextView(ctx).apply {
            text = content
            textSize = 14f
            setTextColor(if (user) Color.WHITE else 0xFF0F172A.toInt())
            setPadding(dp(ctx, 12), dp(ctx, 9), dp(ctx, 12), dp(ctx, 9))
            background = rounded(if (user) 0xFF2563EB.toInt() else 0xFFF1F5F9.toInt(), dp(ctx, 16))
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = if (user) Gravity.END else Gravity.START
                setMargins(0, dp(ctx, 4), 0, dp(ctx, 4))
                width = min(ctx.resources.displayMetrics.widthPixels - dp(ctx, 96), dp(ctx, 300))
            }
            layoutParams = lp
            setOnLongClickListener {
                copyToClipboard(ctx, content, "消息已复制")
                true
            }
        }
    }

    private fun copyToClipboard(ctx: Context, text: String, label: String) {
        val clipboard = ctx.getSystemService(Context.CLIPBOARD_SERVICE)
                as android.content.ClipboardManager
        clipboard.setPrimaryClip(
            android.content.ClipData.newPlainText(label, text)
        )
        Toast.makeText(ctx, label, Toast.LENGTH_SHORT).show()
    }

    private fun chip(ctx: Context, label: String, selected: Boolean, action: () -> Unit): TextView {
        val bg = if (selected) 0xFF2563EB.toInt() else 0xFFF1F5F9.toInt()
        val fg = if (selected) Color.WHITE else 0xFF0F172A.toInt()
        return TextView(ctx).apply {
            text = label
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(fg)
            background = ripple(ctx, bg, dp(ctx, 14))
            setPadding(dp(ctx, 12), dp(ctx, 7), dp(ctx, 12), dp(ctx, 7))
            setOnClickListener { action() }
        }
    }

    private fun space(ctx: Context, width: Int, height: Int): View {
        return SpaceView(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(dp(ctx, width), dp(ctx, height))
        }
    }

    private fun startVoiceRecognition(ctx: Context) {
        if (voiceInputMode == "disabled") return
        if (voiceInputMode == "server") {
            toggleServerRecording(ctx)
            return
        }
        if (speechRecognizer != null) {
            stopSpeechRecognition()
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(ctx)) {
            appendInputText("语音识别不可用")
            return
        }
        voiceButton?.text = "聆听中"
        updateBubbleState()
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(ctx).apply {
            setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) = Unit
                override fun onBeginningOfSpeech() = Unit
                override fun onRmsChanged(rmsdB: Float) = Unit
                override fun onBufferReceived(buffer: ByteArray?) = Unit
                override fun onEndOfSpeech() = Unit
                override fun onPartialResults(partialResults: Bundle?) = Unit
                override fun onEvent(eventType: Int, params: Bundle?) = Unit

                override fun onError(error: Int) {
                    stopSpeechRecognition()
                    updateBubbleState()
                }

                override fun onResults(results: Bundle?) {
                    val text = results
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()
                        .orEmpty()
                    stopSpeechRecognition()
                    appendInputText(text)
                    updateBubbleState()
                }
            })
            startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                )
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            })
        }
    }

    private fun toggleServerRecording(ctx: Context) {
        val currentPath = recordingPath
        if (currentPath != null) {
            stopServerRecording(currentPath)
            return
        }
        val currentActivity = activity ?: return
        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                currentActivity,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                1202
            )
            statusText?.apply {
                text = "需要麦克风权限才能录音"
                setTextColor(0xFFDC2626.toInt())
            }
            return
        }
        val file = File(ctx.cacheDir, "lynai_floating_${System.currentTimeMillis()}.m4a")
        try {
            @Suppress("DEPRECATION")
            val recorder = MediaRecorder().apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setOutputFile(file.absolutePath)
                prepare()
                start()
            }
            mediaRecorder = recorder
            recordingPath = file.absolutePath
            voiceButton?.text = "停止"
            updateBubbleState()
            statusText?.apply {
                text = "正在录音，再点一次转文字"
                setTextColor(0xFFDC2626.toInt())
            }
        } catch (e: Exception) {
            releaseRecorder()
            updateBubbleState()
            file.delete()
            statusText?.apply {
                text = "录音启动失败: ${e.message ?: e.javaClass.simpleName}"
                setTextColor(0xFFDC2626.toInt())
            }
        }
    }

    private fun stopServerRecording(path: String) {
        try {
            mediaRecorder?.stop()
        } catch (_: Exception) {
        } finally {
            releaseRecorder()
        }
        voiceButton?.text = "转写中"
        updateBubbleState()
        statusText?.apply {
            text = "正在转文字..."
            setTextColor(0xFF64748B.toInt())
        }
        channel?.invokeMethod(
            "transcribeAudio",
            mapOf("path" to path),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    val map = result as? Map<*, *>
                    if (map?.get("ok") == true) {
                        appendInputText(map["text"]?.toString().orEmpty())
                        statusText?.apply {
                            text = "语音已转为文字"
                            setTextColor(0xFF64748B.toInt())
                        }
                    } else {
                        statusText?.apply {
                            text = "语音转文字失败: ${map?.get("error") ?: "未知错误"}"
                            setTextColor(0xFFDC2626.toInt())
                        }
                    }
                    voiceButton?.text = "录音"
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    statusText?.apply {
                        text = "语音转文字失败: ${errorMessage ?: errorCode}"
                        setTextColor(0xFFDC2626.toInt())
                    }
                    voiceButton?.text = "录音"
                }

                override fun notImplemented() {
                    statusText?.apply {
                        text = "语音转文字接口未连接"
                        setTextColor(0xFFDC2626.toInt())
                    }
                    voiceButton?.text = "录音"
                }
            }
        )
    }

    private fun releaseRecorder() {
        try {
            mediaRecorder?.release()
        } catch (_: Exception) {
        } finally {
            mediaRecorder = null
            recordingPath = null
            updateBubbleState()
        }
    }

    private fun stopSpeechRecognition() {
        try {
            speechRecognizer?.stopListening()
            speechRecognizer?.destroy()
        } catch (_: Exception) {
        } finally {
            speechRecognizer = null
            voiceButton?.text = "语音"
            updateBubbleState()
        }
    }

    private fun appendInputText(text: String) {
        if (text.isBlank()) return
        val edit = inputEdit ?: return
        val current = edit.text?.toString().orEmpty()
        edit.setText(if (current.isBlank()) text else "$current $text")
        edit.setSelection(edit.text.length)
    }

    private fun openLynAI() {
        val ctx = activity ?: return
        hidePanel()
        TranslationOverlayManager.clear()
        val intent = Intent(ctx, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }
        ctx.startActivity(intent)
        channel?.invokeMethod("openConversation", emptyMap<String, Any>())
    }

    private fun hideKeyboard(ctx: Context) {
        val input = ctx.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        inputEdit?.windowToken?.let { input?.hideSoftInputFromWindow(it, 0) }
    }

    private fun bubbleLayoutParams(ctx: Context): WindowManager.LayoutParams {
        val dm = ctx.resources.displayMetrics
        val defaultX = dm.widthPixels - dp(ctx, 72)
        val defaultY = dm.heightPixels / 3
        return WindowManager.LayoutParams(
            dp(ctx, 56),
            dp(ctx, 56),
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = if (persistedBubbleX >= 0) persistedBubbleX.coerceIn(0, dm.widthPixels - dp(ctx, 56)) else defaultX
            y = if (persistedBubbleY >= 0) persistedBubbleY.coerceIn(0, dm.heightPixels - dp(ctx, 56)) else defaultY
        }
    }

    private fun panelLayoutParams(ctx: Context): WindowManager.LayoutParams {
        val dm = ctx.resources.displayMetrics
        val defaultWidth = min(dm.widthPixels - dp(ctx, 32), dp(ctx, 390))
        val width = if (persistedPanelWidth > 0) {
            persistedPanelWidth.coerceIn(dp(ctx, 240), min(dm.widthPixels - dp(ctx, 32), dp(ctx, 480)))
        } else {
            defaultWidth
        }
        return WindowManager.LayoutParams(
            width,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = if (persistedPanelX >= 0) persistedPanelX.coerceIn(0, dm.widthPixels - width) else dp(ctx, 16)
            y = if (persistedPanelY >= 0) persistedPanelY.coerceIn(0, (dm.heightPixels - dp(ctx, 240)).coerceAtLeast(0)) else dp(ctx, 72)
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
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

    private fun listMaps(raw: Any?): List<Map<String, Any?>> {
        return (raw as? List<*>)
            ?.mapNotNull { item ->
                @Suppress("UNCHECKED_CAST")
                item as? Map<String, Any?>
            }
            ?: emptyList()
    }

    private fun rounded(
        color: Int,
        radius: Int,
        strokeColor: Int? = null,
        strokeWidthDp: Int = 0
    ): GradientDrawable {
        return GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius.toFloat()
            if (strokeColor != null && strokeWidthDp > 0) setStroke(strokeWidthDp, strokeColor)
        }
    }

    private fun ripple(ctx: Context, color: Int, radius: Int): android.graphics.drawable.Drawable {
        val content = rounded(color, radius)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            RippleDrawable(ColorStateList.valueOf(0x332563EB), content, null)
        } else {
            content
        }
    }

    private fun dp(ctx: Context, value: Int): Int {
        return (value * ctx.resources.displayMetrics.density).toInt()
    }

    private class SpaceView(ctx: Context) : FrameLayout(ctx)

    private class DragTouchListener(
        private val ctx: Context,
        private val params: WindowManager.LayoutParams,
        private val maxYProvider: () -> Int,
        private val click: () -> Unit,
        private val onDragEnd: (() -> Unit)? = null,
        private val edgeSnap: Boolean = true
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
                    val maxY = maxYProvider()
                    params.x = startX + (event.rawX - downX).toInt()
                    params.y = startY + (event.rawY - downY).toInt()
                    val dm = ctx.resources.displayMetrics
                    params.x = params.x.coerceIn(0, dm.widthPixels - view.width)
                    params.y = params.y.coerceIn(0, maxY.coerceAtLeast(0))
                    manager.updateViewLayout(view, params)
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    val moved = abs(event.rawX - downX) + abs(event.rawY - downY)
                    if (moved < 12) {
                        click()
                    } else {
                        if (edgeSnap) {
                            val width = ctx.resources.displayMetrics.widthPixels
                            params.x = if (params.x < width / 2) 12 else width - view.width - 12
                            manager.updateViewLayout(view, params)
                        }
                        onDragEnd?.invoke()
                    }
                    return true
                }
            }
            return false
        }
    }

    private class ResizeTouchListener(
        private val ctx: Context,
        private val targetView: View,
        private val panelParams: WindowManager.LayoutParams?,
        private val scrollView: ScrollView,
        private val sizeBoundsProvider: () -> Pair<Pair<Int, Int>, Pair<Int, Int>>,
        private val onResized: (Int, Int) -> Unit
    ) : View.OnTouchListener {
        private var downX = 0f
        private var downY = 0f
        private var startWidth = 0
        private var startHeight = 0
        private var lastUpdate = 0L

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            val params = panelParams ?: return false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startWidth = params.width
                    startHeight = scrollView.height + dp(ctx, 180)
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val now = System.currentTimeMillis()
                    if (now - lastUpdate < 16) return true
                    lastUpdate = now
                    val (widthRange, heightRange) = sizeBoundsProvider()
                    val (minW, maxW) = widthRange
                    val (minH, maxH) = heightRange
                    val dm = ctx.resources.displayMetrics
                    // F2: 受面板当前 x 限制，避免向右溢出屏幕。
                    val maxXWidth = (dm.widthPixels - dp(ctx, 8)) - params.x
                    val effectiveMaxW = minOf(maxW, maxXWidth.coerceAtLeast(minW))
                    params.width = (startWidth + (event.rawX - downX).toInt())
                        .coerceIn(minW, effectiveMaxW)
                    val newHeight = (startHeight + (event.rawY - downY).toInt())
                        .coerceIn(minH, maxH)
                    val manager = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
                    try {
                        manager.updateViewLayout(targetView, params)
                    } catch (_: Exception) {
                    }
                    onResized(params.width, newHeight)
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    onResized(params.width, scrollView.height + dp(ctx, 180))
                    return true
                }
            }
            return false
        }

        private fun dp(ctx: Context, value: Int): Int {
            return (value * ctx.resources.displayMetrics.density).toInt()
        }
    }
}
