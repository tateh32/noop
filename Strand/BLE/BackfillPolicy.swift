import Foundation

/// What prompted a sync attempt. Mirrors WHOOP (15-min periodic floor + event-triggered "process now"
/// syncs + the strap's own prompt events + manual), adapted to iOS.
enum BackfillTrigger {
    case periodic    // the repeating timer while connected+bonded
    case connect     // a (re)connect / bond confirmation
    case foreground  // the app became active (scenePhase .active)
    case background  // the app left the screen — keep historical pull alive
    case resume      // watchdog timeout / drop — finish the pull without the 90s floor
    case manual      // the user tapped "Sync now"
    case strap       // an incoming strap EVENT packet (WHOOP's HighFreqSyncPrompt analog)
}

/// Pure rate-limiter for historical-offload kicks. No BLE/store deps. Floors match WHOOP
/// (observed: ~15-min periodic + expedited event syncs).
enum BackfillPolicy {
    static let periodicFloorSeconds: TimeInterval = 900   // 15 min
    static let eventFloorSeconds: TimeInterval = 90       // absorbs reconnect-flaps / event bursts

    static func shouldRun(trigger: BackfillTrigger, now: TimeInterval,
                          lastBackfillAt: TimeInterval?) -> Bool {
        guard let last = lastBackfillAt else { return true }
        let elapsed = now - last
        switch trigger {
        case .manual, .resume:               return true
        case .connect, .foreground, .background, .strap:  return elapsed >= eventFloorSeconds
        case .periodic:                      return elapsed >= periodicFloorSeconds
        }
    }

    /// A deferred beginBackfill (handshake not done, store not ready) must NOT consume the
    /// rate-limit token. On iOS, CoreBluetooth restore marks connected+bonded before the
    /// connect handshake; scenePhase `.active` then calls requestSync(.foreground), which
    /// used to stamp `backfillLastAt` and return. The real `.connect` kick 1.5s later was
    /// then skipped for 90s — and the 15-min timer does not fire while suspended — so
    /// overnight history never left the strap.
    static func shouldStartSession(handshakeDone: Bool, storeReady: Bool) -> Bool {
        handshakeDone && storeReady
    }
}
