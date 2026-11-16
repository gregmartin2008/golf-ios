import CaddieCore
import SwiftUI

/// Change a mark's lie, club or penalty, or remove it.
struct MarkEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mark: BallMark
    let clubs: [String]
    let canDelete: Bool
    let onSave: (BallMark) -> Void
    let onDelete: () -> Void

    init(mark: BallMark, clubs: [String], canDelete: Bool, onSave: @escaping (BallMark) -> Void,
         onDelete: @escaping () -> Void) {
        _mark = State(initialValue: mark)
        self.clubs = clubs
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private let lies: [Lie] = [.tee, .fairway, .rough, .bunker, .fringe, .green, .recovery]

    var body: some View {
        NavigationStack {
            Form {
                Section("Where the ball is") {
                    Picker("Lie", selection: $mark.lie) {
                        ForEach(lies, id: \.self) { lie in
                            Text(lie.label).tag(lie)
                        }
                        if mark.lie == .unknown { Text("Not set").tag(Lie.unknown) }
                        if mark.lie == .water { Text("Water").tag(Lie.water) }
                    }
                    if mark.lie == .water {
                        Text("A ball in the water is not played from there. Mark where you dropped instead, and set the penalty below.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Club for the shot from here") {
                    Picker("Club", selection: clubBinding) {
                        Text("Not set").tag("")
                        ForEach(clubs, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
                Section("Penalty taken to get here") {
                    Picker("Penalty", selection: penaltyBinding) {
                        Text("None").tag("")
                        ForEach(PenaltyKind.allCases, id: \.self) { kind in
                            Text("\(kind.label) (+1)").tag(kind.rawValue)
                        }
                    }
                }
                if let accuracy = mark.accuracy {
                    Section {
                        Text("Placed by GPS, accurate to about \(Int(accuracy.rounded())) m. Drag the pin on the map to adjust it.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if canDelete {
                    Section {
                        Button("Remove this mark", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Mark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(mark)
                        dismiss()
                    }
                }
            }
        }
    }

    private var clubBinding: Binding<String> {
        Binding(get: { mark.club ?? "" }, set: { mark.club = $0.isEmpty ? nil : $0 })
    }

    private var penaltyBinding: Binding<String> {
        Binding(get: { mark.penaltyBefore?.rawValue ?? "" }, set: { mark.penaltyBefore = PenaltyKind(rawValue: $0) })
    }
}

/// Enter each putt's length, or say the ball went in from off the green.
struct PuttsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var feet: [Double]
    @State private var holedFromOff: Bool
    @State private var entry: Double
    let score: HoleScore
    let onSave: ([Putt], Bool) -> Void

    static let quickLengths: [Double] = [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30, 40, 50, 60]

    init(score: HoleScore, suggestedFeet: Double?, onSave: @escaping ([Putt], Bool) -> Void) {
        self.score = score
        self.onSave = onSave
        _feet = State(initialValue: score.putts.map { $0.feet })
        _holedFromOff = State(initialValue: score.holedFromOffGreen)
        _entry = State(initialValue: score.putts.isEmpty ? (suggestedFeet ?? 20) : 3)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if feet.isEmpty {
                        Text("No putts yet").foregroundStyle(.secondary)
                    }
                    ForEach(Array(feet.enumerated()), id: \.offset) { offset, length in
                        HStack {
                            Text(offset == feet.count - 1 ? "Putt \(offset + 1) (holed)" : "Putt \(offset + 1)")
                            Spacer()
                            Text(Format.feet(length)).monospacedDigit()
                        }
                    }
                    .onDelete { offsets in
                        feet.remove(atOffsets: offsets)
                    }
                } header: {
                    Text("Putts on hole \(score.number)")
                } footer: {
                    Text("Add every putt in order. The last one in the list is the one that went in.")
                }

                if !holedFromOff {
                    Section(feet.isEmpty ? "First putt" : "Next putt") {
                        Stepper(value: $entry, in: 1...150, step: 1) {
                            Text("Length: \(Format.feet(entry))").font(.headline)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                            ForEach(PuttsEditor.quickLengths, id: \.self) { length in
                                Button {
                                    entry = length
                                } label: {
                                    Text("\(Int(length))")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(entry == length ? Theme.green.opacity(0.25) : Color(.secondarySystemBackground),
                                                    in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Button {
                            feet.append(entry)
                            entry = min(entry, 3)
                        } label: {
                            Label("Add putt of \(Format.feet(entry))", systemImage: "plus.circle.fill")
                        }
                    }
                }

                if feet.isEmpty {
                    Section {
                        Toggle("Holed out from off the green", isOn: $holedFromOff)
                    } footer: {
                        Text("Turn this on when a chip, bunker shot or approach went in and there were no putts.")
                    }
                }
            }
            .navigationTitle("Putting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(feet.map { Putt(feet: $0) }, feet.isEmpty && holedFromOff)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Type a hole in without the map.
struct QuickEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var strokes: Int
    @State private var putts: Int
    @State private var teeResult: String
    @State private var penaltyStrokes: Int
    @State private var sandShots: Int
    @State private var chips: Int
    let score: HoleScore
    let onSave: (QuickEntry?) -> Void

    init(score: HoleScore, onSave: @escaping (QuickEntry?) -> Void) {
        self.score = score
        self.onSave = onSave
        let existing = score.quick
        _strokes = State(initialValue: existing?.strokes ?? score.strokes ?? score.par)
        _putts = State(initialValue: existing?.putts ?? (score.putts.isEmpty ? 2 : score.putts.count))
        _teeResult = State(initialValue: existing?.teeResult?.rawValue ?? "")
        _penaltyStrokes = State(initialValue: existing?.penaltyStrokes ?? 0)
        _sandShots = State(initialValue: existing?.sandShots ?? 0)
        _chips = State(initialValue: existing?.chips ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Score: \(strokes)  (\(Format.scoreName(strokes: strokes, par: score.par)))", value: $strokes, in: 1...15)
                    Stepper("Putts: \(putts)", value: $putts, in: 0...6)
                } header: {
                    Text("Hole \(score.number), par \(score.par)")
                }
                if score.par >= 4 {
                    Section("Tee shot") {
                        Picker("Tee shot", selection: $teeResult) {
                            Text("Not set").tag("")
                            ForEach(TeeResult.allCases, id: \.self) { result in
                                Text(result.label).tag(result.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                Section("Other") {
                    Stepper("Penalty strokes: \(penaltyStrokes)", value: $penaltyStrokes, in: 0...6)
                    Stepper("Chips and pitches: \(chips)", value: $chips, in: 0...6)
                    Stepper("Bunker shots: \(sandShots)", value: $sandShots, in: 0...6)
                }
                if score.quick != nil {
                    Section {
                        Button("Remove quick score", role: .destructive) {
                            onSave(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Quick score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let entry = QuickEntry(strokes: strokes, putts: min(putts, strokes),
                                               teeResult: TeeResult(rawValue: teeResult), penaltyStrokes: penaltyStrokes,
                                               sandShots: sandShots, chips: chips)
                        onSave(entry)
                        dismiss()
                    }
                }
            }
        }
    }
}
