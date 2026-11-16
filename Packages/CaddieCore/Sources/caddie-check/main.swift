import CaddieCore
import Foundation

// Imports the golf course nearest a point from live OpenStreetMap data and prints what was found.
// usage: caddie-check <latitude> <longitude> [name]

let arguments = CommandLine.arguments
guard arguments.count >= 3, let latitude = Double(arguments[1]), let longitude = Double(arguments[2]) else {
    print("usage: caddie-check <latitude> <longitude> [name]")
    exit(2)
}
let label = arguments.count >= 4 ? arguments[3] : "Golf course"
let point = Coordinate(lat: latitude, lon: longitude)

do {
    let started = Date()
    let data = try await OverpassClient().fetch(near: point)
    let seconds = Date().timeIntervalSince(started)
    let tally = OSMImport.tally(from: data)
    print("map contains: " + tally.counts.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", "))
    print("hole numbers on the map: " + tally.holeRefs.prefix(40).joined(separator: " "))
    let options = OSMImport.candidates(from: data, near: point)
    print("reply: \(data.count) bytes in \(String(format: "%.1f", seconds)) s; \(options.count) course outlines nearby")
    for option in options.prefix(5) {
        print("  outline \(option.id): \(option.name)")
    }
    let result = OSMImport.course(from: data, near: point, fallbackName: label)
    let course = result.course
    let coverage = result.coverage
    print("course: \(course.name), \(course.holes.count) holes, par \(course.par)")
    print("coverage: \(coverage.summary)")
    print("holes with tee and green: \(coverage.holesFound); with front and back of green: \(coverage.holesWithGreen); with a fairway: \(coverage.holesWithFairway)")
    for hole in course.holes {
        var parts: [String] = ["hole \(hole.number)", "par \(hole.par)", "index \(hole.strokeIndex)"]
        if let tee = hole.tee, let green = hole.greenCenter {
            parts.append("\(Int(Geo.yards(tee, green).rounded())) yd tee to green")
        } else {
            parts.append("not mapped")
        }
        if let front = hole.greenFront, let back = hole.greenBack {
            parts.append("green \(Int(Geo.yards(front, back).rounded())) yd deep")
        }
        let own = course.features.filter { $0.hole == hole.number }
        let bunkers = own.filter { $0.kind == .bunker }.count
        let fairways = own.filter { $0.kind == .fairway }.count
        parts.append("\(fairways) fairway, \(bunkers) bunkers")
        print("  " + parts.joined(separator: ", "))
    }
    print("RESULT ok")
} catch {
    print("RESULT failed: \(error.localizedDescription)")
    exit(1)
}
