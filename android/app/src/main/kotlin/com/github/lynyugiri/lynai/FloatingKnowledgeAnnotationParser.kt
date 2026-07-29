package com.github.lynyugiri.lynai

internal data class FloatingKnowledgeAnnotation(
    val start: Int,
    val end: Int,
    val category: String,
    val text: String
)

internal data class FloatingKnowledgeCategoryResolution(
    val id: String?,
    val colorValue: Int?
)

internal object FloatingKnowledgeCategoryResolver {
    fun resolve(
        category: String,
        defaultId: String?,
        categories: Map<String, Map<String, Any?>>
    ): FloatingKnowledgeCategoryResolution {
        val requested = categories[category].orEmpty()
        val value = if (requested.isEmpty() && defaultId != null) {
            categories[defaultId].orEmpty()
        } else {
            requested
        }
        return FloatingKnowledgeCategoryResolution(
            id = value["id"]?.toString() ?: defaultId,
            colorValue = (value["colorValue"] as? Number)?.toInt()?.takeUnless { it == 0 }
        )
    }
}

internal object FloatingKnowledgeAnnotationParser {
    private val annotation = Regex("\\[\\[([^\\[\\]\\r\\n:|]+):([^\\[\\]\\r\\n|]+)]]")
    private val fenceStart = Regex("^[ \\t]{0,3}(`{3,}|~{3,})[^\\r\\n]*$")

    fun parse(source: String): List<FloatingKnowledgeAnnotation> {
        if (source.isEmpty()) return emptyList()
        val excluded = excludedCodeRanges(source)
        var excludedIndex = 0
        return annotation.findAll(source).mapNotNull { match ->
            if (isEscaped(source, match.range.first)) return@mapNotNull null
            while (excludedIndex < excluded.size && excluded[excludedIndex].last < match.range.first) {
                excludedIndex++
            }
            if (excludedIndex < excluded.size && excluded[excludedIndex].first <= match.range.last) {
                return@mapNotNull null
            }
            val category = match.groupValues[1].trim()
            val text = match.groupValues[2].trim()
            if (category.isEmpty() || text.isEmpty()) {
                null
            } else {
                FloatingKnowledgeAnnotation(
                    start = match.range.first,
                    end = match.range.last + 1,
                    category = category,
                    text = text
                )
            }
        }.toList()
    }

    private fun excludedCodeRanges(source: String): List<IntRange> {
        val fenced = fencedCodeRanges(source)
        return (fenced + inlineCodeRanges(source, fenced)).sortedBy(IntRange::first)
    }

    private fun fencedCodeRanges(source: String): List<IntRange> {
        val ranges = mutableListOf<IntRange>()
        var offset = 0
        var fenceStartOffset: Int? = null
        var fenceMarker = ' '
        var fenceLength = 0
        source.splitToSequence('\n').forEach { line ->
            val lineEnd = offset + line.length
            val activeFenceStart = fenceStartOffset
            if (activeFenceStart == null) {
                val match = fenceStart.matchEntire(line.trimEnd('\r'))
                if (match != null) {
                    val marker = match.groupValues[1]
                    fenceStartOffset = offset
                    fenceMarker = marker.first()
                    fenceLength = marker.length
                }
            } else if (isFenceClose(line, fenceMarker, fenceLength)) {
                ranges += activeFenceStart..lineEnd
                fenceStartOffset = null
            }
            offset = lineEnd + 1
        }
        fenceStartOffset?.let { ranges += it..source.lastIndex }
        return ranges
    }

    private fun isFenceClose(line: String, marker: Char, minimumLength: Int): Boolean {
        val value = line.trimEnd('\r')
        val indent = value.takeWhile { it == ' ' || it == '\t' }
        if (indent.length > 3) return false
        val body = value.substring(indent.length)
        val markerLength = body.takeWhile { it == marker }.length
        return markerLength >= minimumLength && body.substring(markerLength).isBlank()
    }

    private fun inlineCodeRanges(source: String, fenced: List<IntRange>): List<IntRange> {
        val ranges = mutableListOf<IntRange>()
        var fencedIndex = 0
        var cursor = 0
        while (cursor < source.length) {
            while (fencedIndex < fenced.size && fenced[fencedIndex].last < cursor) fencedIndex++
            if (fencedIndex < fenced.size && cursor >= fenced[fencedIndex].first) {
                cursor = fenced[fencedIndex].last + 1
                continue
            }
            if (source[cursor] != '`' || isEscaped(source, cursor)) {
                cursor++
                continue
            }
            val openingStart = cursor
            while (cursor < source.length && source[cursor] == '`') cursor++
            val delimiterLength = cursor - openingStart
            var closingStart = cursor
            var closingFencedIndex = fencedIndex
            while (closingStart < source.length) {
                while (closingFencedIndex < fenced.size && fenced[closingFencedIndex].last < closingStart) {
                    closingFencedIndex++
                }
                if (closingFencedIndex < fenced.size && closingStart >= fenced[closingFencedIndex].first) {
                    closingStart = fenced[closingFencedIndex].last + 1
                    continue
                }
                if (source[closingStart] != '`' || isEscaped(source, closingStart)) {
                    closingStart++
                    continue
                }
                var closingEnd = closingStart
                while (closingEnd < source.length && source[closingEnd] == '`') closingEnd++
                if (closingEnd - closingStart == delimiterLength) {
                    ranges += openingStart..(closingEnd - 1)
                    cursor = closingEnd
                    break
                }
                closingStart = closingEnd
            }
            if (closingStart >= source.length) cursor = openingStart + delimiterLength
        }
        return ranges
    }

    private fun isEscaped(source: String, offset: Int): Boolean {
        var slashCount = 0
        var cursor = offset - 1
        while (cursor >= 0 && source[cursor] == '\\') {
            slashCount++
            cursor--
        }
        return slashCount % 2 == 1
    }
}
