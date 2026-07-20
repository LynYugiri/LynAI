package com.github.lynyugiri.lynai

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.view.Choreographer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque

class ScreenTranslationPipeline(private val activity: Activity) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingCaptures = ArrayDeque<MethodChannel.Result>()
    private var capturing = false

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "captureAndRecognize" -> captureAndRecognize(result)
            "showTranslations" -> {
                val args = arguments(call.arguments)
                TranslationOverlayHost.setBlocks(
                    activity,
                    args,
                    args["style"]?.toString() ?: "auto",
                    (args["opacity"] as? Number)?.toDouble() ?: 0.92,
                    args["layoutMode"]?.toString() ?: "auto",
                    args["targetLanguage"]?.toString() ?: "zh-CN",
                )
                result.success(mapOf("ok" to true))
            }
            "clearTranslations" -> {
                TranslationOverlayHost.clear()
                result.success(mapOf("ok" to true))
            }
            "scrollSceneBy" -> {
                val args = arguments(call.arguments)
                TranslationOverlayHost.onScrollDelta(
                    (args["deltaX"] as? Number)?.toInt() ?: 0,
                    (args["deltaY"] as? Number)?.toInt() ?: 0,
                )
                result.success(mapOf("ok" to true))
            }
            else -> result.notImplemented()
        }
    }

    private fun captureAndRecognize(result: MethodChannel.Result) {
        if (capturing) {
            pendingCaptures.addLast(result)
            return
        }
        capturing = true
        runCapture(result)
    }

    private fun runCapture(result: MethodChannel.Result) {
        val service = LynAIAccessibilityService.instance
        if (service == null) {
            finishCapture()
            result.success(error("accessibility_unavailable", "Accessibility service is not connected"))
            return
        }
        FloatingAssistantOverlay.hideForScreenTranslation()
        waitForCleanFrame {
            service.captureBitmap { capture ->
                val bitmap = capture.getOrElse {
                    finishCapture()
                    result.success(error("screenshot_failed", it.message ?: "Screenshot failed"))
                    return@captureBitmap
                }
                NcnnOcrRecognizer.recognize(bitmap) { response ->
                    val width = bitmap.width
                    val height = bitmap.height
                    bitmap.recycle()
                    finishCapture()
                    if (response["ok"] != true) {
                        result.success(response)
                        return@recognize
                    }
                    @Suppress("UNCHECKED_CAST")
                    val blocks = response["result"] as? List<Map<String, Any?>> ?: emptyList()
                    val packageName = service.currentExternalPackageName()
                    val groups = OcrTextGrouper.group(blocks).map { group ->
                        group + ("packageName" to packageName)
                    }
                    result.success(
                        mapOf(
                            "ok" to true,
                            "result" to mapOf(
                                "blocks" to blocks,
                                "groups" to groups,
                                "packageName" to packageName,
                                "width" to width,
                                "height" to height,
                                "timestamp" to System.currentTimeMillis().toString(),
                            ),
                        )
                    )
                }
            }
        }
    }

    private fun waitForCleanFrame(action: () -> Unit) {
        Choreographer.getInstance().postFrameCallback {
            Choreographer.getInstance().postFrameCallback {
                mainHandler.postDelayed(action, 32L)
            }
        }
    }

    private fun finishCapture() {
        FloatingAssistantOverlay.restoreAfterScreenTranslation()
        val next = if (pendingCaptures.isEmpty()) null else pendingCaptures.removeFirst()
        if (next == null) {
            capturing = false
        } else {
            mainHandler.post { runCapture(next) }
        }
    }

    private fun arguments(value: Any?): Map<String, Any?> {
        @Suppress("UNCHECKED_CAST")
        return value as? Map<String, Any?> ?: emptyMap()
    }

    private fun error(code: String, message: String) = mapOf(
        "ok" to false,
        "error" to mapOf("code" to code, "message" to message),
    )
}
