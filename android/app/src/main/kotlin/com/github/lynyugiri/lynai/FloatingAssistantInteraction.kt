package com.github.lynyugiri.lynai

import android.view.KeyEvent

object FloatingAssistantInteraction {
    fun shouldCollapsePanelOnBack(action: Int, imeVisible: Boolean): Boolean =
        action == KeyEvent.ACTION_UP && !imeVisible

    fun shouldSendComposerKey(
        keyCode: Int,
        action: Int,
        controlPressed: Boolean,
        composing: Boolean
    ): Boolean = keyCode == KeyEvent.KEYCODE_ENTER &&
        action == KeyEvent.ACTION_DOWN &&
        controlPressed &&
        !composing

    fun answerPayload(
        kind: String,
        text: String = "",
        confirmed: Boolean? = null,
        choiceIds: Collection<String> = emptyList()
    ): Map<String, Any?>? {
        val answer = when (kind) {
            "text" -> text.trim().takeIf { it.isNotEmpty() }?.let {
                mapOf("kind" to kind, "text" to it)
            }
            "confirm" -> confirmed?.let {
                mapOf("kind" to kind, "confirmed" to it)
            }
            "singleChoice" -> choiceIds.singleOrNull()?.let {
                mapOf("kind" to kind, "choiceIds" to listOf(it))
            }
            "multipleChoice" -> mapOf(
                "kind" to kind,
                "choiceIds" to choiceIds.distinct()
            )
            else -> null
        } ?: return null
        return mapOf("answer" to answer)
    }
}
