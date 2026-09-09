import XCTest
import StrandImport
import WhoopStore
@testable import Strand

final class HealthKitMapperTests: XCTestCase {

    func testSleepStageFromHKCategoryInts() {
        XCTAssertEqual(HealthKitMapper.sleepStage(fromCategoryValue: 0), .inBed)
        XCTAssertEqual(HealthKitMapper.sleepStage(fromCategoryValue: 1), .asleepUnspecified)
        XCTAssertEqual(HealthKitMapper.sleepStage(fromCategoryValue: 2), .awake)
        XCTAssertEqual(HealthKitMapper.sleepStage(fromCategoryValue: 3), .asleepCore)
        XCTAssertEqual(HealthKitMapper.sleepStage(fromCategoryValue: 4), .asleepDeep)
        XCTAssertEqual(HealthKitMapper.sleepStage(fromCategoryValue: 5), .asleepREM)
        XCTAssertEqual(HealthKitMapper.sleepStage(fromCategoryValue: 99), .unknown)
    }

    func testCategoryValueRoundTripLabels() {
        XCTAssertEqual(HealthKitMapper.categoryValue(stageLabel: "deep"), 4)
        XCTAssertEqual(HealthKitMapper.categoryValue(stageLabel: "rem"), 5)
        XCTAssertEqual(HealthKitMapper.categoryValue(stageLabel: "light"), 3)
        XCTAssertEqual(HealthKitMapper.categoryValue(stageLabel: "wake"), 2)
        XCTAssertEqual(HealthKitMapper.sleepStage(fromCategoryValue: 4), .asleepDeep)
    }

    func testRelevantTypesMatchImporter() {
        XCTAssertEqual(HealthKitMapper.relevantTypes(), AppleHealthImporter.relevantTypes)
        XCTAssertTrue(HealthKitMapper.relevantTypes().contains("SleepAnalysis"))
        XCTAssertTrue(HealthKitMapper.relevantTypes().contains("HeartRate"))
    }

    func testSportMapping() {
        XCTAssertEqual(HealthKitMapper.workoutActivityTypeName(sport: "Running"), "Running")
        XCTAssertEqual(HealthKitMapper.workoutActivityTypeName(sport: "HIIT"),
                       "HighIntensityIntervalTraining")
        XCTAssertEqual(HealthKitMapper.sportName(fromActivityType: "HKWorkoutActivityTypeRunning"),
                       "Running")
    }

    func testRecoveryMetadata() {
        XCTAssertEqual(HealthKitMapper.recoveryMetadata(score: 72)["NOOPRecovery"], 72)
    }

    func testWriteWatermarksSkipOlder() {
        let old = CachedSleepSession(startTs: 100, endTs: 200, efficiency: nil,
                                       restingHr: nil, avgHrv: nil, stagesJSON: nil)
        let fresh = CachedSleepSession(startTs: 300, endTs: 400, efficiency: nil,
                                         restingHr: nil, avgHrv: nil, stagesJSON: nil)
        XCTAssertEqual(HealthKitMapper.sleepsAfter([old, fresh], endTs: 200).map(\.endTs), [400])
        let wOld = WorkoutRow(startTs: 1, endTs: 10, sport: "Running", source: "logged",
                              durationS: 9, energyKcal: Double?.none, avgHr: Int?.none, maxHr: Int?.none,
                              strain: Double?.none, distanceM: Double?.none, zonesJSON: String?.none,
                              notes: String?.none)
        let wNew = WorkoutRow(startTs: 20, endTs: 50, sport: "Running", source: "logged",
                              durationS: 30, energyKcal: Double?.none, avgHr: Int?.none, maxHr: Int?.none,
                              strain: Double?.none, distanceM: Double?.none, zonesJSON: String?.none,
                              notes: String?.none)
        XCTAssertEqual(HealthKitMapper.workoutsAfter([wOld, wNew], endTs: 10).map(\.endTs), [50])
        let dOld = DailyMetric(day: "2026-09-07", totalSleepMin: 450, efficiency: nil,
                               deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil,
                               restingHr: nil, avgHrv: nil, recovery: 70, strain: nil,
                               exerciseCount: nil)
        let dNew = DailyMetric(day: "2026-09-09", totalSleepMin: 450, efficiency: nil,
                               deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil,
                               restingHr: nil, avgHrv: nil, recovery: 80, strain: nil,
                               exerciseCount: nil)
        XCTAssertEqual(HealthKitMapper.daysAfter([dOld, dNew], day: "2026-09-07").map(\.day),
                       ["2026-09-09"])
        XCTAssertEqual(HealthKitMapper.daysAfter([dOld], day: "").count, 1)
    }

    func testCachedSleepSessionsFromIntervals() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14 22:13 UTC
        let ivs = [
            SleepStageInterval(stage: .asleepDeep, start: start,
                                end: start.addingTimeInterval(3600), tzOffsetMin: 0, sourceName: "NOOP"),
            SleepStageInterval(stage: .asleepREM,
                                start: start.addingTimeInterval(3600),
                                end: start.addingTimeInterval(5400), tzOffsetMin: 0, sourceName: "NOOP"),
        ]
        let sessions = HealthKitMapper.cachedSleepSessions(from: ivs)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].startTs, Int(start.timeIntervalSince1970))
        XCTAssertEqual(sessions[0].endTs, Int(start.addingTimeInterval(5400).timeIntervalSince1970))
        XCTAssertNotNil(SleepStageBreakdown.decode(sessions[0].stagesJSON))
    }

    func testWriteSegmentsFromHypnogramJSON() {
        let json = "[{\"start\":100,\"end\":200,\"stage\":\"deep\"},{\"start\":200,\"end\":400,\"stage\":\"light\"}]"
        let segs = HealthKitMapper.writeSegments(from: json)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].label, "deep")
        XCTAssertEqual(segs[0].start, 100)
        XCTAssertEqual(segs[1].end, 400)
    }
}
