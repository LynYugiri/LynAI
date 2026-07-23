package com.github.lynyugiri.lynai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.util.TimeZone

class CalendarProjectionStoreTest {
    @Test
    fun parsesVersionedOccurrencesAndMultipleTriggers() {
        val projection = CalendarProjectionStore.parse(
            """
            {
              "version": 1,
              "widgetOccurrences": [
                {
                  "occurrenceId": "taskDue:task:2026-07-24",
                  "title": "Ship",
                  "date": "2026-07-24",
                  "startTime": "18:30",
                  "endAtLocal": "2026-07-24T19:15",
                  "endDateExclusive": "2026-07-25",
                  "isCompleted": false
                }
              ],
              "notificationTriggers": [
                {
                  "triggerId": "taskDue:task:2026-07-24:first",
                  "sourceType": "taskDue",
                  "title": "Ship",
                  "note": "",
                  "triggerAtLocal": "2026-07-24T17:30"
                },
                {
                  "triggerId": "taskDue:task:2026-07-24:second",
                  "sourceType": "taskDue",
                  "title": "Ship",
                  "note": "",
                  "triggerAtLocal": "2026-07-24T18:15"
                }
              ]
            }
            """.trimIndent()
        )

        assertEquals(1, projection.widgetOccurrences.size)
        assertEquals(2, projection.notificationTriggers.size)
        assertEquals("18:30", projection.widgetOccurrences.single().startTime.toString())
        assertEquals("2026-07-24T19:15", projection.widgetOccurrences.single().endAt.toString())
        assertEquals(
            java.time.LocalDate.parse("2026-07-25"),
            projection.widgetOccurrences.single().endDateExclusive
        )
    }

    @Test
    fun rejectsUnknownProjectionVersion() {
        val projection = CalendarProjectionStore.parse(
            """{"version":3,"widgetOccurrences":[],"notificationTriggers":[]}"""
        )

        assertTrue(projection.widgetOccurrences.isEmpty())
        assertTrue(projection.notificationTriggers.isEmpty())
    }

    @Test
    fun treatsJsonNullNotificationNoteAsEmpty() {
        val projection = CalendarProjectionStore.parse(
            """
            {
              "version": 1,
              "widgetOccurrences": [],
              "notificationTriggers": [
                {
                  "triggerId": "event:event:2026-07-24:first",
                  "sourceType": "event",
                  "title": "Meeting",
                  "note": null,
                  "triggerAtLocal": "2026-07-24T17:30"
                }
              ]
            }
            """.trimIndent()
        )

        assertEquals("", projection.notificationTriggers.single().note)
    }

    @Test
    fun absoluteTimedValuesDoNotChangeWithSystemTimezone() {
        val original = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("Asia/Shanghai"))
            val projection = CalendarProjectionStore.parse(
                """
                {
                  "version": 2,
                  "widgetOccurrences": [
                    {
                      "occurrenceId": "event:meeting:2026-07-23",
                      "title": "Meeting",
                      "date": "2026-07-23",
                      "startTime": "18:00",
                      "endAtLocal": "2026-07-23T19:00",
                      "startAtEpochMillis": 1784800800000,
                      "endAtEpochMillis": 1784804400000,
                      "endDateExclusive": "2026-07-24",
                      "isCompleted": false
                    }
                  ],
                  "notificationTriggers": [
                    {
                      "triggerId": "event:meeting:2026-07-23:before",
                      "sourceType": "event",
                      "title": "Meeting",
                      "note": "",
                      "triggerAtLocal": "2026-07-23T17:30",
                      "triggerAtEpochMillis": 1784799000000
                    }
                  ]
                }
                """.trimIndent()
            )

            TimeZone.setDefault(TimeZone.getTimeZone("Asia/Tokyo"))

            assertEquals(1784800800000, projection.widgetOccurrences.single().start.time)
            assertEquals(1784804400000, projection.widgetOccurrences.single().end.time)
            assertEquals(1784799000000, projection.notificationTriggers.single().triggerAtMillis)
            assertEquals(
                Instant.ofEpochMilli(1784800800000),
                projection.widgetOccurrences.single().start.toInstant()
            )
        } finally {
            TimeZone.setDefault(original)
        }
    }
}
