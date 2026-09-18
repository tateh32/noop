import Foundation

/// What to do when the iPhone scene moves. Pure so lock-the-phone offload
/// can be tested without CoreBluetooth or UIKit.
enum BackgroundOffload {
    enum Phase: Equatable {
        case active, background, inactive
    }

    enum Action: Equatable {
        case persistSession
        case pruneRaw
        case stopLiveHR
        case startLiveHR
        case requestOffload
        case resumeConnection
    }

    static func actions(phase: Phase, trainRunning: Bool,
                        connected: Bool, bonded: Bool) -> [Action] {
        switch phase {
        case .inactive:
            return []
        case .active:
            var a: [Action] = []
            if trainRunning && bonded { a.append(.startLiveHR) }
            a.append(.resumeConnection)
            return a
        case .background:
            var a: [Action] = []
            if trainRunning { a.append(.persistSession) }
            a.append(.pruneRaw)
            if trainRunning { return a }
            a.append(.stopLiveHR)
            if bonded {
                a.append(.requestOffload)
            } else {
                a.append(.resumeConnection)
            }
            return a
        }
    }

    /// Heavy type-40/43 realtime starves type-47 during a pull. Keep-alive
    /// already skipped this; `startRealtime()` did not, and last night's
    /// offload timed out after a Toggle Realtime mid-session.
    static func shouldSendRealtime(backfilling: Bool) -> Bool { !backfilling }
}
