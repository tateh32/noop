import XCTest
import WhoopProtocol
@testable import Strand

final class SmartWakeTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ m: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: m))!
    }

    private func snap(now: Date, target: Date, window: Int = 30,
                      enabled: Bool = true, connected: Bool = true,
                      fired: Bool = false, stage: SmartWake.Stage = .light) -> SmartWake.Snapshot {
        SmartWake.Snapshot(now: now, targetWake: target, windowMinutes: window,
                           enabled: enabled, connected: connected,
                           alreadyFired: fired, stage: stage)
    }

    func testFiresOnLightInsideWindow() {
        let target = date(2026, 9, 9, 7, 0)
        let now = date(2026, 9, 9, 6, 40)
        XCTAssertEqual(SmartWake.decide(snap(now: now, target: target)), .fireEarly)
    }

    func testDoesNotFireOutsideWindow() {
        let target = date(2026, 9, 9, 7, 0)
        let now = date(2026, 9, 9, 6, 20)   // 40 min before, window is 30
        XCTAssertEqual(SmartWake.decide(snap(now: now, target: target)), .wait)
    }

    func testDeepDoesNotFire() {
        let target = date(2026, 9, 9, 7, 0)
        let now = date(2026, 9, 9, 6, 45)
        XCTAssertEqual(SmartWake.decide(snap(now: now, target: target, stage: .deep)), .wait)
        XCTAssertEqual(SmartWake.decide(snap(now: now, target: target, stage: .rem)), .wait)
        XCTAssertEqual(SmartWake.decide(snap(now: now, target: target, stage: .unknown)), .wait)
        XCTAssertEqual(SmartWake.decide(snap(now: now, target: target, stage: .wake)), .wait)
    }

    func testFirmwareStillAtTarget() {
        let target = date(2026, 9, 9, 7, 0)
        XCTAssertEqual(SmartWake.decide(snap(now: target, target: target)), .firmwareAtTarget)
        XCTAssertEqual(SmartWake.decide(snap(now: date(2026, 9, 9, 7, 1), target: target)),
                       .firmwareAtTarget)
        // Past target we do not steal the firmware path even on light + connected.
        XCTAssertNotEqual(SmartWake.decide(snap(now: target, target: target, stage: .light)),
                        .fireEarly)
    }

    func testDisconnectedNoEarlyFire() {
        let target = date(2026, 9, 9, 7, 0)
        let now = date(2026, 9, 9, 6, 45)
        XCTAssertEqual(SmartWake.decide(snap(now: now, target: target, connected: false)), .none)
        // Firmware still describes the at-target path when the clock hits even if disconnected.
        XCTAssertEqual(SmartWake.decide(snap(now: target, target: target, connected: false)),
                       .firmwareAtTarget)
    }

    func testDisabledAndAlreadyFired() {
        let target = date(2026, 9, 9, 7, 0)
        let now = date(2026, 9, 9, 6, 45)
        XCTAssertEqual(SmartWake.decide(snap(now: now, target: target, enabled: false)), .none)
        XCTAssertEqual(SmartWake.decide(snap(now: now, target: target, fired: true)), .none)
    }

    func testZeroWindowNeverFiresEarly() {
        let target = date(2026, 9, 9, 7, 0)
        let now = date(2026, 9, 9, 6, 59)
        XCTAssertEqual(SmartWake.decide(snap(now: now, target: target, window: 0)), .wait)
    }

    func testNextTargetWakeRollsToTomorrow() {
        let now = date(2026, 9, 9, 8, 0)
        let next = SmartWake.nextTargetWake(minutesFromMidnight: 7 * 60, now: now, calendar: cal)
        XCTAssertEqual(cal.component(.day, from: next), 10)
        XCTAssertEqual(cal.component(.hour, from: next), 7)
    }

    func testClassifyLightVsDeepFromHR() {
        let now = 2_000_000
        // Stable 48 bpm → deep.
        let deepHR = (0..<120).map { HRSample(ts: now - 120 + $0, bpm: 48) }
        XCTAssertEqual(SmartWake.classify(now: Date(timeIntervalSince1970: TimeInterval(now)),
                                          hr: deepHR, gravity: []).rawValue, "deep")
        // 58 bpm around a 55 median → light.
        let lightHR = (0..<120).map { i -> HRSample in
            HRSample(ts: now - 120 + i, bpm: 54 + (i % 3))
        }
        XCTAssertEqual(SmartWake.classify(now: Date(timeIntervalSince1970: TimeInterval(now)),
                                          hr: lightHR, gravity: []), .light)
        XCTAssertEqual(SmartWake.classify(now: Date(timeIntervalSince1970: TimeInterval(now)),
                                          hr: [], gravity: []), .unknown)
    }

    func testMovingGravityIsWake() {
        let now = 3_000_000
        let hr = (0..<60).map { HRSample(ts: now - 60 + $0, bpm: 55) }
        let grav = (0..<60).map { i -> GravitySample in
            GravitySample(ts: now - 60 + i, x: Double(i % 2) * 0.5, y: 0, z: 1)
        }
        XCTAssertEqual(SmartWake.classify(now: Date(timeIntervalSince1970: TimeInterval(now)),
                                          hr: hr, gravity: grav), .wake)
    }
}
