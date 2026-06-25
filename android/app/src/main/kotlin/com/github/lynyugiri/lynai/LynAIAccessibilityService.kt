package com.github.lynyugiri.lynai

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class LynAIAccessibilityService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private val nodeCache = linkedMapOf<String, AccessibilityNodeInfo>()
    private var suppressTouchUntil = 0L
    private var lastScrollY = Int.MIN_VALUE
    private var lastScrollX = Int.MIN_VALUE
    private var lastScrollUpdateTime = 0L
    private val scrollSettledRunnable = Runnable {
        DeviceControlBridge.emit(mapOf("type" to "translation_scroll_settled"))
    }

    override fun onServiceConnected() {
        instance = this
        DeviceControlBridge.emit(mapOf("type" to "accessibility_service_reconnected"))
    }

    override fun onDestroy() {
        handler.removeCallbacks(scrollSettledRunnable)
        if (instance == this) instance = null
        clearNodeCache()
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val type = event?.eventType ?: return
        when (type) {
            AccessibilityEvent.TYPE_TOUCH_INTERACTION_START -> {
                if (System.currentTimeMillis() > suppressTouchUntil) {
                    DeviceControlBridge.emit(mapOf("type" to "user_touch"))
                }
            }
            AccessibilityEvent.TYPE_VIEW_SCROLLED -> {
                handleScrollEvent(event)
            }
        }
    }

    private fun handleScrollEvent(event: AccessibilityEvent) {
        val deltaY: Int
        val deltaX: Int
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            deltaY = event.scrollDeltaY.toInt()
            deltaX = event.scrollDeltaX.toInt()
        } else {
            val currentY = event.scrollY
            val currentX = event.scrollX
            deltaY = if (lastScrollY != Int.MIN_VALUE) currentY - lastScrollY else 0
            deltaX = if (lastScrollX != Int.MIN_VALUE) currentX - lastScrollX else 0
            lastScrollY = currentY
            lastScrollX = currentX
        }
        if (deltaX == 0 && deltaY == 0) return

        val now = System.currentTimeMillis()
        if (now - lastScrollUpdateTime >= 16) {
            lastScrollUpdateTime = now
            TranslationOverlayManager.onScrollDelta(deltaX, deltaY)
        }

        handler.removeCallbacks(scrollSettledRunnable)
        handler.postDelayed(scrollSettledRunnable, 500)
    }

    override fun onInterrupt() {
        handler.removeCallbacks(scrollSettledRunnable)
    }

    fun snapshot(): Map<String, Any?> {
        val root = rootInActiveWindow ?: return error("no_active_window", "当前没有可读取窗口")
        clearNodeCache()
        val rootMap = nodeMap(root, "0")
        return mapOf(
            "ok" to true,
            "result" to mapOf(
                "platform" to "android",
                "packageName" to (root.packageName?.toString() ?: ""),
                "windowTitle" to "",
                "timestamp" to System.currentTimeMillis().toString(),
                "roots" to listOf(rootMap)
            )
        )
    }

    fun screenContext(): Map<String, Any?> {
        val snapshot = snapshot()
        if (snapshot["ok"] != true) return snapshot
        @Suppress("UNCHECKED_CAST")
        val result = snapshot["result"] as? Map<String, Any?> ?: return snapshot
        val lines = mutableListOf<String>()
        val clickableNodes = mutableListOf<Map<String, Any?>>()
        val editableNodes = mutableListOf<Map<String, Any?>>()
        val scrollableNodes = mutableListOf<Map<String, Any?>>()
        @Suppress("UNCHECKED_CAST")
        val roots = result["roots"] as? List<Map<String, Any?>> ?: emptyList()
        roots.forEach {
            collectContextLines(it, lines)
            collectNodeSummaries(it, clickableNodes, editableNodes, scrollableNodes)
        }
        return mapOf(
            "ok" to true,
            "result" to mapOf(
                "platform" to "android",
                "packageName" to result["packageName"],
                "text" to lines.distinct().take(120).joinToString("\n"),
                "clickableNodes" to clickableNodes.take(80),
                "editableNodes" to editableNodes.take(30),
                "scrollableNodes" to scrollableNodes.take(30)
            )
        )
    }

    fun screenshot(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            result.success(error("unsupported_android_version", "无障碍截屏需要 Android 11 或更高版本"))
            return
        }
        try {
            takeScreenshot(Display.DEFAULT_DISPLAY, mainExecutor, object : TakeScreenshotCallback {
                override fun onSuccess(screenshot: ScreenshotResult) {
                    try {
                        val bitmap = Bitmap.wrapHardwareBuffer(screenshot.hardwareBuffer, screenshot.colorSpace)
                        if (bitmap == null) {
                            result.success(error("screenshot_failed", "系统未返回可用截图"))
                            return
                        }
                        val stream = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                        result.success(
                            mapOf(
                                "ok" to true,
                                "result" to mapOf(
                                    "mimeType" to "image/png",
                                    "width" to bitmap.width,
                                    "height" to bitmap.height,
                                    "dataBase64" to Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP),
                                    "timestamp" to System.currentTimeMillis().toString()
                                )
                            )
                        )
                    } finally {
                        screenshot.hardwareBuffer.close()
                    }
                }

                override fun onFailure(errorCode: Int) {
                    result.success(error("screenshot_failed", "系统截屏失败: $errorCode"))
                }
            })
        } catch (e: Exception) {
            result.success(error("screenshot_failed", "系统截屏异常: ${e.message ?: e.javaClass.simpleName}"))
        }
    }

    fun tap(args: Map<String, Any?>, result: MethodChannel.Result) {
        val x = number(args["x"]) ?: return result.success(error("invalid_arguments", "device.tap 缺少 x"))
        val y = number(args["y"]) ?: return result.success(error("invalid_arguments", "device.tap 缺少 y"))
        dispatch(pathTap(x.toFloat(), y.toFloat()), 1L, result)
    }

    fun tapRepeat(args: Map<String, Any?>, result: MethodChannel.Result) {
        val x = number(args["x"]) ?: return result.success(error("invalid_arguments", "device.tapRepeat 缺少 x"))
        val y = number(args["y"]) ?: return result.success(error("invalid_arguments", "device.tapRepeat 缺少 y"))
        val repeat = (number(args["repeat"])?.toInt() ?: 1).coerceIn(1, 1000)
        val interval = (number(args["intervalMs"])?.toLong() ?: 80L).coerceIn(16L, 10000L)
        runTapRepeat(x.toFloat(), y.toFloat(), repeat, interval, 0, result)
    }

    fun swipe(args: Map<String, Any?>, result: MethodChannel.Result) {
        val startX = number(args["startX"]) ?: return result.success(error("invalid_arguments", "device.swipe 缺少 startX"))
        val startY = number(args["startY"]) ?: return result.success(error("invalid_arguments", "device.swipe 缺少 startY"))
        val endX = number(args["endX"]) ?: return result.success(error("invalid_arguments", "device.swipe 缺少 endX"))
        val endY = number(args["endY"]) ?: return result.success(error("invalid_arguments", "device.swipe 缺少 endY"))
        val duration = (number(args["durationMs"])?.toLong() ?: 300L).coerceIn(50L, 10000L)
        val path = Path().apply {
            moveTo(startX.toFloat(), startY.toFloat())
            lineTo(endX.toFloat(), endY.toFloat())
        }
        dispatch(path, duration, result)
    }

    fun pressBack(): Map<String, Any?> {
        return mapOf("ok" to performGlobalAction(GLOBAL_ACTION_BACK))
    }

    fun inputText(args: Map<String, Any?>): Map<String, Any?> {
        val text = args["text"]?.toString() ?: return error("invalid_arguments", "device.inputText 缺少 text")
        val node = nodeArg(args) ?: findFocusedEditable(rootInActiveWindow)
            ?: return error("editable_not_found", "未找到可输入节点")
        val bundle = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        return mapOf("ok" to node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, bundle))
    }

    fun nodeAction(args: Map<String, Any?>): Map<String, Any?> {
        val action = args["action"]?.toString().orEmpty()
        val node = nodeArg(args) ?: return error("node_not_found", "节点不存在或已过期")
        val ok = when (action) {
            "click" -> node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            "longClick" -> node.performAction(AccessibilityNodeInfo.ACTION_LONG_CLICK)
            "focus" -> node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
            "clearFocus" -> node.performAction(AccessibilityNodeInfo.ACTION_CLEAR_FOCUS)
            "accessibilityFocus" -> node.performAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS)
            "clearAccessibilityFocus" -> node.performAction(AccessibilityNodeInfo.ACTION_CLEAR_ACCESSIBILITY_FOCUS)
            "scrollForward" -> node.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
            "scrollBackward" -> node.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)
            "scrollDown" -> node.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
            "scrollUp" -> node.performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)
            "setText", "clearText" -> {
                val text = args["text"]?.toString() ?: ""
                val bundle = Bundle().apply {
                    putCharSequence(
                        AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                        if (action == "clearText") "" else text
                    )
                }
                node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, bundle)
            }
            else -> return error("unsupported_action", "不支持的节点动作: $action")
        }
        if (!ok) return error("action_failed", "节点动作执行失败: $action")
        return mapOf("ok" to true, "action" to action)
    }

    private fun runTapRepeat(
        x: Float,
        y: Float,
        repeat: Int,
        intervalMs: Long,
        index: Int,
        result: MethodChannel.Result
    ) {
        if (index >= repeat) {
            result.success(mapOf("ok" to true, "clicked" to repeat))
            return
        }
        dispatch(pathTap(x, y), 1L, object : MethodChannel.Result {
            override fun success(value: Any?) {
                handler.postDelayed({ runTapRepeat(x, y, repeat, intervalMs, index + 1, result) }, intervalMs)
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                result.error(errorCode, errorMessage, errorDetails)
            }

            override fun notImplemented() = result.notImplemented()
        })
    }

    private fun dispatch(path: Path, durationMs: Long, result: MethodChannel.Result) {
        suppressTouchUntil = System.currentTimeMillis() + durationMs + 400L
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0L, durationMs))
            .build()
        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                result.success(mapOf("ok" to true))
            }

            override fun onCancelled(gestureDescription: GestureDescription?) {
                result.success(error("gesture_cancelled", "手势被系统取消"))
            }
        }, handler)
    }

    private fun nodeMap(node: AccessibilityNodeInfo, id: String): Map<String, Any?> {
        nodeCache[id] = AccessibilityNodeInfo.obtain(node)
        val bounds = Rect()
        node.getBoundsInScreen(bounds)
        val children = mutableListOf<Map<String, Any?>>()
        for (index in 0 until node.childCount) {
            node.getChild(index)?.let { child ->
                children.add(nodeMap(child, "$id.$index"))
            }
        }
        return mapOf(
            "id" to id,
            "text" to (node.text?.toString() ?: ""),
            "description" to (node.contentDescription?.toString() ?: ""),
            "className" to (node.className?.toString() ?: ""),
            "packageName" to (node.packageName?.toString() ?: ""),
            "viewId" to (node.viewIdResourceName ?: ""),
            "bounds" to mapOf(
                "left" to bounds.left,
                "top" to bounds.top,
                "right" to bounds.right,
                "bottom" to bounds.bottom
            ),
            "clickable" to node.isClickable,
            "longClickable" to node.isLongClickable,
            "scrollable" to node.isScrollable,
            "editable" to node.isEditable,
            "enabled" to node.isEnabled,
            "focused" to node.isFocused,
            "selected" to node.isSelected,
            "checked" to node.isChecked,
            "checkable" to node.isCheckable,
            "password" to node.isPassword,
            "visibleToUser" to node.isVisibleToUser,
            "actions" to actionNames(node),
            "children" to children
        )
    }

    private fun collectContextLines(node: Map<String, Any?>, lines: MutableList<String>) {
        val text = node["text"]?.toString().orEmpty().trim()
        val description = node["description"]?.toString().orEmpty().trim()
        if (text.isNotEmpty()) lines.add(text)
        if (description.isNotEmpty()) lines.add(description)
        @Suppress("UNCHECKED_CAST")
        val children = node["children"] as? List<Map<String, Any?>> ?: emptyList()
        children.forEach { collectContextLines(it, lines) }
    }

    private fun collectNodeSummaries(
        node: Map<String, Any?>,
        clickableNodes: MutableList<Map<String, Any?>>,
        editableNodes: MutableList<Map<String, Any?>>,
        scrollableNodes: MutableList<Map<String, Any?>>
    ) {
        if (node["clickable"] == true) clickableNodes.add(nodeSummary(node))
        if (node["editable"] == true) editableNodes.add(nodeSummary(node))
        if (node["scrollable"] == true) scrollableNodes.add(nodeSummary(node))
        @Suppress("UNCHECKED_CAST")
        val children = node["children"] as? List<Map<String, Any?>> ?: emptyList()
        children.forEach { collectNodeSummaries(it, clickableNodes, editableNodes, scrollableNodes) }
    }

    private fun nodeSummary(node: Map<String, Any?>): Map<String, Any?> {
        return mapOf(
            "id" to node["id"],
            "text" to node["text"],
            "description" to node["description"],
            "className" to node["className"],
            "viewId" to node["viewId"],
            "bounds" to node["bounds"],
            "actions" to node["actions"]
        )
    }

    private fun actionNames(node: AccessibilityNodeInfo): List<String> {
        val actions = mutableListOf<String>()
        node.actionList.forEach { action ->
            when (action.id) {
                AccessibilityNodeInfo.ACTION_CLICK -> actions.add("click")
                AccessibilityNodeInfo.ACTION_LONG_CLICK -> actions.add("longClick")
                AccessibilityNodeInfo.ACTION_FOCUS -> actions.add("focus")
                AccessibilityNodeInfo.ACTION_CLEAR_FOCUS -> actions.add("clearFocus")
                AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS -> actions.add("accessibilityFocus")
                AccessibilityNodeInfo.ACTION_CLEAR_ACCESSIBILITY_FOCUS -> actions.add("clearAccessibilityFocus")
                AccessibilityNodeInfo.ACTION_SET_TEXT -> actions.add("setText")
                AccessibilityNodeInfo.ACTION_SCROLL_FORWARD -> actions.add("scrollForward")
                AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD -> actions.add("scrollBackward")
            }
        }
        return actions.distinct()
    }

    private fun findFocusedEditable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.isFocused && node.isEditable) return node
        for (index in 0 until node.childCount) {
            val found = findFocusedEditable(node.getChild(index))
            if (found != null) return found
        }
        return null
    }

    private fun nodeArg(args: Map<String, Any?>): AccessibilityNodeInfo? {
        val id = args["nodeId"]?.toString() ?: args["id"]?.toString() ?: return null
        return nodeCache[id]
    }

    private fun pathTap(x: Float, y: Float): Path {
        return Path().apply {
            moveTo(x, y)
            lineTo(x, y)
        }
    }

    private fun clearNodeCache() {
        nodeCache.values.forEach { it.recycle() }
        nodeCache.clear()
    }

    private fun number(raw: Any?): Double? {
        return when (raw) {
            is Number -> raw.toDouble()
            is String -> raw.toDoubleOrNull()
            else -> null
        }
    }

    private fun error(code: String, message: String): Map<String, Any?> {
        return mapOf("ok" to false, "error" to mapOf("code" to code, "message" to message))
    }

    companion object {
        var instance: LynAIAccessibilityService? = null
            private set
    }
}
