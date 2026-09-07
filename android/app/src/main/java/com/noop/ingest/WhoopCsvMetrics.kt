package com.noop.ingest

import com.noop.data.MetricSeriesRow
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Builds the generic `metricSeries` rows a WHOOP CSV import should persist.
 *
 * Port of `Strand/Data/WhoopImporter.swift` (the cycle-field projection, derived
 * restorative / hours-vs-needed / stress series, and workout zone-minute rollups).
 * Android's [WhoopCsvImporter] used to write only `dailyMetric` / sleep / workouts /
 * journal — Explore, Compare, Insights and Stress then looked empty after a
 * successful import even though the daily cache was populated.
 */
internal data class CycleSeriesSource(
    val day: String,
    val recovery: Double? = null,
    val strain: Double? = null,
    val rhr: Double? = null,
    val hrv: Double? = null,
    val spo2: Double? = null,
    val skinTemp: Double? = null,
    val resp: Double? = null,
    val energyKcal: Double? = null,
    val avgHr: Double? = null,
    val maxHr: Double? = null,
    val asleepMin: Double? = null,
    val inBedMin: Double? = null,
    val deepMin: Double? = null,
    val remMin: Double? = null,
    val lightMin: Double? = null,
    val awakeMin: Double? = null,
    val efficiency: Double? = null,
    val sleepPerformance: Double? = null,
    val sleepConsistency: Double? = null,
    val sleepNeedMin: Double? = null,
    val sleepDebtMin: Double? = null,
)

internal data class WorkoutSeriesSource(
    val day: String,
    val durationMin: Double,
    val z1: Double? = null,
    val z2: Double? = null,
    val z3: Double? = null,
    val z4: Double? = null,
    val z5: Double? = null,
    val activityName: String? = null,
)

internal object WhoopCsvMetrics {

    private val DAY_FMT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")

    fun sourcesFromCycles(table: CsvTable): List<CycleSeriesSource> {
        val out = ArrayList<CycleSeriesSource>(table.rows.size)
        for (row in table.rows) {
            val tz = WhoopTime.tzOffsetMinutes(row["cycle_timezone"])
            val cycleStart = WhoopTime.parseEpochSeconds(row.cell("cycle_start_time"), tz)
            val cycleEnd = WhoopTime.parseEpochSeconds(row.cell("cycle_end_time"), tz)
            if (cycleStart == null && cycleEnd == null) continue
            out.add(
                CycleSeriesSource(
                    day = dayString(cycleStart ?: cycleEnd!!, tz),
                    recovery = row.double("recovery_score_pct"),
                    strain = row.double("day_strain"),
                    rhr = row.double("resting_heart_rate_bpm", "resting_heart_rate"),
                    hrv = row.double("heart_rate_variability_ms", "heart_rate_variability_rmssd_ms"),
                    spo2 = row.double("blood_oxygen_pct", "blood_oxygen_pct_pct"),
                    skinTemp = row.double("skin_temp_celsius", "skin_temp_f"),
                    resp = row.double("respiratory_rate_rpm", "respiratory_rate"),
                    energyKcal = row.double("energy_burned_cal"),
                    avgHr = row.double("average_hr_bpm", "average_heart_rate_bpm"),
                    maxHr = row.double("max_hr_bpm", "max_heart_rate_bpm"),
                    asleepMin = row.double("asleep_duration_min"),
                    inBedMin = row.double("in_bed_duration_min"),
                    deepMin = row.double("deep_sws_duration_min", "deep_sleep_duration_min"),
                    remMin = row.double("rem_duration_min"),
                    lightMin = row.double("light_sleep_duration_min"),
                    awakeMin = row.double("awake_duration_min"),
                    efficiency = row.double("sleep_efficiency_pct"),
                    sleepPerformance = row.double("sleep_performance_pct"),
                    sleepConsistency = row.double("sleep_consistency_pct"),
                    sleepNeedMin = row.double("sleep_need_min"),
                    sleepDebtMin = row.double("sleep_debt_min"),
                )
            )
        }
        return out
    }

    fun sourcesFromWorkouts(table: CsvTable): List<WorkoutSeriesSource> {
        val out = ArrayList<WorkoutSeriesSource>(table.rows.size)
        for (row in table.rows) {
            val tz = WhoopTime.tzOffsetMinutes(row["cycle_timezone"])
            val cycleStart = WhoopTime.parseEpochSeconds(row.cell("cycle_start_time"), tz)
            val workoutStart = WhoopTime.parseEpochSeconds(row.cell("workout_start_time"), tz)
            val workoutEnd = WhoopTime.parseEpochSeconds(row.cell("workout_end_time"), tz)
            if (workoutStart == null && workoutEnd == null && cycleStart == null) continue
            val start = workoutStart ?: cycleStart ?: workoutEnd!!
            val durationMin = if (workoutStart != null && workoutEnd != null && workoutEnd >= workoutStart) {
                (workoutEnd - workoutStart) / 60.0
            } else {
                0.0
            }
            out.add(
                WorkoutSeriesSource(
                    day = dayString(start, tz),
                    durationMin = durationMin,
                    z1 = row.double("hr_zone_1_pct", "zone_1_pct", "hr_zone_1_pct_pct"),
                    z2 = row.double("hr_zone_2_pct", "zone_2_pct", "hr_zone_2_pct_pct"),
                    z3 = row.double("hr_zone_3_pct", "zone_3_pct", "hr_zone_3_pct_pct"),
                    z4 = row.double("hr_zone_4_pct", "zone_4_pct", "hr_zone_4_pct_pct"),
                    z5 = row.double("hr_zone_5_pct", "zone_5_pct", "hr_zone_5_pct_pct"),
                    activityName = row.cell("activity_name"),
                )
            )
        }
        return out
    }

    fun build(
        deviceId: String,
        cycles: List<CycleSeriesSource>,
        workouts: List<WorkoutSeriesSource>,
    ): List<MetricSeriesRow> {
        val points = ArrayList<MetricSeriesRow>()
        fun add(day: String, key: String, value: Double?) {
            if (value != null) points.add(MetricSeriesRow(deviceId, day, key, value))
        }

        for (c in cycles) {
            add(c.day, "recovery", c.recovery)
            add(c.day, "strain", c.strain)
            add(c.day, "rhr", c.rhr)
            add(c.day, "hrv", c.hrv)
            add(c.day, "spo2", c.spo2)
            add(c.day, "skin_temp", c.skinTemp)
            add(c.day, "resp_rate", c.resp)
            add(c.day, "energy_kcal", c.energyKcal)
            add(c.day, "avg_hr", c.avgHr)
            add(c.day, "max_hr", c.maxHr)
            add(c.day, "sleep_total_min", c.asleepMin)
            add(c.day, "in_bed_min", c.inBedMin)
            add(c.day, "sleep_deep_min", c.deepMin)
            add(c.day, "sleep_rem_min", c.remMin)
            add(c.day, "sleep_light_min", c.lightMin)
            add(c.day, "awake_min", c.awakeMin)
            add(c.day, "sleep_efficiency", c.efficiency)
            add(c.day, "sleep_performance", c.sleepPerformance)
            add(c.day, "sleep_consistency", c.sleepConsistency)
            add(c.day, "sleep_need_min", c.sleepNeedMin)
            add(c.day, "sleep_debt_min", c.sleepDebtMin)
            val deep = c.deepMin
            val rem = c.remMin
            if (deep != null && rem != null) {
                val restorative = deep + rem
                add(c.day, "restorative_min", restorative)
                val asleep = c.asleepMin
                if (asleep != null && asleep > 0) {
                    add(c.day, "restorative_pct", restorative / asleep * 100.0)
                }
            }
            val asleep = c.asleepMin
            val need = c.sleepNeedMin
            if (asleep != null && need != null && need > 0) {
                add(c.day, "hours_vs_needed_pct", asleep / need * 100.0)
            }
        }

        val (rm, rs) = meanStd(cycles.mapNotNull { it.rhr })
        val (hm, hs) = meanStd(cycles.mapNotNull { it.hrv })
        for (c in cycles) {
            val rhr = c.rhr ?: continue
            val hrv = c.hrv ?: continue
            val z = 0.6 * ((rhr - rm) / rs) - 0.6 * ((hrv - hm) / hs)
            add(c.day, "stress", max(0.0, min(3.0, 1.5 + z)))
        }

        val zoneByDay = LinkedHashMap<String, DoubleArray>()
        val strengthByDay = LinkedHashMap<String, Double>()
        for (w in workouts) {
            val arr = zoneByDay.getOrPut(w.day) { doubleArrayOf(0.0, 0.0, 0.0, 0.0, 0.0) }
            val zp = arrayOf(w.z1, w.z2, w.z3, w.z4, w.z5)
            for (i in 0 until 5) {
                val p = zp[i] ?: continue
                arr[i] += w.durationMin * p / 100.0
            }
            val name = w.activityName?.lowercase() ?: ""
            if (name.contains("strength") || name.contains("weight")) {
                strengthByDay[w.day] = (strengthByDay[w.day] ?: 0.0) + w.durationMin
            }
        }
        for ((day, a) in zoneByDay) {
            add(day, "hr_zone1_min", a[0])
            add(day, "hr_zone2_min", a[1])
            add(day, "hr_zone3_min", a[2])
            add(day, "hr_zone4_min", a[3])
            add(day, "hr_zone5_min", a[4])
            add(day, "hr_zones13_min", a[0] + a[1] + a[2])
            add(day, "hr_zones45_min", a[3] + a[4])
            add(day, "hr_zones_all_min", a.sum())
        }
        for ((day, minutes) in strengthByDay) add(day, "strength_min", minutes)

        return points
    }

    private fun meanStd(values: List<Double>): Pair<Double, Double> {
        if (values.isEmpty()) return 0.0 to 1.0
        val m = values.sum() / values.size
        val v = values.sumOf { (it - m) * (it - m) } / values.size
        return m to max(sqrt(v), 0.0001)
    }

    fun dayString(epochSeconds: Long, offsetMinutes: Int): String {
        val offset = try {
            ZoneOffset.ofTotalSeconds(offsetMinutes * 60)
        } catch (_: Exception) {
            ZoneOffset.UTC
        }
        return Instant.ofEpochSecond(epochSeconds).atOffset(offset).toLocalDate().format(DAY_FMT)
    }
}
