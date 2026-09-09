import Foundation
import Combine

/// Offload / frontier snapshot. Separate from `LiveState` so Today can show
/// last-sync without observing 1 Hz heart rate.
@MainActor
public final class OffloadStatus: ObservableObject {
    @Published public var lastSyncedAt: TimeInterval?
    /// Estimated unread records on the strap (1 Hz: newest unix − our HR frontier).
    @Published public var pendingRecords: Int?
    @Published public var strapNewestTs: Int?
    @Published public var frontierTs: Int?

    public init() {}

    public func noteSynced(at ts: TimeInterval) {
        lastSyncedAt = ts
    }

    public func noteRange(strapNewest: Int?, frontier: Int?) {
        strapNewestTs = strapNewest
        frontierTs = frontier
        pendingRecords = SyncStatus.pendingRecords(strapNewestTs: strapNewest,
                                                    frontierTs: frontier)
    }
}
