package com.github.lynyugiri.lynai

import android.content.Context
import android.graphics.PixelFormat
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.WindowManager

object TranslationOverlayHost {
    private var windowManager: WindowManager? = null
    private var overlayView: TranslationOverlayView? = null

    fun setBlocks(
        context: Context,
        args: Map<String, Any?>,
        overlayStyle: String,
        opacity: Double,
        layoutMode: String,
        targetLanguage: String = "zh-CN",
    ): Map<String, Any?> {
        if (!canDrawOverlays(context)) {
            return error("overlay_permission_denied", "Display over other apps permission is required")
        }
        val rawBlocks = args["blocks"] as? List<*> ?: emptyList<Any?>()
        val blocks = TranslationOverlayBlock.fromArguments(args, layoutMode, targetLanguage)
        if (blocks.size != rawBlocks.size) {
            return error("invalid_overlay_blocks", "Translation blocks contain invalid text or geometry")
        }
        if (blocks.isEmpty()) {
            return clear()
        }
        val wm = windowManager ?: (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).also { windowManager = it }
        val view = overlayView ?: TranslationOverlayView(context).also {
            overlayView = it
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                overlayType(),
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT,
            ).apply { gravity = Gravity.TOP or Gravity.START }
            try {
                wm.addView(it, params)
            } catch (exception: Exception) {
                overlayView = null
                return error("overlay_add_failed", exception.message ?: "Unable to display translation overlay")
            }
        }
        view.setScene(blocks, TranslationOverlayStyle.from(overlayStyle, opacity))
        return success("blockCount" to blocks.size)
    }

    fun onScrollDelta(deltaX: Int, deltaY: Int) {
        overlayView?.scrollSceneBy(-deltaX.toFloat(), -deltaY.toFloat())
    }

    fun clear(): Map<String, Any?> {
        val view = overlayView ?: return success()
        return try {
            windowManager?.removeView(view)
            success()
        } catch (exception: Exception) {
            error("overlay_remove_failed", exception.message ?: "Unable to remove translation overlay")
        } finally {
            overlayView = null
        }
    }

    fun dispose() {
        clear()
        windowManager = null
    }

    private fun overlayType() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
    } else {
        @Suppress("DEPRECATION")
        WindowManager.LayoutParams.TYPE_PHONE
    }

    private fun canDrawOverlays(context: Context) =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    private fun success(vararg values: Pair<String, Any?>) = mapOf("ok" to true, *values)

    private fun error(code: String, message: String) = mapOf(
        "ok" to false,
        "error" to mapOf("code" to code, "message" to message),
    )
}
