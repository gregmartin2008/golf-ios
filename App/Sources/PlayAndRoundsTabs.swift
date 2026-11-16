import CaddieCore
import SwiftUI

/// Start a round or go back to the one in progress.
struct PlayTab: View {
    @EnvironmentObject var model: AppModel
    @State private var path: [UUID] = []
    @State private var courseID: UUID?
    @State private var teeID: UUID?
    @State private var holeCount = 18
    @State private var startHole = 1

    private var chosenCourse: Course? {
        model.course(courseID) ?? model.courses.first
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    handicapCard
                }
                if let active = model.activeRound {
                    Section("Round in progress") {
                        Button {
                            path = [active.id]
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Resume at \(active.courseName)").font(.headline)
                                Text("\(Format.toPar(active.grossSoFar - active.parSoFar)) thru \(active.completedHoles.count) of \(active.holes.count)")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if model.courses.isEmpty {
                    Section {
                        Text("Add a course in the Courses tab to start a round.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    newRoundSection
                }
            }
            .navigationTitle("Caddie")
            .navigationDestination(for: UUID.self) { id in
                if let round = model.round(id), !round.holes.isEmpty {
                    HoleScreen(round: round)
                } else {
                    Text("This round is no longer here.")
                }
            }
        }
    }

    private var handicapCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Handicap Index").font(.footnote).foregroundStyle(.secondary)
                Text(Format.index(model.handicapIndex)).font(.system(size: 40, weight: .bold)).monospacedDigit()
                Text(model.handicapSource).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let last = model.roundsNewestFirst.first(where: { $0.status == .finished }), let total = last.total {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Last round").font(.footnote).foregroundStyle(.secondary)
                    Text("\(total)").font(.title.weight(.semibold)).monospacedDigit()
                    Text(last.courseName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var newRoundSection: some View {
        Section("New round") {
            Picker("Course", selection: courseBinding) {
                ForEach(model.courses) { course in
                    Text(course.name).tag(course.id)
                }
            }
            if let course = chosenCourse {
                if course.tees.isEmpty {
                    Text("No tees set up for this course, so rounds will not count toward a handicap. Add tees under Courses.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Picker("Tees", selection: teeBinding(course)) {
                        ForEach(course.tees) { tee in
                            Text(teeLabel(tee)).tag(tee.id)
                        }
                    }
                }
                Picker("Holes", selection: $holeCount) {
                    Text("18").tag(18)
                    Text("9").tag(9)
                }
                .pickerStyle(.segmented)
                Picker("Start on", selection: $startHole) {
                    ForEach(course.holes) { hole in
                        Text("Hole \(hole.number)").tag(hole.number)
                    }
                }
                if let tee = chosenTee(course), let index = model.handicapIndex {
                    StatRow(label: "Course Handicap",
                            value: "\(Handicap.courseHandicap(index: index, slope: tee.slope, rating: tee.rating, par: tee.par))")
                }
                Button {
                    let round = model.startRound(course: course, tee: chosenTee(course),
                                                 holeCount: min(holeCount, course.holes.count), startHole: startHole)
                    path = [round.id]
                } label: {
                    Text("Start round").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
    }

    private func teeLabel(_ tee: TeeSet) -> String {
        var text = tee.name
        if tee.totalYards > 0 { text += " · \(tee.totalYards) yd" }
        text += " · \(Format.one(tee.rating))/\(tee.slope)"
        return text
    }

    private func chosenTee(_ course: Course) -> TeeSet? {
        course.tees.first { $0.id == teeID } ?? course.tees.first
    }

    private var courseBinding: Binding<UUID> {
        Binding(get: { chosenCourse?.id ?? UUID() }, set: { value in
            courseID = value
            teeID = nil
            startHole = 1
        })
    }

    private func teeBinding(_ course: Course) -> Binding<UUID> {
        Binding(get: { chosenTee(course)?.id ?? UUID() }, set: { teeID = $0 })
    }
}

/// Every round, newest first.
struct RoundsTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if model.rounds.isEmpty {
                    Text("Rounds you play, and scores read from GHIN, appear here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.roundsNewestFirst) { round in
                    NavigationLink {
                        RoundDetailView(roundID: round.id)
                    } label: {
                        row(round)
                    }
                }
                .onDelete { offsets in
                    let list = model.roundsNewestFirst
                    for offset in offsets { model.delete(round: list[offset]) }
                }
            }
            .navigationTitle("Rounds")
        }
    }

    private func row(_ round: Round) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(round.courseName).font(.body.weight(.medium)).lineLimit(1)
                Text(detail(round)).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let total = round.total {
                    Text("\(total)").font(.title3.weight(.semibold)).monospacedDigit()
                } else {
                    Text("\(round.grossSoFar)").font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                }
                if let differential = Handicap.differential(for: round) {
                    Text(Format.one(differential)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func detail(_ round: Round) -> String {
        var parts = [Format.day(round.date)]
        if round.status == .inProgress { parts.append("in progress, thru \(round.completedHoles.count)") }
        if round.source == .ghin { parts.append("from GHIN") }
        if round.ghin.isPosted { parts.append("posted") }
        if round.isPractice { parts.append("practice") }
        if round.source == .app && round.status == .finished && round.holes.count < 18 { parts.append("\(round.holes.count) holes") }
        return parts.joined(separator: " · ")
    }
}

/// A finished round: its card, and each hole on the map.
struct RoundDetailView: View {
    @EnvironmentObject var model: AppModel
    let roundID: UUID
    @State private var replayHole: Int?
    @State private var editing = false

    var body: some View {
        RoundSummaryView(roundID: roundID, onGoToHole: { number in
            replayHole = number
        }, onFinished: nil)
        .toolbar {
            if let round = model.round(roundID), round.source == .app, round.status == .inProgress {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Continue") { editing = true }
                }
            }
        }
        .navigationDestination(isPresented: $editing) {
            if let round = model.round(roundID), !round.holes.isEmpty {
                HoleScreen(round: round)
            }
        }
        .sheet(item: replayBinding) { item in
            if let round = model.round(roundID) {
                HoleReplay(round: round, holeNumber: item.number)
            }
        }
    }

    private struct ReplayItem: Identifiable {
        let number: Int
        var id: Int { number }
    }

    private var replayBinding: Binding<ReplayItem?> {
        Binding(get: { replayHole.map { ReplayItem(number: $0) } }, set: { replayHole = $0?.number })
    }
}

/// One hole of a past round drawn on the map with each shot's club and distance.
struct HoleReplay: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let round: Round
    let holeNumber: Int

    var body: some View {
        let score = round.holes.first { $0.number == holeNumber }
        let course = model.course(round.courseID)
        let hole = course?.hole(holeNumber)
        NavigationStack {
            VStack(spacing: 0) {
                if let score = score {
                    HoleMapView(hole: hole, features: course?.features ?? [], pins: pins(score, hole: hole),
                                path: score.marks.map { $0.coordinate }, measure: [],
                                fallbackCenter: course?.location ?? Coordinate(lat: 39.5, lon: -98.35), showsUser: false,
                                frameToken: holeNumber)
                    List {
                        if let summary = HoleAnalyzer.summary(for: score, hole: hole) {
                            Section {
                                StatRow(label: "Score", value: "\(summary.strokes)", detail: Format.scoreName(strokes: summary.strokes, par: summary.par))
                                ForEach(Array(summary.strokesList.enumerated()), id: \.offset) { _, stroke in
                                    StatRow(label: strokeLabel(stroke), value: strokeValue(stroke))
                                }
                                if !summary.puttFeet.isEmpty {
                                    StatRow(label: "Putts", value: summary.puttFeet.map { Format.feet($0) }.joined(separator: ", "))
                                } else if summary.isQuick {
                                    StatRow(label: "Putts", value: "\(summary.putts)")
                                }
                            }
                        } else {
                            Text("This hole was not finished.").foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxHeight: 280)
                }
            }
            .navigationTitle("Hole \(holeNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func strokeLabel(_ stroke: Stroke) -> String {
        var text = "Shot \(stroke.number): \(stroke.startLie.label)"
        if let club = stroke.club { text += ", \(club)" }
        return text
    }

    private func strokeValue(_ stroke: Stroke) -> String {
        if let penalty = stroke.penalty { return "\(penalty.label) (+1)" }
        if stroke.holed { return "Holed" }
        if let yards = stroke.yards {
            return "\(Format.distance(yards: yards, meters: model.settings.useMeters)) \(Format.unit(model.settings.useMeters))"
        }
        return "–"
    }

    private func pins(_ score: HoleScore, hole: Hole?) -> [MapPin] {
        var result: [MapPin] = []
        if let green = hole?.greenCenter { result.append(MapPin(id: "flag", coordinate: green, kind: .flag)) }
        var number = 0
        for mark in score.marks {
            number += 1 + (mark.penaltyBefore?.strokes ?? 0)
            result.append(MapPin(id: mark.id.uuidString, coordinate: mark.coordinate,
                                 kind: .mark(number: number, lie: mark.lie, penalty: mark.penaltyBefore != nil)))
        }
        return result
    }
}
