import Foundation

/// GPS helpers with no CoreLocation dependency so Mac tests can run them.
enum GeoDistance {
    /// Earth-mean radius used by the haversine formula.
    static let earthRadiusM: Double = 6_371_000

    /// Great-circle distance in metres between two WGS84 points.
    static func meters(fromLat lat1: Double, lon lon1: Double,
                       toLat lat2: Double, lon lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(p1) * cos(p2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusM * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }

    /// Horizontal accuracy from CoreLocation: negative is invalid.
    static func usableAccuracy(_ accuracyM: Double) -> Bool {
        accuracyM >= 0 && accuracyM <= 40
    }

    /// Accumulate a step when it is a real move, not jitter or a teleport.
    static func shouldAccumulate(deltaM: Double, accuracyM: Double) -> Bool {
        usableAccuracy(accuracyM) && deltaM >= 3 && deltaM < 80
    }
}
