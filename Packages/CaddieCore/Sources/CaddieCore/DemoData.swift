import Foundation

/// Invented content for the screenshots and for trying the app without a course: a made-up
/// eighteen-hole course and a handful of made-up rounds on it. Nothing here is real.
public enum DemoData {
    /// A repeatable source of numbers, so the demo looks the same on every run.
    struct Generator {
        var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) % 1_000_000) / 1_000_000.0
        }

        mutating func range(_ low: Double, _ high: Double) -> Double {
            low + (high - low) * next()
        }

        mutating func chance(_ p: Double) -> Bool { next() < p }
    }

    static let origin = Coordinate(lat: 39.5000, lon: -98.3500)
    static let pars = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 5, 3, 4, 4]
    static let indexes = [7, 3, 15, 1, 11, 17, 5, 9, 13, 8, 16, 2, 10, 6, 4, 18, 12, 14]
    static let blueYards = [395, 530, 175, 430, 380, 160, 545, 405, 370, 400, 185, 555, 390, 415, 520, 150, 385, 410]

    static func oval(center: Coordinate, alongMeters: Double, acrossMeters: Double, heading: Double) -> [Coordinate] {
        var ring: [Coordinate] = []
        let steps = 16
        for i in 0..<steps {
            let angle = Double(i) / Double(steps) * 2 * Double.pi
            let along = cos(angle) * alongMeters
            let across = sin(angle) * acrossMeters
            let p = Geo.destination(from: center, bearingDegrees: heading, meters: along)
            ring.append(Geo.destination(from: p, bearingDegrees: heading + 90, meters: across))
        }
        return ring
    }

    /// The made-up course.
    public static func course() -> Course {
        var holes: [Hole] = []
        var features: [CourseFeature] = []
        let yardsToMeters = 1 / Geo.yardsPerMeter
        for i in 0..<18 {
            let number = i + 1
            // Two rows of nine holes, alternating direction, like a simple parkland layout.
            let row = i / 9
            let column = i % 9
            let heading = column % 2 == 0 ? 10.0 : 190.0
            let rowStart = Geo.destination(from: origin, bearingDegrees: 180, meters: Double(row) * 620)
            var tee = Geo.destination(from: rowStart, bearingDegrees: 90, meters: Double(column) * 110)
            if column % 2 == 1 {
                tee = Geo.destination(from: tee, bearingDegrees: 0, meters: 480)
            }
            let length = Double(blueYards[i]) * yardsToMeters
            let green = Geo.destination(from: tee, bearingDegrees: heading, meters: length)
            let greenRing = oval(center: green, alongMeters: 14, acrossMeters: 11, heading: heading)
            let front = Geo.destination(from: green, bearingDegrees: heading + 180, meters: 14)
            let back = Geo.destination(from: green, bearingDegrees: heading, meters: 14)
            holes.append(Hole(number: number, par: pars[i], strokeIndex: indexes[i], tee: tee, greenCenter: green,
                              greenFront: front, greenBack: back, line: [tee, green]))
            features.append(CourseFeature(id: "demo-green-\(number)", kind: .green, ring: greenRing, hole: number))
            features.append(CourseFeature(id: "demo-tee-\(number)", kind: .tee,
                                          ring: oval(center: tee, alongMeters: 9, acrossMeters: 5, heading: heading),
                                          hole: number))
            if pars[i] >= 4 {
                let middle = Geo.destination(from: tee, bearingDegrees: heading, meters: length * 0.58)
                features.append(CourseFeature(
                    id: "demo-fairway-\(number)", kind: .fairway,
                    ring: oval(center: middle, alongMeters: length * 0.34, acrossMeters: 17, heading: heading), hole: number))
            }
            let bunkerSpot = Geo.destination(from: Geo.destination(from: green, bearingDegrees: heading + 180, meters: 6),
                                             bearingDegrees: heading + 90, meters: number % 2 == 0 ? 19 : -19)
            features.append(CourseFeature(id: "demo-bunker-\(number)", kind: .bunker,
                                          ring: oval(center: bunkerSpot, alongMeters: 8, acrossMeters: 5, heading: heading),
                                          hole: number))
            if number == 7 || number == 15 {
                let pond = Geo.destination(from: Geo.destination(from: tee, bearingDegrees: heading, meters: length * 0.55),
                                           bearingDegrees: heading + 90, meters: 38)
                features.append(CourseFeature(id: "demo-water-\(number)", kind: .water,
                                              ring: oval(center: pond, alongMeters: 30, acrossMeters: 14, heading: heading),
                                              hole: number))
            }
        }
        let blue = TeeSet(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!, name: "Blue", rating: 71.4,
                          slope: 128, par: 72, yards: blueYards)
        let white = TeeSet(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!, name: "White", rating: 69.6,
                           slope: 123, par: 72, yards: blueYards.map { Int(Double($0) * 0.93) })
        return Course(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!, name: "Sample Links",
                      city: "Anytown", state: "KS", location: origin, holes: holes, tees: [blue, white],
                      features: features, boundary: [])
    }

    static func playHole(_ hole: Hole, yards: Int, course: Course, generator g: inout Generator) -> HoleScore {
        var score = HoleScore(number: hole.number, par: hole.par, strokeIndex: hole.strokeIndex, yards: yards)
        guard let tee = hole.tee, let green = hole.greenCenter else { return score }
        let heading = Geo.bearing(tee, green)
        var position = tee
        var lie = Lie.tee
        var shot = 0
        var pendingPenalty: PenaltyKind?
        while shot < 9 {
            let remaining = Geo.yards(position, green)
            var club = "Driver"
            if lie == .tee && hole.par == 3 { club = remaining > 170 ? "5 Iron" : "8 Iron" }
            else if remaining < 30 { club = lie == .bunker ? "SW" : "LW" }
            else if remaining < 110 { club = "PW" }
            else if remaining < 150 { club = "9 Iron" }
            else if remaining < 175 { club = "7 Iron" }
            else if remaining < 205 { club = "5 Iron" }
            else if lie != .tee { club = "3 Wood" }
            score.marks.append(BallMark(coordinate: position, lie: lie, source: shot == 0 ? .tee : .gps,
                                        accuracy: shot == 0 ? nil : 4, club: club, penaltyBefore: pendingPenalty))
            pendingPenalty = nil
            shot += 1
            // Where this stroke finishes.
            let reach = lie == .tee && hole.par >= 4 ? g.range(205, 262) : min(remaining, 235)
            let carry: Double
            if remaining <= reach + 5 {
                // Going for the green: finish near it, sometimes on it.
                let spread = remaining < 30 ? 4.0 : max(6.0, remaining * 0.085)
                carry = remaining + g.range(-spread, spread)
            } else {
                carry = reach * g.range(0.9, 1.03)
            }
            let offline = g.range(-1, 1) * (remaining < 30 ? 3.0 : carry * 0.085)
            let forward = Geo.destination(from: position, bearingDegrees: Geo.bearing(position, green),
                                          meters: carry / Geo.yardsPerMeter)
            position = Geo.destination(from: forward, bearingDegrees: heading + 90, meters: offline / Geo.yardsPerMeter)
            lie = LieDetector.lie(at: position, course: course, hole: hole.number)
            if lie == .water {
                // Drop beside the water with a penalty stroke.
                position = Geo.destination(from: position, bearingDegrees: heading + 270, meters: 22)
                pendingPenalty = .water
                lie = .rough
                shot += 1
                continue
            }
            if lie == .unknown || lie == .tee { lie = .rough }
            if lie == .green { break }
        }
        if lie != .green {
            // Ran out of strokes off the green in this made-up hole; finish it with a chip-in.
            score.holedFromOffGreen = true
            return score
        }
        score.marks.append(BallMark(coordinate: position, lie: .green, source: .gps, accuracy: 4, club: "Putter"))
        var feet = max(2, Geo.feet(position, green) * g.range(0.6, 1.4))
        var putts: [Putt] = []
        while putts.count < 4 {
            let length = (feet * 2).rounded() / 2
            putts.append(Putt(feet: max(1, length)))
            let holeChance = feet <= 3 ? 0.97 : (feet <= 6 ? 0.6 : (feet <= 12 ? 0.28 : (feet <= 25 ? 0.1 : 0.03)))
            if g.chance(holeChance) { break }
            feet = max(1, feet * g.range(0.06, 0.22))
        }
        score.putts = putts
        return score
    }

    /// Made-up finished rounds on the made-up course, newest first, plus one in progress.
    public static func rounds(course: Course, now: Date = Date()) -> [Round] {
        var g = Generator(seed: 20_240_601)
        var result: [Round] = []
        guard let tee = course.tees.first else { return [] }
        for i in 0..<7 {
            let date = now.addingTimeInterval(-Double(i * 6 + 2) * 86_400)
            var round = Round.start(course: course, tee: tee, holeCount: 18, startHole: 1, date: date, handicapIndex: 11.8)
            for h in 0..<round.holes.count {
                if let hole = course.hole(round.holes[h].number) {
                    round.holes[h] = playHole(hole, yards: round.holes[h].yards, course: course, generator: &g)
                }
            }
            round.status = .finished
            result.append(round)
        }
        var current = Round.start(course: course, tee: tee, holeCount: 18, startHole: 1, date: now, handicapIndex: 11.8)
        current.id = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
        for h in 0..<4 {
            if let hole = course.hole(current.holes[h].number) {
                current.holes[h] = playHole(hole, yards: current.holes[h].yards, course: course, generator: &g)
            }
        }
        // Hole five is under way: a drive in the fairway and the ball marked for the approach.
        if let hole = course.hole(5), let teePoint = hole.tee, let green = hole.greenCenter {
            let heading = Geo.bearing(teePoint, green)
            let drive = Geo.destination(from: teePoint, bearingDegrees: heading + 1.5, meters: 221)
            current.holes[4].marks = [
                BallMark(coordinate: teePoint, lie: .tee, source: .tee, club: "Driver"),
                BallMark(coordinate: drive, lie: .fairway, source: .gps, accuracy: 3, club: "8 Iron"),
            ]
        }
        result.insert(current, at: 0)
        return result
    }

    /// A whole made-up library.
    public static func library(now: Date = Date()) -> Library {
        let made = course()
        var settings = Settings()
        settings.ghin = GHINAccount(login: "golfer@example.com", ghinNumber: 1234567, name: "Sample Golfer",
                                    handicapIndex: 11.8, lowIndex: 10.9, clubName: "Sample Links Golf Club",
                                    lastSync: now)
        return Library(courses: [made], rounds: rounds(course: made, now: now), bag: Club.standardBag, settings: settings)
    }
}
