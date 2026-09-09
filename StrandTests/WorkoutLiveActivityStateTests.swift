import XCTest
@testable import Strand

final class WorkoutLiveActivityStateTests: XCTestCase {
    func testRoundTrip() throws {
        let state = WorkoutLiveActivityState(elapsedS: 3723, bpm: 148, sport: "Running")
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(WorkoutLiveActivityState.self, from: data)
        XCTAssertEqual(back, state)
    }

    func testElapsedLabel() {
        XCTAssertEqual(WorkoutLiveActivityState.elapsedLabel(0), "0:00")
        XCTAssertEqual(WorkoutLiveActivityState.elapsedLabel(65), "1:05")
        XCTAssertEqual(WorkoutLiveActivityState.elapsedLabel(3723), "1:02:03")
    }
}
