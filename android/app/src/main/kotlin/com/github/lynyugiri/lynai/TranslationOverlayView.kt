package com.github.lynyugiri.lynai

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.view.View
import kotlin.math.floor
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
        val padding = max(2f, box.height() * 0.08f)
        val layout = horizontalLayout(
            block.text,
            box.width() - padding * 2,
            box.height() - padding * 2,
        ) ?: return
        canvas.save()
        canvas.clipRect(box)
        drawBackground(canvas, box)
        configureText(layout.size)
        val metrics = paint.fontMetrics
        val lineHeight = paint.fontSpacing
        var baseline = box.top + padding - metrics.top
        layout.lines.forEach { line ->
            canvas.drawText(line, box.left + padding, baseline, paint)
            baseline += lineHeight
        }
        canvas.restore()
    }

    private fun drawVertical(canvas: Canvas, block: TranslationOverlayBlock) {
        val box = block.bounds
        val glyphs = block.text.codePoints().toArray().map { String(Character.toChars(it)) }.filterNot { it == "\n" || it == "\r" }
        if (glyphs.isEmpty()) return
        val padding = max(2f, minOf(box.width(), box.height()) * 0.06f)
        val layout = verticalLayout(
            glyphs,
            box.width() - padding * 2,
            box.height() - padding * 2,
        ) ?: return
        canvas.save()
        canvas.clipRect(box)
        drawBackground(canvas, box)
        configureText(layout.size)
        val metrics = paint.fontMetrics
        layout.glyphs.forEachIndexed { index, glyph ->
            val column = index / layout.rows
            val row = index % layout.rows
            val centerX = box.right - padding - layout.columnWidth * (column + 0.5f)
            val centerY = box.top + padding + layout.rowHeight * (row + 0.5f)
            val x = centerX - paint.measureText(glyph) / 2f
            val y = centerY - (metrics.ascent + metrics.descent) / 2f
            canvas.drawText(glyph, x, y, paint)
        }
        canvas.restore()
    }

    private fun horizontalLayout(text: String, width: Float, height: Float): HorizontalLayout? {
        if (width < MIN_TEXT_SIZE || height < MIN_TEXT_SIZE) return null
        var low = MIN_TEXT_SIZE
        var high = MAX_TEXT_SIZE
        var best: HorizontalLayout? = null
        repeat(8) {
            val size = (low + high) / 2f
            val layout = horizontalLayoutAtSize(text, width, height, size, false)
            if (layout == null) high = size else {
                best = layout
                low = size
            }
        }
        return best ?: horizontalLayoutAtSize(text, width, height, MIN_TEXT_SIZE, true)
    }

    private fun horizontalLayoutAtSize(
        text: String,
        width: Float,
        height: Float,
        size: Float,
        truncate: Boolean,
    ): HorizontalLayout? {
        paint.textSize = size
        val maxLines = floor(height / paint.fontSpacing).toInt()
        if (maxLines < 1) return null
        val wrapped = text.lines().flatMap { wrap(it, width) }
        if (wrapped.isEmpty()) return null
        if (wrapped.size <= maxLines) return HorizontalLayout(size, wrapped)
        if (!truncate) return null
        val visible = wrapped.take(maxLines).toMutableList()
        visible[visible.lastIndex] = ellipsize(visible.last(), width)
        return HorizontalLayout(size, visible)
    }

    private fun wrap(text: String, width: Float): List<String> {
        if (text.isEmpty()) return listOf("")
        val lines = mutableListOf<String>()
        var start = 0
        while (start < text.length) {
            val count = paint.breakText(text, start, text.length, true, width, null)
            if (count <= 0) return emptyList()
            lines += text.substring(start, start + count)
            start += count
        }
        return lines
    }

    private fun ellipsize(text: String, width: Float): String {
        val ellipsis = "…"
        if (paint.measureText(ellipsis) > width) return ""
        var result = text
        while (result.isNotEmpty() && paint.measureText(result + ellipsis) > width) {
            result = result.substring(0, result.offsetByCodePoints(result.length, -1))
        }
        return result + ellipsis
    }

    private fun verticalLayout(glyphs: List<String>, width: Float, height: Float): VerticalLayout? {
        if (width < MIN_TEXT_SIZE || height < MIN_TEXT_SIZE) return null
        var low = MIN_TEXT_SIZE
        var high = MAX_TEXT_SIZE
        var best: VerticalLayout? = null
        repeat(8) {
            val size = (low + high) / 2f
            val layout = verticalLayoutAtSize(glyphs, width, height, size, false)
            if (layout == null) high = size else {
                best = layout
                low = size
            }
        }
        return best ?: verticalLayoutAtSize(glyphs, width, height, MIN_TEXT_SIZE, true)
    }

    private fun verticalLayoutAtSize(
        glyphs: List<String>,
        width: Float,
        height: Float,
        size: Float,
        truncate: Boolean,
    ): VerticalLayout? {
        paint.textSize = size
        val columnWidth = maxOf(size, paint.measureText("…"), glyphs.maxOfOrNull(paint::measureText) ?: size)
        val rowHeight = paint.fontSpacing
        val rows = floor(height / rowHeight).toInt()
        val columns = floor(width / columnWidth).toInt()
        val capacity = rows * columns
        if (rows < 1 || columns < 1 || capacity < 1) return null
        if (glyphs.size <= capacity) return VerticalLayout(size, rows, columnWidth, rowHeight, glyphs)
        if (!truncate) return null
        val visible = glyphs.take(capacity).toMutableList()
        visible[visible.lastIndex] = "…"
        return VerticalLayout(size, rows, columnWidth, rowHeight, visible)
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

    private data class HorizontalLayout(val size: Float, val lines: List<String>)

    private data class VerticalLayout(
        val size: Float,
        val rows: Int,
        val columnWidth: Float,
        val rowHeight: Float,
        val glyphs: List<String>,
    )

    private companion object {
        const val MIN_TEXT_SIZE = 8f
        const val MAX_TEXT_SIZE = 48f
    }
}
