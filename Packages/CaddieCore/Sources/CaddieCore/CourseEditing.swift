import Foundation

/// Changes the owner makes to a course by hand: how many holes it has, and where each hole's tee
/// and green are when the map does not say.
public extension Course {
    /// Makes the course have `count` holes, adding blank par-4 holes or dropping the highest-numbered.
    mutating func resizeHoles(to count: Int) {
        guard count >= 1 else { return }
        holes.sort { $0.number < $1.number }
        if holes.count > count {
            holes = Array(holes.prefix(count))
        }
        var number = (holes.map { $0.number }.max() ?? 0) + 1
        while holes.count < count {
            holes.append(Hole(number: number))
            number += 1
        }
    }

    /// Sets where hole `number` is played from.
    mutating func setTee(hole number: Int, at point: Coordinate) {
        guard let position = holes.firstIndex(where: { $0.number == number }) else { return }
        holes[position].tee = point
        refreshHole(at: position)
    }

    /// Sets hole `number`'s green. When the point is on or beside a mapped green, that outline
    /// becomes the hole's green and its middle is used; otherwise the point itself is the middle.
    mutating func setGreen(hole number: Int, at point: Coordinate) {
        guard let position = holes.firstIndex(where: { $0.number == number }) else { return }
        // Release a green this hole claimed before.
        for index in 0..<features.count where features[index].kind == .green && features[index].hole == number {
            features[index].hole = nil
        }
        var chosen: Int?
        var nearest = 12.0
        for index in 0..<features.count where features[index].kind == .green {
            let distance = Geo.metersToRing(point, features[index].ring)
            if distance < nearest {
                nearest = distance
                chosen = index
            }
        }
        if let index = chosen, let middle = Geo.center(features[index].ring) {
            features[index].hole = number
            holes[position].greenCenter = middle
        } else {
            holes[position].greenCenter = point
        }
        refreshHole(at: position)
    }

    /// Works out the playing line, the front and back of the green, and which unclaimed outlines
    /// belong to the hole, once its tee and green are both known.
    private mutating func refreshHole(at position: Int) {
        var hole = holes[position]
        guard let tee = hole.tee, let green = hole.greenCenter else {
            holes[position] = hole
            return
        }
        // A line set by hand replaces a mapped one that no longer matches.
        if hole.line.count < 2 || Geo.meters(hole.line[0], tee) > 5 || Geo.meters(hole.line[hole.line.count - 1], green) > 25 {
            hole.line = [tee, green]
        }
        let from = hole.line[hole.line.count - 2]
        var front: Coordinate?
        var back: Coordinate?
        if let outline = features.first(where: { $0.kind == .green && $0.hole == hole.number }) {
            let hits = Geo.crossings(of: outline.ring, from: from, through: green)
            if hits.count >= 2 {
                front = hits.first
                back = hits.last
            }
        }
        if front == nil {
            // No outline: assume a green of typical depth.
            let heading = Geo.bearing(from, green)
            front = Geo.destination(from: green, bearingDegrees: heading + 180, meters: 13)
            back = Geo.destination(from: green, bearingDegrees: heading, meters: 13)
        }
        hole.greenFront = front
        hole.greenBack = back
        holes[position] = hole

        // Give unclaimed fairways, bunkers and water along this hole to it, unless another mapped
        // hole's line is nearer.
        let others = holes.filter { $0.number != hole.number && $0.line.count >= 2 }
        for index in 0..<features.count where features[index].hole == nil {
            let feature = features[index]
            guard let middle = Geo.center(feature.ring) else { continue }
            switch feature.kind {
            case .green:
                continue
            case .tee:
                if Geo.meters(middle, tee) <= 30 { features[index].hole = hole.number }
            default:
                let mine = Geo.metersToLine(middle, hole.line)
                if mine > 60 { continue }
                let theirs = others.map { Geo.metersToLine(middle, $0.line) }.min() ?? Double.greatestFiniteMagnitude
                if mine <= theirs { features[index].hole = hole.number }
            }
        }
    }
}
