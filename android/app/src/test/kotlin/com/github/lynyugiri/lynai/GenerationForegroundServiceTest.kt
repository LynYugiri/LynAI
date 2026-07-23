package com.github.lynyugiri.lynai

import org.junit.Assert.assertEquals
import org.junit.Test

class GenerationForegroundServiceTest {
    @Test
    fun onlyExplicitStartActionStartsForegroundGeneration() {
        assertEquals(
            GenerationServiceCommand.START,
            GenerationForegroundService.commandForAction(
                GenerationForegroundService.ACTION_START
            )
        )
        assertEquals(
            GenerationServiceCommand.STOP,
            GenerationForegroundService.commandForAction(
                GenerationForegroundService.ACTION_STOP
            )
        )
        assertEquals(
            GenerationServiceCommand.STOP,
            GenerationForegroundService.commandForAction(null)
        )
        assertEquals(
            GenerationServiceCommand.STOP,
            GenerationForegroundService.commandForAction("unexpected")
        )
    }
}
