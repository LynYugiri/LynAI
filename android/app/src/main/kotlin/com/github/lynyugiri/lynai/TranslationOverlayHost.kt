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
    ) {
        if (!canDrawOverlays(context)) return
        val blocks = TranslationOverlayBlock.fromArguments(args, layoutMode, targetLanguage)
        if (blocks.isEmpty()) return clear()
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
            } catch (_: Exception) {
                overlayView = null
                return
            }
        }
        view.setScene(blocks, TranslationOverlayStyle.from(overlayStyle, opacity))
    }

    fun onScrollDelta(deltaX: Int, deltaY: Int) {
        overlayView?.scrollSceneBy(-deltaX.toFloat(), -deltaY.toFloat())
    }

    fun clear() {
        val view = overlayView ?: return
        try {
            windowManager?.removeView(view)
        } catch (_: Exception) {
        }
        overlayView = null
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
}
