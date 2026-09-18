import Foundation
import WhoopProtocol

/// Whether a HISTORY_END may trim the strap.
///
/// Empty END (no data frames) at weak RSSI used to be acked, which discarded
/// last night's 1 Hz. Undecoded type-47 must not ack either.
/// CONSOLE_LOGS / EVENT-only chunks *do* ack so the queue can reach type-47.
enum BackfillAck {
    static func biometricCount(_ s: Streams) -> Int {
        s.hr.count + s.rr.count + s.spo2.count + s.skinTemp.count
            + s.resp.count + s.gravity.count
    }

    static func shouldAck(dataFrames: Int, decodedSamples: Int,
                          historicalDataFrames: Int) -> Bool {
        if decodedSamples > 0 { return true }
        if historicalDataFrames > 0 { return false }
        if dataFrames == 0 { return false }
        return true
    }
}
