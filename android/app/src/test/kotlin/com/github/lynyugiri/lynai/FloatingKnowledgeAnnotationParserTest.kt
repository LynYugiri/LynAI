package com.github.lynyugiri.lynai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FloatingKnowledgeAnnotationParserTest {
    @Test
    fun parsesStrictAnnotationsAndTrimsCategoryAndText() {
        val source = "before [[ person : text ]] after [[kind:value]]"

        val annotations = FloatingKnowledgeAnnotationParser.parse(source)

        assertEquals(listOf("person", "kind"), annotations.map { it.category })
        assertEquals(listOf("text", "value"), annotations.map { it.text })
        assertEquals("[[ person : text ]]", source.substring(annotations.first().start, annotations.first().end))
    }

    @Test
    fun leavesPipesBracketsNewlinesAndEmptyValuesUnparsed() {
        val source = "[[cat|other:text]] [[cat:text|other]] [[ca[t:text]] [[cat:te]xt]] [[ :text]] [[cat: ]] [[cat:\ntext]]"

        assertTrue(FloatingKnowledgeAnnotationParser.parse(source).isEmpty())
    }

    @Test
    fun ignoresInlineCodeAndFencedCodeBlocks() {
        val source = """
            `[[person:inline]]` [[person:plain]]

            ```text
            [[person:fenced]]
            ```

            ~~~~
            [[person:tilde]]
            ~~~~
        """.trimIndent()

        assertEquals(listOf("plain"), FloatingKnowledgeAnnotationParser.parse(source).map { it.text })
    }

    @Test
    fun leavesEscapedAnnotationsUnparsed() {
        val source = "\\[[person:escaped]] [[person:shown]]"

        assertEquals(
            listOf("shown"),
            FloatingKnowledgeAnnotationParser.parse(source).map { it.text }
        )
    }

    @Test
    fun handlesMatchingInlineCodeDelimiterLengths() {
        val source = "``code `\n[[person:hidden]] `` \\`[[person:escaped]]\\` [[person:shown]]"

        assertEquals(
            listOf("escaped", "shown"),
            FloatingKnowledgeAnnotationParser.parse(source).map { it.text }
        )
    }

    @Test
    fun resolvesUnknownCategoriesThroughDefaultAndTreatsZeroColorAsMissing() {
        val categories = mapOf(
            "default-id" to mapOf<String, Any?>(
                "id" to "default-id",
                "colorValue" to 0
            ),
            "known" to mapOf<String, Any?>(
                "id" to "known-id",
                "colorValue" to 0xFF123456.toInt()
            )
        )

        assertEquals(
            FloatingKnowledgeCategoryResolution("known-id", 0xFF123456.toInt()),
            FloatingKnowledgeCategoryResolver.resolve("known", "default-id", categories)
        )
        assertEquals(
            FloatingKnowledgeCategoryResolution("default-id", null),
            FloatingKnowledgeCategoryResolver.resolve("unknown", "default-id", categories)
        )
    }
}
