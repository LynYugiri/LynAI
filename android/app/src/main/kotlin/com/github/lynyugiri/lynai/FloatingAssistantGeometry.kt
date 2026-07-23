package com.github.lynyugiri.lynai

internal object FloatingAssistantGeometry {
    fun clampPosition(value: Int, available: Int): Int {
        return value.coerceIn(0, available.coerceAtLeast(0))
    }

    fun resizeDimension(candidate: Int, minimum: Int, maximum: Int, available: Int): Int {
        val effectiveMaximum = minOf(maximum, available.coerceAtLeast(0))
        return if (effectiveMaximum >= minimum) {
            candidate.coerceIn(minimum, effectiveMaximum)
        } else {
            effectiveMaximum
        }
    }
}
