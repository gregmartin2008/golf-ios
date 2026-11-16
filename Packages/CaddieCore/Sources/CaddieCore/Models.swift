import Foundation

// MARK: - Course

/// What a mapped outline on the course is.
public enum FeatureKind: String, Codable, CaseIterable {
    case tee, fairway, green, bunker, water, rough
}

/// One outline from the course map (a green, a bunker, a fairway).
public struct CourseFeature: Codable, Equatable, Identifiable {
    public var id: String
    public var kind: FeatureKind
    public var ring: [Coordinate]
    /// The hole this outline belongs to, when that could be worked out.
    public var hole: Int?

    public init(id: String, kind: FeatureKind, ring: [Coordinate], hole: Int? = nil) {
        self.id = id
        self.kind = kind
        self.ring = ring
        self.hole = hole
    }
}

public struct Hole: Codable, Equatable, Identifiable {
    public var number: Int
    public var par: Int
    public var strokeIndex: Int
    public var tee: Coordinate?
    public var greenCenter: Coordinate?
    public var greenFront: Coordinate?
    public var greenBack: Coordinate?
    /// The playing line from tee to green; two or more points when known.
    public var line: [Coordinate]

    public var id: Int { number }

    public init(number: Int, par: Int = 4, strokeIndex: Int? = nil, tee: Coordinate? = nil,
                greenCenter: Coordinate? = nil, greenFront: Coordinate? = nil, greenBack: Coordinate? = nil,
                line: [Coordinate] = []) {
        self.number = number
        self.par = par
        self.strokeIndex = strokeIndex ?? number
        self.tee = tee
        self.greenCenter = greenCenter
        self.greenFront = greenFront
        self.greenBack = greenBack
        self.line = line
    }

    /// True when the hole has enough on the map to show distances.
    public var isMapped: Bool { tee != nil && greenCenter != nil }

    /// The line used for left and right: the mapped line, else tee to green.
    public var playingLine: [Coordinate] {
        if line.count >= 2 { return line }
        if let tee = tee, let green = greenCenter { return [tee, green] }
        return []
    }
}

public struct TeeSet: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var rating: Double
    public var slope: Int
    public var par: Int
    /// Yardage of each hole from this tee, in hole order. May be empty.
    public var yards: [Int]
    public var ghinTeeSetID: Int?
    public var gender: String?

    public init(id: UUID = UUID(), name: String, rating: Double, slope: Int, par: Int, yards: [Int] = [],
                ghinTeeSetID: Int? = nil, gender: String? = nil) {
        self.id = id
        self.name = name
        self.rating = rating
        self.slope = slope
        self.par = par
        self.yards = yards
        self.ghinTeeSetID = ghinTeeSetID
        self.gender = gender
    }

    public var totalYards: Int { yards.reduce(0, +) }
}

public struct Course: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var city: String
    public var state: String
    public var location: Coordinate
    public var osmID: String?
    public var ghinCourseID: Int?
    public var holes: [Hole]
    public var tees: [TeeSet]
    public var features: [CourseFeature]
    public var boundary: [Coordinate]

    public init(id: UUID = UUID(), name: String, city: String = "", state: String = "", location: Coordinate,
                osmID: String? = nil, ghinCourseID: Int? = nil, holes: [Hole] = [], tees: [TeeSet] = [],
                features: [CourseFeature] = [], boundary: [Coordinate] = []) {
        self.id = id
        self.name = name
        self.city = city
        self.state = state
        self.location = location
        self.osmID = osmID
        self.ghinCourseID = ghinCourseID
        self.holes = holes
        self.tees = tees
        self.features = features
        self.boundary = boundary
    }

    public var par: Int { holes.reduce(0) { $0 + $1.par } }

    public func hole(_ number: Int) -> Hole? {
        holes.first { $0.number == number }
    }

    /// Outlines for one hole, plus any that were never assigned to a hole.
    public func features(forHole number: Int) -> [CourseFeature] {
        features.filter { $0.hole == number || $0.hole == nil }
    }

    /// A blank course with `count` par-4 holes, for a course that is not on the map yet.
    public static func blank(name: String, location: Coordinate, holeCount count: Int = 18) -> Course {
        let holes = (1...max(1, count)).map { Hole(number: $0) }
        return Course(name: name, location: location, holes: holes)
    }
}

// MARK: - Round

/// Where the ball lies.
public enum Lie: String, Codable, CaseIterable {
    case tee, fairway, rough, bunker, green, fringe, recovery, water, unknown

    public var label: String {
        switch self {
        case .tee: return "Tee"
        case .fairway: return "Fairway"
        case .rough: return "Rough"
        case .bunker: return "Bunker"
        case .green: return "Green"
        case .fringe: return "Fringe"
        case .recovery: return "Trees"
        case .water: return "Water"
        case .unknown: return "Not set"
        }
    }
}

public enum PenaltyKind: String, Codable, CaseIterable {
    case water, outOfBounds, lostBall, unplayable

    public var label: String {
        switch self {
        case .water: return "Water"
        case .outOfBounds: return "Out of bounds"
        case .lostBall: return "Lost ball"
        case .unplayable: return "Unplayable"
        }
    }

    /// Penalty strokes added. All four cost one stroke.
    public var strokes: Int { 1 }
}

public enum MarkSource: String, Codable {
    case tee, gps, touch
}

/// A spot the ball lay and a stroke was played from. Mark 0 on a hole is the tee.
public struct BallMark: Codable, Equatable, Identifiable {
    public var id: UUID
    public var coordinate: Coordinate
    public var lie: Lie
    public var source: MarkSource
    /// GPS accuracy in meters when the mark came from GPS.
    public var accuracy: Double?
    /// The club used for the stroke played from this mark.
    public var club: String?
    /// Set when this mark is a drop or a replay after a penalty.
    public var penaltyBefore: PenaltyKind?

    public init(id: UUID = UUID(), coordinate: Coordinate, lie: Lie, source: MarkSource, accuracy: Double? = nil,
                club: String? = nil, penaltyBefore: PenaltyKind? = nil) {
        self.id = id
        self.coordinate = coordinate
        self.lie = lie
        self.source = source
        self.accuracy = accuracy
        self.club = club
        self.penaltyBefore = penaltyBefore
    }
}

public struct Putt: Codable, Equatable {
    /// Length of the putt in feet.
    public var feet: Double

    public init(feet: Double) {
        self.feet = feet
    }
}

public enum TeeResult: String, Codable, CaseIterable {
    case fairway, left, right, short, penalty

    public var label: String {
        switch self {
        case .fairway: return "Fairway"
        case .left: return "Left"
        case .right: return "Right"
        case .short: return "Short"
        case .penalty: return "Penalty"
        }
    }
}

/// A hole typed in without the map.
public struct QuickEntry: Codable, Equatable {
    public var strokes: Int
    public var putts: Int
    public var teeResult: TeeResult?
    public var penaltyStrokes: Int
    public var sandShots: Int
    public var chips: Int

    public init(strokes: Int, putts: Int, teeResult: TeeResult? = nil, penaltyStrokes: Int = 0, sandShots: Int = 0,
                chips: Int = 0) {
        self.strokes = strokes
        self.putts = putts
        self.teeResult = teeResult
        self.penaltyStrokes = penaltyStrokes
        self.sandShots = sandShots
        self.chips = chips
    }
}

public struct HoleScore: Codable, Equatable, Identifiable {
    public var number: Int
    public var par: Int
    public var strokeIndex: Int
    public var yards: Int
    public var marks: [BallMark]
    public var putts: [Putt]
    /// True when the last stroke from off the green went in (no putts).
    public var holedFromOffGreen: Bool
    public var quick: QuickEntry?

    public var id: Int { number }

    public init(number: Int, par: Int, strokeIndex: Int, yards: Int = 0, marks: [BallMark] = [], putts: [Putt] = [],
                holedFromOffGreen: Bool = false, quick: QuickEntry? = nil) {
        self.number = number
        self.par = par
        self.strokeIndex = strokeIndex
        self.yards = yards
        self.marks = marks
        self.putts = putts
        self.holedFromOffGreen = holedFromOffGreen
        self.quick = quick
    }

    /// Marks the ball was played from other than on the green.
    public var offGreenMarks: [BallMark] {
        marks.filter { $0.lie != .green }
    }

    public var penaltyStrokes: Int {
        if let quick = quick { return quick.penaltyStrokes }
        return marks.reduce(0) { $0 + ($1.penaltyBefore?.strokes ?? 0) }
    }

    public var puttCount: Int {
        if let quick = quick { return quick.putts }
        return putts.count
    }

    /// Whether the hole has been finished.
    public var isComplete: Bool {
        if quick != nil { return true }
        if marks.isEmpty { return false }
        return !putts.isEmpty || holedFromOffGreen
    }

    /// Gross strokes including penalty strokes; nil until the hole is finished.
    public var strokes: Int? {
        if let quick = quick { return quick.strokes }
        guard isComplete else { return nil }
        return offGreenMarks.count + putts.count + penaltyStrokes
    }

    /// Strokes so far on a hole in progress.
    public var strokesSoFar: Int {
        if let quick = quick { return quick.strokes }
        return offGreenMarks.count + putts.count + penaltyStrokes
    }
}

public enum RoundStatus: String, Codable {
    case inProgress, finished
}

public enum RoundSource: String, Codable {
    case app, ghin
}

/// What is known about a round read from GHIN, which carries totals but not shots.
public struct ImportedScore: Codable, Equatable {
    public var adjustedGross: Int
    public var differential: Double
    public var ghinScoreID: Int?
    public var scoreType: String?

    public init(adjustedGross: Int, differential: Double, ghinScoreID: Int? = nil, scoreType: String? = nil) {
        self.adjustedGross = adjustedGross
        self.differential = differential
        self.ghinScoreID = ghinScoreID
        self.scoreType = scoreType
    }
}

public struct GHINPostState: Codable, Equatable {
    public var postedAt: Date?
    public var scoreID: Int?
    public var message: String?

    public init(postedAt: Date? = nil, scoreID: Int? = nil, message: String? = nil) {
        self.postedAt = postedAt
        self.scoreID = scoreID
        self.message = message
    }

    public var isPosted: Bool { postedAt != nil }
}

public struct Round: Codable, Equatable, Identifiable {
    public var id: UUID
    public var courseID: UUID?
    public var courseName: String
    public var teeID: UUID?
    public var teeName: String
    public var rating: Double
    public var slope: Int
    public var par: Int
    public var date: Date
    public var holeCount: Int
    public var holes: [HoleScore]
    public var status: RoundStatus
    public var handicapIndexAtPlay: Double?
    public var isPractice: Bool
    public var ghin: GHINPostState
    public var source: RoundSource
    public var imported: ImportedScore?

    public init(id: UUID = UUID(), courseID: UUID? = nil, courseName: String, teeID: UUID? = nil, teeName: String = "",
                rating: Double = 72, slope: Int = 113, par: Int = 72, date: Date = Date(), holeCount: Int = 18,
                holes: [HoleScore] = [], status: RoundStatus = .inProgress, handicapIndexAtPlay: Double? = nil,
                isPractice: Bool = false, ghin: GHINPostState = GHINPostState(), source: RoundSource = .app,
                imported: ImportedScore? = nil) {
        self.id = id
        self.courseID = courseID
        self.courseName = courseName
        self.teeID = teeID
        self.teeName = teeName
        self.rating = rating
        self.slope = slope
        self.par = par
        self.date = date
        self.holeCount = holeCount
        self.holes = holes
        self.status = status
        self.handicapIndexAtPlay = handicapIndexAtPlay
        self.isPractice = isPractice
        self.ghin = ghin
        self.source = source
        self.imported = imported
    }

    public var completedHoles: [HoleScore] { holes.filter { $0.isComplete } }

    /// Gross score over the finished holes.
    public var grossSoFar: Int { completedHoles.reduce(0) { $0 + ($1.strokes ?? 0) } }

    public var parSoFar: Int { completedHoles.reduce(0) { $0 + $1.par } }

    /// True when every hole of the round has a score.
    public var isFullyScored: Bool {
        !holes.isEmpty && holes.allSatisfy { $0.isComplete }
    }

    /// The round's total: the gross score when scored in the app, the adjusted gross from GHIN
    /// when imported.
    public var total: Int? {
        if let imported = imported { return imported.adjustedGross }
        return isFullyScored ? grossSoFar : nil
    }

    /// Builds a new round on `course` from `tee`, starting at `startHole`.
    public static func start(course: Course, tee: TeeSet?, holeCount: Int, startHole: Int, date: Date = Date(),
                             handicapIndex: Double? = nil) -> Round {
        let all = course.holes.sorted { $0.number < $1.number }
        var chosen: [Hole] = []
        if let startIndex = all.firstIndex(where: { $0.number == startHole }) {
            let count = min(holeCount, all.count)
            for offset in 0..<count {
                chosen.append(all[(startIndex + offset) % all.count])
            }
        } else {
            chosen = Array(all.prefix(holeCount))
        }
        let scores: [HoleScore] = chosen.map { hole in
            var yards = 0
            if let tee = tee, hole.number - 1 < tee.yards.count, hole.number >= 1 {
                yards = tee.yards[hole.number - 1]
            }
            return HoleScore(number: hole.number, par: hole.par, strokeIndex: hole.strokeIndex, yards: yards)
        }
        let roundPar = scores.reduce(0) { $0 + $1.par }
        var rating = tee?.rating ?? Double(course.par)
        if chosen.count < all.count, all.count > 0 {
            // A nine-hole round on an eighteen-hole rating: use half the rating.
            rating = rating * Double(chosen.count) / Double(all.count)
        }
        return Round(courseID: course.id, courseName: course.name, teeID: tee?.id, teeName: tee?.name ?? "",
                     rating: rating, slope: tee?.slope ?? 113, par: roundPar, date: date, holeCount: scores.count,
                     holes: scores, status: .inProgress, handicapIndexAtPlay: handicapIndex)
    }
}

// MARK: - Bag and settings

public struct Club: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var inBag: Bool

    public init(id: UUID = UUID(), name: String, inBag: Bool = true) {
        self.id = id
        self.name = name
        self.inBag = inBag
    }

    public static let standardNames: [String] = [
        "Driver", "3 Wood", "5 Wood", "Hybrid", "4 Iron", "5 Iron", "6 Iron", "7 Iron", "8 Iron", "9 Iron",
        "PW", "GW", "SW", "LW", "Putter",
    ]

    public static var standardBag: [Club] {
        standardNames.map { Club(name: $0) }
    }
}

public struct GHINAccount: Codable, Equatable {
    public var login: String
    public var ghinNumber: Int?
    public var name: String?
    public var handicapIndex: Double?
    public var lowIndex: Double?
    public var clubName: String?
    public var lastSync: Date?

    public init(login: String, ghinNumber: Int? = nil, name: String? = nil, handicapIndex: Double? = nil,
                lowIndex: Double? = nil, clubName: String? = nil, lastSync: Date? = nil) {
        self.login = login
        self.ghinNumber = ghinNumber
        self.name = name
        self.handicapIndex = handicapIndex
        self.lowIndex = lowIndex
        self.clubName = clubName
        self.lastSync = lastSync
    }
}

public struct Settings: Codable, Equatable {
    public var useMeters: Bool
    public var ghin: GHINAccount?
    /// A handicap index typed in by hand, used when GHIN is not connected.
    public var manualIndex: Double?
    public var gender: String

    public init(useMeters: Bool = false, ghin: GHINAccount? = nil, manualIndex: Double? = nil, gender: String = "M") {
        self.useMeters = useMeters
        self.ghin = ghin
        self.manualIndex = manualIndex
        self.gender = gender
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        useMeters = try c.decodeIfPresent(Bool.self, forKey: .useMeters) ?? false
        ghin = try c.decodeIfPresent(GHINAccount.self, forKey: .ghin)
        manualIndex = try c.decodeIfPresent(Double.self, forKey: .manualIndex)
        gender = try c.decodeIfPresent(String.self, forKey: .gender) ?? "M"
    }
}
