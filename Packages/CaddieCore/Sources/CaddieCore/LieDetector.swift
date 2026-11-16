import Foundation

/// Works out where the ball lies from a point on the course map.
public enum LieDetector {
    /// How far outside a green still counts as fringe, in meters.
    public static let fringeMeters = 3.0
    /// A point farther than this from every outline of the hole is treated as off the map.
    public static let mappedRangeMeters = 120.0

    /// The lie at `point`, using the outlines in `features`.
    /// Order of precedence: green, bunker, water, tee, fairway, fringe, then rough.
    /// Returns `.unknown` when there are no outlines near the point to judge from.
    public static func lie(at point: Coordinate, features: [CourseFeature]) -> Lie {
        if features.isEmpty { return .unknown }

        func inside(_ kind: FeatureKind) -> Bool {
            for feature in features where feature.kind == kind {
                if Geo.contains(feature.ring, point) { return true }
            }
            return false
        }

        if inside(.green) { return .green }
        if inside(.bunker) { return .bunker }
        if inside(.water) { return .water }
        if inside(.tee) { return .tee }
        if inside(.fairway) { return .fairway }

        for feature in features where feature.kind == .green {
            if Geo.metersToRing(point, feature.ring) <= fringeMeters { return .fringe }
        }

        // Rough is "on the hole but in nothing else". Without a fairway outline there is no way
        // to tell fairway from rough, so say so rather than guess.
        let hasFairway = features.contains { $0.kind == .fairway }
        if !hasFairway { return .unknown }

        var nearest = Double.greatestFiniteMagnitude
        for feature in features {
            nearest = min(nearest, Geo.metersToRing(point, feature.ring))
            if nearest <= mappedRangeMeters { return .rough }
        }
        return .unknown
    }

    /// The lie for a mark on `hole` of `course`.
    public static func lie(at point: Coordinate, course: Course, hole number: Int) -> Lie {
        // A wayward shot can finish on the next hole's fairway or in its bunker, so every outline
        // counts, except other holes' greens and tees: landing there is still rough for this hole.
        let usable = course.features.filter { feature in
            if feature.kind == .green || feature.kind == .tee {
                return feature.hole == number || feature.hole == nil
            }
            return true
        }
        return lie(at: point, features: usable)
    }
}
