package com.github.lynyugiri.lynai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import android.view.KeyEvent

class FloatingAssistantInteractionTest {
    @Test
    fun backOnlyCollapsesPanelAfterKeyboardIsClosed() {
        assertEquals(
            false,
            FloatingAssistantInteraction.shouldCollapsePanelOnBack(
                KeyEvent.ACTION_UP,
                imeVisible = true
            )
        )
        assertEquals(
            true,
            FloatingAssistantInteraction.shouldCollapsePanelOnBack(
                KeyEvent.ACTION_UP,
                imeVisible = false
            )
        )
        assertEquals(
            false,
            FloatingAssistantInteraction.shouldCollapsePanelOnBack(
                KeyEvent.ACTION_DOWN,
                imeVisible = false
            )
        )
    }

    @Test
    fun floatingComposerOnlySendsOnControlEnterKeyDown() {
        assertEquals(
            true,
            FloatingAssistantInteraction.shouldSendComposerKey(
                KeyEvent.KEYCODE_ENTER,
                KeyEvent.ACTION_DOWN,
                controlPressed = true,
                composing = false
            )
        )
        assertEquals(
            false,
            FloatingAssistantInteraction.shouldSendComposerKey(
                KeyEvent.KEYCODE_ENTER,
                KeyEvent.ACTION_DOWN,
                controlPressed = false,
                composing = false
            )
        )
        assertEquals(
            false,
            FloatingAssistantInteraction.shouldSendComposerKey(
                KeyEvent.KEYCODE_ENTER,
                KeyEvent.ACTION_DOWN,
                controlPressed = true,
                composing = true
            )
        )
        assertEquals(
            false,
            FloatingAssistantInteraction.shouldSendComposerKey(
                KeyEvent.KEYCODE_ENTER,
                KeyEvent.ACTION_UP,
                controlPressed = true,
                composing = false
            )
        )
    }

    @Test
    fun buildsNormalizedTextAndChoiceAnswers() {
        assertEquals(
            mapOf("answer" to mapOf("kind" to "text", "text" to "hello")),
            FloatingAssistantInteraction.answerPayload("text", text = "  hello  ")
        )
        assertEquals(
            mapOf(
                "answer" to mapOf(
                    "kind" to "multipleChoice",
                    "choiceIds" to listOf("a", "b")
                )
            ),
            FloatingAssistantInteraction.answerPayload(
                "multipleChoice",
                choiceIds = listOf("a", "a", "b")
            )
        )
    }

    @Test
    fun rejectsIncompleteAnswers() {
        assertNull(FloatingAssistantInteraction.answerPayload("text", text = "  "))
        assertNull(FloatingAssistantInteraction.answerPayload("confirm"))
        assertNull(FloatingAssistantInteraction.answerPayload("singleChoice"))
        assertNull(FloatingAssistantInteraction.answerPayload("unknown"))
    }
}
