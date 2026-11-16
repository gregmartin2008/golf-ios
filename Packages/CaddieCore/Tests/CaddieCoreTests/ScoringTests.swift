import XCTest
@testable import CaddieCore

final class GeoTests: XCTestCase {
    func testDistanceAndDestinationAgree() {
        let start = Coordinate(lat: 40, lon: -80)
        let end = Geo.destination(from: start, bearingDegrees: 37, meters: 250)
        XCTAssertEqual(Geo.meters(start, end), 250, accuracy: 0.05)
        XCTAssertEqual(Geo.bearing(start, end), 37, accuracy: 0.05)
        XCTAssertEqual(Geo.yards(start, end), 273.4, accuracy: 0.1)
    }

    func testContains() {
        let ring = TestHole.box(northFrom: 0, northTo: 10, eastFrom: 0, eastTo: 10)
        XCTAssertTrue(Geo.contains(ring, TestHole.at(north: 5, east: 5)))
        XCTAssertFalse(Geo.contains(ring, TestHole.at(north: 15, east: 5)))
        XCTAssertFalse(Geo.contains(ring, TestHole.at(north: 5, east: -1)))
    }

    func testSideOfLine() {
        let a = TestHole.tee, b = TestHole.green
        XCTAssertGreaterThan(Geo.metersRightOfLine(TestHole.at(north: 200, east: 30), from: a, to: b), 0)
        XCTAssertLessThan(Geo.metersRightOfLine(TestHole.at(north: 200, east: -30), from: a, to: b), 0)
        XCTAssertEqual(Geo.metersRightOfLine(TestHole.at(north: 200, east: 30), from: a, to: b) * Geo.yardsPerMeter, 30,
                       accuracy: 0.2)
        XCTAssertEqual(Geo.metersAlongLine(TestHole.at(north: 200, east: 30), from: a, to: b) * Geo.yardsPerMeter, 200,
                       accuracy: 0.2)
    }

    func testDistanceToRingAndCrossings() {
        let ring = TestHole.box(northFrom: 388, northTo: 412, eastFrom: -12, eastTo: 12)
        XCTAssertEqual(Geo.metersToRing(TestHole.at(north: 400), ring), 0)
        XCTAssertEqual(Geo.metersToRing(TestHole.at(north: 380), ring) * Geo.yardsPerMeter, 8, accuracy: 0.1)
        let hits = Geo.crossings(of: ring, from: TestHole.tee, through: TestHole.green)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(Geo.yards(TestHole.tee, hits[0]), 388, accuracy: 0.3)
        XCTAssertEqual(Geo.yards(TestHole.tee, hits[1]), 412, accuracy: 0.3)
    }
}

final class LieDetectorTests: XCTestCase {
    func testLies() {
        let features = TestHole.features()
        XCTAssertEqual(LieDetector.lie(at: TestHole.at(north: 0), features: features), .tee)
        XCTAssertEqual(LieDetector.lie(at: TestHole.at(north: 250), features: features), .fairway)
        XCTAssertEqual(LieDetector.lie(at: TestHole.at(north: 250, east: 30), features: features), .rough)
        XCTAssertEqual(LieDetector.lie(at: TestHole.at(north: 400), features: features), .green)
        XCTAssertEqual(LieDetector.lie(at: TestHole.at(north: 398, east: 20), features: features), .bunker)
        XCTAssertEqual(LieDetector.lie(at: TestHole.at(north: 230, east: -45), features: features), .water)
        XCTAssertEqual(LieDetector.lie(at: TestHole.at(north: 386), features: features), .fringe)
    }

    func testUnknownWhenNothingToJudgeFrom() {
        XCTAssertEqual(LieDetector.lie(at: TestHole.at(north: 250), features: []), .unknown)
        let greenOnly = TestHole.features().filter { $0.kind == .green }
        XCTAssertEqual(LieDetector.lie(at: TestHole.at(north: 250), features: greenOnly), .unknown)
        XCTAssertEqual(LieDetector.lie(at: TestHole.at(north: 400), features: greenOnly), .green)
    }

    func testAnotherHolesGreenIsNotThisHolesGreen() {
        var course = TestHole.course()
        course.features = TestHole.features(hole: 2)
        XCTAssertEqual(LieDetector.lie(at: TestHole.at(north: 400), course: course, hole: 1), .rough)
        XCTAssertEqual(LieDetector.lie(at: TestHole.at(north: 250), course: course, hole: 1), .fairway)
    }
}

final class StrokeCountTests: XCTestCase {
    func testFairwayGreenTwoPutts() {
        let score = TestHole.score(marks: [
            TestHole.mark(north: 0, lie: .tee), TestHole.mark(north: 250, lie: .fairway), TestHole.mark(north: 395, lie: .green),
        ], putts: [20, 2])
        XCTAssertEqual(score.strokes, 4)
        XCTAssertTrue(score.isComplete)
    }

    func testOutOfBoundsOffTheTee() {
        // Tee shot out of bounds, third from the tee into the fairway, on in four, two putts: 6.
        let score = TestHole.score(marks: [
            TestHole.mark(north: 0, lie: .tee), TestHole.mark(north: 0, lie: .tee, penalty: .outOfBounds),
            TestHole.mark(north: 250, lie: .fairway),
        ], putts: [15, 1])
        XCTAssertEqual(score.strokes, 6)
        XCTAssertEqual(score.penaltyStrokes, 1)
    }

    func testIncompleteUntilPuttsOrHoledOut() {
        var score = TestHole.score(marks: [TestHole.mark(north: 0, lie: .tee), TestHole.mark(north: 250, lie: .fairway)],
                                   putts: [])
        XCTAssertNil(score.strokes)
        XCTAssertEqual(score.strokesSoFar, 2)
        score.holedFromOffGreen = true
        XCTAssertEqual(score.strokes, 2)
    }

    func testQuickEntryWins() {
        var score = TestHole.score(marks: [TestHole.mark(north: 0, lie: .tee)], putts: [])
        score.quick = QuickEntry(strokes: 5, putts: 2, teeResult: .left, penaltyStrokes: 1)
        XCTAssertEqual(score.strokes, 5)
        XCTAssertEqual(score.puttCount, 2)
        XCTAssertEqual(score.penaltyStrokes, 1)
    }
}

final class HoleAnalyzerTests: XCTestCase {
    func testRegulationPar() throws {
        let score = TestHole.score(marks: [
            TestHole.mark(north: 0, lie: .tee, club: "Driver"), TestHole.mark(north: 250, lie: .fairway, club: "8 Iron"),
            TestHole.mark(north: 395, lie: .green),
        ], putts: [20, 2])
        let summary = try XCTUnwrap(HoleAnalyzer.summary(for: score, hole: TestHole.hole()))
        XCTAssertEqual(summary.strokes, 4)
        XCTAssertTrue(summary.gir)
        XCTAssertEqual(summary.teeResult, .fairway)
        XCTAssertEqual(summary.approach, .green)
        XCTAssertEqual(try XCTUnwrap(summary.approachYards), 150, accuracy: 0.5)
        XCTAssertEqual(summary.chips, 0)
        XCTAssertFalse(summary.scrambleChance)
        XCTAssertEqual(summary.firstPuttFeet, 20)
        XCTAssertEqual(summary.strokesList.count, 2)
        XCTAssertEqual(try XCTUnwrap(summary.strokesList[0].yards), 250, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(summary.strokesList[1].yards), 145, accuracy: 0.5)
    }

    func testMissedFairwayLeftAndRight() throws {
        let left = TestHole.score(marks: [TestHole.mark(north: 0, lie: .tee), TestHole.mark(north: 240, east: -30, lie: .rough)],
                                  putts: [10, 1])
        XCTAssertEqual(try XCTUnwrap(HoleAnalyzer.summary(for: left, hole: TestHole.hole())).teeResult, .left)
        let right = TestHole.score(marks: [TestHole.mark(north: 0, lie: .tee), TestHole.mark(north: 240, east: 30, lie: .rough)],
                                   putts: [10, 1])
        XCTAssertEqual(try XCTUnwrap(HoleAnalyzer.summary(for: right, hole: TestHole.hole())).teeResult, .right)
    }

    func testPenaltyOffTheTee() throws {
        let score = TestHole.score(marks: [
            TestHole.mark(north: 0, lie: .tee), TestHole.mark(north: 230, east: -25, lie: .rough, penalty: .water),
            TestHole.mark(north: 396, lie: .green),
        ], putts: [12, 1])
        let summary = try XCTUnwrap(HoleAnalyzer.summary(for: score, hole: TestHole.hole()))
        XCTAssertEqual(summary.strokes, 5)
        XCTAssertEqual(summary.teeResult, .penalty)
        XCTAssertEqual(summary.penalties, [.water])
        XCTAssertFalse(summary.gir)
        XCTAssertEqual(summary.strokesList[0].penaltyStrokes, 1)
        XCTAssertNil(summary.strokesList[0].yards)
        XCTAssertEqual(summary.strokesList[1].number, 3)
    }

    func testMissedGreenUpAndDownFromBunker() throws {
        let score = TestHole.score(marks: [
            TestHole.mark(north: 0, lie: .tee), TestHole.mark(north: 250, lie: .fairway),
            TestHole.mark(north: 398, east: 20, lie: .bunker),
        ], putts: [4])
        let summary = try XCTUnwrap(HoleAnalyzer.summary(for: score, hole: TestHole.hole()))
        XCTAssertEqual(summary.strokes, 4)
        XCTAssertFalse(summary.gir)
        XCTAssertEqual(summary.approach, .right)
        XCTAssertEqual(summary.chips, 1)
        XCTAssertEqual(summary.sandShots, 1)
        XCTAssertTrue(summary.scrambled)
        XCTAssertTrue(summary.upAndDown)
        XCTAssertTrue(summary.sandSave)
    }

    func testApproachShortAndLong() throws {
        let short = TestHole.score(marks: [
            TestHole.mark(north: 0, lie: .tee), TestHole.mark(north: 250, lie: .fairway), TestHole.mark(north: 370, lie: .fairway),
        ], putts: [6, 1])
        XCTAssertEqual(try XCTUnwrap(HoleAnalyzer.summary(for: short, hole: TestHole.hole())).approach, .short)
        let long = TestHole.score(marks: [
            TestHole.mark(north: 0, lie: .tee), TestHole.mark(north: 250, lie: .fairway), TestHole.mark(north: 425, lie: .rough),
        ], putts: [6, 1])
        XCTAssertEqual(try XCTUnwrap(HoleAnalyzer.summary(for: long, hole: TestHole.hole())).approach, .long)
    }

    func testParThreeHasNoFairway() throws {
        let score = TestHole.score(par: 3, marks: [TestHole.mark(north: 240, lie: .tee)], putts: [25, 3])
        let summary = try XCTUnwrap(HoleAnalyzer.summary(for: score, hole: TestHole.hole(par: 3)))
        XCTAssertNil(summary.teeResult)
        XCTAssertTrue(summary.gir)
        XCTAssertEqual(summary.approach, .green)
        XCTAssertEqual(summary.strokes, 3)
    }

    func testQuickHole() throws {
        var score = TestHole.score(marks: [], putts: [])
        score.quick = QuickEntry(strokes: 5, putts: 2, teeResult: .right, penaltyStrokes: 0, sandShots: 1, chips: 1)
        let summary = try XCTUnwrap(HoleAnalyzer.summary(for: score, hole: nil))
        XCTAssertEqual(summary.strokes, 5)
        XCTAssertFalse(summary.gir)
        XCTAssertEqual(summary.teeResult, .right)
        XCTAssertTrue(summary.isQuick)
        XCTAssertFalse(summary.scrambled)
    }

    func testHoledFromOffTheGreen() throws {
        let score = TestHole.score(marks: [
            TestHole.mark(north: 0, lie: .tee), TestHole.mark(north: 250, lie: .fairway), TestHole.mark(north: 380, lie: .rough),
        ], putts: [], holed: true)
        let summary = try XCTUnwrap(HoleAnalyzer.summary(for: score, hole: TestHole.hole()))
        XCTAssertEqual(summary.strokes, 3)
        XCTAssertEqual(summary.putts, 0)
        XCTAssertTrue(summary.strokesList[2].holed)
        XCTAssertTrue(summary.upAndDown)
    }
}

final class HandicapTests: XCTestCase {
    func testCourseHandicap() {
        XCTAssertEqual(Handicap.courseHandicap(index: 12.0, slope: 130, rating: 71.5, par: 72), 13)
        XCTAssertEqual(Handicap.courseHandicap(index: 0, slope: 113, rating: 72, par: 72), 0)
    }

    func testStrokesReceived() {
        XCTAssertEqual(Handicap.strokesReceived(courseHandicap: 13, strokeIndex: 13), 1)
        XCTAssertEqual(Handicap.strokesReceived(courseHandicap: 13, strokeIndex: 14), 0)
        XCTAssertEqual(Handicap.strokesReceived(courseHandicap: 20, strokeIndex: 2), 2)
        XCTAssertEqual(Handicap.strokesReceived(courseHandicap: 20, strokeIndex: 3), 1)
        XCTAssertEqual(Handicap.strokesReceived(courseHandicap: -2, strokeIndex: 18), -1)
        XCTAssertEqual(Handicap.strokesReceived(courseHandicap: -2, strokeIndex: 16), 0)
    }

    func testNetDoubleBogey() {
        XCTAssertEqual(Handicap.adjustedHoleScore(strokes: 9, par: 4, strokesReceived: 1), 7)
        XCTAssertEqual(Handicap.adjustedHoleScore(strokes: 5, par: 4, strokesReceived: 1), 5)
    }

    func testDifferential() {
        XCTAssertEqual(Handicap.differential(adjustedGross: 85, rating: 71.5, slope: 130), 11.7, accuracy: 0.0001)
    }

    func testIndexTable() throws {
        XCTAssertNil(Handicap.index(fromNewestFirst: [10, 12]))
        XCTAssertEqual(try XCTUnwrap(Handicap.index(fromNewestFirst: [15, 10, 12])).index, 8.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(Handicap.index(fromNewestFirst: [15, 10, 12, 20, 11])).index, 10.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(Handicap.index(fromNewestFirst: [15, 10, 12, 20, 11, 14])).index, 9.5, accuracy: 0.0001)
        let twenty = (1...20).map { Double($0) }
        let result = try XCTUnwrap(Handicap.index(fromNewestFirst: twenty))
        XCTAssertEqual(result.index, 4.5, accuracy: 0.0001)
        XCTAssertEqual(result.usedPositions, [0, 1, 2, 3, 4, 5, 6, 7])
        // Only the newest twenty count.
        let more = twenty + [0.0, 0.0, 0.0]
        XCTAssertEqual(try XCTUnwrap(Handicap.index(fromNewestFirst: more)).index, 4.5, accuracy: 0.0001)
    }

    func testAdjustedGrossCapsABlowUpHole() throws {
        var holes: [HoleScore] = []
        for number in 1...18 {
            var hole = HoleScore(number: number, par: 4, strokeIndex: number)
            hole.quick = QuickEntry(strokes: number == 1 ? 10 : 5, putts: 2)
            holes.append(hole)
        }
        var round = Round(courseName: "Test", rating: 72, slope: 113, par: 72, holes: holes, status: .finished,
                          handicapIndexAtPlay: 18.0)
        // Course handicap 18: one stroke a hole, so the most any hole counts is 7.
        XCTAssertEqual(Handicap.adjustedGross(for: round), 7 + 17 * 5)
        XCTAssertEqual(try XCTUnwrap(Handicap.differential(for: round)), 20.0, accuracy: 0.0001)
        round.isPractice = true
        XCTAssertNil(Handicap.differential(for: round))
    }
}

final class StrokesGainedTests: XCTestCase {
    func testTableLookups() throws {
        XCTAssertEqual(try XCTUnwrap(StrokesGained.expected(lie: .fairway, distance: 100)), 2.80, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(StrokesGained.expected(lie: .fairway, distance: 110)), 2.825, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(StrokesGained.expected(lie: .green, distance: 8)), 1.50, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(StrokesGained.expected(lie: .tee, distance: 400)), 3.99, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(StrokesGained.expected(lie: .tee, distance: 700)), 4.82, accuracy: 0.0001)
        XCTAssertNil(StrokesGained.expected(lie: .unknown, distance: 100))
    }

    func testHoleAddsUpToExpectedMinusStrokes() {
        let score = TestHole.score(marks: [
            TestHole.mark(north: 0, lie: .tee), TestHole.mark(north: 250, lie: .fairway), TestHole.mark(north: 395, lie: .green),
        ], putts: [20, 2])
        let totals = StrokesGained.totals(for: score, hole: TestHole.hole())
        // From 400 yards the baseline is 3.99; the hole took 4.
        XCTAssertEqual(totals.total, -0.01, accuracy: 0.02)
        XCTAssertEqual(totals.offTheTee, 3.99 - 2.945 - 1, accuracy: 0.02)
        XCTAssertEqual(totals.approach, 2.945 - 1.87 - 1, accuracy: 0.02)
        XCTAssertEqual(totals.putting, (1.87 - 1.01 - 1) + (1.01 - 1), accuracy: 0.0001)
        XCTAssertEqual(totals.measuredStrokes, 4)
    }

    func testPenaltyCostsItsStroke() {
        // Tee shot into water, drop in the rough 170 out, on the green, one putt from 3 feet: 4.
        let score = TestHole.score(marks: [
            TestHole.mark(north: 0, lie: .tee), TestHole.mark(north: 230, east: -25, lie: .rough, penalty: .water),
            TestHole.mark(north: 396, lie: .green),
        ], putts: [3])
        let totals = StrokesGained.totals(for: score, hole: TestHole.hole())
        XCTAssertEqual(score.strokes, 4)
        XCTAssertEqual(totals.total, 3.99 - 4, accuracy: 0.03)
    }
}
