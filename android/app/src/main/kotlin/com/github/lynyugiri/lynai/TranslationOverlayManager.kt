package com.github.lynyugiri.lynai

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import kotlin.math.min

object TranslationOverlayManager {
    private var windowManager: WindowManager? = null
    private val activeOverlays = mutableListOf<OverlayEntry>()
    private val viewPool = mutableListOf<TextView>()
    private var maxBlocks = 30

    private data class OverlayEntry(
        val view: TextView,
        val params: WindowManager.LayoutParams,
        val originalText: String,
        val blockId: String,
    )

    fun setBlocks(
        context: Context,
        args: Map<String, Any?>,
        overlayStyle: String,
        opacity: Double,
        layoutMode: String,
    ) {
        if (!canDrawOverlays(context)) return
        val wm = windowManager
            ?: (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).also {
                windowManager = it
            }

        val blocks = (args["blocks"] as? List<*>) ?: emptyList<Any?>()
        clear()

        for (blockRaw in blocks.take(maxBlocks)) {
            val block = blockRaw as? Map<*, *> ?: continue
            val text = block["translatedText"]?.toString().orEmpty().trim()
            if (text.isEmpty()) continue
            val bounds = block["bounds"] as? Map<*, *>
            val left = (bounds?.get("left") as? Number)?.toInt() ?: continue
            val top = (bounds?.get("top") as? Number)?.toInt() ?: continue
            val right = (bounds?.get("right") as? Number)?.toInt() ?: continue
            val bottom = (bounds?.get("bottom") as? Number)?.toInt() ?: continue
            val w = (right - left).coerceAtLeast(dp(context, 40))
            val h = (bottom - top).coerceAtLeast(dp(context, 24))
            val blockId = block["id"]?.toString() ?: text.hashCode().toString()

            val view = obtainView(context)
            applyStyle(view, text, overlayStyle, opacity, layoutMode, w, h)

            val params = WindowManager.LayoutParams(
                w,
                h,
                overlayType(),
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                    or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = left
                y = top
            }

            try {
                wm.addView(view, params)
                activeOverlays.add(OverlayEntry(view, params, text, blockId))
            } catch (_: Exception) {
                recycleView(view)
            }
        }
    }

    fun onScrollDelta(deltaX: Int, deltaY: Int) {
        val wm = windowManager ?: return
        val iterator = activeOverlays.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            entry.params.x -= deltaX
            entry.params.y -= deltaY
            val dm = entry.view.context.resources.displayMetrics
            val onScreen = entry.params.x + entry.params.width > 0 &&
                entry.params.x < dm.widthPixels &&
                entry.params.y + entry.params.height > 0 &&
                entry.params.y < dm.heightPixels
            if (onScreen) {
                try {
                    wm.updateViewLayout(entry.view, entry.params)
                } catch (_: Exception) {
                    iterator.remove()
                    recycleView(entry.view)
                }
            } else {
                try {
                    wm.removeView(entry.view)
                } catch (_: Exception) {
                }
                iterator.remove()
                recycleView(entry.view)
            }
        }
    }

    fun clear() {
        val wm = windowManager ?: return
        for (entry in activeOverlays) {
            try {
                wm.removeView(entry.view)
            } catch (_: Exception) {
            }
            recycleView(entry.view)
        }
        activeOverlays.clear()
    }

    fun dispose() {
        clear()
        for (view in viewPool) {
            try {
                (view.context.getSystemService(Context.WINDOW_SERVICE) as WindowManager)
                    .removeView(view)
            } catch (_: Exception) {
            }
        }
        viewPool.clear()
        windowManager = null
    }

    private fun obtainView(context: Context): TextView {
        return if (viewPool.isNotEmpty()) viewPool.removeAt(0) else TextView(context)
    }

    private fun recycleView(view: TextView) {
        if (viewPool.size < maxBlocks) {
            viewPool.add(view)
        }
    }

    private fun applyStyle(
        view: TextView,
        text: String,
        style: String,
        opacity: Double,
        layoutMode: String,
        width: Int,
        height: Int,
    ) {
        view.text = text
        view.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        view.setPadding(dp(view.context, 4), dp(view.context, 2), dp(view.context, 4), dp(view.context, 2))
        view.alpha = opacity.toFloat()
        when (style) {
            "dark" -> {
                view.setBackgroundColor(Color.argb(220, 0, 0, 0))
                view.setTextColor(Color.WHITE)
                view.setShadowLayer(0f, 0f, 0f, Color.TRANSPARENT)
            }
            "stroke" -> {
                view.setBackgroundColor(Color.TRANSPARENT)
                view.setTextColor(Color.WHITE)
                view.setShadowLayer(3f, 0f, 0f, Color.BLACK)
            }
            else -> {
                // `auto` 样式没有额外信息可拟合，退化为浅色实底。
                view.setBackgroundColor(Color.argb(220, 255, 255, 255))
                view.setTextColor(Color.parseColor("#0F172A"))
                view.setShadowLayer(0f, 0f, 0f, Color.TRANSPARENT)
            }
        }
        // A5: 让译文排布真正按横排/竖排改变呈现方式。
        // auto：以块宽高比自动决定；vertical：窄列单行居中；horizontal：宽松多行换行。
        val portrait = height > width
        val asVertical = when (layoutMode) {
            "vertical" -> true
            "horizontal" -> false
            else -> portrait
        }
        if (asVertical) {
            view.gravity = Gravity.CENTER
            view.maxLines = 1
            view.ellipsize = null
            // 强制单列，避免译文溢出到相邻文本块
            view.setLines(1)
        } else {
            view.gravity = Gravity.CENTER
            view.maxLines = 0
            view.setLines(0)
            view.ellipsize = null
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

    private fun canDrawOverlays(context: Context): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)
    }

    private fun dp(context: Context, value: Int): Int {
        return (value * context.resources.displayMetrics.density).toInt()
    }
}
