import XCTest
@testable import Strand

final class BackfillPolicyTests: XCTestCase {

    func testEventTriggersWaitNinetySeconds() {
        let last = 1_000.0
        XCTAssertFalse(BackfillPolicy.shouldRun(trigger: .foreground, now: last + 89, lastBackfillAt: last))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .foreground, now: last + 90, lastBackfillAt: last))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .connect, now: last + 90, lastBackfillAt: last))
        XCTAssertFalse(BackfillPolicy.shouldRun(trigger: .background, now: last + 89, lastBackfillAt: last))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .background, now: last + 90, lastBackfillAt: last))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .manual, now: last + 1, lastBackfillAt: last))
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .periodic, now: last + 900, lastBackfillAt: last))
        XCTAssertFalse(BackfillPolicy.shouldRun(trigger: .periodic, now: last + 899, lastBackfillAt: last))
        // A timed-out pull must resume immediately. Stamping lastBackfillAt at
        // begin() used to impose the 90s event floor, so last night sat on the
        // strap while we waited between watchdog timeouts.
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .resume, now: last + 1, lastBackfillAt: last))
    }

    func testFirstAttemptAlwaysRuns() {
        XCTAssertTrue(BackfillPolicy.shouldRun(trigger: .foreground, now: 1, lastBackfillAt: nil))
    }

    func testDeferredHandshakeDoesNotStartSession() {
        XCTAssertFalse(BackfillPolicy.shouldStartSession(handshakeDone: false, storeReady: true))
        XCTAssertFalse(BackfillPolicy.shouldStartSession(handshakeDone: true, storeReady: false))
        XCTAssertTrue(BackfillPolicy.shouldStartSession(handshakeDone: true, storeReady: true))
    }
}
