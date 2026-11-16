import CaddieCore
import SwiftUI

/// Playing a round: the map of the current hole on top and the scoring panel below.
struct HoleScreen: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var location = LocationService()

    @State var round: Round
    @State var index: Int

    @State private var frameToken = 0
    @State private var measurePoint: Coordinate?
    @State private var pendingPenalty: PenaltyKind?
    @State private var editingMark: BallMark?
    @State private var showPutts = false
    @State private var showQuick = false
    @State private var showSummary = false

    init(round: Round, startIndex: Int? = nil) {
        _round = State(initialValue: round)
        let firstOpen = round.holes.firstIndex { !$0.isComplete } ?? max(0, round.holes.count - 1)
        _index = State(initialValue: min(startIndex ?? firstOpen, max(0, round.holes.count - 1)))
    }

    private var course: Course? { model.course(round.courseID) }
    private var score: HoleScore { round.holes[index] }
    private var hole: Hole? { course?.hole(score.number) }
    private var useMeters: Bool { model.settings.useMeters }

    var body: some View {
        VStack(spacing: 0) {
            map
            panel
        }
        .navigationTitle("Hole \(score.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Card") { showSummary = true }
            }
        }
        .onAppear {
            if !model.isDemo { location.start() }
            if model.demoScreen == "putts" { showPutts = true }
        }
        .onDisappear { location.stop() }
        .sheet(item: $editingMark) { mark in
            MarkEditor(mark: mark, clubs: model.clubNames, canDelete: true) { updated in
                replace(updated)
            } onDelete: {
                remove(mark)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPutts) {
            PuttsEditor(score: score, suggestedFeet: suggestedFirstPutt) { putts, holed in
                round.holes[index].putts = putts
                round.holes[index].holedFromOffGreen = holed
                round.holes[index].quick = nil
                save()
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showQuick) {
            QuickEditor(score: score) { quick in
                round.holes[index].quick = quick
                save()
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSummary) {
            NavigationStack {
                RoundSummaryView(roundID: round.id, onGoToHole: { number in
                    if let target = round.holes.firstIndex(where: { $0.number == number }) {
                        go(to: target)
                    }
                    showSummary = false
                }, onFinished: {
                    showSummary = false
                    dismiss()
                })
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showSummary = false }
                    }
                }
            }
            .modifier(NoticeLayer())
        }
        .onChange(of: showSummary) { _, showing in
            // The summary can finish or change the round; pick up what it saved.
            if !showing, let fresh = model.round(round.id) { round = fresh }
        }
    }

    // MARK: Map

    private var pins: [MapPin] {
        var result: [MapPin] = []
        if let green = hole?.greenCenter {
            result.append(MapPin(id: "flag", coordinate: green, kind: .flag))
        }
        if score.marks.isEmpty, let tee = hole?.tee {
            result.append(MapPin(id: "tee", coordinate: tee, kind: .teeMarker))
        }
        var number = 0
        for mark in score.marks {
            number += 1 + (mark.penaltyBefore?.strokes ?? 0)
            result.append(MapPin(id: mark.id.uuidString, coordinate: mark.coordinate,
                                 kind: .mark(number: number, lie: mark.lie, penalty: mark.penaltyBefore != nil),
                                 draggable: true))
        }
        if let point = measurePoint {
            result.append(MapPin(id: "measure", coordinate: point, kind: .measure))
        }
        return result
    }

    private var measureLine: [Coordinate] {
        guard let point = measurePoint else { return [] }
        var line: [Coordinate] = []
        if let from = reference { line.append(from) }
        line.append(point)
        if let green = hole?.greenCenter { line.append(green) }
        return line
    }

    private var map: some View {
        HoleMapView(
            hole: hole,
            features: course?.features ?? [],
            pins: pins,
            path: score.marks.map { $0.coordinate },
            measure: measureLine,
            fallbackCenter: location.coordinate ?? course?.location ?? Coordinate(lat: 39.5, lon: -98.35),
            showsUser: !model.isDemo,
            frameToken: frameToken,
            onTap: { point in measurePoint = point },
            onLongPress: { point in addMark(at: point, source: .touch, accuracy: nil) },
            onMovePin: { id, point in movePin(id: id, to: point) },
            onSelectPin: { id in editingMark = score.marks.first { $0.id.uuidString == id } }
        )
        .overlay(alignment: .topLeading) { measureReadout }
        .overlay(alignment: .topTrailing) {
            Button {
                measurePoint = nil
                frameToken += 1
            } label: {
                Image(systemName: "scope")
                    .padding(10)
                    .background(.thinMaterial, in: Circle())
            }
            .padding(10)
            .accessibilityLabel("Show the whole hole")
        }
    }

    @ViewBuilder
    private var measureReadout: some View {
        if let point = measurePoint {
            VStack(alignment: .leading, spacing: 2) {
                if let from = reference {
                    Text("\(Format.distance(yards: Geo.yards(from, point), meters: useMeters)) \(Format.unit(useMeters)) to point")
                }
                if let green = hole?.greenCenter {
                    Text("\(Format.distance(yards: Geo.yards(point, green), meters: useMeters)) \(Format.unit(useMeters)) from there to green")
                }
                Button("Clear") { measurePoint = nil }
                    .font(.caption)
            }
            .font(.footnote.weight(.semibold))
            .padding(8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(10)
        }
    }

    /// Where distances are measured from: the phone when it has a good fix on the course, else
    /// the last mark, else the tee.
    private var reference: Coordinate? {
        if let here = location.coordinate, let green = hole?.greenCenter, Geo.yards(here, green) < 900 {
            return here
        }
        return score.marks.last?.coordinate ?? hole?.tee
    }

    private var referenceLabel: String {
        if let here = location.coordinate, let green = hole?.greenCenter, Geo.yards(here, green) < 900 {
            if let accuracy = location.accuracy, accuracy > 15 { return "From you (weak GPS, ±\(Int(accuracy)) m)" }
            return "From you"
        }
        if !score.marks.isEmpty { return "From your last mark" }
        return "From the tee"
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 10) {
            header
            distances
            markStrip
            actions
            navigation
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color(.systemBackground))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Hole \(score.number)").font(.title3.weight(.bold))
                Text(headerDetail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if let strokes = score.strokes {
                    Text("\(strokes)").font(.title2.weight(.bold)).foregroundStyle(Theme.color(toPar: strokes - score.par))
                    Text(Format.scoreName(strokes: strokes, par: score.par)).font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text(score.marks.isEmpty ? "–" : "Lying \(score.strokesSoFar)").font(.title3.weight(.semibold))
                    Text("Round \(Format.toPar(round.grossSoFar - round.parSoFar)) thru \(round.completedHoles.count)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var headerDetail: String {
        var parts = ["Par \(score.par)"]
        if score.yards > 0 { parts.append("\(score.yards) yd") }
        parts.append("Index \(score.strokeIndex)")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var distances: some View {
        if let hole = hole, let green = hole.greenCenter, let from = reference {
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    distanceCell("Front", hole.greenFront.map { Geo.yards(from, $0) })
                    distanceCell("Center", Geo.yards(from, green), large: true)
                    distanceCell("Back", hole.greenBack.map { Geo.yards(from, $0) })
                }
                Text(referenceLabel).font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("This hole is not on the map yet. Long-press the map to place marks, or use Quick score.")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func distanceCell(_ label: String, _ yards: Double?, large: Bool = false) -> some View {
        VStack(spacing: 0) {
            Text(yards.map { Format.distance(yards: $0, meters: useMeters) } ?? "–")
                .font(large ? .system(size: 34, weight: .bold) : .title2.weight(.semibold))
                .monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var markStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if score.quick != nil {
                    chip("Quick score entered", color: .secondary)
                }
                ForEach(Array(score.marks.enumerated()), id: \.element.id) { offset, mark in
                    Button {
                        editingMark = mark
                    } label: {
                        chip(markLabel(offset: offset, mark: mark), color: mark.penaltyBefore == nil ? Theme.green : .red)
                    }
                    .buttonStyle(.plain)
                }
                if !score.putts.isEmpty {
                    Button {
                        showPutts = true
                    } label: {
                        chip("Putts: " + score.putts.map { Format.feet($0.feet) }.joined(separator: ", "), color: .blue)
                    }
                    .buttonStyle(.plain)
                } else if score.holedFromOffGreen {
                    chip("Holed out", color: .blue)
                }
                if let penalty = pendingPenalty {
                    chip("Next mark is your drop (\(penalty.label), +1)", color: .red)
                }
            }
        }
        .frame(height: 30)
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func markLabel(offset: Int, mark: BallMark) -> String {
        var text = mark.lie.label
        if let club = mark.club { text += " · \(club)" }
        if offset + 1 < score.marks.count {
            let next = score.marks[offset + 1]
            if next.penaltyBefore == nil {
                text += " · \(Format.distance(yards: Geo.yards(mark.coordinate, next.coordinate), meters: useMeters)) \(Format.unit(useMeters))"
            }
        }
        if let penalty = mark.penaltyBefore { text = "\(penalty.label) +1 · " + text }
        return text
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                markHere()
            } label: {
                Label("Mark ball", systemImage: "location.fill")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(location.coordinate == nil)

            Menu {
                ForEach(model.clubNames, id: \.self) { name in
                    Button(name) { setClub(name) }
                }
            } label: {
                Label(score.marks.last?.club ?? "Club", systemImage: "figure.golf")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(score.marks.isEmpty)

            Menu {
                Button("Putts") { showPutts = true }
                Button("Quick score (no map)") { showQuick = true }
                Divider()
                ForEach(PenaltyKind.allCases, id: \.self) { kind in
                    Button("Penalty: \(kind.label)") { addPenalty(kind) }
                }
                Divider()
                Button("Undo last mark", role: .destructive) { undo() }
                    .disabled(score.marks.isEmpty)
                Button("Clear this hole", role: .destructive) { clearHole() }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.regular)
    }

    private var navigation: some View {
        HStack {
            Button {
                go(to: index - 1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(index == 0)
            Spacer()
            Button("Putts") { showPutts = true }
                .buttonStyle(.bordered)
            Spacer()
            if index + 1 < round.holes.count {
                Button {
                    go(to: index + 1)
                } label: {
                    Label("Next", systemImage: "chevron.right").labelStyle(.titleAndIcon)
                }
            } else {
                Button("Finish") { showSummary = true }
                    .fontWeight(.semibold)
            }
        }
        .font(.callout)
    }

    // MARK: Changes

    private func save() {
        model.save(round: round)
    }

    private func go(to target: Int) {
        guard target >= 0, target < round.holes.count else { return }
        index = target
        measurePoint = nil
        pendingPenalty = nil
        frameToken += 1
    }

    private var suggestedFirstPutt: Double? {
        guard let green = hole?.greenCenter, let mark = score.marks.last(where: { $0.lie == .green }) else { return nil }
        return max(1, Geo.feet(mark.coordinate, green).rounded())
    }

    private func markHere() {
        guard let here = location.coordinate else { return }
        addMark(at: here, source: .gps, accuracy: location.accuracy)
    }

    private func addMark(at point: Coordinate, source: MarkSource, accuracy: Double?) {
        var hole = round.holes[index]
        hole.quick = nil
        if hole.isComplete {
            // The hole was finished; a new mark means it is being re-entered from here.
            hole.putts = []
            hole.holedFromOffGreen = false
        }
        if hole.marks.isEmpty {
            // The first mark is the tee. If this point is well down the hole, the tee was not
            // marked, so put it in from the map.
            if let tee = self.hole?.tee, Geo.yards(point, tee) > 40 {
                hole.marks.append(BallMark(coordinate: tee, lie: .tee, source: .tee,
                                           club: hole.par >= 4 ? "Driver" : nil))
            } else {
                hole.marks.append(BallMark(coordinate: point, lie: .tee, source: source, accuracy: accuracy,
                                           club: hole.par >= 4 ? "Driver" : nil))
                round.holes[index] = hole
                save()
                return
            }
        }
        var lie = Lie.unknown
        if let course = course { lie = LieDetector.lie(at: point, course: course, hole: hole.number) }
        if lie == .tee { lie = .rough }
        var mark = BallMark(coordinate: point, lie: lie, source: source, accuracy: accuracy, penaltyBefore: pendingPenalty)
        if lie == .green { mark.club = "Putter" }
        pendingPenalty = nil
        hole.marks.append(mark)
        round.holes[index] = hole
        measurePoint = nil
        save()
        if lie == .unknown || lie == .water {
            editingMark = mark
        } else if lie == .green {
            showPutts = true
        }
    }

    private func movePin(id: String, to point: Coordinate) {
        guard let position = round.holes[index].marks.firstIndex(where: { $0.id.uuidString == id }) else { return }
        var mark = round.holes[index].marks[position]
        mark.coordinate = point
        mark.source = .touch
        mark.accuracy = nil
        if position > 0, let course = course {
            let lie = LieDetector.lie(at: point, course: course, hole: score.number)
            if lie != .unknown && lie != .tee { mark.lie = lie }
        }
        round.holes[index].marks[position] = mark
        save()
    }

    private func replace(_ mark: BallMark) {
        guard let position = round.holes[index].marks.firstIndex(where: { $0.id == mark.id }) else { return }
        round.holes[index].marks[position] = mark
        save()
        if mark.lie == .green && round.holes[index].putts.isEmpty {
            // Wait for the mark sheet to close before opening the putting sheet.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showPutts = true }
        }
    }

    private func remove(_ mark: BallMark) {
        round.holes[index].marks.removeAll { $0.id == mark.id }
        save()
    }

    private func setClub(_ name: String) {
        guard !round.holes[index].marks.isEmpty else { return }
        round.holes[index].marks[round.holes[index].marks.count - 1].club = name
        save()
    }

    private func addPenalty(_ kind: PenaltyKind) {
        switch kind {
        case .outOfBounds, .lostBall:
            // Stroke and distance: play again from the same spot.
            guard let last = round.holes[index].marks.last else {
                pendingPenalty = kind
                return
            }
            round.holes[index].marks.append(BallMark(coordinate: last.coordinate, lie: last.lie, source: last.source,
                                                     club: last.club, penaltyBefore: kind))
            save()
        case .water, .unplayable:
            pendingPenalty = kind
        }
    }

    private func undo() {
        guard !round.holes[index].marks.isEmpty else { return }
        round.holes[index].marks.removeLast()
        save()
    }

    private func clearHole() {
        round.holes[index].marks = []
        round.holes[index].putts = []
        round.holes[index].holedFromOffGreen = false
        round.holes[index].quick = nil
        pendingPenalty = nil
        save()
    }
}
