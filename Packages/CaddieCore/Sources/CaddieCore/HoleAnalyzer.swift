import Foundation

public enum ApproachResult: String, Codable, CaseIterable {
    case green, short, long, left, right

    public var label: String {
        switch self {
        case .green: return "On the green"
        case .short: return "Short"
        case .long: return "Long"
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

/// One stroke worked out from two consecutive marks.
public struct Stroke: Equatable {
    /// 1 for the tee shot.
    public var number: Int
    public var club: String?
    public var startLie: Lie
    public var start: Coordinate
    /// Where the ball finished. Nil when it was lost, out of bounds or in water and not found.
    public var end: Coordinate?
    public var endLie: Lie?
    /// Penalty strokes this stroke cost.
    public var penaltyStrokes: Int
    public var penalty: PenaltyKind?
    /// Yards to the green center before the stroke; nil when the green is not mapped.
    public var yardsToGreenBefore: Double?
    public var yardsToGreenAfter: Double?
    /// Yards the ball travelled; nil when the end is unknown.
    public var yards: Double? {
        guard let end = end else { return nil }
        return Geo.yards(start, end)
    }
    public var holed: Bool
}

/// Everything the statistics need to know about one finished hole.
public struct HoleSummary: Equatable {
    public var number: Int
    public var par: Int
    public var strokes: Int
    public var putts: Int
    public var penaltyStrokes: Int
    public var penalties: [PenaltyKind]
    public var gir: Bool
    /// Nil on par 3s and when not recorded.
    public var teeResult: TeeResult?
    public var approach: ApproachResult?
    /// Yards from the green center when the approach shot was played.
    public var approachYards: Double?
    public var chips: Int
    public var sandShots: Int
    public var scrambleChance: Bool
    public var scrambled: Bool
    public var upAndDownChance: Bool
    public var upAndDown: Bool
    public var sandSaveChance: Bool
    public var sandSave: Bool
    public var firstPuttFeet: Double?
    public var puttFeet: [Double]
    /// True when the hole was typed in without the map.
    public var isQuick: Bool
    public var strokesList: [Stroke]

    public var toPar: Int { strokes - par }
    public var threePutt: Bool { putts >= 3 }
    public var onePutt: Bool { putts == 1 }
}

/// Turns the marks and putts recorded on a hole into its statistics.
public enum HoleAnalyzer {
    /// Shots from inside this many yards of the green center, off the green, are chips.
    public static let shortGameYards = 30.0

    /// The strokes played from off the green, in order, each with where it finished.
    public static func strokes(for score: HoleScore, hole: Hole?) -> [Stroke] {
        let green = hole?.greenCenter
        let off = score.offGreenMarks
        // The spot the ball first came to rest on the green, when it was marked.
        let greenMark = score.marks.first { $0.lie == .green }
        var result: [Stroke] = []
        for (index, mark) in off.enumerated() {
            var end: Coordinate?
            var endLie: Lie?
            var penalty: PenaltyKind?
            var holed = false
            if index + 1 < off.count {
                let next = off[index + 1]
                if let kind = next.penaltyBefore {
                    // The ball was not played from where it finished.
                    penalty = kind
                    end = nil
                    endLie = kind == .water ? .water : nil
                } else {
                    end = next.coordinate
                    endLie = next.lie
                }
            } else if score.holedFromOffGreen {
                end = green
                endLie = .green
                holed = true
            } else if !score.putts.isEmpty {
                end = greenMark?.coordinate ?? green
                endLie = .green
            }
            var before: Double?
            var after: Double?
            if let green = green {
                before = Geo.yards(mark.coordinate, green)
                if holed {
                    after = 0
                } else if let end = end {
                    after = Geo.yards(end, green)
                }
            }
            result.append(Stroke(number: 0, club: mark.club, startLie: mark.lie, start: mark.coordinate, end: end,
                                 endLie: endLie, penaltyStrokes: penalty?.strokes ?? 0, penalty: penalty,
                                 yardsToGreenBefore: before, yardsToGreenAfter: after, holed: holed))
        }
        // Number the strokes, counting the penalty strokes in between.
        var number = 1
        for i in 0..<result.count {
            result[i].number = number
            number += 1 + result[i].penaltyStrokes
        }
        return result
    }

    /// The summary of a finished hole; nil when the hole is not finished.
    public static func summary(for score: HoleScore, hole: Hole?) -> HoleSummary? {
        guard let strokes = score.strokes else { return nil }
        let putts = score.puttCount
        let gir = (strokes - putts) <= (score.par - 2)

        if let quick = score.quick {
            let missed = !gir
            let saved = missed && strokes <= score.par
            return HoleSummary(
                number: score.number, par: score.par, strokes: strokes, putts: putts,
                penaltyStrokes: quick.penaltyStrokes, penalties: [], gir: gir,
                teeResult: score.par >= 4 ? quick.teeResult : nil, approach: nil, approachYards: nil,
                chips: quick.chips, sandShots: quick.sandShots, scrambleChance: missed, scrambled: saved,
                upAndDownChance: false, upAndDown: false, sandSaveChance: false, sandSave: false,
                firstPuttFeet: nil, puttFeet: [], isQuick: true, strokesList: [])
        }

        let list = HoleAnalyzer.strokes(for: score, hole: hole)
        let off = score.offGreenMarks
        let green = hole?.greenCenter
        let penalties = score.marks.compactMap { $0.penaltyBefore }

        // Tee shot result.
        var teeResult: TeeResult?
        if score.par >= 4, let first = list.first {
            if first.penalty != nil {
                teeResult = .penalty
            } else if let endLie = first.endLie, let end = first.end {
                if endLie == .fairway || endLie == .green || endLie == .fringe {
                    teeResult = .fairway
                } else if endLie == .unknown {
                    teeResult = nil
                } else {
                    teeResult = side(of: end, hole: hole, from: first.start)
                }
            }
        }

        // Approach shot.
        var approach: ApproachResult?
        var approachYards: Double?
        if let stroke = approachStroke(in: list, par: score.par) {
            approachYards = stroke.yardsToGreenBefore
            if stroke.endLie == .green {
                approach = .green
            } else if let end = stroke.end, let green = green {
                approach = miss(from: stroke.start, end: end, green: green)
            }
        }

        // Short game.
        var chips = 0
        var sandShots = 0
        for (index, mark) in off.enumerated() {
            if mark.lie == .bunker { sandShots += 1 }
            if index == 0 { continue }
            if let green = green, Geo.yards(mark.coordinate, green) <= shortGameYards {
                chips += 1
            }
        }

        let missed = !gir
        var upAndDownChance = false
        var sandSaveChance = false
        if missed, off.count >= 2, let last = off.last {
            var near = false
            if let green = green {
                near = Geo.yards(last.coordinate, green) <= shortGameYards
            } else {
                near = last.lie == .bunker || last.lie == .fringe
            }
            if near {
                upAndDownChance = true
                sandSaveChance = last.lie == .bunker
            }
        }
        let downInTwo = putts <= 1
        let feet = score.putts.map { $0.feet }

        return HoleSummary(
            number: score.number, par: score.par, strokes: strokes, putts: putts,
            penaltyStrokes: score.penaltyStrokes, penalties: penalties, gir: gir, teeResult: teeResult,
            approach: approach, approachYards: approachYards, chips: chips, sandShots: sandShots,
            scrambleChance: missed, scrambled: missed && strokes <= score.par,
            upAndDownChance: upAndDownChance, upAndDown: upAndDownChance && downInTwo,
            sandSaveChance: sandSaveChance, sandSave: sandSaveChance && downInTwo,
            firstPuttFeet: feet.first, puttFeet: feet, isQuick: false, strokesList: list)
    }

    /// The stroke counted as the approach: the tee shot on a par 3, otherwise the first stroke
    /// after the tee shot played from more than `shortGameYards` out.
    static func approachStroke(in list: [Stroke], par: Int) -> Stroke? {
        if par <= 3 { return list.first }
        for stroke in list.dropFirst() {
            if let yards = stroke.yardsToGreenBefore {
                if yards > shortGameYards { return stroke }
            } else {
                return stroke
            }
        }
        return nil
    }

    /// Left or right of the hole's playing line.
    static func side(of point: Coordinate, hole: Hole?, from start: Coordinate) -> TeeResult? {
        var segment: (Coordinate, Coordinate)?
        if let line = hole?.playingLine, line.count >= 2 {
            segment = Geo.nearestSegment(of: line, to: point)
        }
        if segment == nil, let green = hole?.greenCenter {
            segment = (start, green)
        }
        guard let (a, b) = segment else { return nil }
        let offset = Geo.metersRightOfLine(point, from: a, to: b)
        return offset < 0 ? .left : .right
    }

    /// How an approach that missed the green missed it, judged along the line of the shot.
    static func miss(from start: Coordinate, end: Coordinate, green: Coordinate) -> ApproachResult {
        let along = Geo.metersAlongLine(end, from: start, to: green) - Geo.meters(start, green)
        let across = Geo.metersRightOfLine(end, from: start, to: green)
        if abs(along) >= abs(across) {
            return along < 0 ? .short : .long
        }
        return across < 0 ? .left : .right
    }
}
