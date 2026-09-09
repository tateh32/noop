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
