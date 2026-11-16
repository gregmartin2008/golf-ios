import Foundation

/// Strokes gained against the PGA Tour baseline published by Mark Broadie.
///
/// Off-green values are from Table B.1 of Broadie (2012), "Assessing Golfer Performance on the
/// PGA TOUR", Interfaces 42(2). Putting values are from Broadie (2011), "Putts Gained". Distances
/// are yards off the green and feet on it. Values between published points are interpolated in a
/// straight line; values beyond either end use the end value.
public enum StrokesGained {
    public enum Category: String, CaseIterable, Codable {
        case offTheTee, approach, aroundGreen, putting

        public var label: String {
            switch self {
            case .offTheTee: return "Off the tee"
            case .approach: return "Approach"
            case .aroundGreen: return "Around the green"
            case .putting: return "Putting"
            }
        }
    }

    public struct Totals: Equatable {
        public var offTheTee = 0.0
        public var approach = 0.0
        public var aroundGreen = 0.0
        public var putting = 0.0
        /// Number of strokes that could be measured.
        public var measuredStrokes = 0

        public init() {}

        public var total: Double { offTheTee + approach + aroundGreen + putting }

        public func value(_ category: Category) -> Double {
            switch category {
            case .offTheTee: return offTheTee
            case .approach: return approach
            case .aroundGreen: return aroundGreen
            case .putting: return putting
            }
        }

        mutating func add(_ value: Double, to category: Category) {
            switch category {
            case .offTheTee: offTheTee += value
            case .approach: approach += value
            case .aroundGreen: aroundGreen += value
            case .putting: putting += value
            }
            measuredStrokes += 1
        }

        public static func + (a: Totals, b: Totals) -> Totals {
            var sum = Totals()
            sum.offTheTee = a.offTheTee + b.offTheTee
            sum.approach = a.approach + b.approach
            sum.aroundGreen = a.aroundGreen + b.aroundGreen
            sum.putting = a.putting + b.putting
            sum.measuredStrokes = a.measuredStrokes + b.measuredStrokes
            return sum
        }
    }

    static let tee: [(Double, Double)] = [
        (100, 2.92), (120, 2.99), (140, 2.97), (160, 2.99), (180, 3.05), (200, 3.12), (220, 3.17), (240, 3.25),
        (260, 3.45), (280, 3.65), (300, 3.71), (320, 3.79), (340, 3.86), (360, 3.92), (380, 3.96), (400, 3.99),
        (420, 4.02), (440, 4.08), (460, 4.17), (480, 4.28), (500, 4.41), (520, 4.54), (540, 4.65), (560, 4.74),
        (580, 4.79), (600, 4.82),
    ]
    static let fairway: [(Double, Double)] = [
        (10, 2.18), (20, 2.40), (30, 2.52), (40, 2.60), (50, 2.66), (60, 2.70), (70, 2.72), (80, 2.75), (90, 2.77),
        (100, 2.80), (120, 2.85), (140, 2.91), (160, 2.98), (180, 3.08), (200, 3.19), (220, 3.32), (240, 3.45),
        (260, 3.58), (280, 3.69), (300, 3.78), (320, 3.84), (340, 3.88), (360, 3.95), (380, 4.03), (400, 4.11),
        (420, 4.19), (440, 4.27), (460, 4.34), (480, 4.42), (500, 4.50), (520, 4.58), (540, 4.66), (560, 4.74),
        (580, 4.82), (600, 4.89),
    ]
    static let rough: [(Double, Double)] = [
        (10, 2.34), (20, 2.59), (30, 2.70), (40, 2.78), (50, 2.87), (60, 2.91), (70, 2.93), (80, 2.96), (90, 2.99),
        (100, 3.02), (120, 3.08), (140, 3.15), (160, 3.23), (180, 3.31), (200, 3.42), (220, 3.53), (240, 3.64),
        (260, 3.74), (280, 3.83), (300, 3.90), (320, 3.95), (340, 4.02), (360, 4.11), (380, 4.21), (400, 4.30),
        (420, 4.40), (440, 4.49), (460, 4.58), (480, 4.68), (500, 4.77), (520, 4.87), (540, 4.96), (560, 5.06),
        (580, 5.15), (600, 5.25),
    ]
    static let sand: [(Double, Double)] = [
        (10, 2.43), (20, 2.53), (30, 2.66), (40, 2.82), (50, 2.92), (60, 3.15), (70, 3.21), (80, 3.24), (90, 3.24),
        (100, 3.23), (120, 3.21), (140, 3.22), (160, 3.28), (180, 3.40), (200, 3.55), (220, 3.70), (240, 3.84),
        (260, 3.93), (280, 4.00), (300, 4.04), (320, 4.12), (340, 4.26), (360, 4.41), (380, 4.55), (400, 4.69),
        (420, 4.83), (440, 4.97), (460, 5.11), (480, 5.25), (500, 5.40), (520, 5.54), (540, 5.68), (560, 5.82),
        (580, 5.96), (600, 6.10),
    ]
    static let recovery: [(Double, Double)] = [
        (10, 3.45), (20, 3.51), (30, 3.57), (40, 3.71), (50, 3.79), (60, 3.83), (70, 3.84), (80, 3.84), (90, 3.82),
        (100, 3.80), (120, 3.78), (140, 3.80), (160, 3.81), (180, 3.82), (200, 3.87), (220, 3.92), (240, 3.97),
        (260, 4.03), (280, 4.10), (300, 4.20), (320, 4.31), (340, 4.44), (360, 4.56), (380, 4.66), (400, 4.75),
        (420, 4.84), (440, 4.94), (460, 5.03), (480, 5.13), (500, 5.22), (520, 5.32), (540, 5.41), (560, 5.51),
        (580, 5.60), (600, 5.70),
    ]
    /// A one-foot tap-in is added so very short putts do not take the two-foot value.
    static let green: [(Double, Double)] = [
        (1, 1.00), (2, 1.01), (3, 1.05), (4, 1.14), (5, 1.24), (6, 1.34), (7, 1.43), (8, 1.50), (9, 1.56),
        (10, 1.61), (15, 1.78), (20, 1.87), (30, 1.98), (40, 2.06), (50, 2.14), (60, 2.21), (90, 2.36),
    ]

    static func interpolate(_ table: [(Double, Double)], _ x: Double) -> Double {
        guard let first = table.first, let last = table.last else { return 0 }
        if x <= first.0 { return first.1 }
        if x >= last.0 { return last.1 }
        for i in 1..<table.count {
            let a = table[i - 1], b = table[i]
            if x <= b.0 {
                let t = (x - a.0) / (b.0 - a.0)
                return a.1 + t * (b.1 - a.1)
            }
        }
        return last.1
    }

    /// Expected strokes to hole out from `lie` at `distance` (yards off the green, feet on it).
    /// Nil when the lie is not known.
    public static func expected(lie: Lie, distance: Double) -> Double? {
        if distance <= 0 { return 0 }
        switch lie {
        case .tee: return interpolate(tee, distance)
        case .fairway, .fringe: return interpolate(fairway, distance)
        case .rough: return interpolate(rough, distance)
        case .bunker: return interpolate(sand, distance)
        case .recovery: return interpolate(recovery, distance)
        case .green: return interpolate(green, distance)
        case .water, .unknown: return nil
        }
    }

    /// Which category a stroke from off the green belongs to.
    public static func category(strokeNumber: Int, par: Int, yardsToGreen: Double) -> Category {
        if strokeNumber == 1 && par >= 4 { return .offTheTee }
        if yardsToGreen <= HoleAnalyzer.shortGameYards { return .aroundGreen }
        return .approach
    }

    /// Strokes gained for one finished hole. Strokes whose start or finish cannot be measured
    /// (green not mapped, lie unknown) are left out.
    public static func totals(for score: HoleScore, hole: Hole?) -> Totals {
        var totals = Totals()
        if score.quick != nil { return totals }
        let feet = score.putts.map { $0.feet }
        let strokes = HoleAnalyzer.strokes(for: score, hole: hole)

        for (index, stroke) in strokes.enumerated() {
            guard let before = stroke.yardsToGreenBefore,
                  let expectedStart = expected(lie: stroke.startLie, distance: before) else { continue }
            var expectedEnd: Double?
            if stroke.holed {
                expectedEnd = 0
            } else if stroke.penalty != nil {
                // The next stroke is played from the next mark; use what is expected from there.
                if index + 1 < strokes.count, let nextBefore = strokes[index + 1].yardsToGreenBefore {
                    expectedEnd = expected(lie: strokes[index + 1].startLie, distance: nextBefore)
                }
            } else if stroke.endLie == .green {
                if let first = feet.first {
                    expectedEnd = expected(lie: .green, distance: first)
                } else if let after = stroke.yardsToGreenAfter {
                    expectedEnd = expected(lie: .green, distance: max(1, after * 3))
                }
            } else if let endLie = stroke.endLie, let after = stroke.yardsToGreenAfter {
                expectedEnd = expected(lie: endLie, distance: after)
            }
            guard let end = expectedEnd else { continue }
            let gained = expectedStart - end - 1 - Double(stroke.penaltyStrokes)
            totals.add(gained, to: category(strokeNumber: stroke.number, par: score.par, yardsToGreen: before))
        }

        for (index, length) in feet.enumerated() {
            guard let start = expected(lie: .green, distance: length) else { continue }
            var end = 0.0
            if index + 1 < feet.count {
                end = expected(lie: .green, distance: feet[index + 1]) ?? 0
            }
            totals.add(start - end - 1, to: .putting)
        }
        return totals
    }

    /// Strokes gained for a whole round.
    public static func totals(for round: Round, course: Course?) -> Totals {
        var sum = Totals()
        for score in round.holes where score.isComplete {
            sum = sum + totals(for: score, hole: course?.hole(score.number))
        }
        return sum
    }
}
