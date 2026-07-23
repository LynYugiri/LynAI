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
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
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
    private var modeContent: LinearLayout? = null
    private var messagesContainer: LinearLayout? = null
    private var statusText: TextView? = null
    private var inputEdit: EditText? = null
    private var voiceButton: TextView? = null
    private var sendButton: TextView? = null
    private val modeButtons = mutableMapOf<PanelMode, TextView>()
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
    private var translationState: Map<String, Any?> = emptyMap()
    private var selectedMode = PanelMode.CHAT
    private var lastAgentActive = false
    private var interactionEnabled = true
    private var chatInputDraft = ""

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

    private enum class PanelMode(val label: String) {
        CHAT("Chat"), TRANSLATION("Translation"), AGENT("Agent")
    }

    private val screenStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    TranslationOverlayHost.clear()
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
        if (this.activity != null) uninstall()
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
                    val next = arguments(call.arguments)
                    val active = next["active"] == true || mapValue(next["run"])["active"] == true
                    if (active && !lastAgentActive) selectedMode = PanelMode.AGENT
                    lastAgentActive = active
                    agentState = next
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
                "updateTranslationState" -> {
                    val next = arguments(call.arguments)
                    translationState = next
                    translationRunning = next["translating"] == true ||
                        next["isTranslating"] == true || next["running"] == true ||
                        next["automatic"] == true || next["isAutomatic"] == true || next["auto"] == true
                    updatePanelViews()
                    updateBubbleState()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun uninstall(owner: Activity? = null) {
        if (owner != null && activity !== owner) return
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
        TranslationOverlayHost.dispose()
        channel?.setMethodCallHandler(null)
        activity = null
        channel = null
        screenOffReceiver = null
        screenshotBubbleVisible = false
        screenshotSavedExpanded = false
        screenshotHiding = false
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
        if (!showTranslationAction && selectedMode == PanelMode.TRANSLATION) {
            selectedMode = PanelMode.CHAT
        }
        updatePanelViews()
    }

    fun setInteractionEnabled(enabled: Boolean) {
        if (interactionEnabled == enabled) return
        interactionEnabled = enabled
        val ctx = activity ?: return
        val manager = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        updateTouchableFlag(manager, bubble, params, enabled)
        updateTouchableFlag(manager, panel, panelParams, enabled)
    }

    private fun updateTouchableFlag(
        manager: WindowManager,
        view: View?,
        layoutParams: WindowManager.LayoutParams?,
        enabled: Boolean
    ) {
        if (view == null || layoutParams == null) return
        layoutParams.flags = if (enabled) {
            layoutParams.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
        } else {
            layoutParams.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        }
        try {
            manager.updateViewLayout(view, layoutParams)
        } catch (_: Exception) {
        }
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
        val nextBubble = buildBubble(ctx, nextParams)
        try {
            manager.addView(nextBubble, nextParams)
        } catch (_: Exception) {
            return
        }
        params = nextParams
        bubble = nextBubble
        refreshBubbleAppearance()
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
            val nextPanel = buildPanel(ctx)
            try {
                manager.addView(nextPanel, nextParams)
            } catch (_: Exception) {
                clearPanelReferences()
                return
            }
            panel = nextPanel
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
            clearPanelReferences()
        }
    }

    private fun clearPanelReferences() {
        scrollMessageHeight = -1
        panel = null
        modeContent = null
        messagesContainer = null
        statusText = null
        inputEdit = null
        voiceButton = null
        sendButton = null
        modeButtons.clear()
        panelParams = null
        expanded = false
    }

    private fun hideAll() {
        screenshotBubbleVisible = false
        screenshotSavedExpanded = false
        screenshotHiding = false
        hidePanel()
        stopSpeechRecognition()
        releaseRecorder()
        stopPulse()
        TranslationOverlayHost.clear()
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

    private fun hideForTranslationCapture() {
        if (screenshotHiding) return
        screenshotHiding = true
        screenshotBubbleVisible = bubble != null
        screenshotSavedExpanded = expanded
        TranslationOverlayHost.clear()
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

    fun hideForScreenTranslation() = hideForTranslationCapture()

    private fun restoreAfterTranslationCapture() {
        if (!screenshotHiding) return
        screenshotHiding = false
        val restoreBubble = screenshotBubbleVisible
        val restorePanel = screenshotSavedExpanded
        screenshotBubbleVisible = false
        screenshotSavedExpanded = false
        val ctx = activity ?: return
        if (!canDrawOverlays(ctx)) {
            params = null
            channel?.invokeMethod("overlayPermissionLost", emptyMap<String, Any>())
            return
        }
        val manager = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        if (restoreBubble) {
            val nextParams = params ?: bubbleLayoutParams(ctx).also { params = it }
            val nextBubble = buildBubble(ctx, nextParams)
            try {
                manager.addView(nextBubble, nextParams)
                params = nextParams
                bubble = nextBubble
            } catch (_: Exception) {
                bubble = null
            }
            refreshBubbleAppearance()
        }
        if (restorePanel && panel == null) {
            showPanel()
        }
    }

    fun restoreAfterScreenTranslation() = restoreAfterTranslationCapture()

    private fun buildPanel(ctx: Context): LinearLayout {
        val root = SuppressingLinearLayout(ctx).apply {
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
                ctx.resources.displayMetrics.heightPixels - root.height
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

        val modeRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(ctx, 10), 0, dp(ctx, 6))
        }
        val visibleModes = PanelMode.entries.filter {
            it != PanelMode.TRANSLATION || showTranslationAction
        }
        visibleModes.forEachIndexed { index, mode ->
            val button = chip(ctx, mode.label, selectedMode == mode) {
                selectedMode = mode
                updateModeButtons(ctx)
                rebuildModeContent(ctx)
            }
            modeButtons[mode] = button
            modeRow.addView(button, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            if (index < visibleModes.lastIndex) modeRow.addView(space(ctx, 6, 1))
        }
        root.addView(modeRow)

        modeContent = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
        }.also {
            root.addView(it)
        }

        val resizeHandle = View(ctx).apply {
            background = rounded(0xFFCBD5E1.toInt(), dp(ctx, 3))
            setOnTouchListener(ResizeTouchListener(ctx, root, panelParams, {
                val w = ctx.resources.displayMetrics.widthPixels
                val h = ctx.resources.displayMetrics.heightPixels
                val maxW = min(w - dp(ctx, 32), dp(ctx, 480))
                (dp(ctx, 240) to maxW) to (dp(ctx, 200) to (h * 7 / 10))
            }) { width, height ->
                scrollMessageHeight = height - dp(ctx, 180)
                rebuildModeContent(ctx)
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

        rebuildModeContent(ctx)

        return root
    }

    private fun updatePanelViews() {
        val ctx = activity ?: return
        if (panel == null) return
        updateModeButtons(ctx)
        rebuildModeContent(ctx)
        updateBubbleState()
    }

    private fun rebuildModeContent(ctx: Context) {
        val content = modeContent ?: return
        content.removeAllViews()
        messagesContainer = null
        statusText = null
        inputEdit = null
        voiceButton = null
        sendButton = null
        when (selectedMode) {
            PanelMode.CHAT -> buildChatMode(ctx, content)
            PanelMode.TRANSLATION -> buildTranslationMode(ctx, content)
            PanelMode.AGENT -> buildAgentMode(ctx, content)
        }
    }

    private fun updateModeButtons(ctx: Context) {
        modeButtons.forEach { (mode, button) ->
            val selected = mode == selectedMode
            button.setTextColor(if (selected) Color.WHITE else 0xFF0F172A.toInt())
            button.background = ripple(
                ctx,
                if (selected) 0xFF2563EB.toInt() else 0xFFF1F5F9.toInt(),
                dp(ctx, 14)
            )
        }
    }

    private fun buildChatMode(ctx: Context, content: LinearLayout) {
        statusText = modeStatus(ctx).also { content.addView(it) }
        updateStatus()
        val scroll = modeScroll(ctx)
        messagesContainer = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(ctx, 8), 0, dp(ctx, 4))
        }.also { scroll.addView(it) }
        content.addView(scroll, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            modeScrollHeight(ctx)
        ))
        updateMessages(ctx)

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
            setText(chatInputDraft)
            setSelection(text.length)
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(text: CharSequence?, start: Int, count: Int, after: Int) = Unit
                override fun onTextChanged(text: CharSequence?, start: Int, before: Int, count: Int) {
                    chatInputDraft = text?.toString().orEmpty()
                }
                override fun afterTextChanged(text: Editable?) = Unit
            })
        }.also { composer.addView(it, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)) }
        if (voiceInputMode != "disabled") {
            val voiceLabel = when {
                recordingPath != null -> "停止"
                speechRecognizer != null -> "聆听中"
                voiceInputMode == "server" -> "录音"
                else -> "语音"
            }
            voiceButton = chip(ctx, voiceLabel, false) {
                startVoiceRecognition(ctx)
            }.also { composer.addView(it) }
            composer.addView(space(ctx, 8, 1))
        }
        val streaming = chatState["streaming"] == true
        sendButton = chip(ctx, if (streaming) "停止" else "发送", true) {
            if (streaming) {
                channel?.invokeMethod("stopGeneration", emptyMap<String, Any>())
            } else {
                val text = inputEdit?.text?.toString().orEmpty().trim()
                if (text.isNotEmpty()) {
                    channel?.invokeMethod("sendMessage", mapOf("text" to text))
                    chatInputDraft = ""
                    inputEdit?.setText("")
                }
            }
        }.also { composer.addView(it) }
        content.addView(composer)
    }

    private fun buildTranslationMode(ctx: Context, content: LinearLayout) {
        val status = translationState["status"]?.toString().orEmpty()
        val error = translationState["error"]?.toString().orEmpty()
        val count = (translationState["count"] as? Number)?.toInt()
            ?: (translationState["translationCount"] as? Number)?.toInt()
            ?: listMaps(translationState["translations"]).size
        content.addView(modeStatus(ctx).apply {
            text = when {
                error.isNotEmpty() -> error
                status.isNotEmpty() && count > 0 -> "$status · $count"
                status.isNotEmpty() -> status
                count > 0 -> "已翻译 $count 段"
                else -> "翻译当前屏幕上的文字"
            }
            setTextColor(if (error.isNotEmpty()) 0xFFDC2626.toInt() else 0xFF64748B.toInt())
            setOnLongClickListener {
                channel?.invokeMethod("clearTranslation", emptyMap<String, Any>())
                true
            }
        })
        val automatic = translationState["automatic"] == true ||
            translationState["isAutomatic"] == true || translationState["auto"] == true
        val translating = translationIsRunning()
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(ctx, 12), 0, dp(ctx, 10))
        }
        val manual = chip(ctx, if (translating && !automatic) "翻译中" else "翻译", true) {
            channel?.invokeMethod("requestManualTranslation", emptyMap<String, Any>())
        }.apply {
            isEnabled = !automatic && !translating && showTranslationAction
            alpha = if (isEnabled) 1f else 0.45f
        }
        row.addView(manual, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(space(ctx, 8, 1))
        row.addView(chip(ctx, if (automatic) "停止翻译" else "自动翻译", automatic) {
            channel?.invokeMethod(
                if (automatic) "stopAutoTranslation" else "startAutoTranslation",
                emptyMap<String, Any>()
            )
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        content.addView(row)
    }

    private fun buildAgentMode(ctx: Context, content: LinearLayout) {
        val run = mapValue(agentState["run"]).ifEmpty { agentState }
        val active = agentState["active"] == true || run["active"] == true
        val status = run["status"]?.toString().orEmpty()
        val purpose = run["purpose"]?.toString().orEmpty()
        val step = run["currentStep"]?.toString().orEmpty()
        val action = run["lastAction"]?.toString().orEmpty()
        val summary = run["summary"]?.toString().orEmpty()
        val pauseReason = run["pauseReason"]?.toString().orEmpty()
        content.addView(modeStatus(ctx).apply {
            text = buildString {
                append(if (active) status.ifEmpty { "运行中" } else status.ifEmpty { "暂无运行中的 Agent" })
                if (purpose.isNotEmpty()) append(" · $purpose")
            }
        })
        val scroll = modeScroll(ctx)
        val body = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(ctx, 8), 0, dp(ctx, 8))
        }
        body.addView(TextView(ctx).apply {
            text = buildString {
                if (summary.isNotEmpty()) appendLine(summary)
                if (step.isNotEmpty()) appendLine("当前: $step")
                if (action.isNotEmpty()) appendLine("最近: $action")
                if (pauseReason.isNotEmpty()) appendLine("暂停: $pauseReason")
            }.trim().ifEmpty { if (active) "Agent 正在准备执行" else "启动 Agent 后，运行摘要和计划会显示在这里。" }
            textSize = 13f
            setTextColor(0xFF334155.toInt())
            setPadding(dp(ctx, 12), dp(ctx, 10), dp(ctx, 12), dp(ctx, 10))
            background = rounded(0xFFF8FAFC.toInt(), dp(ctx, 14), 0x1F64748B, 1)
        })
        val plan = mapValue(agentState["plan"])
        val items = listMaps(plan["items"] ?: agentState["items"])
        if (items.isNotEmpty()) {
            body.addView(TextView(ctx).apply {
                text = plan["title"]?.toString().orEmpty().ifEmpty { "Plan" }
                textSize = 13f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(0xFF0F172A.toInt())
                setPadding(0, dp(ctx, 12), 0, dp(ctx, 4))
            })
            items.forEachIndexed { index, item -> body.addView(agentPlanItem(ctx, index, item)) }
        }
        scroll.addView(body)
        content.addView(scroll, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            modeScrollHeight(ctx)
        ))
        if (active) {
            val paused = status.equals("paused", true) || run["canResume"] == true
            val row = LinearLayout(ctx).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.END
                setPadding(0, dp(ctx, 8), 0, 0)
            }
            row.addView(chip(ctx, if (paused) "继续" else "暂停", true) {
                channel?.invokeMethod(if (paused) "resumeAgent" else "pauseAgent", emptyMap<String, Any>())
            })
            row.addView(space(ctx, 8, 1))
            row.addView(chip(ctx, "停止", false) {
                channel?.invokeMethod("stopAgent", emptyMap<String, Any>())
            })
            content.addView(row)
        }
    }

    private fun modeStatus(ctx: Context) = TextView(ctx).apply {
        textSize = 12f
        setTextColor(0xFF64748B.toInt())
        setPadding(0, dp(ctx, 6), 0, 0)
    }

    private fun modeScroll(ctx: Context) = ScrollView(ctx).apply {
        isFillViewport = false
        overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS
    }

    private fun modeScrollHeight(ctx: Context): Int {
        if (scrollMessageHeight > 0) return scrollMessageHeight.coerceAtLeast(dp(ctx, 120))
        return if (persistedPanelHeight > 0) {
            (persistedPanelHeight - dp(ctx, 180)).coerceAtLeast(dp(ctx, 120))
        } else {
            dp(ctx, 280)
        }
    }

    private fun agentPlanItem(ctx: Context, index: Int, item: Map<String, Any?>) = TextView(ctx).apply {
        val status = item["status"]?.toString().orEmpty()
        val detail = item["error"]?.toString().orEmpty()
            .ifEmpty { item["resultSummary"]?.toString().orEmpty() }
            .ifEmpty { item["summary"]?.toString().orEmpty() }
        text = buildString {
            append("${index + 1}. ${item["title"]?.toString().orEmpty()}")
            if (status.isNotEmpty()) append(" [$status]")
            if (detail.isNotEmpty()) append("\n$detail")
        }
        textSize = 12f
        setTextColor(if (status == "failed") 0xFFDC2626.toInt() else 0xFF475569.toInt())
        setPadding(dp(ctx, 10), dp(ctx, 7), dp(ctx, 10), dp(ctx, 7))
    }

    private fun translationIsRunning(): Boolean {
        return translationState["translating"] == true ||
            translationState["isTranslating"] == true ||
            translationState["running"] == true ||
            translationState["automatic"] == true ||
            translationState["isAutomatic"] == true ||
            translationState["auto"] == true ||
            translationRunning
    }

    private fun updateBubbleState() {
        val newState = when {
            recordingPath != null || speechRecognizer != null -> BubbleState.RECORDING
            translationIsRunning() -> BubbleState.TRANSLATING
            agentState["active"] == true -> BubbleState.AGENT_RUNNING
            chatState["streaming"] == true -> BubbleState.STREAMING
            else -> BubbleState.IDLE
        }
        if (newState != bubbleState) {
            bubbleState = newState
            refreshBubbleAppearance()
        }
    }

    private fun refreshBubbleAppearance() {
        val ctx = activity ?: return
        val bub = bubble ?: return
        bub.background = rounded(bubbleColorForState(bubbleState), dp(ctx, 22))
        if (bubbleState != BubbleState.IDLE) {
            startPulse(bub)
        } else {
            stopPulse()
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
        chatInputDraft = if (current.isBlank()) text else "$current $text"
        edit.setText(chatInputDraft)
        edit.setSelection(edit.text.length)
    }

    private fun openLynAI() {
        val ctx = activity ?: return
        hidePanel()
        TranslationOverlayHost.clear()
        val intent = Intent(ctx, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }
        ctx.startActivity(intent)
        channel?.invokeMethod("openConversation", emptyMap<String, Any>())
    }

    private fun buildBubble(ctx: Context, layoutParams: WindowManager.LayoutParams): TextView {
        return TextView(ctx).apply {
            text = "AI"
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            background = rounded(bubbleColorForState(bubbleState), dp(ctx, 22))
            elevation = dp(ctx, 8).toFloat()
            setPadding(dp(ctx, 14), 0, dp(ctx, 14), 0)
            setOnTouchListener(DragTouchListener(ctx, layoutParams, {
                ctx.resources.displayMetrics.heightPixels - layoutParams.height
            }, { togglePanel() }, {
                channel?.invokeMethod(
                    "bubbleMoved",
                    mapOf("x" to layoutParams.x, "y" to layoutParams.y)
                )
            }))
        }
    }

    private fun hideKeyboard(ctx: Context) {
        val input = ctx.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        inputEdit?.windowToken?.let { input?.hideSoftInputFromWindow(it, 0) }
    }

    private fun bubbleLayoutParams(ctx: Context): WindowManager.LayoutParams {
        val dm = ctx.resources.displayMetrics
        val bubbleSize = dp(ctx, 56)
        val defaultX = (dm.widthPixels - dp(ctx, 72)).coerceAtLeast(0)
        val defaultY = dm.heightPixels / 3
        return WindowManager.LayoutParams(
            bubbleSize,
            bubbleSize,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                if (interactionEnabled) 0 else WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = FloatingAssistantGeometry.clampPosition(
                if (persistedBubbleX >= 0) persistedBubbleX else defaultX,
                dm.widthPixels - bubbleSize
            )
            y = FloatingAssistantGeometry.clampPosition(
                if (persistedBubbleY >= 0) persistedBubbleY else defaultY,
                dm.heightPixels - bubbleSize
            )
        }
    }

    private fun panelLayoutParams(ctx: Context): WindowManager.LayoutParams {
        val dm = ctx.resources.displayMetrics
        val availableWidth = dm.widthPixels - dp(ctx, 32)
        val width = FloatingAssistantGeometry.resizeDimension(
            if (persistedPanelWidth > 0) persistedPanelWidth else dp(ctx, 390),
            dp(ctx, 240),
            dp(ctx, 480),
            availableWidth
        )
        val height = if (persistedPanelHeight > 0) {
            FloatingAssistantGeometry.resizeDimension(
                persistedPanelHeight,
                dp(ctx, 200),
                dm.heightPixels * 7 / 10,
                dm.heightPixels
            )
        } else {
            WindowManager.LayoutParams.WRAP_CONTENT
        }
        return WindowManager.LayoutParams(
            width,
            height,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                if (interactionEnabled) 0 else WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = FloatingAssistantGeometry.clampPosition(
                if (persistedPanelX >= 0) persistedPanelX else dp(ctx, 16),
                dm.widthPixels - width
            )
            y = FloatingAssistantGeometry.clampPosition(
                if (persistedPanelY >= 0) persistedPanelY else dp(ctx, 72),
                dm.heightPixels - if (height > 0) height else dp(ctx, 240)
            )
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

    private fun mapValue(raw: Any?): Map<String, Any?> {
        @Suppress("UNCHECKED_CAST")
        return raw as? Map<String, Any?> ?: emptyMap()
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

    private class SuppressingLinearLayout(ctx: Context) : LinearLayout(ctx) {
        override fun dispatchTouchEvent(event: MotionEvent): Boolean {
            if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                LynAIAccessibilityService.instance?.suppressOwnTouch()
            }
            return super.dispatchTouchEvent(event)
        }
    }

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
        private val touchSlop = ViewConfiguration.get(ctx).scaledTouchSlop

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            val manager = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    LynAIAccessibilityService.instance?.suppressOwnTouch()
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
                    val viewWidth = view.width.takeIf { it > 0 } ?: params.width.coerceAtLeast(0)
                    params.x = FloatingAssistantGeometry.clampPosition(
                        params.x,
                        dm.widthPixels - viewWidth
                    )
                    params.y = FloatingAssistantGeometry.clampPosition(params.y, maxY)
                    try {
                        manager.updateViewLayout(view, params)
                    } catch (_: Exception) {
                        // View was detached asynchronously (screen off, hide,
                        // permission revoked) mid-gesture. Abort silently.
                    }
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    val moved = abs(event.rawX - downX) + abs(event.rawY - downY)
                    if (moved < touchSlop) {
                        click()
                    } else {
                        if (edgeSnap) {
                            val width = ctx.resources.displayMetrics.widthPixels
                            val inset = dp(ctx, 12)
                            val viewWidth = view.width.takeIf { it > 0 }
                                ?: params.width.coerceAtLeast(0)
                            params.x = if (params.x < width / 2) {
                                inset
                            } else {
                                width - viewWidth - inset
                            }
                            params.x = FloatingAssistantGeometry.clampPosition(
                                params.x,
                                width - viewWidth
                            )
                            try {
                                manager.updateViewLayout(view, params)
                            } catch (_: Exception) {
                            }
                        }
                        onDragEnd?.invoke()
                    }
                    return true
                }
                MotionEvent.ACTION_CANCEL -> {
                    onDragEnd?.invoke()
                    return true
                }
            }
            return false
        }

        private fun dp(ctx: Context, value: Int): Int {
            return (value * ctx.resources.displayMetrics.density).toInt()
        }
    }

    private class ResizeTouchListener(
        private val ctx: Context,
        private val targetView: View,
        private val panelParams: WindowManager.LayoutParams?,
        private val sizeBoundsProvider: () -> Pair<Pair<Int, Int>, Pair<Int, Int>>,
        private val onResized: (Int, Int) -> Unit
    ) : View.OnTouchListener {
        private var downX = 0f
        private var downY = 0f
        private var startWidth = 0
        private var startHeight = 0
        private var currentHeight = 0
        private var lastUpdate = 0L

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            val params = panelParams ?: return false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    LynAIAccessibilityService.instance?.suppressOwnTouch()
                    downX = event.rawX
                    downY = event.rawY
                    startWidth = params.width
                    startHeight = targetView.height
                    currentHeight = startHeight
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
                    params.width = FloatingAssistantGeometry.resizeDimension(
                        startWidth + (event.rawX - downX).toInt(),
                        minW,
                        maxW,
                        dm.widthPixels - dp(ctx, 8) - params.x
                    )
                    currentHeight = FloatingAssistantGeometry.resizeDimension(
                        startHeight + (event.rawY - downY).toInt(),
                        minH,
                        maxH,
                        dm.heightPixels - dp(ctx, 8) - params.y
                    )
                    params.height = currentHeight
                    val manager = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
                    try {
                        manager.updateViewLayout(targetView, params)
                    } catch (_: Exception) {
                    }
                    onResized(params.width, currentHeight)
                    return true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    onResized(params.width, currentHeight)
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
