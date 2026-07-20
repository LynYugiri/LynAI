package com.github.lynyugiri.lynai

import org.junit.Assert.assertEquals
import org.junit.Test

class OcrTextGrouperTest {
    @Test
    fun groupsHorizontalNeighborsInReadingOrder() {
        val groups = OcrTextGrouper.group(
            listOf(
                block("world", 42, 10, 80, 30),
                block("hello", 0, 10, 38, 30),
                block("next", 0, 60, 40, 80),
            )
        )

        assertEquals(2, groups.size)
        assertEquals("g_1", groups[0]["id"])
        assertEquals("hello world", groups[0]["text"])
        assertEquals("next", groups[1]["text"])
    }

    @Test
    fun groupsVerticalTopToBottomAndColumnsRightToLeft() {
        val groups = OcrTextGrouper.group(
            listOf(
                block("下", 80, 35, 100, 55, 1),
                block("上", 80, 10, 100, 30, 1),
                block("左", 40, 10, 60, 30, 1),
            )
        )

        assertEquals(listOf("上\n下", "左"), groups.map { it["text"] })
        assertEquals(listOf("g_1", "g_2"), groups.map { it["id"] })
    }

    private fun block(text: String, left: Int, top: Int, right: Int, bottom: Int, orientation: Int = 0): Map<String, Any?> = mapOf(
        "text" to text,
        "displayBounds" to mapOf("left" to left, "top" to top, "right" to right, "bottom" to bottom),
        "orientation" to orientation,
        "confidence" to 0.9,
    )
}
