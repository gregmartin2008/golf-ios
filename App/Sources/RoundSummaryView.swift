import CaddieCore
import SwiftUI

/// The scorecard and statistics of one round, with finishing and posting to GHIN.
struct RoundSummaryView: View {
    @EnvironmentObject var model: AppModel
    let roundID: UUID
    var onGoToHole: ((Int) -> Void)?
    var onFinished: (() -> Void)?

    @State private var postPreview: GHINPost?
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    private var round: Round? { model.round(roundID) }

    var body: some View {
        Group {
            if let round = round {
                content(round)
            } else {
                Text("This round is no longer here.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Scorecard")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ round: Round) -> some View {
        let course = model.course(round.courseID)
        List {
            Section {
                headline(round)
            }
            if !round.holes.isEmpty {
                Section("Card") {
                    ScorecardGrid(round: round, onSelect: onGoToHole)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
                statsSection(round, course: course)
                gainedSection(round, course: course)
            }
            actionsSection(round)
        }
        .sheet(item: $postPreview) { post in
            PostConfirmation(post: post, round: round) {
                Task { await model.ghinSend(post, for: round) }
            }
        }
        .confirmationDialog("Delete this round?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete round", role: .destructive) {
                model.delete(round: round)
                onFinished?()
                dismiss()
            }
        }
    }

    private func headline(_ round: Round) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(round.courseName).font(.headline)
            Text(subtitle(round)).font(.footnote).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let total = round.total {
                    Text("\(total)").font(.system(size: 44, weight: .bold)).monospacedDigit()
                    if round.imported == nil {
                        Text(Format.toPar(total - round.par)).font(.title2).foregroundStyle(.secondary)
                    }
                } else {
                    Text("\(round.grossSoFar)").font(.system(size: 44, weight: .bold)).monospacedDigit()
                    Text("\(Format.toPar(round.grossSoFar - round.parSoFar)) thru \(round.completedHoles.count)")
                        .font(.title3).foregroundStyle(.secondary)
                }
                Spacer()
                if let differential = Handicap.differential(for: round) {
                    VStack(alignment: .trailing) {
                        Text(Format.one(differential)).font(.title3.weight(.semibold))
                        Text("Differential").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if round.source == .ghin {
                Text("Read from GHIN. Totals only; shots and statistics are not available for this round.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func postedLabel(_ round: Round) -> String {
        if let date = round.ghin.postedAt { return "Posted to GHIN " + Format.day(date) }
        return "Posted to GHIN"
    }

    private func subtitle(_ round: Round) -> String {
        var parts = [Format.day(round.date)]
        if !round.teeName.isEmpty { parts.append("\(round.teeName) tees") }
        parts.append("\(Format.one(round.rating)) / \(round.slope)")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func statsSection(_ round: Round, course: Course?) -> some View {
        let report = Stats.report(rounds: [round], courses: course.map { [$0] } ?? [])
        if report.holes > 0 {
            Section("This round") {
                StatRow(label: "Fairways hit", value: Format.percent(report.fairways), detail: Format.ratio(report.fairways))
                StatRow(label: "Greens in regulation", value: Format.percent(report.greens), detail: Format.ratio(report.greens))
                StatRow(label: "Putts", value: "\(round.completedHoles.reduce(0) { $0 + $1.puttCount })")
                StatRow(label: "Three-putts", value: "\(report.threePutts.made)")
                StatRow(label: "Scrambling", value: Format.percent(report.scrambling), detail: Format.ratio(report.scrambling))
                StatRow(label: "Sand saves", value: Format.percent(report.sandSaves), detail: Format.ratio(report.sandSaves))
                StatRow(label: "Penalty strokes", value: "\(report.penaltyStrokes)")
            }
        }
    }

    @ViewBuilder
    private func gainedSection(_ round: Round, course: Course?) -> some View {
        let gained = StrokesGained.totals(for: round, course: course)
        if gained.measuredStrokes > 0 {
            Section {
                ForEach(StrokesGained.Category.allCases, id: \.self) { category in
                    StatRow(label: category.label, value: Format.gained(gained.value(category)))
                }
                StatRow(label: "Total", value: Format.gained(gained.total))
            } header: {
                Text("Strokes gained")
            } footer: {
                Text("Against the PGA Tour baseline, so most numbers are negative. What matters is which part of the game loses the most.")
            }
        }
    }

    @ViewBuilder
    private func actionsSection(_ round: Round) -> some View {
        Section {
            if round.status == .inProgress {
                Button {
                    var finished = round
                    finished.status = .finished
                    model.save(round: finished)
                    onFinished?()
                } label: {
                    Label(round.isFullyScored ? "Finish round" : "Finish round with holes missing", systemImage: "checkmark.circle.fill")
                }
            } else if round.source == .app {
                if round.ghin.isPosted {
                    Label(postedLabel(round), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        switch model.ghinPost(for: round) {
                        case .success(let post): postPreview = post
                        case .failure(let problem): model.notice = problem.message
                        }
                    } label: {
                        Label("Post to GHIN…", systemImage: "arrow.up.circle")
                    }
                }
                Toggle("Practice round (leave out of statistics)", isOn: Binding(
                    get: { round.isPractice },
                    set: { value in
                        var changed = round
                        changed.isPractice = value
                        model.save(round: changed)
                    }))
                Button {
                    var reopened = round
                    reopened.status = .inProgress
                    model.save(round: reopened)
                } label: {
                    Label("Reopen to edit", systemImage: "pencil")
                }
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete round", systemImage: "trash")
            }
        }
    }
}

/// Shows exactly what will be sent to GHIN and asks for a clear yes.
struct PostConfirmation: View {
    @Environment(\.dismiss) private var dismiss
    let post: GHINPost
    let round: Round
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StatRow(label: "Course", value: round.courseName)
                    StatRow(label: "Tees", value: round.teeName)
                    StatRow(label: "Date played", value: Format.day(post.playedAt))
                    StatRow(label: "Holes", value: "\(post.holeCount)")
                    StatRow(label: "Gross score", value: "\(post.total)")
                } header: {
                    Text("This will be posted to your GHIN record")
                } footer: {
                    Text("GHIN applies its own adjustments to each hole. Once posted, a score can only be changed or removed by your club. Caddie's connection to GHIN is unofficial.")
                }
                Section("Hole by hole") {
                    ForEach(post.holes, id: \.number) { hole in
                        StatRow(label: "Hole \(hole.number)", value: "\(hole.strokes)")
                    }
                }
                Section {
                    Button {
                        onConfirm()
                        dismiss()
                    } label: {
                        Text("Post this score to GHIN").fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Post to GHIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// The card: two rows of nine with par and score.
struct ScorecardGrid: View {
    let round: Round
    var onSelect: ((Int) -> Void)?

    var body: some View {
        let halves = stride(from: 0, to: round.holes.count, by: 9).map { start in
            Array(round.holes[start..<min(start + 9, round.holes.count)])
        }
        VStack(spacing: 10) {
            ForEach(Array(halves.enumerated()), id: \.offset) { _, nine in
                half(nine)
            }
        }
    }

    private func half(_ holes: [HoleScore]) -> some View {
        let done = holes.filter { $0.isComplete }
        return VStack(spacing: 2) {
            row(label: "Hole", cells: holes.map { "\($0.number)" }, total: "", weight: .regular, color: .secondary)
            row(label: "Par", cells: holes.map { "\($0.par)" }, total: "\(holes.reduce(0) { $0 + $1.par })", weight: .regular,
                color: .secondary)
            HStack(spacing: 0) {
                Text("Score").font(.caption).frame(width: 40, alignment: .leading)
                ForEach(holes) { hole in
                    Button {
                        onSelect?(hole.number)
                    } label: {
                        Text(hole.strokes.map { "\($0)" } ?? "·")
                            .font(.callout.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(hole.strokes.map { Theme.color(toPar: $0 - hole.par) } ?? .secondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(onSelect == nil)
                }
                Text(done.isEmpty ? "" : "\(done.reduce(0) { $0 + ($1.strokes ?? 0) })")
                    .font(.callout.weight(.bold)).monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
            row(label: "Putts", cells: holes.map { $0.isComplete ? "\($0.puttCount)" : "" },
                total: done.isEmpty ? "" : "\(done.reduce(0) { $0 + $1.puttCount })", weight: .regular, color: .secondary)
        }
    }

    private func row(label: String, cells: [String], total: String, weight: Font.Weight, color: Color) -> some View {
        HStack(spacing: 0) {
            Text(label).font(.caption).frame(width: 40, alignment: .leading)
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell).font(.caption.weight(weight)).monospacedDigit().frame(maxWidth: .infinity)
            }
            Text(total).font(.caption.weight(.semibold)).monospacedDigit().frame(width: 34, alignment: .trailing)
        }
        .foregroundStyle(color)
    }
}
