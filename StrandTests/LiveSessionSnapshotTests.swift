import XCTest
@testable import Strand

final class LiveSessionSnapshotTests: XCTestCase {
    private func snapshot(startedAt: TimeInterval) -> LiveSessionSnapshot {
        LiveSessionSnapshot(sport: "Running", startedAt: startedAt,
                            distanceM: 1234.5, steps: 88,
                            hrSum: 360, hrCount: 3, hrMax: 122)
    }

    func testRoundTrip() throws {
        let snap = snapshot(startedAt: 1_700_000_000)
        let data = try JSONEncoder().encode(snap)
        let back = try XCTUnwrap(LiveSessionSnapshot.decode(data))
        XCTAssertEqual(back, snap)
    }

    /// Aggregates, not the whole beat series — the series reached ~29k entries on a
    /// long session and was re-encoded every 15 seconds.
    func testPayloadStaysSmallRegardlessOfSessionLength() throws {
        let long = LiveSessionSnapshot(sport: "Cycling", startedAt: 1_700_000_000,
                                       distanceM: 90_000, steps: 0,
                                       hrSum: 4_000_000, hrCount: 28_800, hrMax: 181)
        let data = try JSONEncoder().encode(long)
        XCTAssertLessThan(data.count, 256)
    }

    func testFreshWithinTwelveHours() {
        XCTAssertTrue(snapshot(startedAt: Date().timeIntervalSince1970 - 600).isFresh)
        XCTAssertFalse(snapshot(startedAt: Date().timeIntervalSince1970 - 13 * 3600).isFresh)
        // A start time in the future means the clock moved; do not resume.
        XCTAssertFalse(snapshot(startedAt: Date().timeIntervalSince1970 + 60).isFresh)
    }
}
