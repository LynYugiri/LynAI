package com.github.lynyugiri.lynai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FloatingAssistantInteractionTest {
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
