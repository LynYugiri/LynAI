package com.github.lynyugiri.lynai

import org.junit.Assert.assertEquals
import org.junit.Test

class FloatingAssistantGeometryTest {
    @Test
    fun clampsPositionWhenWindowIsLargerThanAvailableSpace() {
        assertEquals(0, FloatingAssistantGeometry.clampPosition(80, -20))
        assertEquals(40, FloatingAssistantGeometry.clampPosition(80, 40))
    }

    @Test
    fun resizeDimensionRespectsBoundsAndRemainingScreenSpace() {
        assertEquals(240, FloatingAssistantGeometry.resizeDimension(120, 240, 480, 400))
        assertEquals(400, FloatingAssistantGeometry.resizeDimension(460, 240, 480, 400))
        assertEquals(180, FloatingAssistantGeometry.resizeDimension(300, 240, 480, 180))
    }
}
