import XCTest
@testable import Strand

final class LiveSessionSnapshotTests: XCTestCase {
    func testRoundTrip() throws {
        let snap = LiveSessionSnapshot(sport: "Running", startedAt: 1_700_000_000,
                                       distanceM: 1234.5, steps: 88,
                                       hrTicks: [120, 122, 118])
        let data = try JSONEncoder().encode(snap)
        let back = try XCTUnwrap(LiveSessionSnapshot.decode(data))
        XCTAssertEqual(back, snap)
    }

    func testFreshWithinTwelveHours() {
        var snap = LiveSessionSnapshot(sport: "Walking",
                                       startedAt: Date().timeIntervalSince1970 - 600,
                                       distanceM: 0, steps: 0, hrTicks: [])
        XCTAssertTrue(snap.isFresh)
        snap.startedAt = Date().timeIntervalSince1970 - (13 * 3600)
        XCTAssertFalse(snap.isFresh)
        snap.startedAt = Date().timeIntervalSince1970 + 60
        XCTAssertFalse(snap.isFresh)
    }
}
