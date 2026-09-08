import XCTest
@testable import Strand

final class GeoDistanceTests: XCTestCase {
    func testSamePointIsZero() {
        XCTAssertEqual(GeoDistance.meters(fromLat: 51.5, lon: -0.1, toLat: 51.5, lon: -0.1), 0, accuracy: 0.01)
    }

    func testOneDegreeLatitudeIsAbout111km() {
        let m = GeoDistance.meters(fromLat: 0, lon: 0, toLat: 1, lon: 0)
        XCTAssertEqual(m, 111_195, accuracy: 200)
    }

    func testRejectsInvalidAccuracy() {
        XCTAssertFalse(GeoDistance.usableAccuracy(-1))
        XCTAssertFalse(GeoDistance.usableAccuracy(80))
        XCTAssertTrue(GeoDistance.usableAccuracy(8))
    }

    func testJitterAndTeleportAreDropped() {
        XCTAssertFalse(GeoDistance.shouldAccumulate(deltaM: 1.2, accuracyM: 8))
        XCTAssertFalse(GeoDistance.shouldAccumulate(deltaM: 250, accuracyM: 8))
        XCTAssertTrue(GeoDistance.shouldAccumulate(deltaM: 12, accuracyM: 8))
    }

    func testRunningUsesPhoneGPS() {
        XCTAssertTrue(WorkoutSport.running.usesPhoneGPS)
        XCTAssertTrue(WorkoutSport.cycling.usesPhoneGPS)
        XCTAssertFalse(WorkoutSport.strength.usesPhoneGPS)
        XCTAssertTrue(WorkoutSport.running.usesPedometer)
        XCTAssertFalse(WorkoutSport.cycling.usesPedometer)
    }
}
