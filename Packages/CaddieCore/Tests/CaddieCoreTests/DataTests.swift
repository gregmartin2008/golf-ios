import XCTest
@testable import CaddieCore

final class OSMImportTests: XCTestCase {
    static func geometry(_ points: [Coordinate]) -> [[String: Any]] {
        points.map { ["lat": $0.lat, "lon": $0.lon] }
    }

    static func way(_ id: Int, tags: [String: String], _ points: [Coordinate], closed: Bool = true) -> [String: Any] {
        var ring = points
        if closed, let first = points.first { ring.append(first) }
        return ["type": "way", "id": id, "tags": tags, "geometry": geometry(ring)]
    }

    /// A reply shaped like the Overpass service's, holding one mapped hole of a nine-hole course.
    static func reply() -> Data {
        let boundary = TestHole.box(northFrom: -50, northTo: 500, eastFrom: -150, eastTo: 150)
        let elements: [[String: Any]] = [
            way(1, tags: ["leisure": "golf_course", "name": "Fixture Golf Club"], boundary),
            // Drawn green to tee, the wrong way round, to check it is turned.
            way(2, tags: ["golf": "hole", "ref": "1", "par": "4", "handicap": "5"],
                [TestHole.green, TestHole.at(north: 200), TestHole.tee], closed: false),
            way(3, tags: ["golf": "green"], TestHole.box(northFrom: 388, northTo: 412, eastFrom: -12, eastTo: 12)),
            way(4, tags: ["golf": "fairway"], TestHole.box(northFrom: 150, northTo: 330, eastFrom: -20, eastTo: 20)),
            way(5, tags: ["golf": "bunker"], TestHole.box(northFrom: 392, northTo: 404, eastFrom: 16, eastTo: 26)),
            way(6, tags: ["golf": "tee"], TestHole.box(northFrom: -5, northTo: 5, eastFrom: -5, eastTo: 5)),
            way(7, tags: ["natural": "water"], TestHole.box(northFrom: 200, northTo: 260, eastFrom: -60, eastTo: -30)),
            // A bunker on the course next door, which must be left out.
            way(8, tags: ["golf": "bunker"], TestHole.box(northFrom: 100, northTo: 110, eastFrom: 400, eastTo: 410)),
            [
                "type": "relation", "id": 9, "tags": ["golf": "rough", "type": "multipolygon"],
                "members": [
                    ["type": "way", "ref": 90, "role": "outer",
                     "geometry": geometry([TestHole.at(north: 340, east: 30), TestHole.at(north: 340, east: 50),
                                           TestHole.at(north: 360, east: 50)])],
                    ["type": "way", "ref": 91, "role": "outer",
                     "geometry": geometry([TestHole.at(north: 360, east: 50), TestHole.at(north: 360, east: 30),
                                           TestHole.at(north: 340, east: 30)])],
                ],
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: ["version": 0.6, "elements": elements])
    }

    func testBuildsCourse() throws {
        let result = OSMImport.course(from: OSMImportTests.reply(), near: TestHole.at(north: 200))
        let course = result.course
        XCTAssertEqual(course.name, "Fixture Golf Club")
        XCTAssertEqual(course.osmID, "way/1")
        XCTAssertEqual(course.holes.count, 9)
        let hole = try XCTUnwrap(course.hole(1))
        XCTAssertEqual(hole.par, 4)
        XCTAssertEqual(hole.strokeIndex, 5)
        XCTAssertEqual(Geo.yards(try XCTUnwrap(hole.tee), TestHole.tee), 0, accuracy: 0.5)
        XCTAssertEqual(Geo.yards(try XCTUnwrap(hole.greenCenter), TestHole.green), 0, accuracy: 3)
        XCTAssertEqual(Geo.yards(TestHole.tee, try XCTUnwrap(hole.greenFront)), 388, accuracy: 1)
        XCTAssertEqual(Geo.yards(TestHole.tee, try XCTUnwrap(hole.greenBack)), 412, accuracy: 1)
        XCTAssertFalse(try XCTUnwrap(course.hole(2)).isMapped)

        XCTAssertEqual(course.features.filter { $0.kind == .bunker }.count, 1)
        XCTAssertEqual(course.features.filter { $0.kind == .water }.count, 1)
        XCTAssertEqual(course.features.filter { $0.kind == .rough }.count, 1)
        XCTAssertTrue(course.features.allSatisfy { $0.hole == 1 })
        XCTAssertEqual(result.coverage.holesFound, 1)
        XCTAssertEqual(result.coverage.holesWithGreen, 1)
        XCTAssertEqual(result.coverage.holesWithFairway, 1)
        XCTAssertTrue(result.coverage.hasBoundary)

        // The imported outlines drive lie detection.
        XCTAssertEqual(LieDetector.lie(at: TestHole.at(north: 250), course: course, hole: 1), .fairway)
        XCTAssertEqual(LieDetector.lie(at: TestHole.at(north: 398, east: 20), course: course, hole: 1), .bunker)
    }

    func testEmptyReplyGivesBlankCourse() {
        let data = Data("{\"elements\": []}".utf8)
        let result = OSMImport.course(from: data, near: TestHole.tee, fallbackName: "My Club")
        XCTAssertEqual(result.course.name, "My Club")
        XCTAssertEqual(result.course.holes.count, 18)
        XCTAssertEqual(result.coverage.holesFound, 0)
        XCTAssertTrue(OSMImport.candidates(from: Data("not json".utf8), near: TestHole.tee).isEmpty)
    }

    func testHoleNumbers() {
        XCTAssertEqual(OSMImport.holeNumber("7"), 7)
        XCTAssertEqual(OSMImport.holeNumber("07"), 7)
        XCTAssertEqual(OSMImport.holeNumber("B12"), 12)
        XCTAssertEqual(OSMImport.holeNumber(" 3 "), 3)
        XCTAssertNil(OSMImport.holeNumber("Black"))
        XCTAssertNil(OSMImport.holeNumber(nil))
        XCTAssertNil(OSMImport.holeNumber("0"))
        let tally = OSMImport.tally(from: OSMImportTests.reply())
        XCTAssertEqual(tally.counts["hole"], 1)
        XCTAssertEqual(tally.counts["bunker"], 2)
        XCTAssertEqual(tally.holeRefs, ["1"])
    }

    func testQueryMentionsThePoint() {
        let query = OSMImport.query(near: Coordinate(lat: 40.5, lon: -80.25), radiusMeters: 3000)
        XCTAssertTrue(query.contains("around:3000,40.5,-80.25"))
        XCTAssertTrue(query.contains("out tags geom;"))
    }

    func testClientFallsBackToSecondServer() async throws {
        let good = String(data: OSMImportTests.reply(), encoding: .utf8) ?? ""
        // The outline step fails on the first server and succeeds on the second; then the feature step.
        let transport = ScriptedTransport([("busy", 504), (good, 200), (good, 200)])
        let data = try await OverpassClient(transport: transport).fetch(near: TestHole.at(north: 200))
        XCTAssertEqual(transport.requests.count, 3)
        let second = String(data: transport.requests[2].httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(second.contains("golf"))
        XCTAssertEqual(OSMImport.course(from: data, near: TestHole.at(north: 200)).coverage.holesFound, 1)
        XCTAssertEqual(OSMImport.candidates(from: data, near: TestHole.tee).first?.name, "Fixture Golf Club")
        let body = String(data: transport.requests[0].httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.hasPrefix("data=%5Bout%3Ajson%5D"))
    }
}

final class GHINTests: XCTestCase {
    func testIndexFormats() {
        XCTAssertEqual(GHINFormat.index("12.3"), 12.3)
        XCTAssertEqual(GHINFormat.index("+1.4"), -1.4)
        XCTAssertEqual(GHINFormat.index(7.5), 7.5)
        XCTAssertNil(GHINFormat.index("NH"))
        XCTAssertEqual(GHINFormat.stateCode("pa"), "US-PA")
        XCTAssertNil(GHINFormat.stateCode("Pennsylvania"))
    }

    func testSignInThenReadScores() async throws {
        let session = #"{"authToken": {"token": "session-token", "expiresIn": "604800s"}}"#
        let login = #"{"golfer_user": {"golfer_user_token": "user-token", "golfers": [{"ghin": "7654321", "first_name": "Sam", "last_name": "Player", "handicap_index": "11.8", "low_hi": "10.9", "club_name": "Fixture GC"}]}}"#
        let scores = #"{"scores": [{"id": 11, "played_at": "2026-05-02", "adjusted_gross_score": 86, "differential": 12.6, "course_name": "Fixture Golf Club", "tee_name": "Blue", "course_rating": 71.5, "slope_rating": 130, "number_of_holes": 18, "score_type": "H"}, {"id": 12, "played_at": "2026-05-09", "adjusted_gross_score": "84", "differential": "10.9", "facility_name": "Other Club", "score_type": "A"}, {"id": 13}], "total_count": 3}"#
        let transport = ScriptedTransport([(session, 200), (login, 200), (scores, 200)])
        let client = GHINClient(transport: transport)
        let golfer = try await client.signIn(login: "sam@example.com", password: "secret")
        XCTAssertTrue(client.isSignedIn)
        XCTAssertEqual(golfer.ghinNumber, 7654321)
        XCTAssertEqual(golfer.name, "Sam Player")
        XCTAssertEqual(golfer.handicapIndex, 11.8)
        XCTAssertEqual(golfer.lowIndex, 10.9)

        let list = try await client.scores(ghinNumber: 7654321)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].id, 12)
        XCTAssertEqual(list[0].adjustedGross, 84)
        XCTAssertEqual(list[0].courseName, "Other Club")
        XCTAssertEqual(list[1].differential, 12.6)

        XCTAssertEqual(transport.requests[0].value(forHTTPHeaderField: "x-goog-api-key")?.isEmpty, false)
        let loginBody = String(data: transport.requests[1].httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(loginBody.contains("session-token"))
        XCTAssertTrue(loginBody.contains("email_or_ghin"))
        let third = transport.requests[2]
        XCTAssertEqual(third.value(forHTTPHeaderField: "Authorization"), "Bearer user-token")
        let url = third.url?.absoluteString ?? ""
        XCTAssertTrue(url.hasPrefix("https://api2.ghin.com/api/v1/scores.json?source=GHINcom"))
        XCTAssertTrue(url.contains("golfer_id=7654321"))
    }

    func testBadPasswordGivesAMessage() async {
        let session = #"{"authToken": {"token": "session-token"}}"#
        let transport = ScriptedTransport([(session, 200), (#"{"errors": {"password": ["is invalid"]}}"#, 401)])
        let client = GHINClient(transport: transport)
        do {
            _ = try await client.signIn(login: "sam@example.com", password: "wrong")
            XCTFail("sign-in should have failed")
        } catch {
            XCTAssertEqual(error.localizedDescription, "password: is invalid")
        }
        XCTAssertFalse(client.isSignedIn)
    }

    func testCourseDetails() throws {
        let json = #"""
        {"CourseId": 4242, "CourseName": "Fixture Golf Club", "CourseCity": "Anytown", "CourseState": "US-PA",
         "TeeSets": [
          {"TeeSetRatingId": 77, "TeeSetRatingName": "Blue", "Gender": "Male", "TotalPar": 8, "TotalYardage": 575,
           "Ratings": [{"RatingType": "Front", "CourseRating": 35.1, "SlopeRating": 128},
                       {"RatingType": "Total", "CourseRating": 71.5, "SlopeRating": 130}],
           "Holes": [{"Number": 2, "Par": 3, "Allocation": 17, "Length": 175}, {"Number": 1, "Par": 5, "Allocation": 3, "Length": 400}]},
          {"TeeSetRatingId": 78, "TeeSetRatingName": "Unrated", "Ratings": [], "Holes": []}
         ]}
        """#
        let details = try XCTUnwrap(GHINWire.courseDetails(from: Data(json.utf8)))
        XCTAssertEqual(details.id, 4242)
        XCTAssertEqual(details.state, "PA")
        XCTAssertEqual(details.tees.count, 1)
        XCTAssertEqual(details.tees[0].name, "Blue")
        XCTAssertEqual(details.tees[0].rating, 71.5)
        XCTAssertEqual(details.tees[0].slope, 130)
        XCTAssertEqual(details.tees[0].yards, [400, 175])
        XCTAssertEqual(details.tees[0].ghinTeeSetID, 77)
        XCTAssertEqual(details.pars, [5, 3])
        XCTAssertEqual(details.strokeIndexes, [3, 17])
    }

    func testPostBody() {
        let date = GHINFormat.date("2026-06-01") ?? Date()
        let post = GHINPost(golferID: 7654321, courseID: 4242, teeSetID: 77, playedAt: date, holeCount: 18,
                            holes: (1...18).map { (number: $0, strokes: 5) })
        let body = GHINWire.postBody(post)
        XCTAssertEqual(body["golfer_id"] as? Int, 7654321)
        XCTAssertEqual(body["played_at"] as? String, "2026-06-01")
        XCTAssertEqual(body["tee_set_side"] as? String, "All18")
        XCTAssertEqual(body["number_of_holes"] as? Int, 18)
        XCTAssertEqual((body["hole_details"] as? [[String: Int]])?.count, 18)
        XCTAssertEqual((body["hole_details"] as? [[String: Int]])?.first?["raw_score"], 5)
        XCTAssertEqual(post.total, 90)
    }
}

final class StoreTests: XCTestCase {
    func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("caddie-tests-\(UUID().uuidString)")
    }

    func testRoundTrip() {
        let folder = temporaryFolder()
        let store = Store(folder: folder)
        let library = DemoData.library(now: Date(timeIntervalSince1970: 1_780_000_000))
        store.save(library)
        let loaded = Store(folder: folder).load()
        XCTAssertEqual(loaded.courses, library.courses)
        XCTAssertEqual(loaded.rounds.count, library.rounds.count)
        XCTAssertEqual(loaded.rounds.first?.holes, library.rounds.first?.holes)
        XCTAssertEqual(loaded.bag.map { $0.name }, Club.standardNames)
        XCTAssertEqual(loaded.settings.ghin?.ghinNumber, 1234567)
        try? FileManager.default.removeItem(at: folder)
    }

    func testEmptyFolderGivesDefaults() {
        let store = Store(folder: temporaryFolder())
        let library = store.load()
        XCTAssertTrue(library.courses.isEmpty)
        XCTAssertEqual(library.bag.count, Club.standardNames.count)
        XCTAssertFalse(library.settings.useMeters)
    }

    func testOlderSettingsFileStillOpens() throws {
        let settings = try Store.decoder().decode(Settings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.gender, "M")
        XCTAssertNil(settings.ghin)
    }

    func testBackupLeavesOutTheSignIn() throws {
        let library = DemoData.library()
        let data = try XCTUnwrap(Store.backupData(library))
        let restored = try XCTUnwrap(Store.library(fromBackup: data))
        XCTAssertNil(restored.settings.ghin)
        XCTAssertEqual(restored.courses.count, 1)
        XCTAssertEqual(restored.rounds.count, library.rounds.count)
    }
}

final class RoundAndStatsTests: XCTestCase {
    func testStartNineFromTheTenth() {
        let course = DemoData.course()
        let round = Round.start(course: course, tee: course.tees[0], holeCount: 9, startHole: 10)
        XCTAssertEqual(round.holes.map { $0.number }, Array(10...18))
        XCTAssertEqual(round.rating, 71.4 / 2, accuracy: 0.001)
        XCTAssertEqual(round.holes[0].yards, 400)
        XCTAssertEqual(round.par, 36)
    }

    func testDemoRoundsAreSensible() throws {
        let library = DemoData.library(now: Date(timeIntervalSince1970: 1_780_000_000))
        XCTAssertEqual(library.rounds.count, 8)
        let finished = Stats.eligible(library.rounds, limit: nil)
        XCTAssertEqual(finished.count, 7)
        for round in finished {
            XCTAssertTrue(round.isFullyScored)
            let total = try XCTUnwrap(round.total)
            XCTAssertGreaterThan(total, 62)
            XCTAssertLessThan(total, 125)
            for hole in round.holes {
                let strokes = try XCTUnwrap(hole.strokes)
                XCTAssertGreaterThanOrEqual(strokes, 1)
                XCTAssertLessThanOrEqual(strokes, 14)
            }
        }
        let report = Stats.report(rounds: finished, courses: library.courses)
        XCTAssertEqual(report.rounds, 7)
        XCTAssertEqual(report.holes, 126)
        XCTAssertEqual(report.fullRounds, 7)
        XCTAssertEqual(report.fairways.chances, 7 * 14)
        XCTAssertEqual(report.greens.chances, 126)
        XCTAssertEqual(report.eagles + report.birdies + report.pars + report.bogeys + report.doubles + report.worse, 126)
        XCTAssertNotNil(report.averageScore)
        XCTAssertNotNil(report.puttsPerRound)
        XCTAssertEqual(report.strokesGainedRounds, 7)
        XCTAssertFalse(report.clubs.isEmpty)
        XCTAssertEqual(report.puttBuckets.count, 6)

        let handicap = Handicap.report(rounds: library.rounds)
        XCTAssertEqual(handicap.entries.count, 7)
        XCTAssertNotNil(handicap.index)
        XCTAssertEqual(handicap.entries.filter { $0.counts }.count, 2)

        let unfinished = try XCTUnwrap(library.rounds.first)
        XCTAssertEqual(unfinished.status, .inProgress)
        XCTAssertEqual(unfinished.completedHoles.count, 4)
        XCTAssertEqual(unfinished.holes[4].marks.count, 2)
    }

    func testHandMadeRoundStats() {
        var holes: [HoleScore] = []
        for number in 1...18 {
            var hole = HoleScore(number: number, par: 4, strokeIndex: number)
            // Nine pars with a fairway hit and two putts, nine bogeys from the left rough with two putts.
            if number <= 9 {
                hole.quick = QuickEntry(strokes: 4, putts: 2, teeResult: .fairway)
            } else {
                hole.quick = QuickEntry(strokes: 5, putts: 2, teeResult: .left, penaltyStrokes: 0, sandShots: 0, chips: 1)
            }
            holes.append(hole)
        }
        let round = Round(courseName: "Test", rating: 72, slope: 113, par: 72, holes: holes, status: .finished)
        let report = Stats.report(rounds: [round], courses: [])
        XCTAssertEqual(report.averageScore, 81)
        XCTAssertEqual(report.fairways.made, 9)
        XCTAssertEqual(report.fairways.chances, 18)
        XCTAssertEqual(report.missLeft, 9)
        XCTAssertEqual(report.greens.made, 9)
        XCTAssertEqual(report.greensFromFairway.made, 9)
        XCTAssertEqual(report.greensFromMiss.made, 0)
        XCTAssertEqual(report.puttsPerRound, 36)
        XCTAssertEqual(report.pars, 9)
        XCTAssertEqual(report.bogeys, 9)
        XCTAssertEqual(report.scrambling.chances, 9)
        XCTAssertEqual(report.scrambling.made, 0)
        XCTAssertEqual(report.chipsPerRound ?? 0, 9, accuracy: 0.001)
        XCTAssertEqual(report.strokesGainedRounds, 0)
    }
}
