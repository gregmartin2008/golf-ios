import Foundation
@testable import CaddieCore

/// A straight test hole running due north, with outlines whose positions are known in yards.
enum TestHole {
    static let tee = Coordinate(lat: 40.0, lon: -80.0)
    static let metersPerYard = 1 / Geo.yardsPerMeter

    /// A point `north` yards up the hole from the tee and `east` yards right of the center line.
    static func at(north: Double, east: Double = 0) -> Coordinate {
        let up = Geo.destination(from: tee, bearingDegrees: 0, meters: north * metersPerYard)
        return Geo.destination(from: up, bearingDegrees: 90, meters: east * metersPerYard)
    }

    static func box(northFrom: Double, northTo: Double, eastFrom: Double, eastTo: Double) -> [Coordinate] {
        [at(north: northFrom, east: eastFrom), at(north: northFrom, east: eastTo), at(north: northTo, east: eastTo),
         at(north: northTo, east: eastFrom)]
    }

    static let length = 400.0
    static var green: Coordinate { at(north: length) }

    /// Par 4, 400 yards. Fairway from 150 to 330 yards, 40 yards wide. Green a 24-yard square.
    /// Bunker right of the green. Water left of the fairway.
    static func features(hole: Int = 1) -> [CourseFeature] {
        [
            CourseFeature(id: "tee", kind: .tee, ring: box(northFrom: -5, northTo: 5, eastFrom: -5, eastTo: 5), hole: hole),
            CourseFeature(id: "fairway", kind: .fairway, ring: box(northFrom: 150, northTo: 330, eastFrom: -20, eastTo: 20),
                          hole: hole),
            CourseFeature(id: "green", kind: .green, ring: box(northFrom: 388, northTo: 412, eastFrom: -12, eastTo: 12),
                          hole: hole),
            CourseFeature(id: "bunker", kind: .bunker, ring: box(northFrom: 392, northTo: 404, eastFrom: 16, eastTo: 26),
                          hole: hole),
            CourseFeature(id: "water", kind: .water, ring: box(northFrom: 200, northTo: 260, eastFrom: -60, eastTo: -30),
                          hole: hole),
        ]
    }

    static func hole(par: Int = 4) -> Hole {
        Hole(number: 1, par: par, strokeIndex: 5, tee: tee, greenCenter: green, greenFront: at(north: 388),
             greenBack: at(north: 412), line: [tee, green])
    }

    static func course() -> Course {
        Course(name: "Test", location: tee, holes: [hole()], tees: [TeeSet(name: "Blue", rating: 71.5, slope: 130, par: 72)],
               features: features())
    }

    static func mark(north: Double, east: Double = 0, lie: Lie, club: String? = nil, penalty: PenaltyKind? = nil) -> BallMark {
        BallMark(coordinate: at(north: north, east: east), lie: lie, source: .touch, club: club, penaltyBefore: penalty)
    }

    static func score(par: Int = 4, marks: [BallMark], putts: [Double], holed: Bool = false) -> HoleScore {
        HoleScore(number: 1, par: par, strokeIndex: 5, yards: 400, marks: marks, putts: putts.map { Putt(feet: $0) },
                  holedFromOffGreen: holed)
    }
}

/// A transport that answers from a script and records what it was asked.
final class ScriptedTransport: HTTPTransport {
    var replies: [(Data, Int)]
    var requests: [URLRequest] = []

    init(_ replies: [(String, Int)]) {
        self.replies = replies.map { (Data($0.0.utf8), $0.1) }
    }

    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        requests.append(request)
        if replies.isEmpty { return (Data(), 500) }
        let next = replies.removeFirst()
        return (next.0, next.1)
    }
}
