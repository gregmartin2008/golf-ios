import Foundation

/// What the course map did and did not contain, so the owner knows what to fix by hand.
public struct Coverage: Codable, Equatable {
    public var holesFound = 0
    public var holesWithGreen = 0
    public var holesWithFairway = 0
    public var greens = 0
    public var tees = 0
    public var fairways = 0
    public var bunkers = 0
    public var water = 0
    public var hasBoundary = false

    public init() {}

    /// True when the map has outlines (greens, fairways, bunkers) but no numbered holes, so the
    /// owner only needs to say which tee and green belong to each hole.
    public var hasShapesButNoHoles: Bool { holesFound == 0 && (greens + fairways + bunkers) > 0 }

    public var summary: String {
        if holesFound == 0 {
            return "No holes are mapped for this course yet. Place the tee and green for each hole by hand."
        }
        var parts = ["\(holesFound) holes", "\(greens) greens", "\(fairways) fairways", "\(bunkers) bunkers"]
        if water > 0 { parts.append("\(water) water") }
        return parts.joined(separator: ", ")
    }

    /// Coverage of a stored course.
    public static func of(_ course: Course) -> Coverage {
        var c = Coverage()
        c.holesFound = course.holes.filter { $0.isMapped }.count
        c.holesWithGreen = course.holes.filter { $0.greenFront != nil }.count
        let withFairway = Set(course.features.filter { $0.kind == .fairway }.compactMap { $0.hole })
        c.holesWithFairway = withFairway.count
        c.greens = course.features.filter { $0.kind == .green }.count
        c.tees = course.features.filter { $0.kind == .tee }.count
        c.fairways = course.features.filter { $0.kind == .fairway }.count
        c.bunkers = course.features.filter { $0.kind == .bunker }.count
        c.water = course.features.filter { $0.kind == .water }.count
        c.hasBoundary = !course.boundary.isEmpty
        return c
    }
}

/// A golf course outline found near a point, before its details are loaded.
public struct CourseCandidate: Equatable, Identifiable {
    public var id: String
    public var name: String
    public var center: Coordinate
    public var boundary: [Coordinate]
}

/// Builds a `Course` from OpenStreetMap data returned by the Overpass service.
public enum OSMImport {
    /// How far around the search point to look, in meters.
    public static let radiusMeters = 3000

    /// The Overpass query for everything golf-related near a point.
    public static func query(near point: Coordinate, radiusMeters radius: Int = OSMImport.radiusMeters) -> String {
        let around = "(around:\(radius),\(point.lat),\(point.lon))"
        return """
        [out:json][timeout:60];
        (
          nwr["leisure"="golf_course"]\(around);
          way["golf"="hole"]\(around);
          nwr["golf"~"^(tee|fairway|green|bunker|water_hazard|lateral_water_hazard|rough)$"]\(around);
          nwr["natural"="water"]\(around);
        );
        out tags geom;
        """
    }

    /// The Overpass query for golf course outlines near a point. Small and quick.
    public static func outlineQuery(near point: Coordinate, radiusMeters radius: Int = OSMImport.radiusMeters) -> String {
        """
        [out:json][timeout:60];
        nwr["leisure"="golf_course"](around:\(radius),\(point.lat),\(point.lon));
        out tags geom;
        """
    }

    /// The Overpass query for the holes and outlines inside a box (south, west, north, east).
    public static func featureQuery(south: Double, west: Double, north: Double, east: Double) -> String {
        let box = "(\(south),\(west),\(north),\(east))"
        return """
        [out:json][timeout:60];
        (
          way["golf"="hole"]\(box);
          nwr["golf"~"^(tee|fairway|green|bunker|water_hazard|lateral_water_hazard|rough)$"]\(box);
          way["natural"="water"]\(box);
        );
        out tags geom;
        """
    }

    /// Joins two Overpass replies into one.
    public static func merge(_ first: Data, _ second: Data) -> Data {
        let a = (JSON.object(first)?["elements"] as? [Any]) ?? []
        let b = (JSON.object(second)?["elements"] as? [Any]) ?? []
        return (try? JSONSerialization.data(withJSONObject: ["elements": a + b])) ?? first
    }

    /// What a reply contains, for checking coverage: how many of each golf feature, and the
    /// numbers the hole lines carry.
    public static func tally(from data: Data) -> (counts: [String: Int], holeRefs: [String]) {
        var counts: [String: Int] = [:]
        var refs: [String] = []
        for element in elements(from: data) {
            if let golf = element.tags["golf"] {
                counts[golf, default: 0] += 1
                if golf == "hole" { refs.append(element.tags["ref"] ?? "(none)") }
            } else if element.tags["leisure"] == "golf_course" {
                counts["course outline", default: 0] += 1
            } else if element.tags["natural"] == "water" {
                counts["water", default: 0] += 1
            }
        }
        return (counts, refs)
    }

    /// The hole number in a `ref` tag: "7", "07", or a prefixed form such as "B7".
    static func holeNumber(_ ref: String?) -> Int? {
        guard let ref = ref else { return nil }
        var digits = ""
        for character in ref.reversed() {
            if character.isNumber { digits.insert(character, at: digits.startIndex) } else if !digits.isEmpty { break }
        }
        guard let number = Int(digits), number >= 1, number <= 27 else { return nil }
        return number
    }

    struct Element {
        var id: String
        var tags: [String: String]
        /// Closed outlines or, for a hole, one open line.
        var rings: [[Coordinate]]
    }

    static func points(_ value: Any?) -> [Coordinate] {
        guard let array = value as? [Any] else { return [] }
        var result: [Coordinate] = []
        for item in array {
            guard let d = item as? [String: Any], let lat = JSON.double(d["lat"]), let lon = JSON.double(d["lon"]) else {
                continue
            }
            result.append(Coordinate(lat: lat, lon: lon))
        }
        return result
    }

    /// Joins the pieces of an outline that the map stores as several ways.
    static func stitch(_ pieces: [[Coordinate]]) -> [[Coordinate]] {
        var open = pieces.filter { $0.count >= 2 }
        var rings: [[Coordinate]] = []
        func same(_ a: Coordinate, _ b: Coordinate) -> Bool {
            abs(a.lat - b.lat) < 1e-7 && abs(a.lon - b.lon) < 1e-7
        }
        while !open.isEmpty {
            var current = open.removeFirst()
            var grew = true
            while grew, let first = current.first, let last = current.last, !same(first, last) {
                grew = false
                for i in 0..<open.count {
                    let piece = open[i]
                    guard let pFirst = piece.first, let pLast = piece.last else { continue }
                    if same(last, pFirst) {
                        current.append(contentsOf: piece.dropFirst())
                    } else if same(last, pLast) {
                        current.append(contentsOf: Array(piece.reversed()).dropFirst())
                    } else if same(first, pLast) {
                        current = piece + Array(current.dropFirst())
                    } else if same(first, pFirst) {
                        current = Array(piece.reversed()) + Array(current.dropFirst())
                    } else {
                        continue
                    }
                    open.remove(at: i)
                    grew = true
                    break
                }
            }
            rings.append(current)
        }
        return rings
    }

    static func elements(from data: Data) -> [Element] {
        guard let root = JSON.object(data), let list = root["elements"] as? [[String: Any]] else { return [] }
        var result: [Element] = []
        for item in list {
            guard let type = item["type"] as? String, let idNumber = JSON.int(item["id"]) else { continue }
            var tags: [String: String] = [:]
            if let raw = item["tags"] as? [String: Any] {
                for (key, value) in raw { tags[key] = JSON.string(value) }
            }
            var rings: [[Coordinate]] = []
            if type == "way" {
                let line = points(item["geometry"])
                if line.count >= 2 { rings = [line] }
            } else if type == "relation", let members = item["members"] as? [[String: Any]] {
                var outers: [[Coordinate]] = []
                for member in members {
                    let role = (member["role"] as? String) ?? ""
                    if role == "inner" { continue }
                    let line = points(member["geometry"])
                    if line.count >= 2 { outers.append(line) }
                }
                rings = stitch(outers)
            }
            if rings.isEmpty { continue }
            result.append(Element(id: "\(type)/\(idNumber)", tags: tags, rings: rings))
        }
        return result
    }

    static func kind(for tags: [String: String]) -> FeatureKind? {
        if let golf = tags["golf"] {
            switch golf {
            case "tee": return .tee
            case "fairway": return .fairway
            case "green": return .green
            case "bunker": return .bunker
            case "water_hazard", "lateral_water_hazard": return .water
            case "rough": return .rough
            default: return nil
            }
        }
        if tags["natural"] == "water" { return .water }
        return nil
    }

    /// The golf course outlines in an Overpass reply, nearest to `point` first.
    public static func candidates(from data: Data, near point: Coordinate) -> [CourseCandidate] {
        var found: [CourseCandidate] = []
        for element in elements(from: data) where element.tags["leisure"] == "golf_course" {
            guard let ring = element.rings.max(by: { $0.count < $1.count }), let center = Geo.center(ring) else {
                continue
            }
            found.append(CourseCandidate(id: element.id, name: element.tags["name"] ?? "Golf course", center: center,
                                         boundary: ring))
        }
        return found.sorted {
            Geo.metersToRing(point, $0.boundary) < Geo.metersToRing(point, $1.boundary)
        }
    }

    /// Builds the course nearest `point` from an Overpass reply.
    /// - Parameters:
    ///   - candidateID: the outline to use; nil picks the one containing or nearest the point.
    ///   - fallbackName: the name to use when the map has none.
    public static func course(from data: Data, near point: Coordinate, candidateID: String? = nil,
                              fallbackName: String = "Golf course") -> (course: Course, coverage: Coverage) {
        let all = elements(from: data)
        let options = candidates(from: data, near: point)
        let chosen = options.first { $0.id == candidateID } ?? options.first
        let boundary = chosen?.boundary ?? []

        func onCourse(_ p: Coordinate) -> Bool {
            if boundary.count >= 3 { return Geo.metersToRing(p, boundary) <= 15 }
            return Geo.meters(p, point) <= 2000
        }

        // Holes.
        var holeLines: [Int: (line: [Coordinate], par: Int?, index: Int?)] = [:]
        for element in all where element.tags["golf"] == "hole" {
            guard let line = element.rings.first, line.count >= 2,
                  let number = holeNumber(element.tags["ref"]) else { continue }
            guard let middle = Geo.center(line), onCourse(middle) else { continue }
            if holeLines[number] != nil { continue }
            holeLines[number] = (line, element.tags["par"].flatMap { Int($0) }, element.tags["handicap"].flatMap { Int($0) })
        }

        // Outlines.
        var features: [CourseFeature] = []
        for element in all {
            guard let featureKind = OSMImport.kind(for: element.tags) else { continue }
            for (offset, ring) in element.rings.enumerated() where ring.count >= 3 {
                guard let center = Geo.center(ring), onCourse(center) else { continue }
                // A lake that happens to be nearby is only a hazard if it is on the course.
                if element.tags["golf"] == nil && boundary.count < 3 { continue }
                let id = element.rings.count > 1 ? "\(element.id)#\(offset)" : element.id
                features.append(CourseFeature(id: id, kind: featureKind, ring: ring))
            }
        }

        let greens = features.filter { $0.kind == .green }

        // Make every hole line run from tee to green.
        for (number, entry) in holeLines {
            guard let first = entry.line.first, let last = entry.line.last else { continue }
            let startToGreen = greens.map { Geo.metersToRing(first, $0.ring) }.min() ?? 1e9
            let endToGreen = greens.map { Geo.metersToRing(last, $0.ring) }.min() ?? 1e9
            if startToGreen < 20 && endToGreen > 40 {
                holeLines[number] = (Array(entry.line.reversed()), entry.par, entry.index)
            }
        }

        // Build the holes.
        let highest = holeLines.keys.max() ?? 0
        // Nine holes only when the map has exactly holes 1 to 9. A course with a few holes mapped
        // is far more often an eighteen-hole course that volunteers have not finished.
        let isNine = highest == 9 && holeLines.count == 9
        let holeCount = isNine ? 9 : max(18, highest)
        var holes: [Hole] = []
        var greenOwner: [String: Int] = [:]
        for number in 1...holeCount {
            guard let entry = holeLines[number], let tee = entry.line.first, let end = entry.line.last else {
                holes.append(Hole(number: number))
                continue
            }
            var hole = Hole(number: number, par: entry.par ?? 4, strokeIndex: entry.index ?? number, tee: tee,
                            greenCenter: end, line: entry.line)
            var nearest: CourseFeature?
            var nearestMeters = 45.0
            for green in greens {
                let d = Geo.metersToRing(end, green.ring)
                if d < nearestMeters {
                    nearestMeters = d
                    nearest = green
                }
            }
            if let green = nearest, let center = Geo.center(green.ring) {
                hole.greenCenter = center
                greenOwner[green.id] = number
                let from = entry.line[entry.line.count - 2]
                let hits = Geo.crossings(of: green.ring, from: from, through: center)
                if hits.count >= 2 {
                    hole.greenFront = hits.first
                    hole.greenBack = hits.last
                }
            }
            holes.append(hole)
        }

        // Give each outline to the hole it belongs to.
        let mapped = holes.filter { $0.line.count >= 2 }
        if !mapped.isEmpty {
            for i in 0..<features.count {
                let feature = features[i]
                if let owner = greenOwner[feature.id] {
                    features[i].hole = owner
                    continue
                }
                guard let center = Geo.center(feature.ring) else { continue }
                var best: Int?
                var bestMeters = 150.0
                for hole in mapped {
                    var d: Double
                    switch feature.kind {
                    case .tee:
                        d = Geo.meters(center, hole.line[0])
                    case .green:
                        d = Geo.meters(center, hole.line[hole.line.count - 1])
                    default:
                        d = Geo.metersToLine(center, hole.line)
                    }
                    if feature.kind == .fairway, Geo.contains(feature.ring, hole.line[hole.line.count / 2]) {
                        d = 0
                    }
                    if d < bestMeters {
                        bestMeters = d
                        best = hole.number
                    }
                }
                features[i].hole = best
            }
        }

        let location = chosen?.center ?? point
        var course = Course(name: chosen?.name ?? fallbackName, location: location, osmID: chosen?.id, holes: holes,
                            features: features, boundary: boundary)
        if course.name == "Golf course" { course.name = fallbackName }
        return (course, Coverage.of(course))
    }
}

/// Fetches course data from the public Overpass servers.
public struct OverpassClient {
    public static let servers = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
    ]

    let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport(timeout: 90)) {
        self.transport = transport
    }

    /// Golf course outlines near a point: the quick first step, also used for "courses near me".
    public func fetchOutlines(near point: Coordinate, radiusMeters: Int = OSMImport.radiusMeters) async throws -> Data {
        try await run(OSMImport.outlineQuery(near: point, radiusMeters: radiusMeters))
    }

    /// Everything needed to build the course at `point`: its outline, then the holes and shapes
    /// inside that outline. Asking in two steps keeps each reply small, which matters in built-up
    /// areas where one wide query is slow.
    public func fetch(near point: Coordinate, candidateID: String? = nil) async throws -> Data {
        let outlines = try await fetchOutlines(near: point)
        let options = OSMImport.candidates(from: outlines, near: point)
        let chosen = options.first { $0.id == candidateID } ?? options.first
        guard let boundary = chosen?.boundary, let box = Geo.bounds(boundary) else {
            // No course outline on the map: take whatever golf features are close by.
            return try await run(OSMImport.query(near: point, radiusMeters: 1500))
        }
        let margin = 0.0006
        let features = try await run(OSMImport.featureQuery(south: box.south - margin, west: box.west - margin,
                                                            north: box.north + margin, east: box.east + margin))
        return OSMImport.merge(outlines, features)
    }

    /// Sends one query, trying each server in turn.
    func run(_ query: String) async throws -> Data {
        var lastError: Error = HTTPError(status: 0, message: "The map service could not be reached.")
        for server in OverpassClient.servers {
            guard let url = URL(string: server) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.setValue("Caddie golf app (personal use)", forHTTPHeaderField: "User-Agent")
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
            request.httpBody = Data("data=\(encoded)".utf8)
            do {
                let (data, status) = try await transport.send(request)
                if status == 200, JSON.object(data)?["elements"] != nil {
                    return data
                }
                lastError = HTTPError(status: status, message: "The map service answered with an error (\(status)).")
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
