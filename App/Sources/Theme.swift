import CaddieCore
import CoreLocation
import SwiftUI
import UIKit

extension Coordinate {
    var clLocation: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

    init(_ location: CLLocationCoordinate2D) {
        self.init(lat: location.latitude, lon: location.longitude)
    }
}

enum Theme {
    static let green = Color(red: 0.086, green: 0.471, blue: 0.290)

    static func color(for lie: Lie) -> UIColor {
        switch lie {
        case .tee: return .white
        case .fairway: return UIColor(red: 0.30, green: 0.78, blue: 0.40, alpha: 1)
        case .rough: return UIColor(red: 0.13, green: 0.50, blue: 0.22, alpha: 1)
        case .bunker: return UIColor(red: 0.93, green: 0.82, blue: 0.55, alpha: 1)
        case .green: return UIColor(red: 0.55, green: 0.92, blue: 0.55, alpha: 1)
        case .fringe: return UIColor(red: 0.45, green: 0.80, blue: 0.45, alpha: 1)
        case .recovery: return UIColor(red: 0.45, green: 0.33, blue: 0.20, alpha: 1)
        case .water: return UIColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 1)
        case .unknown: return .lightGray
        }
    }

    /// Color for a score against par: under par red, par plain, over par blue, as on a scorecard.
    static func color(toPar: Int) -> Color {
        if toPar < 0 { return .red }
        if toPar == 0 { return .primary }
        if toPar == 1 { return .blue }
        return .indigo
    }
}

enum Format {
    /// A distance in the user's unit, without the unit: "152".
    static func distance(yards: Double, meters useMeters: Bool) -> String {
        let value = useMeters ? yards / Geo.yardsPerMeter : yards
        return String(Int(value.rounded()))
    }

    static func unit(_ useMeters: Bool) -> String { useMeters ? "m" : "yd" }

    static func percent(_ rate: Rate) -> String {
        guard let fraction = rate.fraction else { return "–" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    static func ratio(_ rate: Rate) -> String {
        rate.chances == 0 ? "" : "\(rate.made) of \(rate.chances)"
    }

    static func one(_ value: Double?) -> String {
        guard let value = value else { return "–" }
        return String(format: "%.1f", value)
    }

    static func two(_ value: Double?) -> String {
        guard let value = value else { return "–" }
        return String(format: "%.2f", value)
    }

    /// Strokes gained with its sign: "+0.42", "−1.10".
    static func gained(_ value: Double?) -> String {
        guard let value = value else { return "–" }
        let text = String(format: "%.2f", abs(value))
        if value > 0.004 { return "+" + text }
        if value < -0.004 { return "−" + text }
        return "0.00"
    }

    static func toPar(_ value: Int) -> String {
        if value == 0 { return "E" }
        return value > 0 ? "+\(value)" : "−\(abs(value))"
    }

    /// A handicap index as golfers write it: a plus handicap shows as "+1.4".
    static func index(_ value: Double?) -> String {
        guard let value = value else { return "–" }
        if value < 0 { return "+" + String(format: "%.1f", abs(value)) }
        return String(format: "%.1f", value)
    }

    static func feet(_ value: Double) -> String {
        if value == value.rounded() { return "\(Int(value)) ft" }
        return String(format: "%.1f ft", value)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }

    static func scoreName(strokes: Int, par: Int) -> String {
        switch strokes - par {
        case ...(-3): return "Albatross"
        case -2: return "Eagle"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Double bogey"
        case 3: return "Triple bogey"
        default: return "+\(strokes - par)"
        }
    }
}

/// A label and a value on one line, used throughout the statistics.
struct StatRow: View {
    let label: String
    let value: String
    var detail: String = ""

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if !detail.isEmpty {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
    }
}
