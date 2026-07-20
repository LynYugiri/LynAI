package com.github.lynyugiri.lynai

import kotlin.math.max
import kotlin.math.min

data class OcrRect(val left: Float, val top: Float, val right: Float, val bottom: Float) {
    val width: Float get() = right - left
    val height: Float get() = bottom - top
    val centerX: Float get() = (left + right) / 2f
    val centerY: Float get() = (top + bottom) / 2f

    fun union(other: OcrRect) = OcrRect(
        min(left, other.left), min(top, other.top), max(right, other.right), max(bottom, other.bottom)
    )
}

data class OcrTextBlock(
    val text: String,
    val bounds: OcrRect,
    val orientation: Int,
    val confidence: Double,
    val angle: Double,
    val fontSize: Double,
    val source: Map<String, Any?>,
)

object OcrTextGrouper {
    fun group(rawBlocks: List<Map<String, Any?>>): List<Map<String, Any?>> {
        val blocks = rawBlocks.mapNotNull(::parse).sortedWith(
            compareBy<OcrTextBlock> { if (it.orientation == 1) 1 else 0 }
                .thenBy { if (it.orientation == 1) -it.bounds.centerX else it.bounds.centerY }
                .thenBy { if (it.orientation == 1) it.bounds.centerY else it.bounds.centerX }
        )
        val groups = mutableListOf<MutableList<OcrTextBlock>>()
        for (block in blocks) {
            val group = groups.lastOrNull()
            if (group != null && belongs(group.last(), block)) group += block else groups += mutableListOf(block)
        }
        return groups.mapIndexed { index, group -> serialize("g_${index + 1}", group) }
    }

    private fun belongs(a: OcrTextBlock, b: OcrTextBlock): Boolean {
        if (a.orientation != b.orientation) return false
        return if (a.orientation == 1) {
            val columnDistance = kotlin.math.abs(a.bounds.centerX - b.bounds.centerX)
            val gap = b.bounds.top - a.bounds.bottom
            columnDistance <= max(a.bounds.width, b.bounds.width) * 0.8f && gap <= max(a.bounds.height, b.bounds.height) * 1.25f
        } else {
            val lineDistance = kotlin.math.abs(a.bounds.centerY - b.bounds.centerY)
            val gap = b.bounds.left - a.bounds.right
            lineDistance <= max(a.bounds.height, b.bounds.height) * 0.65f && gap <= max(a.bounds.height, b.bounds.height) * 2f
        }
    }

    private fun serialize(id: String, blocks: List<OcrTextBlock>): Map<String, Any?> {
        val vertical = blocks.first().orientation == 1
        val bounds = blocks.drop(1).fold(blocks.first().bounds) { value, block -> value.union(block.bounds) }
        val text = blocks.joinToString(if (vertical) "\n" else " ") { it.text }
        return mapOf(
            "id" to id,
            "text" to text,
            "bounds" to bounds.toMap(),
            "displayBounds" to bounds.toMap(),
            "polygon" to listOf(
                mapOf("x" to bounds.left, "y" to bounds.top),
                mapOf("x" to bounds.right, "y" to bounds.top),
                mapOf("x" to bounds.right, "y" to bounds.bottom),
                mapOf("x" to bounds.left, "y" to bounds.bottom),
            ),
            "orientation" to if (vertical) 1 else 0,
            "confidence" to blocks.map { it.confidence }.average(),
            "angle" to blocks.map { it.angle }.average(),
            "fontSize" to blocks.map { it.fontSize }.sorted().let { values ->
                if (values.isEmpty()) 0.0 else values[values.size / 2]
            },
            "members" to blocks.map { it.source },
        )
    }

    private fun parse(raw: Map<String, Any?>): OcrTextBlock? {
        val text = raw["text"]?.toString()?.trim().orEmpty()
        val bounds = (raw["displayBounds"] as? Map<*, *>) ?: (raw["bounds"] as? Map<*, *>) ?: return null
        fun number(key: String) = (bounds[key] as? Number)?.toFloat()
        val rect = OcrRect(number("left") ?: return null, number("top") ?: return null, number("right") ?: return null, number("bottom") ?: return null)
        if (text.isEmpty() || rect.width <= 0f || rect.height <= 0f) return null
        return OcrTextBlock(
            text,
            rect,
            (raw["orientation"] as? Number)?.toInt() ?: 0,
            (raw["confidence"] as? Number)?.toDouble() ?: 0.0,
            (raw["angle"] as? Number)?.toDouble() ?: 0.0,
            (raw["fontSize"] as? Number)?.toDouble() ?: 0.0,
            raw,
        )
    }
}

fun OcrRect.toMap(): Map<String, Float> = mapOf("left" to left, "top" to top, "right" to right, "bottom" to bottom)
