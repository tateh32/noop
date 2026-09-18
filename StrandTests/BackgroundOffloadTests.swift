import XCTest
@testable import Strand

final class BackgroundOffloadTests: XCTestCase {

    func testLockingPhoneStopsLiveHRAndKeepsHistoricalPull() {
        let actions = BackgroundOffload.actions(
            phase: .background, trainRunning: false, connected: true, bonded: true)
        XCTAssertEqual(actions, [.pruneRaw, .stopLiveHR, .requestOffload])
    }

    func testLockingPhoneWhileDisconnectedRescans() {
        let actions = BackgroundOffload.actions(
            phase: .background, trainRunning: false, connected: false, bonded: false)
        XCTAssertEqual(actions, [.pruneRaw, .stopLiveHR, .resumeConnection])
    }

    func testLockingDuringTrainKeepsLiveHRAndDoesNotStartOffload() {
        let actions = BackgroundOffload.actions(
            phase: .background, trainRunning: true, connected: true, bonded: true)
        XCTAssertEqual(actions, [.persistSession, .pruneRaw])
    }

    func testBecomingActiveWithTrainRestartsLiveHR() {
        let actions = BackgroundOffload.actions(
            phase: .active, trainRunning: true, connected: true, bonded: true)
        XCTAssertEqual(actions, [.startLiveHR, .resumeConnection])
    }

    func testBecomingActiveWithoutTrainJustResumesConnection() {
        let actions = BackgroundOffload.actions(
            phase: .active, trainRunning: false, connected: true, bonded: true)
        XCTAssertEqual(actions, [.resumeConnection])
    }

    func testInactiveIsANoOp() {
        XCTAssertEqual(
            BackgroundOffload.actions(
                phase: .inactive, trainRunning: false, connected: true, bonded: true),
            [])
    }

    func testRealtimeIsNotSentDuringOffload() {
        XCTAssertFalse(BackgroundOffload.shouldSendRealtime(backfilling: true))
        XCTAssertTrue(BackgroundOffload.shouldSendRealtime(backfilling: false))
    }
}
