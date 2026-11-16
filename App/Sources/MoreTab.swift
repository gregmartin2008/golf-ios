import CaddieCore
import SwiftUI
import UniformTypeIdentifiers

struct MoreTab: View {
    @EnvironmentObject var model: AppModel
    @State private var importing = false
    @State private var backupURL: URL?
    @State private var manualIndex = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        HandicapView()
                    } label: {
                        StatRow(label: "Handicap", value: Format.index(model.handicapIndex))
                    }
                    NavigationLink {
                        GHINView()
                    } label: {
                        StatRow(label: "GHIN", value: model.ghinAccount == nil ? "Not connected" : "Connected")
                    }
                    NavigationLink("Clubs in the bag") {
                        BagView()
                    }
                }
                Section {
                    Toggle("Show distances in meters", isOn: Binding(
                        get: { model.settings.useMeters },
                        set: { value in
                            model.settings.useMeters = value
                            model.saveSettings()
                        }))
                    HStack {
                        Text("Handicap Index, if not using GHIN")
                        Spacer()
                        TextField("none", text: $manualIndex)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            .onSubmit { saveManualIndex() }
                            .onChange(of: manualIndex) { _, _ in saveManualIndex() }
                    }
                } header: {
                    Text("Settings")
                }
                Section {
                    if let url = backupURL {
                        ShareLink(item: url) {
                            Label("Save or send the backup file", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            backupURL = model.backupFile()
                            if backupURL == nil { model.notice = "The backup could not be written." }
                        } label: {
                            Label("Make a backup file", systemImage: "externaldrive")
                        }
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("Restore from a backup file", systemImage: "arrow.down.doc")
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Everything is kept on this iPhone only. A backup file holds your courses, rounds and bag; save one to Files or email it to yourself now and then. Restoring replaces what is in the app.")
                }
                Section {
                    Text("Course maps © OpenStreetMap contributors, used under the Open Database License. Strokes gained uses the PGA Tour baseline published by Mark Broadie. Caddie's GHIN connection is unofficial and is not endorsed by the USGA.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("More")
            .onAppear {
                if let value = model.settings.manualIndex { manualIndex = String(format: "%.1f", value) }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { model.restore(from: url) }
            }
        }
    }

    private func saveManualIndex() {
        let trimmed = manualIndex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let value = Double(trimmed)
        if value != model.settings.manualIndex {
            model.settings.manualIndex = value
            model.saveSettings()
        }
    }
}

/// The index and the rounds behind it.
struct HandicapView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let report = model.handicapReport
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Format.index(model.handicapIndex)).font(.system(size: 52, weight: .bold)).monospacedDigit()
                    Text(model.handicapSource).font(.footnote).foregroundStyle(.secondary)
                }
                if let low = model.ghinAccount?.lowIndex {
                    StatRow(label: "Low index (GHIN)", value: Format.index(low))
                }
                StatRow(label: "Caddie's own estimate", value: Format.index(report.index),
                        detail: report.entries.isEmpty ? "" : "from \(report.entries.count) scores")
            } footer: {
                Text("The estimate uses the World Handicap System: the lowest 8 of the last 20 score differentials, fewer when there are fewer rounds. It leaves out the daily course-conditions adjustment and the caps GHIN applies, so it can differ slightly. Only GHIN's number is official.")
            }
            if report.entries.isEmpty {
                Section {
                    Text("Finish three 18-hole rounds, or connect GHIN to bring in your score history.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Last \(report.entries.count) scores") {
                    ForEach(report.entries) { entry in
                        HStack {
                            Image(systemName: entry.counts ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(entry.counts ? Theme.green : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.courseName).lineLimit(1)
                                Text(Format.day(entry.date) + (entry.fromGHIN ? " · GHIN" : "")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(entry.score)").monospacedDigit().foregroundStyle(.secondary)
                            Text(Format.one(entry.differential)).fontWeight(.semibold).monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .navigationTitle("Handicap")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Sign in to GHIN, see what it holds, and refresh.
struct GHINView: View {
    @EnvironmentObject var model: AppModel
    @State private var login = ""
    @State private var password = ""
    @State private var number = ""

    var body: some View {
        Form {
            if let account = model.ghinAccount {
                Section("Connected") {
                    if let name = account.name { StatRow(label: "Golfer", value: name) }
                    if let value = account.ghinNumber { StatRow(label: "GHIN number", value: String(value)) }
                    if let club = account.clubName { StatRow(label: "Club", value: club) }
                    StatRow(label: "Handicap Index", value: Format.index(account.handicapIndex))
                    StatRow(label: "Low index", value: Format.index(account.lowIndex))
                    StatRow(label: "Scores read from GHIN", value: "\(model.rounds.filter { $0.source == .ghin }.count)")
                    if let date = account.lastSync { StatRow(label: "Last refreshed", value: Format.day(date)) }
                }
                Section {
                    Button("Refresh from GHIN") {
                        Task { await model.ghinRefresh() }
                    }
                    Button("Sign out", role: .destructive) {
                        model.ghinSignOut()
                    }
                }
            } else {
                Section {
                    TextField("Email or GHIN number", text: $login)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    SecureField("GHIN password", text: $password)
                    TextField("GHIN number (if you sign in with email)", text: $number)
                        .keyboardType(.numberPad)
                    Button("Sign in") {
                        Task {
                            await model.ghinSignIn(login: login.trimmingCharacters(in: .whitespaces), password: password,
                                                   ghinNumber: Int(number.trimmingCharacters(in: .whitespaces)))
                            password = ""
                        }
                    }
                    .disabled(login.count < 3 || password.isEmpty)
                } header: {
                    Text("Sign in with your GHIN account")
                } footer: {
                    Text("The same email (or GHIN number) and password you use in the GHIN app. The password is kept in this iPhone's Keychain and sent only to GHIN.")
                }
            }
            Section {
                Text("What this does: reads your Handicap Index and score history, brings in official tees, ratings and yardages for a course, and can post a finished round after you confirm it.")
                Text("What to know: this is not an official USGA connection. It uses the same service the GHIN website uses, signed in as you. GHIN can change that service at any time, which would stop this working until Caddie is updated. Posting has not been proven until your first score goes through; check it in the GHIN app afterwards.")
            } header: {
                Text("About this connection")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("GHIN")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Which clubs are offered when marking a shot.
struct BagView: View {
    @EnvironmentObject var model: AppModel
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                ForEach(model.bag) { club in
                    Toggle(club.name, isOn: Binding(
                        get: { club.inBag },
                        set: { value in
                            var bag = model.bag
                            if let position = bag.firstIndex(where: { $0.id == club.id }) {
                                bag[position].inBag = value
                                model.save(bag: bag)
                            }
                        }))
                }
                .onDelete { offsets in
                    var bag = model.bag
                    bag.remove(atOffsets: offsets)
                    model.save(bag: bag)
                }
                .onMove { source, destination in
                    var bag = model.bag
                    bag.move(fromOffsets: source, toOffset: destination)
                    model.save(bag: bag)
                }
            } footer: {
                Text("Clubs switched on are offered when you mark a shot. Swipe to remove one; use Edit to reorder.")
            }
            Section("Add a club") {
                TextField("Name, for example 7 Wood", text: $newName)
                Button("Add") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    model.save(bag: model.bag + [Club(name: name)])
                    newName = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Bag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }
}
