import XCTest
@testable import Strand
import WhoopProtocol
import WhoopStore

final class BackfillAckTests: XCTestCase {

    func testEmptyEndMustNotAck() {
        // Overnight at RSSI −86, METADATA END arrived without type-47.
        // Acking that trimmed last night off the strap with nothing stored.
        XCTAssertFalse(BackfillAck.shouldAck(dataFrames: 0, decodedSamples: 0,
                                            historicalDataFrames: 0))
    }

    func testDecodedChunkAcks() {
        XCTAssertTrue(BackfillAck.shouldAck(dataFrames: 50, decodedSamples: 50,
                                           historicalDataFrames: 50))
    }

    func testUndecodedDataFramesMustNotAck() {
        // type-47 frames arrived, extract produced nothing (unmapped
        // hist_version), and we still trimmed the strap.
        XCTAssertFalse(BackfillAck.shouldAck(dataFrames: 50, decodedSamples: 0,
                                            historicalDataFrames: 50))
    }

    func testConsoleLogsAndEventsMayAck() {
        // After 13 Sep the strap served CONSOLE_LOGS + EVENT, not type-47.
        // Refusing that ack froze trim at 75984 and last night never moved.
        XCTAssertTrue(BackfillAck.shouldAck(dataFrames: 32, decodedSamples: 0,
                                           historicalDataFrames: 0))
    }

    func testEventsAndBatteryDoNotCountAsBiometrics() {
        var onlyEvents = Streams.empty
        onlyEvents.events = [WhoopEvent(ts: 1, kind: "BATTERY_LEVEL(3)", payload: [:])]
        onlyEvents.battery = [BatterySample(ts: 1, soc: 80, mv: 4000)]
        XCTAssertEqual(BackfillAck.biometricCount(onlyEvents), 0)

        var sleep = Streams.empty
        sleep.gravity = [GravitySample(ts: 1, x: 0, y: 0, z: 1)]
        sleep.hr = [HRSample(ts: 1, bpm: 52)]
        XCTAssertEqual(BackfillAck.biometricCount(sleep), 2)
    }
}

@MainActor
final class BackfillerEmptyAckTests: XCTestCase {

    func testEmptyHistoryEndDoesNotTrimOrAck() async {
        let store = SpyBackfillStore()
        var acks: [UInt32] = []
        let backfiller = Backfiller(
            store: store,
            deviceId: "d",
            ackTrim: { trim, _ in acks.append(trim) })
        backfiller.begin()
        await backfiller.ingest(Self.historyEnd(unix: 1_700_000_000, trim: 99))
        XCTAssertEqual(acks, [])
        XCTAssertNil(store.cursors["strap_trim"])
        XCTAssertEqual(store.inserts, 0)
    }

    func testConsoleLogChunkAcksWithoutBiometrics() async {
        let store = SpyBackfillStore()
        var acks: [UInt32] = []
        let backfiller = Backfiller(
            store: store,
            deviceId: "d",
            ackTrim: { trim, _ in acks.append(trim) })
        backfiller.begin()
        await backfiller.ingest(frameFromPayload([0x4c, 0x6f, 0x67], type: 50, seq: 0, cmd: 0))
        await backfiller.ingest(Self.historyEnd(unix: 1_700_000_000, trim: 7))
        XCTAssertEqual(acks, [7])
        XCTAssertEqual(store.cursors["strap_trim"], 7)
    }

    func testDecodedHistoricalChunkAcks() async {
        let store = SpyBackfillStore()
        var acks: [UInt32] = []
        let backfiller = Backfiller(
            store: store,
            deviceId: "d",
            ackTrim: { trim, _ in acks.append(trim) })
        backfiller.begin()
        await backfiller.ingest(Self.v24Record)
        await backfiller.ingest(Self.historyEnd(unix: 1_700_000_000, trim: 42))
        XCTAssertEqual(acks, [42])
        XCTAssertEqual(store.cursors["strap_trim"], 42)
        XCTAssertEqual(store.inserts, 1)
    }

    private static func historyEnd(unix: UInt32, trim: UInt32) -> [UInt8] {
        func le32(_ v: UInt32) -> [UInt8] {
            [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
             UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
        }
        func le16(_ v: UInt16) -> [UInt8] {
            [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]
        }
        // unix + subsec + unk0 + trim + extra u32 so frame[17..<25] exists
        let payload = le32(unix) + le16(0) + le32(0) + le32(trim) + le32(0)
        return frameFromPayload(payload, type: 49, seq: 0, cmd: 2)
    }

    private static let v24Record: [UInt8] = {
        let hex =
            "aa5a008e2f18000000000000f153650000000000003f0152030000000000000000dc053075" +
            "000000cdcc4c3dcdcccc3d5a657e3f00000040cdcc4c3dcdcccc3d5a657e3f504668428403" +
            "200364006400b80bb80b000000000000c25c1a88"
        var out = [UInt8]()
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            out.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        return out
    }()
}

@MainActor
private final class SpyBackfillStore: BackfillStoreWriting {
    var inserts = 0
    var cursors: [String: Int] = [:]

    func insert(_ streams: Streams, deviceId: String) async throws
        -> (hr: Int, rr: Int, events: Int, battery: Int,
            spo2: Int, skinTemp: Int, resp: Int, gravity: Int) {
        inserts += 1
        return (streams.hr.count, streams.rr.count, streams.events.count, streams.battery.count,
                streams.spo2.count, streams.skinTemp.count, streams.resp.count, streams.gravity.count)
    }

    func enqueueRawBatch(_ meta: RawBatchMeta, frames: [[UInt8]]) async throws {}

    func setCursor(_ name: String, _ value: Int) async throws {
        cursors[name] = value
    }

    func cursor(_ name: String) async throws -> Int? {
        cursors[name]
    }
}
