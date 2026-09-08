import XCTest
import WhoopStore
@testable import Strand

final class WorkoutMergeTests: XCTestCase {
    private func row(start: Int, end: Int, sport: String = "Run", source: String) -> WorkoutRow {
        WorkoutRow(startTs: start, endTs: end, sport: sport, source: source,
                   durationS: Double(end - start), energyKcal: nil, avgHr: nil, maxHr: nil,
                   strain: nil, distanceM: nil, zonesJSON: nil, notes: nil)
    }

    func testComputedFillsGapWhenNoOverlap() {
        let whoop = row(start: 1_000, end: 2_000, source: "whoop")
        let detected = row(start: 5_000, end: 6_000, sport: "Workout", source: "noop")
        let merged = Repository.mergeWorkouts(imported: [whoop], apple: [], computed: [detected])
        XCTAssertEqual(merged.map(\.source), ["noop", "whoop"])
        XCTAssertEqual(merged.map(\.startTs), [5_000, 1_000])
    }

    func testOverlapDropsComputedInFavorOfWhoop() {
        let whoop = row(start: 1_000, end: 4_000, source: "whoop")
        let detected = row(start: 2_000, end: 3_000, sport: "Workout", source: "noop")
        let merged = Repository.mergeWorkouts(imported: [whoop], apple: [], computed: [detected])
        XCTAssertEqual(merged.map(\.source), ["whoop"])
    }

    func testOverlapDropsComputedInFavorOfApple() {
        let apple = row(start: 1_000, end: 4_000, sport: "Cycling", source: "apple_health")
        let detected = row(start: 3_500, end: 5_000, sport: "Workout", source: "noop")
        let merged = Repository.mergeWorkouts(imported: [], apple: [apple], computed: [detected])
        XCTAssertEqual(merged.map(\.source), ["apple_health"])
    }

    func testTouchingEndpointsAreNotOverlap() {
        let whoop = row(start: 1_000, end: 2_000, source: "whoop")
        let detected = row(start: 2_000, end: 3_000, sport: "Workout", source: "noop")
        XCTAssertFalse(Repository.workoutsOverlap(whoop, detected))
        let merged = Repository.mergeWorkouts(imported: [whoop], apple: [], computed: [detected])
        XCTAssertEqual(merged.count, 2)
    }

    func testWhoopAndAppleBothKeptEvenIfTheyOverlap() {
        let whoop = row(start: 1_000, end: 3_000, source: "whoop")
        let apple = row(start: 2_000, end: 4_000, sport: "Run", source: "apple_health")
        let merged = Repository.mergeWorkouts(imported: [whoop], apple: [apple], computed: [])
        XCTAssertEqual(merged.count, 2)
    }

    func testNewestFirst() {
        let a = row(start: 100, end: 200, source: "whoop")
        let b = row(start: 500, end: 600, source: "apple_health")
        let c = row(start: 300, end: 350, sport: "Workout", source: "noop")
        let merged = Repository.mergeWorkouts(imported: [a], apple: [b], computed: [c])
        XCTAssertEqual(merged.map(\.startTs), [500, 300, 100])
    }

    func testLoggedKeptEvenWhenOverlappingWhoop() {
        let whoop = row(start: 1_000, end: 4_000, source: "whoop")
        let logged = row(start: 2_000, end: 3_000, sport: "Running", source: "logged")
        let merged = Repository.mergeWorkouts(imported: [whoop], apple: [], computed: [logged])
        XCTAssertEqual(Set(merged.map(\.source)), ["whoop", "logged"])
    }

    func testLoggedSourceHelper() {
        XCTAssertTrue(Repository.isLoggedSource("logged"))
        XCTAssertFalse(Repository.isLoggedSource("noop"))
        XCTAssertFalse(Repository.isLoggedSource("whoop"))
        XCTAssertFalse(Repository.isLoggedSource("apple_health"))
    }
}
