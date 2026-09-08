import Foundation

/// Helpers for chart series that were built for a Mac-sized window.
///
/// A WHOOP import is often years of daily points. Rendering every point as a
/// SwiftUI `Chart` mark (and giving each a fresh `UUID` identity) is what makes
/// Trends / Sleep hitch and jetsam on an iPhone.
public enum ChartSeries {

    /// Keep at most `maxCount` points, always including the first and last, by
    /// even stride. Empty / already-short series are returned unchanged.
    public static func downsample(_ points: [TrendPoint], maxCount: Int = 160) -> [TrendPoint] {
        guard maxCount >= 2, points.count > maxCount else { return points }
        let last = points.count - 1
        let step = Double(last) / Double(maxCount - 1)
        var out: [TrendPoint] = []
        out.reserveCapacity(maxCount)
        var seen = Set<Int>()
        for i in 0..<maxCount {
            let idx = i == maxCount - 1 ? last : min(last, Int((Double(i) * step).rounded()))
            if seen.insert(idx).inserted { out.append(points[idx]) }
        }
        return out
    }
}
