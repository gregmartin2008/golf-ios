import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// An unofficial client for GHIN, using the endpoints the ghin.com website uses, with the
// golfer's own login. Field names follow the MIT-licensed n8io/ghin client. GHIN can change
// these at any time, so every reader here tolerates missing and renamed fields.

public struct GHINCourseHit: Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var city: String
    public var state: String
}

public struct GHINCourseDetails: Equatable {
    public var id: Int
    public var name: String
    public var city: String
    public var state: String
    public var tees: [TeeSet]
    /// Par and stroke index per hole, from the first tee set that lists them.
    public var pars: [Int]
    public var strokeIndexes: [Int]
}

public struct GHINScore: Equatable, Identifiable {
    public var id: Int
    public var playedAt: Date
    public var adjustedGross: Int
    public var differential: Double
    public var courseName: String
    public var teeName: String
    public var rating: Double
    public var slope: Int
    public var holes: Int
    public var scoreType: String
}

public struct GHINGolfer: Equatable {
    public var ghinNumber: Int?
    public var name: String?
    public var handicapIndex: Double?
    public var lowIndex: Double?
    public var clubName: String?
}

/// What will be sent when a round is posted. Shown to the golfer before anything is sent.
public struct GHINPost: Equatable, Identifiable {
    public var golferID: Int
    public var courseID: Int
    public var teeSetID: Int
    public var playedAt: Date
    public var holeCount: Int
    /// "H" home, "A" away, "T" tournament.
    public var scoreType: String
    public var gender: String
    /// Hole number and gross strokes.
    public var holes: [(number: Int, strokes: Int)]

    public init(golferID: Int, courseID: Int, teeSetID: Int, playedAt: Date, holeCount: Int, scoreType: String = "H",
                gender: String = "M", holes: [(number: Int, strokes: Int)]) {
        self.golferID = golferID
        self.courseID = courseID
        self.teeSetID = teeSetID
        self.playedAt = playedAt
        self.holeCount = holeCount
        self.scoreType = scoreType
        self.gender = gender
        self.holes = holes
    }

    public static func == (a: GHINPost, b: GHINPost) -> Bool {
        a.golferID == b.golferID && a.courseID == b.courseID && a.teeSetID == b.teeSetID && a.playedAt == b.playedAt
            && a.holeCount == b.holeCount && a.scoreType == b.scoreType && a.gender == b.gender
            && a.holes.map { $0.number } == b.holes.map { $0.number }
            && a.holes.map { $0.strokes } == b.holes.map { $0.strokes }
    }

    public var total: Int { holes.reduce(0) { $0 + $1.strokes } }

    public var id: String { "\(golferID)-\(courseID)-\(teeSetID)-\(GHINFormat.day(playedAt))-\(total)" }
}

public enum GHINFormat {
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func day(_ date: Date) -> String { dayFormatter.string(from: date) }

    public static func date(_ value: Any?) -> Date? {
        guard let text = JSON.string(value) else { return nil }
        return dayFormatter.date(from: String(text.prefix(10)))
    }

    /// A handicap index as GHIN writes it: "12.3", "+1.4" (a plus handicap), or "NH" for none.
    public static func index(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        guard var text = JSON.string(value)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        var sign = 1.0
        if text.hasPrefix("+") {
            sign = -1.0
            text.removeFirst()
        }
        guard let number = Double(text) else { return nil }
        return sign * number
    }

    /// GHIN's code for a US state in course searches, for example "US-PA".
    public static func stateCode(_ state: String) -> String? {
        let trimmed = state.trimmingCharacters(in: .whitespaces).uppercased()
        if trimmed.count == 2 { return "US-\(trimmed)" }
        if trimmed.hasPrefix("US-") { return trimmed }
        return nil
    }
}

/// Builds requests and reads replies. Kept apart from the client so it can be tested without a network.
public enum GHINWire {
    public static let base = "https://api2.ghin.com/api/v1"
    static let sessionURL = "https://firebaseinstallations.googleapis.com/v1/projects/ghin-mobile-app/installations"
    // The public web key and app identifiers that ghin.com itself sends from the browser.
    static let webKey = "AIzaSyBxgTOAWxiud0HuaE5tN-5NTlzFnrtyz-I"
    static let sessionBody: [String: String] = [
        "appId": "1:884417644529:web:47fb315bc6c70242f72650",
        "authVersion": "FIS_v2",
        "fid": "fg6JfS0U01YmrelthLX9Iz",
        "sdkVersion": "w:0.5.7",
    ]
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    static let source = "GHINcom"

    static func jsonBody(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    public static func sessionRequest() -> URLRequest {
        var request = URLRequest(url: URL(string: sessionURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(webKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = jsonBody(sessionBody)
        return request
    }

    public static func loginRequest(sessionToken: String, login: String, password: String) -> URLRequest {
        var request = URLRequest(url: URL(string: base + "/golfer_login.json")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = ["token": sessionToken, "user": ["email_or_ghin": login, "password": password]]
        request.httpBody = jsonBody(body)
        return request
    }

    public static func request(path: String, query: [(String, String)], token: String, method: String = "GET",
                               body: Any? = nil) -> URLRequest {
        var components = URLComponents(string: base + path)!
        var items = [URLQueryItem(name: "source", value: source)]
        for (name, value) in query { items.append(URLQueryItem(name: name, value: value)) }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(source, forHTTPHeaderField: "source")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body = body { request.httpBody = jsonBody(body) }
        return request
    }

    public static func postBody(_ post: GHINPost) -> [String: Any] {
        [
            "golfer_id": post.golferID,
            "course_id": post.courseID,
            "tee_set_id": post.teeSetID,
            "tee_set_side": post.holeCount <= 9 ? "F9" : "All18",
            "played_at": GHINFormat.day(post.playedAt),
            "score_type": post.scoreType,
            "number_of_holes": post.holeCount,
            "gender": post.gender,
            "override_confirmation": false,
            "is_manual": false,
            "hole_details": post.holes.map { ["hole_number": $0.number, "raw_score": $0.strokes] },
        ]
    }

    // MARK: Reading replies

    static func sessionToken(from data: Data) -> String? {
        guard let root = JSON.object(data), let auth = root["authToken"] as? [String: Any] else { return nil }
        return auth["token"] as? String
    }

    static func login(from data: Data) -> (token: String, golfer: GHINGolfer)? {
        guard let root = JSON.object(data), let user = root["golfer_user"] as? [String: Any],
              let token = user["golfer_user_token"] as? String else { return nil }
        var golfer = GHINGolfer()
        if let list = user["golfers"] as? [[String: Any]], let first = list.first {
            golfer = GHINWire.golfer(from: first)
        }
        return (token, golfer)
    }

    static func golfer(from d: [String: Any]) -> GHINGolfer {
        var golfer = GHINGolfer()
        golfer.ghinNumber = JSON.int(d["ghin"]) ?? JSON.int(d["ghin_number"]) ?? JSON.int(d["golfer_id"]) ?? JSON.int(d["id"])
        let first = JSON.string(d["first_name"]) ?? ""
        let last = JSON.string(d["last_name"]) ?? ""
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        golfer.name = full.isEmpty ? JSON.string(d["player_name"]) : full
        golfer.handicapIndex = GHINFormat.index(d["handicap_index"]) ?? GHINFormat.index(d["hi_value"])
            ?? GHINFormat.index(d["hi_display"])
        golfer.lowIndex = GHINFormat.index(d["low_hi"]) ?? GHINFormat.index(d["low_hi_value"])
            ?? GHINFormat.index(d["low_hi_display"])
        golfer.clubName = JSON.string(d["club_name"])
        if golfer.clubName == nil, let clubs = d["clubs"] as? [[String: Any]] {
            golfer.clubName = JSON.string(clubs.first?["club_name"])
        }
        return golfer
    }

    static func golfer(fromSearch data: Data) -> GHINGolfer? {
        guard let root = JSON.object(data) else { return nil }
        if let list = root["golfers"] as? [[String: Any]], let first = list.first { return golfer(from: first) }
        if let one = root["golfer"] as? [String: Any] { return golfer(from: one) }
        return nil
    }

    static func scores(from data: Data) -> [GHINScore] {
        guard let root = JSON.object(data), let list = root["scores"] as? [[String: Any]] else { return [] }
        var result: [GHINScore] = []
        for d in list {
            guard let id = JSON.int(d["id"]), let played = GHINFormat.date(d["played_at"]),
                  let gross = JSON.int(d["adjusted_gross_score"]), let differential = JSON.double(d["differential"])
            else { continue }
            let course = JSON.string(d["course_name"]) ?? JSON.string(d["facility_name"])
                ?? JSON.string(d["course_display_value"]) ?? "Course"
            result.append(GHINScore(
                id: id, playedAt: played, adjustedGross: gross, differential: differential, courseName: course,
                teeName: JSON.string(d["tee_name"]) ?? "", rating: JSON.double(d["course_rating"]) ?? 72,
                slope: JSON.int(d["slope_rating"]) ?? 113, holes: JSON.int(d["number_of_holes"]) ?? 18,
                scoreType: JSON.string(d["score_type"]) ?? ""))
        }
        return result
    }

    static func courseHits(from data: Data) -> [GHINCourseHit] {
        guard let root = JSON.object(data), let list = root["courses"] as? [[String: Any]] else { return [] }
        var result: [GHINCourseHit] = []
        for d in list {
            guard let id = JSON.int(d["CourseID"]) ?? JSON.int(d["CourseId"]) else { continue }
            let name = JSON.string(d["FullName"]) ?? JSON.string(d["CourseName"]) ?? JSON.string(d["FacilityName"]) ?? "Course"
            result.append(GHINCourseHit(id: id, name: name, city: JSON.string(d["City"]) ?? "",
                                        state: JSON.string(d["State"]) ?? ""))
        }
        return result
    }

    static func courseDetails(from data: Data) -> GHINCourseDetails? {
        guard let root = JSON.object(data), let id = JSON.int(root["CourseId"]) ?? JSON.int(root["CourseID"]) else {
            return nil
        }
        var tees: [TeeSet] = []
        var pars: [Int] = []
        var indexes: [Int] = []
        for t in (root["TeeSets"] as? [[String: Any]]) ?? [] {
            var rating = 0.0
            var slope = 0
            for r in (t["Ratings"] as? [[String: Any]]) ?? [] where JSON.string(r["RatingType"]) == "Total" {
                rating = JSON.double(r["CourseRating"]) ?? 0
                slope = JSON.int(r["SlopeRating"]) ?? 0
            }
            if rating == 0 || slope == 0 { continue }
            let holes = ((t["Holes"] as? [[String: Any]]) ?? []).sorted {
                (JSON.int($0["Number"]) ?? 0) < (JSON.int($1["Number"]) ?? 0)
            }
            let yards = holes.map { JSON.int($0["Length"]) ?? 0 }
            let holePars = holes.map { JSON.int($0["Par"]) ?? 4 }
            if pars.isEmpty && !holePars.isEmpty {
                pars = holePars
                indexes = holes.enumerated().map { JSON.int($0.element["Allocation"]) ?? ($0.offset + 1) }
            }
            let par = JSON.int(t["TotalPar"]) ?? holePars.reduce(0, +)
            tees.append(TeeSet(name: JSON.string(t["TeeSetRatingName"]) ?? "Tee", rating: rating, slope: slope, par: par,
                               yards: yards, ghinTeeSetID: JSON.int(t["TeeSetRatingId"]), gender: JSON.string(t["Gender"])))
        }
        var state = ""
        if let text = JSON.string(root["CourseState"]) { state = text.replacingOccurrences(of: "US-", with: "") }
        return GHINCourseDetails(id: id, name: JSON.string(root["CourseName"]) ?? "Course",
                                 city: JSON.string(root["CourseCity"]) ?? "", state: state, tees: tees, pars: pars,
                                 strokeIndexes: indexes)
    }

    /// The server's own words for what went wrong, when it gave any.
    static func errorMessage(from data: Data, status: Int) -> String {
        if let root = JSON.object(data) {
            if let text = JSON.string(root["error"]) { return text }
            if let text = JSON.string(root["message"]) { return text }
            if let errors = root["errors"] as? [String: Any] {
                let parts = errors.map { key, value -> String in
                    if let list = value as? [Any] { return "\(key): " + list.map { "\($0)" }.joined(separator: ", ") }
                    return "\(key): \(value)"
                }
                if !parts.isEmpty { return parts.sorted().joined(separator: "; ") }
            }
            if let list = root["errors"] as? [Any], !list.isEmpty {
                return list.map { "\($0)" }.joined(separator: "; ")
            }
        }
        if status == 401 || status == 403 { return "GHIN did not accept the sign-in. Check the email or GHIN number and the password." }
        return "GHIN answered with an error (\(status))."
    }
}

/// Talks to GHIN. One instance holds the signed-in session.
public final class GHINClient {
    let transport: HTTPTransport
    public private(set) var token: String?

    public init(transport: HTTPTransport = URLSessionTransport(timeout: 40)) {
        self.transport = transport
    }

    public var isSignedIn: Bool { token != nil }

    public func signOut() { token = nil }

    /// Signs in and returns what GHIN said about the golfer.
    @discardableResult
    public func signIn(login: String, password: String) async throws -> GHINGolfer {
        let (sessionData, sessionStatus) = try await transport.send(GHINWire.sessionRequest())
        guard sessionStatus < 300, let sessionToken = GHINWire.sessionToken(from: sessionData) else {
            throw HTTPError(status: sessionStatus, message: "GHIN's sign-in service could not be reached (\(sessionStatus)).")
        }
        let (data, status) = try await transport.send(
            GHINWire.loginRequest(sessionToken: sessionToken, login: login, password: password))
        guard status < 300, let result = GHINWire.login(from: data) else {
            throw HTTPError(status: status, message: GHINWire.errorMessage(from: data, status: status))
        }
        token = result.token
        return result.golfer
    }

    func get(_ path: String, _ query: [(String, String)]) async throws -> Data {
        guard let token = token else { throw HTTPError(status: 401, message: "Sign in to GHIN first.") }
        let (data, status) = try await transport.send(GHINWire.request(path: path, query: query, token: token))
        guard status < 300 else {
            throw HTTPError(status: status, message: GHINWire.errorMessage(from: data, status: status))
        }
        return data
    }

    public func golfer(ghinNumber: Int) async throws -> GHINGolfer {
        let query = [("golfer_id", String(ghinNumber)), ("from_ghin", "true"), ("per_page", "25"), ("page", "1")]
        if let data = try? await get("/golfers.json", query), let found = GHINWire.golfer(fromSearch: data) {
            return found
        }
        let data = try await get("/search_golfer.json", [("ghin", String(ghinNumber))])
        guard let found = GHINWire.golfer(fromSearch: data) else {
            throw HTTPError(status: 200, message: "GHIN did not return a golfer for that number.")
        }
        return found
    }

    /// The golfer's posted scores, newest first.
    public func scores(ghinNumber: Int, limit: Int = 40) async throws -> [GHINScore] {
        let data = try await get("/scores.json", [("golfer_id", String(ghinNumber)), ("limit", String(limit)), ("offset", "0")])
        return GHINWire.scores(from: data).sorted { $0.playedAt > $1.playedAt }
    }

    public func searchCourses(name: String, state: String) async throws -> [GHINCourseHit] {
        var query = [("name", name)]
        if let code = GHINFormat.stateCode(state) {
            query.append(("country", "USA"))
            query.append(("state", code))
        }
        let data = try await get("/crsCourseMethods.asmx/SearchCourses.json", query)
        return GHINWire.courseHits(from: data)
    }

    public func courseDetails(id: Int) async throws -> GHINCourseDetails {
        let data = try await get("/crsCourseMethods.asmx/GetCourseDetails.json",
                                 [("course_id", String(id)), ("include_altered_tees", "false")])
        guard let details = GHINWire.courseDetails(from: data) else {
            throw HTTPError(status: 200, message: "GHIN's course details could not be read.")
        }
        return details
    }

    /// Posts a round hole by hole. Sent once; the caller must have shown the golfer exactly what
    /// is in `post` first. Returns GHIN's id for the new score when it gave one.
    public func post(_ post: GHINPost) async throws -> Int? {
        guard let token = token else { throw HTTPError(status: 401, message: "Sign in to GHIN first.") }
        let request = GHINWire.request(path: "/scores/hbh.json", query: [], token: token, method: "POST",
                                       body: GHINWire.postBody(post))
        let (data, status) = try await transport.send(request)
        guard status < 300 else {
            throw HTTPError(status: status, message: GHINWire.errorMessage(from: data, status: status))
        }
        if let root = JSON.object(data), let score = root["score"] as? [String: Any] {
            return JSON.int(score["id"])
        }
        return nil
    }
}
