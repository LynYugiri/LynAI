package com.github.lynyugiri.lynai

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.util.Date

class ScheduleWidgetLogicTest {
    @Test
    fun meetingIsNotOngoingAfterItsExactEnd() {
        val meeting = CalendarWidgetOccurrence(
            occurrenceId = "event:meeting:2026-07-23",
            title = "Meeting",
            date = LocalDate.of(2026, 7, 23),
            startTime = LocalTime.of(10, 0),
            endAt = LocalDateTime.of(2026, 7, 23, 11, 0),
            startAtMillis = null,
            endAtMillis = null,
            endDateExclusive = LocalDate.of(2026, 7, 24),
            isCompleted = false
        )
        val noon = Date.from(
            LocalDateTime.of(2026, 7, 23, 12, 0)
                .atZone(ZoneId.systemDefault())
                .toInstant()
        )
        val during = Date.from(
            LocalDateTime.of(2026, 7, 23, 10, 30)
                .atZone(ZoneId.systemDefault())
                .toInstant()
        )

        assertEquals("进行中 · Meeting", ScheduleWidgetLogic.nextScheduleText(listOf(meeting), during))
        assertEquals("近期无日程", ScheduleWidgetLogic.nextScheduleText(listOf(meeting), noon))
    }
}
