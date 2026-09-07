package com.noop.ingest

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * WHOOP CSV → metricSeries projection. This is the piece Android was missing:
 * dailyMetric imported, but Explore / Compare / Insights / Stress stayed empty.
 */
class WhoopCsvMetricsTest {

    @Test
    fun englishCycleRowProjectsCatalogKeys() {
        val csv = """
            Cycle start time,Cycle timezone,Recovery score %,Resting heart rate (bpm),Heart rate variability (ms),Day strain,Energy burned (cal),Average HR (bpm),Max HR (bpm),Asleep duration (min),In bed duration (min),Deep (SWS) duration (min),REM duration (min),Sleep performance %,Sleep need (min)
            2024-03-01 06:00:00,UTC+00:00,80,52,95,12.5,2400,61,165,420,455,95,115,85,480
        """.trimIndent()
        val sources = WhoopCsvMetrics.sourcesFromCycles(CsvTable.fromText(csv))
        assertEquals(1, sources.size)
        assertEquals("2024-03-01", sources[0].day)
        assertEquals(80.0, sources[0].recovery)
        assertEquals(52.0, sources[0].rhr)
        assertEquals(95.0, sources[0].hrv)

        val series = WhoopCsvMetrics.build("my-whoop", sources, emptyList())
        val byKey = series.associate { it.key to it.value }
        assertEquals(80.0, byKey["recovery"])
        assertEquals(12.5, byKey["strain"])
        assertEquals(52.0, byKey["rhr"])
        assertEquals(95.0, byKey["hrv"])
        assertEquals(2400.0, byKey["energy_kcal"])
        assertEquals(61.0, byKey["avg_hr"])
        assertEquals(165.0, byKey["max_hr"])
        assertEquals(420.0, byKey["sleep_total_min"])
        assertEquals(455.0, byKey["in_bed_min"])
        assertEquals(210.0, byKey["restorative_min"]) // 95 deep + 115 rem
        assertEquals(87.5, byKey["hours_vs_needed_pct"]!!, 1e-9) // 420 / 480 * 100
        assertNotNull(byKey["stress"])
        assertTrue(series.all { it.deviceId == "my-whoop" && it.day == "2024-03-01" })
    }

    @Test
    fun germanCycleHeadersAliasOntoEnglishKeys() {
        val csv = """
            Startzeit des Zyklus,Endzeit des Zyklus,Zeitzone des Zyklus,Erholungswert %,Ruheherzfrequenz (Schläge pro Minute),Herzfrequenzvariabilität (ms),Tagesbelastung
            2024-03-01 06:00:00,2024-03-02 06:00:00,UTC+00:00,80,52,95,12.5
        """.trimIndent()
        val sources = WhoopCsvMetrics.sourcesFromCycles(CsvTable.fromText(csv))
        assertEquals(1, sources.size)
        assertEquals(80.0, sources[0].recovery)
        assertEquals(52.0, sources[0].rhr)
        assertEquals(95.0, sources[0].hrv)
        assertEquals(12.5, sources[0].strain)
    }

    @Test
    fun workoutZoneMinutesAndStrengthRollup() {
        val csv = """
            Workout start time,Workout end time,Cycle timezone,Activity name,HR Zone 1 %,HR Zone 2 %,HR Zone 3 %,HR Zone 4 %,HR Zone 5 %
            2024-03-01 09:00:00,2024-03-01 10:00:00,UTC+00:00,Weightlifting,10,20,30,25,15
        """.trimIndent()
        val workouts = WhoopCsvMetrics.sourcesFromWorkouts(CsvTable.fromText(csv))
        assertEquals(1, workouts.size)
        assertEquals(60.0, workouts[0].durationMin, 1e-9)

        val series = WhoopCsvMetrics.build("my-whoop", emptyList(), workouts)
        val byKey = series.associate { it.key to it.value }
        assertEquals(6.0, byKey["hr_zone1_min"]!!, 1e-9)
        assertEquals(12.0, byKey["hr_zone2_min"]!!, 1e-9)
        assertEquals(18.0, byKey["hr_zone3_min"]!!, 1e-9)
        assertEquals(15.0, byKey["hr_zone4_min"]!!, 1e-9)
        assertEquals(9.0, byKey["hr_zone5_min"]!!, 1e-9)
        assertEquals(36.0, byKey["hr_zones13_min"]!!, 1e-9)
        assertEquals(24.0, byKey["hr_zones45_min"]!!, 1e-9)
        assertEquals(60.0, byKey["hr_zones_all_min"]!!, 1e-9)
        assertEquals(60.0, byKey["strength_min"]!!, 1e-9)
    }
}
