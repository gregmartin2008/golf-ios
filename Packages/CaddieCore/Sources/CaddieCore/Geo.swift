import Foundation

/// A point on the earth, in degrees.
public struct Coordinate: Codable, Hashable {
    public var lat: Double
    public var lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

/// Distance and shape arithmetic on coordinates. Everything here treats a golf course as flat,
/// which is accurate to well under a yard at these sizes.
public enum Geo {
    public static let earthRadiusMeters = 6_371_000.0
    public static let yardsPerMeter = 1.0936133
    public static let feetPerMeter = 3.2808399

    static func radians(_ degrees: Double) -> Double { degrees * Double.pi / 180 }
    static func degrees(_ radians: Double) -> Double { radians * 180 / Double.pi }

    /// Great-circle distance in meters.
    public static func meters(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = radians(a.lat), lat2 = radians(b.lat)
        let dLat = lat2 - lat1
        let dLon = radians(b.lon - a.lon)
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusMeters * asin(min(1, sqrt(h)))
    }

    public static func yards(_ a: Coordinate, _ b: Coordinate) -> Double {
        meters(a, b) * yardsPerMeter
    }

    public static func feet(_ a: Coordinate, _ b: Coordinate) -> Double {
        meters(a, b) * feetPerMeter
    }

    /// Compass bearing from `a` to `b`, in degrees from north, 0 to 360.
    public static func bearing(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = radians(a.lat), lat2 = radians(b.lat)
        let dLon = radians(b.lon - a.lon)
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let result = degrees(atan2(y, x))
        return result < 0 ? result + 360 : result
    }

    /// The point `distance` meters from `start` along `bearingDegrees`.
    public static func destination(from start: Coordinate, bearingDegrees: Double, meters distance: Double) -> Coordinate {
        let angular = distance / earthRadiusMeters
        let bearing = radians(bearingDegrees)
        let lat1 = radians(start.lat), lon1 = radians(start.lon)
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
        return Coordinate(lat: degrees(lat2), lon: degrees(lon2))
    }

    /// Position of `p` in meters east (x) and north (y) of `origin`.
    static func local(_ p: Coordinate, origin: Coordinate) -> (x: Double, y: Double) {
        let x = radians(p.lon - origin.lon) * cos(radians(origin.lat)) * earthRadiusMeters
        let y = radians(p.lat - origin.lat) * earthRadiusMeters
        return (x, y)
    }

    static func fromLocal(x: Double, y: Double, origin: Coordinate) -> Coordinate {
        let lat = origin.lat + degrees(y / earthRadiusMeters)
        let lon = origin.lon + degrees(x / (earthRadiusMeters * cos(radians(origin.lat))))
        return Coordinate(lat: lat, lon: lon)
    }

    /// Whether `p` is inside the closed outline `ring` (first and last point need not repeat).
    public static func contains(_ ring: [Coordinate], _ p: Coordinate) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let a = ring[i], b = ring[j]
            if (a.lat > p.lat) != (b.lat > p.lat) {
                let crossing = (b.lon - a.lon) * (p.lat - a.lat) / (b.lat - a.lat) + a.lon
                if p.lon < crossing { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Shortest distance in meters from `p` to the segment `a`–`b`.
    public static func metersToSegment(_ p: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Double {
        let pa = local(p, origin: a)
        let ba = local(b, origin: a)
        let lengthSquared = ba.x * ba.x + ba.y * ba.y
        if lengthSquared == 0 { return (pa.x * pa.x + pa.y * pa.y).squareRoot() }
        var t = (pa.x * ba.x + pa.y * ba.y) / lengthSquared
        t = max(0, min(1, t))
        let dx = pa.x - t * ba.x
        let dy = pa.y - t * ba.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Shortest distance in meters from `p` to an open line of points.
    public static func metersToLine(_ p: Coordinate, _ line: [Coordinate]) -> Double {
        guard let first = line.first else { return Double.greatestFiniteMagnitude }
        if line.count == 1 { return meters(p, first) }
        var best = Double.greatestFiniteMagnitude
        for i in 1..<line.count {
            best = min(best, metersToSegment(p, line[i - 1], line[i]))
        }
        return best
    }

    /// Shortest distance in meters from `p` to the edge of a closed outline; 0 when inside.
    public static func metersToRing(_ p: Coordinate, _ ring: [Coordinate]) -> Double {
        guard ring.count >= 2 else { return ring.first.map { meters(p, $0) } ?? Double.greatestFiniteMagnitude }
        if contains(ring, p) { return 0 }
        var best = Double.greatestFiniteMagnitude
        var j = ring.count - 1
        for i in 0..<ring.count {
            best = min(best, metersToSegment(p, ring[j], ring[i]))
            j = i
        }
        return best
    }

    /// Average of the points; good enough as the middle of a green or bunker.
    public static func center(_ points: [Coordinate]) -> Coordinate? {
        guard !points.isEmpty else { return nil }
        var lat = 0.0, lon = 0.0
        for p in points { lat += p.lat; lon += p.lon }
        return Coordinate(lat: lat / Double(points.count), lon: lon / Double(points.count))
    }

    /// Which side of the directed line `from`→`to` the point is on: negative is left, positive is
    /// right, in meters from the line.
    public static func metersRightOfLine(_ p: Coordinate, from: Coordinate, to: Coordinate) -> Double {
        let d = local(to, origin: from)
        let q = local(p, origin: from)
        let length = (d.x * d.x + d.y * d.y).squareRoot()
        if length == 0 { return 0 }
        // Cross product of direction and point: positive when the point is to the left.
        let cross = d.x * q.y - d.y * q.x
        return -cross / length
    }

    /// Distance of `p` along the directed line `from`→`to`, in meters from `from`.
    public static func metersAlongLine(_ p: Coordinate, from: Coordinate, to: Coordinate) -> Double {
        let d = local(to, origin: from)
        let q = local(p, origin: from)
        let length = (d.x * d.x + d.y * d.y).squareRoot()
        if length == 0 { return 0 }
        return (d.x * q.x + d.y * q.y) / length
    }

    /// The segment of an open line nearest to `p`, as its two end points.
    public static func nearestSegment(of line: [Coordinate], to p: Coordinate) -> (Coordinate, Coordinate)? {
        guard line.count >= 2 else { return nil }
        var best = Double.greatestFiniteMagnitude
        var result = (line[0], line[1])
        for i in 1..<line.count {
            let d = metersToSegment(p, line[i - 1], line[i])
            if d < best {
                best = d
                result = (line[i - 1], line[i])
            }
        }
        return result
    }

    /// Where the ray from `from` through `through` enters and leaves `ring`, nearest first.
    /// Used for the front and back of a green. Empty when the ray misses the outline.
    public static func crossings(of ring: [Coordinate], from: Coordinate, through: Coordinate) -> [Coordinate] {
        guard ring.count >= 3 else { return [] }
        let d = local(through, origin: from)
        let length = (d.x * d.x + d.y * d.y).squareRoot()
        if length == 0 { return [] }
        let ux = d.x / length, uy = d.y / length
        var hits: [(Double, Coordinate)] = []
        var j = ring.count - 1
        for i in 0..<ring.count {
            let a = local(ring[j], origin: from)
            let b = local(ring[i], origin: from)
            j = i
            let ex = b.x - a.x, ey = b.y - a.y
            let denominator = ux * ey - uy * ex
            if abs(denominator) < 1e-12 { continue }
            // Solve from + t*u = a + s*e
            let t = (a.x * ey - a.y * ex) / denominator
            let s = (a.x * uy - a.y * ux) / denominator
            if t >= 0 && s >= 0 && s <= 1 {
                hits.append((t, fromLocal(x: t * ux, y: t * uy, origin: from)))
            }
        }
        return hits.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    /// The bounding box of a set of points as (south, west, north, east).
    public static func bounds(_ points: [Coordinate]) -> (south: Double, west: Double, north: Double, east: Double)? {
        guard let first = points.first else { return nil }
        var s = first.lat, n = first.lat, w = first.lon, e = first.lon
        for p in points {
            s = min(s, p.lat); n = max(n, p.lat)
            w = min(w, p.lon); e = max(e, p.lon)
        }
        return (s, w, n, e)
    }
}
