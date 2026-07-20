package com.github.lynyugiri.lynai

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.view.View
import kotlin.math.max

data class TranslationOverlayBlock(
    val id: String,
    val text: String,
    val bounds: RectF,
    val vertical: Boolean,
) {
    companion object {
        fun fromArguments(
            args: Map<String, Any?>,
            layoutMode: String,
            targetLanguage: String,
        ): List<TranslationOverlayBlock> {
            val rawBlocks = args["blocks"] as? List<*> ?: return emptyList()
            return rawBlocks.mapNotNull { raw ->
                val block = raw as? Map<*, *> ?: return@mapNotNull null
                val text = block["translatedText"]?.toString()?.trim().orEmpty()
                val bounds = (block["displayBounds"] as? Map<*, *>) ?: (block["bounds"] as? Map<*, *>) ?: return@mapNotNull null
                fun value(key: String) = (bounds[key] as? Number)?.toFloat()
                val rect = RectF(value("left") ?: return@mapNotNull null, value("top") ?: return@mapNotNull null, value("right") ?: return@mapNotNull null, value("bottom") ?: return@mapNotNull null)
                if (text.isEmpty() || rect.width() <= 0f || rect.height() <= 0f) return@mapNotNull null
                val orientation = (block["orientation"] as? Number)?.toInt() ?: 0
                val cjkTarget = targetLanguage == "zh-CN" || targetLanguage == "zh-TW" ||
                    targetLanguage == "ja" || targetLanguage == "ko"
                val vertical = when (layoutMode) {
                    "vertical" -> true
                    "horizontal" -> false
                    else -> cjkTarget && (orientation == 1 || rect.height() > rect.width() * 1.25f)
                }
                TranslationOverlayBlock(block["id"]?.toString() ?: text.hashCode().toString(), text, rect, vertical)
            }
        }
    }
}

data class TranslationOverlayStyle(val background: Int, val foreground: Int, val alpha: Int, val stroke: Boolean) {
    companion object {
        fun from(name: String, opacity: Double): TranslationOverlayStyle {
            val alpha = (opacity.coerceIn(0.0, 1.0) * 255).toInt()
            return when (name) {
                "dark" -> TranslationOverlayStyle(Color.BLACK, Color.WHITE, alpha, false)
                "stroke" -> TranslationOverlayStyle(Color.TRANSPARENT, Color.WHITE, alpha, true)
                else -> TranslationOverlayStyle(Color.WHITE, Color.rgb(15, 23, 42), alpha, false)
            }
        }
    }
}

class TranslationOverlayView(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = Typeface.DEFAULT }
    private var blocks: List<TranslationOverlayBlock> = emptyList()
    private var style = TranslationOverlayStyle.from("auto", 0.92)
    private var offsetX = 0f
    private var offsetY = 0f

    fun setScene(blocks: List<TranslationOverlayBlock>, style: TranslationOverlayStyle) {
        this.blocks = blocks
        this.style = style
        offsetX = 0f
        offsetY = 0f
        invalidate()
    }

    fun scrollSceneBy(dx: Float, dy: Float) {
        offsetX += dx
        offsetY += dy
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.save()
        canvas.translate(offsetX, offsetY)
        blocks.forEach { if (it.vertical) drawVertical(canvas, it) else drawHorizontal(canvas, it) }
        canvas.restore()
    }

    private fun drawHorizontal(canvas: Canvas, block: TranslationOverlayBlock) {
        val box = block.bounds
        drawBackground(canvas, box)
        val padding = max(2f, box.height() * 0.08f)
        val availableWidth = max(1f, box.width() - padding * 2)
        val availableHeight = max(1f, box.height() - padding * 2)
        val lines = block.text.lines().flatMap { wrap(it, availableWidth, availableHeight) }
        val size = fittedSize(lines, availableWidth, availableHeight)
        configureText(size)
        val lineHeight = size * 1.15f
        var baseline = box.top + padding - paint.fontMetrics.top
        lines.forEach { line ->
            if (baseline > box.bottom - padding - paint.fontMetrics.bottom) return@forEach
            canvas.drawText(line, box.left + padding, baseline, paint)
            baseline += lineHeight
        }
    }

    private fun drawVertical(canvas: Canvas, block: TranslationOverlayBlock) {
        val box = block.bounds
        drawBackground(canvas, box)
        val glyphs = block.text.codePoints().toArray().map { String(Character.toChars(it)) }.filterNot { it == "\n" || it == "\r" }
        if (glyphs.isEmpty()) return
        val padding = max(2f, minOf(box.width(), box.height()) * 0.06f)
        val maxRows = max(1, (box.height() / 10f).toInt())
        val columns = (glyphs.size + maxRows - 1) / maxRows
        val size = minOf((box.height() - padding * 2) / minOf(glyphs.size, maxRows), (box.width() - padding * 2) / max(1, columns)).coerceIn(8f, 48f)
        configureText(size)
        glyphs.forEachIndexed { index, glyph ->
            val column = index / maxRows
            val row = index % maxRows
            val x = box.right - padding - size * (column + 0.5f) - paint.measureText(glyph) / 2f
            val y = box.top + padding + size * (row + 1) - paint.fontMetrics.bottom
            canvas.drawText(glyph, x, y, paint)
        }
    }

    private fun wrap(text: String, width: Float, height: Float): List<String> {
        if (text.isEmpty()) return listOf("")
        paint.textSize = height.coerceIn(8f, 48f)
        val lines = mutableListOf<String>()
        var start = 0
        while (start < text.length) {
            val count = paint.breakText(text, start, text.length, true, width, null).coerceAtLeast(1)
            lines += text.substring(start, start + count)
            start += count
        }
        return lines
    }

    private fun fittedSize(lines: List<String>, width: Float, height: Float): Float {
        var low = 8f
        var high = 48f
        repeat(8) {
            val mid = (low + high) / 2f
            paint.textSize = mid
            val fits = lines.size * mid * 1.15f <= height && lines.maxOfOrNull { paint.measureText(it) }?.let { it <= width } != false
            if (fits) low = mid else high = mid
        }
        return low
    }

    private fun drawBackground(canvas: Canvas, box: RectF) {
        if (style.background == Color.TRANSPARENT) return
        paint.style = Paint.Style.FILL
        paint.color = Color.argb(style.alpha, Color.red(style.background), Color.green(style.background), Color.blue(style.background))
        canvas.drawRect(box, paint)
    }

    private fun configureText(size: Float) {
        paint.style = Paint.Style.FILL
        paint.textSize = size
        paint.color = Color.argb(style.alpha, Color.red(style.foreground), Color.green(style.foreground), Color.blue(style.foreground))
        if (style.stroke) paint.setShadowLayer(3f, 0f, 0f, Color.BLACK) else paint.clearShadowLayer()
    }
}
