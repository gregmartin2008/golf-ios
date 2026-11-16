import Foundation

/// World Handicap System arithmetic. The index this produces is an estimate: only a golf
/// association can issue an official one.
public enum Handicap {
    /// Course Handicap for an index on a set of tees, rounded to the nearest whole stroke.
    public static func courseHandicap(index: Double, slope: Int, rating: Double, par: Int) -> Int {
        let value = index * Double(slope) / 113.0 + (rating - Double(par))
        return Int(value.rounded())
    }

    /// Handicap strokes received on a hole with the given stroke index.
    /// Works for handicaps above 18 (two strokes on some holes) and plus handicaps (strokes given back).
    public static func strokesReceived(courseHandicap: Int, strokeIndex: Int, holeCount: Int = 18) -> Int {
        let holes = max(1, holeCount)
        if courseHandicap >= 0 {
            let base = courseHandicap / holes
            let extra = courseHandicap % holes
            return base + (strokeIndex <= extra ? 1 : 0)
        }
        // A plus handicap gives strokes back, starting with the easiest holes.
        let give = -courseHandicap
        let base = give / holes
        let extra = give % holes
        return -(base + (strokeIndex > holes - extra ? 1 : 0))
    }

    /// The most a hole can count for handicap purposes: net double bogey.
    public static func adjustedHoleScore(strokes: Int, par: Int, strokesReceived: Int) -> Int {
        min(strokes, par + 2 + strokesReceived)
    }

    /// Adjusted gross score of a round scored in the app. Without an index, a hole is capped at
    /// par plus five, which is the rule for a player with no handicap yet.
    public static func adjustedGross(for round: Round) -> Int? {
        if let imported = round.imported { return imported.adjustedGross }
        guard round.isFullyScored else { return nil }
        var total = 0
        var course: Int?
        if let index = round.handicapIndexAtPlay {
            course = courseHandicap(index: index, slope: round.slope, rating: round.rating, par: round.par)
        }
        for hole in round.holes {
            guard let strokes = hole.strokes else { return nil }
            if let course = course {
                // Stroke indexes run 1 to 18 even on a nine-hole round, so allocate over 18.
                let received = strokesReceived(courseHandicap: round.holes.count <= 9 ? course * 2 : course,
                                               strokeIndex: hole.strokeIndex, holeCount: 18)
                total += adjustedHoleScore(strokes: strokes, par: hole.par, strokesReceived: received)
            } else {
                total += min(strokes, hole.par + 5)
            }
        }
        return total
    }

    /// Score Differential, to one decimal.
    public static func differential(adjustedGross: Int, rating: Double, slope: Int) -> Double {
        guard slope > 0 else { return 0 }
        let value = (113.0 / Double(slope)) * (Double(adjustedGross) - rating)
        return (value * 10).rounded() / 10
    }

    /// The differential a round contributes; nil for unfinished, practice and nine-hole rounds
    /// scored in the app (nine-hole rounds are left to GHIN, which combines them).
    public static func differential(for round: Round) -> Double? {
        if let imported = round.imported { return imported.differential }
        guard round.status == .finished, !round.isPractice, round.holes.count >= 18 else { return nil }
        guard let gross = adjustedGross(for: round) else { return nil }
        return differential(adjustedGross: gross, rating: round.rating, slope: round.slope)
    }

    /// How many of the lowest differentials count, and the adjustment, for `count` available.
    public static func rule(forCount count: Int) -> (used: Int, adjustment: Double)? {
        switch count {
        case ..<3: return nil
        case 3: return (1, -2.0)
        case 4: return (1, -1.0)
        case 5: return (1, 0)
        case 6: return (2, -1.0)
        case 7...8: return (2, 0)
        case 9...11: return (3, 0)
        case 12...14: return (4, 0)
        case 15...16: return (5, 0)
        case 17...18: return (6, 0)
        case 19: return (7, 0)
        default: return (8, 0)
        }
    }

    public struct IndexResult: Equatable {
        public var index: Double
        /// Positions, within the differentials passed in, of those that counted.
        public var usedPositions: [Int]
        public var considered: Int
    }

    /// Handicap Index from differentials listed newest first. Uses the newest 20.
    /// Nil with fewer than three.
    public static func index(fromNewestFirst differentials: [Double]) -> IndexResult? {
        let recent = Array(differentials.prefix(20))
        guard let rule = rule(forCount: recent.count) else { return nil }
        let ordered = recent.enumerated().sorted { a, b in
            if a.element == b.element { return a.offset < b.offset }
            return a.element < b.element
        }
        let lowest = ordered.prefix(rule.used)
        let average = lowest.reduce(0.0) { $0 + $1.element } / Double(rule.used)
        var value = average + rule.adjustment
        value = (value * 10).rounded() / 10
        value = min(value, 54.0)
        return IndexResult(index: value, usedPositions: lowest.map { $0.offset }.sorted(), considered: recent.count)
    }

    public struct Entry: Equatable, Identifiable {
        public var id: UUID
        public var date: Date
        public var courseName: String
        public var score: Int
        public var differential: Double
        public var counts: Bool
        public var fromGHIN: Bool
    }

    public struct Report: Equatable {
        public var index: Double?
        /// Newest first, at most twenty.
        public var entries: [Entry]
    }

    /// The estimate and the rounds behind it, from every round that produces a differential.
    public static func report(rounds: [Round]) -> Report {
        var rows: [Entry] = []
        for round in rounds.sorted(by: { $0.date > $1.date }) {
            guard let value = differential(for: round), let score = adjustedGross(for: round) else { continue }
            rows.append(Entry(id: round.id, date: round.date, courseName: round.courseName, score: score,
                              differential: value, counts: false, fromGHIN: round.source == .ghin))
            if rows.count == 20 { break }
        }
        let result = index(fromNewestFirst: rows.map { $0.differential })
        if let result = result {
            for position in result.usedPositions where position < rows.count {
                rows[position].counts = true
            }
        }
        return Report(index: result?.index, entries: rows)
    }
}
