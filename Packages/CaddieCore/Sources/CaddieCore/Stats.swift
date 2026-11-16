import Foundation

/// A count out of a number of chances, shown as a percentage.
public struct Rate: Equatable {
    public var made: Int
    public var chances: Int

    public init(made: Int = 0, chances: Int = 0) {
        self.made = made
        self.chances = chances
    }

    /// 0 to 1; nil when there were no chances.
    public var fraction: Double? {
        chances > 0 ? Double(made) / Double(chances) : nil
    }

    mutating func count(_ success: Bool) {
        chances += 1
        if success { made += 1 }
    }
}

public struct PuttBucket: Equatable, Identifiable {
    public var label: String
    public var lowFeet: Double
    public var highFeet: Double
    public var holed: Rate

    public var id: String { label }
}

public struct ClubStat: Equatable, Identifiable {
    public var club: String
    public var shots: Int
    public var averageYards: Double
    public var longestYards: Double

    public var id: String { club }
}

/// Statistics over a set of rounds.
public struct StatsReport: Equatable {
    public var rounds = 0
    public var holes = 0
    /// Rounds that were scored on every hole (eighteen-hole rounds only), for scoring averages.
    public var fullRounds = 0
    public var averageScore: Double?
    public var averageToPar: Double?
    public var bestScore: Int?
    public var worstScore: Int?
    public var averagePar3: Double?
    public var averagePar4: Double?
    public var averagePar5: Double?

    public var eagles = 0
    public var birdies = 0
    public var pars = 0
    public var bogeys = 0
    public var doubles = 0
    public var worse = 0

    public var fairways = Rate()
    public var missLeft = 0
    public var missRight = 0
    public var teePenalties = 0
    public var greens = Rate()
    public var greensPar3 = Rate()
    public var greensPar4 = Rate()
    public var greensPar5 = Rate()
    public var greensFromFairway = Rate()
    public var greensFromMiss = Rate()
    public var approachShort = 0
    public var approachLong = 0
    public var approachLeft = 0
    public var approachRight = 0
    public var approachOnGreen = 0

    public var puttsPerRound: Double?
    public var puttsPerHole: Double?
    public var puttsPerGIR: Double?
    public var onePutts = Rate()
    public var threePutts = Rate()
    public var averageFirstPuttFeet: Double?
    public var puttBuckets: [PuttBucket] = []

    public var scrambling = Rate()
    public var upAndDowns = Rate()
    public var sandSaves = Rate()
    public var chipsPerRound: Double?

    public var penaltiesPerRound: Double?
    public var penaltyStrokes = 0
    public var penaltiesByKind: [PenaltyKind: Int] = [:]

    public var strokesGained = StrokesGained.Totals()
    /// Rounds in which strokes gained could be measured.
    public var strokesGainedRounds = 0
    public var clubs: [ClubStat] = []

    public init() {}

    /// Strokes gained per round in a category; nil when nothing was measured.
    public func strokesGainedPerRound(_ category: StrokesGained.Category) -> Double? {
        strokesGainedRounds > 0 ? strokesGained.value(category) / Double(strokesGainedRounds) : nil
    }

    public var strokesGainedTotalPerRound: Double? {
        strokesGainedRounds > 0 ? strokesGained.total / Double(strokesGainedRounds) : nil
    }
}

public enum Stats {
    static let bucketEdges: [(String, Double, Double)] = [
        ("0–3 ft", 0, 3), ("4–6 ft", 3, 6), ("7–10 ft", 6, 10), ("11–20 ft", 10, 20), ("21–30 ft", 20, 30),
        ("31+ ft", 30, 10_000),
    ]

    /// The most recent `limit` finished, non-practice rounds scored in the app, newest first.
    /// A nil limit keeps them all.
    public static func eligible(_ rounds: [Round], limit: Int?) -> [Round] {
        let filtered = rounds
            .filter { $0.source == .app && $0.status == .finished && !$0.isPractice && !$0.completedHoles.isEmpty }
            .sorted { $0.date > $1.date }
        if let limit = limit { return Array(filtered.prefix(limit)) }
        return filtered
    }

    /// Statistics for `rounds` (already filtered). `courses` supplies hole positions for the
    /// rounds played on them.
    public static func report(rounds: [Round], courses: [Course]) -> StatsReport {
        var report = StatsReport()
        var courseByID: [UUID: Course] = [:]
        for course in courses { courseByID[course.id] = course }

        var scoreSum = 0, toParSum = 0
        var par3Sum = 0, par3Count = 0, par4Sum = 0, par4Count = 0, par5Sum = 0, par5Count = 0
        var puttSum = 0, puttHoles = 0, girPuttSum = 0, girHoles = 0
        var firstPuttSum = 0.0, firstPuttCount = 0
        var chipSum = 0
        var penaltyCount = 0
        var buckets = bucketEdges.map { PuttBucket(label: $0.0, lowFeet: $0.1, highFeet: $0.2, holed: Rate()) }
        var clubYards: [String: [Double]] = [:]
        var equivalentRounds = 0.0

        for round in rounds {
            let course = round.courseID.flatMap { courseByID[$0] }
            report.rounds += 1
            if round.isFullyScored && round.holes.count >= 18 {
                report.fullRounds += 1
                let gross = round.grossSoFar
                scoreSum += gross
                toParSum += gross - round.par
                report.bestScore = min(report.bestScore ?? gross, gross)
                report.worstScore = max(report.worstScore ?? gross, gross)
            }
            var roundGained = StrokesGained.Totals()

            for score in round.holes {
                let hole = course?.hole(score.number)
                guard let summary = HoleAnalyzer.summary(for: score, hole: hole) else { continue }
                report.holes += 1
                equivalentRounds += 1.0 / 18.0

                switch summary.par {
                case ...3: par3Sum += summary.strokes; par3Count += 1
                case 4: par4Sum += summary.strokes; par4Count += 1
                default: par5Sum += summary.strokes; par5Count += 1
                }
                switch summary.toPar {
                case ...(-2): report.eagles += 1
                case -1: report.birdies += 1
                case 0: report.pars += 1
                case 1: report.bogeys += 1
                case 2: report.doubles += 1
                default: report.worse += 1
                }

                if summary.par >= 4, let tee = summary.teeResult {
                    report.fairways.count(tee == .fairway)
                    if tee == .left { report.missLeft += 1 }
                    if tee == .right { report.missRight += 1 }
                    if tee == .penalty { report.teePenalties += 1 }
                    report.greensFromFairway.chances += tee == .fairway ? 1 : 0
                    report.greensFromMiss.chances += tee == .fairway ? 0 : 1
                    if summary.gir {
                        if tee == .fairway { report.greensFromFairway.made += 1 } else { report.greensFromMiss.made += 1 }
                    }
                }

                report.greens.count(summary.gir)
                switch summary.par {
                case ...3: report.greensPar3.count(summary.gir)
                case 4: report.greensPar4.count(summary.gir)
                default: report.greensPar5.count(summary.gir)
                }
                if let approach = summary.approach {
                    switch approach {
                    case .green: report.approachOnGreen += 1
                    case .short: report.approachShort += 1
                    case .long: report.approachLong += 1
                    case .left: report.approachLeft += 1
                    case .right: report.approachRight += 1
                    }
                }

                puttSum += summary.putts
                puttHoles += 1
                if summary.gir { girPuttSum += summary.putts; girHoles += 1 }
                report.onePutts.count(summary.putts == 1)
                report.threePutts.count(summary.putts >= 3)
                if let first = summary.firstPuttFeet {
                    firstPuttSum += first
                    firstPuttCount += 1
                }
                for (index, feet) in summary.puttFeet.enumerated() {
                    let holed = index == summary.puttFeet.count - 1
                    for b in 0..<buckets.count where feet > buckets[b].lowFeet && feet <= buckets[b].highFeet {
                        buckets[b].holed.count(holed)
                    }
                }

                if summary.scrambleChance { report.scrambling.count(summary.scrambled) }
                if summary.upAndDownChance { report.upAndDowns.count(summary.upAndDown) }
                if summary.sandSaveChance { report.sandSaves.count(summary.sandSave) }
                chipSum += summary.chips

                report.penaltyStrokes += summary.penaltyStrokes
                penaltyCount += summary.isQuick ? summary.penaltyStrokes : summary.penalties.count
                for kind in summary.penalties {
                    report.penaltiesByKind[kind, default: 0] += 1
                }

                roundGained = roundGained + StrokesGained.totals(for: score, hole: hole)

                for stroke in summary.strokesList {
                    guard let club = stroke.club, let yards = stroke.yards, stroke.penalty == nil else { continue }
                    // Only full shots: leave out anything played from inside sixty yards.
                    if let before = stroke.yardsToGreenBefore, before < 60 { continue }
                    if stroke.startLie == .bunker || stroke.startLie == .recovery { continue }
                    clubYards[club, default: []].append(yards)
                }
            }

            if roundGained.measuredStrokes > 0 {
                report.strokesGained = report.strokesGained + roundGained
                report.strokesGainedRounds += 1
            }
        }

        if report.fullRounds > 0 {
            report.averageScore = Double(scoreSum) / Double(report.fullRounds)
            report.averageToPar = Double(toParSum) / Double(report.fullRounds)
        }
        if par3Count > 0 { report.averagePar3 = Double(par3Sum) / Double(par3Count) }
        if par4Count > 0 { report.averagePar4 = Double(par4Sum) / Double(par4Count) }
        if par5Count > 0 { report.averagePar5 = Double(par5Sum) / Double(par5Count) }
        if puttHoles > 0 {
            report.puttsPerHole = Double(puttSum) / Double(puttHoles)
            report.puttsPerRound = Double(puttSum) / Double(puttHoles) * 18
        }
        if girHoles > 0 { report.puttsPerGIR = Double(girPuttSum) / Double(girHoles) }
        if firstPuttCount > 0 { report.averageFirstPuttFeet = firstPuttSum / Double(firstPuttCount) }
        report.puttBuckets = buckets
        if equivalentRounds > 0 {
            report.chipsPerRound = Double(chipSum) / equivalentRounds
            report.penaltiesPerRound = Double(penaltyCount) / equivalentRounds
        }
        report.clubs = clubYards.map { club, yards in
            ClubStat(club: club, shots: yards.count, averageYards: yards.reduce(0, +) / Double(yards.count),
                     longestYards: yards.max() ?? 0)
        }.sorted { $0.averageYards > $1.averageYards }
        return report
    }
}
