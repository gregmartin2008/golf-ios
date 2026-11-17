import CaddieCore
import MapKit
import SwiftUI

struct CoursesTab: View {
    @EnvironmentObject var model: AppModel
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                if model.courses.isEmpty {
                    Text("No courses yet. Tap + to find one. Caddie draws it from OpenStreetMap, the free map that volunteers keep up.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.courses) { course in
                    NavigationLink {
                        CourseDetailView(courseID: course.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name).font(.body.weight(.medium))
                            Text(subtitle(course)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Courses")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        adding = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add a course")
                }
            }
            .sheet(isPresented: $adding) {
                AddCourseView()
            }
        }
    }

    private func subtitle(_ course: Course) -> String {
        var parts: [String] = []
        let place = [course.city, course.state].filter { !$0.isEmpty }.joined(separator: ", ")
        if !place.isEmpty { parts.append(place) }
        parts.append("par \(course.par)")
        let mapped = course.holes.filter { $0.isMapped }.count
        parts.append("\(mapped) of \(course.holes.count) holes on the map")
        return parts.joined(separator: " · ")
    }
}

/// A place found by the search, before its course map is loaded.
struct FoundPlace: Identifiable {
    let id = UUID()
    var name: String
    var city: String
    var state: String
    var coordinate: Coordinate
}

/// Find a course by name or near the phone, then load its map.
struct AddCourseView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var location = LocationService()
    @State private var text = ""
    @State private var places: [FoundPlace] = []
    @State private var working = false
    @State private var message = ""
    @State private var result: Course?
    @State private var coverage: Coverage?

    var body: some View {
        NavigationStack {
            Form {
                if let course = result, let coverage = coverage {
                    found(course, coverage)
                } else {
                    search
                }
            }
            .navigationTitle("Add a course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { location.start() }
            .onDisappear { location.stop() }
        }
    }

    @ViewBuilder
    private var search: some View {
        Section {
            TextField("Course name and town", text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await runSearch() } }
            Button("Search") { Task { await runSearch() } }
                .disabled(text.trimmingCharacters(in: .whitespaces).count < 3 || working)
            Button("Courses near me") { Task { await nearMe() } }
                .disabled(location.coordinate == nil || working)
        } footer: {
            Text(message)
        }
        if working {
            Section {
                HStack {
                    ProgressView()
                    Text("Working…").foregroundStyle(.secondary)
                }
            }
        }
        if !places.isEmpty {
            Section("Results") {
                ForEach(places) { place in
                    Button {
                        Task { await load(place) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).foregroundStyle(.primary)
                            Text([place.city, place.state].filter { !$0.isEmpty }.joined(separator: ", "))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(working)
                }
            }
        }
        Section {
            Button("Add a course without a map") {
                let name = text.trimmingCharacters(in: .whitespaces)
                let center = location.coordinate ?? Coordinate(lat: 39.5, lon: -98.35)
                model.save(course: Course.blank(name: name.isEmpty ? "My course" : name, location: center))
                dismiss()
            }
        } footer: {
            Text("Use this when the search finds nothing. You can score rounds straight away and place tees and greens on the map later.")
        }
    }

    @ViewBuilder
    private func found(_ course: Course, _ coverage: Coverage) -> some View {
        Section {
            Text(course.name).font(.headline)
            StatRow(label: "Holes on the map", value: "\(coverage.holesFound) of \(course.holes.count)")
            StatRow(label: "Greens", value: "\(coverage.greens)")
            StatRow(label: "Fairways", value: "\(coverage.fairways)")
            StatRow(label: "Bunkers", value: "\(coverage.bunkers)")
            StatRow(label: "Water", value: "\(coverage.water)")
        } header: {
            Text("What the map has")
        } footer: {
            Text(coverageAdvice(course, coverage))
        }
        Section {
            Button {
                model.save(course: course)
                dismiss()
            } label: {
                Text("Add this course").fontWeight(.semibold).frame(maxWidth: .infinity)
            }
            Button("Back to search") {
                result = nil
                self.coverage = nil
            }
        }
    }

    private func coverageAdvice(_ course: Course, _ coverage: Coverage) -> String {
        if coverage.hasShapesButNoHoles {
            return "The map has this course's greens, fairways and bunkers but not which hole is which. Add it, then under Edit hole positions press each hole's tee and green once. The shapes are then used for yardages and lies."
        }
        if coverage.holesFound == 0 {
            return "The map has no holes for this course. You can still add it and place each tee and green yourself, which takes a few minutes."
        }
        if coverage.holesFound < course.holes.count {
            return "Some holes are missing. Add the course, then place the missing tees and greens under Edit hole positions."
        }
        if coverage.fairways == 0 {
            return "Holes and greens are mapped but fairways are not, so Caddie will ask whether each shot found the fairway."
        }
        return "This course is well mapped. Yardages, lies and fairways hit will be worked out for you."
    }

    private func runSearch() async {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard query.count >= 3 else { return }
        working = true
        message = ""
        defer { working = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query.lowercased().contains("golf") || query.lowercased().contains("club") ? query : query + " golf"
        request.resultTypes = .pointOfInterest
        if let here = location.coordinate {
            request.region = MKCoordinateRegion(center: here.clLocation, latitudinalMeters: 300_000, longitudinalMeters: 300_000)
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            places = response.mapItems.prefix(12).map { item in
                FoundPlace(name: item.name ?? query, city: item.placemark.locality ?? "",
                           state: item.placemark.administrativeArea ?? "", coordinate: Coordinate(item.placemark.coordinate))
            }
            if places.isEmpty { message = "Nothing found. Try adding the town, or add the course without a map." }
        } catch {
            places = []
            message = "Nothing found. Try adding the town, or add the course without a map."
        }
    }

    private func nearMe() async {
        guard let here = location.coordinate else { return }
        working = true
        message = ""
        defer { working = false }
        do {
            let data = try await OverpassClient().fetchOutlines(near: here, radiusMeters: 15_000)
            places = OSMImport.candidates(from: data, near: here).prefix(15).map {
                FoundPlace(name: $0.name, city: "", state: "", coordinate: $0.center)
            }
            if places.isEmpty { message = "The map shows no golf courses within about nine miles." }
        } catch {
            message = "The map service could not be reached. Check the connection and try again."
        }
    }

    private func load(_ place: FoundPlace) async {
        working = true
        message = ""
        defer { working = false }
        do {
            let data = try await OverpassClient().fetch(near: place.coordinate)
            let made = OSMImport.course(from: data, near: place.coordinate, fallbackName: place.name)
            var course = made.course
            course.city = place.city
            course.state = place.state
            result = course
            coverage = made.coverage
        } catch {
            message = "The map service could not be reached. Check the connection and try again."
        }
    }
}

/// One course: its scorecard, tees, map coverage and its link to GHIN.
struct CourseDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let courseID: UUID
    @State private var linking = false
    @State private var confirmDelete = false
    @State private var refreshing = false

    var body: some View {
        if let course = model.course(courseID) {
            content(course)
        } else {
            Text("This course is no longer here.").foregroundStyle(.secondary)
        }
    }

    private func binding(_ course: Course) -> Binding<Course> {
        Binding(get: { model.course(courseID) ?? course }, set: { model.save(course: $0) })
    }

    private func content(_ course: Course) -> some View {
        let live = binding(course)
        let coverage = Coverage.of(course)
        return Form {
            Section("Course") {
                TextField("Name", text: live.name)
                TextField("City", text: live.city)
                TextField("State", text: live.state)
                    .textInputAutocapitalization(.characters)
            }
            Section {
                StatRow(label: "Holes on the map", value: "\(coverage.holesFound) of \(course.holes.count)")
                StatRow(label: "Greens / fairways / bunkers / water",
                        value: "\(coverage.greens) / \(coverage.fairways) / \(coverage.bunkers) / \(coverage.water)")
                Picker("Holes", selection: Binding(get: { course.holes.count <= 9 ? 9 : 18 }, set: { value in
                    var changed = course
                    changed.resizeHoles(to: value)
                    model.save(course: changed)
                })) {
                    Text("9 holes").tag(9)
                    Text("18 holes").tag(18)
                }
                NavigationLink("Edit hole positions") {
                    HoleEditorView(courseID: courseID)
                }
                Button(refreshing ? "Loading the map…" : "Load the map again") {
                    Task { await reload(course) }
                }
                .disabled(refreshing)
            } header: {
                Text("Map")
            } footer: {
                Text("The map comes from OpenStreetMap contributors. Loading it again picks up improvements made there and keeps your tees, pars and positions you set by hand.")
            }
            Section {
                if course.tees.isEmpty {
                    Text("No tees yet. Link to GHIN to bring in the official tees, ratings and yardages, or add one by hand.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(course.tees) { tee in
                    NavigationLink {
                        TeeEditor(courseID: courseID, teeID: tee.id)
                    } label: {
                        StatRow(label: tee.name, value: "\(Format.one(tee.rating)) / \(tee.slope)",
                                detail: tee.totalYards > 0 ? "\(tee.totalYards) yd" : "")
                    }
                }
                .onDelete { offsets in
                    var changed = course
                    changed.tees.remove(atOffsets: offsets)
                    model.save(course: changed)
                }
                Button("Add a tee by hand") {
                    var changed = course
                    changed.tees.append(TeeSet(name: "Tee \(course.tees.count + 1)", rating: Double(course.par), slope: 113,
                                               par: course.par, yards: Array(repeating: 0, count: course.holes.count)))
                    model.save(course: changed)
                }
                Button(course.ghinCourseID == nil ? "Link to GHIN…" : "Refresh from GHIN…") {
                    linking = true
                }
            } header: {
                Text("Tees")
            } footer: {
                Text(course.ghinCourseID == nil ? "Not linked to GHIN. Rounds here cannot be posted until it is." : "Linked to GHIN course \(course.ghinCourseID ?? 0).")
            }
            Section("Holes") {
                ForEach(course.holes) { hole in
                    HoleRow(courseID: courseID, number: hole.number)
                }
            }
            Section {
                Button("Delete course", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $linking) {
            GHINLinkView(course: course)
        }
        .confirmationDialog("Delete this course? Rounds played on it are kept.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete course", role: .destructive) {
                model.delete(course: course)
                dismiss()
            }
        }
    }

    private func reload(_ course: Course) async {
        refreshing = true
        defer { refreshing = false }
        do {
            let data = try await OverpassClient().fetch(near: course.location, candidateID: course.osmID)
            let fresh = OSMImport.course(from: data, near: course.location, candidateID: course.osmID, fallbackName: course.name).course
            var merged = course
            merged.features = fresh.features
            merged.boundary = fresh.boundary
            if merged.osmID == nil { merged.osmID = fresh.osmID }
            if fresh.holes.count > merged.holes.count { merged.resizeHoles(to: fresh.holes.count) }
            for index in 0..<merged.holes.count {
                guard let found = fresh.hole(merged.holes[index].number), found.isMapped else { continue }
                // Keep par and stroke index; take positions from the map.
                merged.holes[index].tee = found.tee
                merged.holes[index].greenCenter = found.greenCenter
                merged.holes[index].greenFront = found.greenFront
                merged.holes[index].greenBack = found.greenBack
                merged.holes[index].line = found.line
            }
            model.save(course: merged)
            model.notice = "Map loaded: " + Coverage.of(merged).summary + "."
        } catch {
            model.notice = "The map service could not be reached. Check the connection and try again."
        }
    }
}

/// Par and stroke index for one hole.
struct HoleRow: View {
    @EnvironmentObject var model: AppModel
    let courseID: UUID
    let number: Int

    var body: some View {
        if let course = model.course(courseID), let hole = course.hole(number) {
            HStack {
                Text("\(number)").font(.body.weight(.semibold)).frame(width: 28, alignment: .leading)
                Image(systemName: hole.isMapped ? "mappin.circle.fill" : "mappin.slash")
                    .foregroundStyle(hole.isMapped ? Theme.green : .secondary)
                Spacer()
                Picker("Par", selection: Binding(get: { hole.par }, set: { update(course, par: $0, index: nil) })) {
                    Text("Par 3").tag(3)
                    Text("Par 4").tag(4)
                    Text("Par 5").tag(5)
                    Text("Par 6").tag(6)
                }
                .labelsHidden()
                Picker("Index", selection: Binding(get: { hole.strokeIndex }, set: { update(course, par: nil, index: $0) })) {
                    ForEach(1...18, id: \.self) { value in
                        Text("Index \(value)").tag(value)
                    }
                }
                .labelsHidden()
            }
        }
    }

    private func update(_ course: Course, par: Int?, index: Int?) {
        var changed = course
        guard let position = changed.holes.firstIndex(where: { $0.number == number }) else { return }
        if let par = par { changed.holes[position].par = par }
        if let index = index { changed.holes[position].strokeIndex = index }
        model.save(course: changed)
    }
}

/// Name, rating, slope and yardages of one tee.
struct TeeEditor: View {
    @EnvironmentObject var model: AppModel
    let courseID: UUID
    let teeID: UUID

    var body: some View {
        if let course = model.course(courseID), let position = course.tees.firstIndex(where: { $0.id == teeID }) {
            let tee = course.tees[position]
            Form {
                Section("Tee") {
                    TextField("Name", text: Binding(get: { tee.name }, set: { value in change(course, position) { $0.name = value } }))
                    HStack {
                        Text("Course Rating")
                        Spacer()
                        TextField("72.0", value: Binding(get: { tee.rating }, set: { value in change(course, position) { $0.rating = value } }),
                                  format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                    }
                    Stepper("Slope: \(tee.slope)", value: Binding(get: { tee.slope }, set: { value in change(course, position) { $0.slope = value } }),
                            in: 55...155)
                    Stepper("Par: \(tee.par)", value: Binding(get: { tee.par }, set: { value in change(course, position) { $0.par = value } }),
                            in: 27...78)
                }
                Section {
                    ForEach(course.holes) { hole in
                        HStack {
                            Text("Hole \(hole.number)")
                            Spacer()
                            TextField("0", value: yardsBinding(course, position, hole.number), format: .number)
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                        }
                    }
                } header: {
                    Text("Yardages")
                } footer: {
                    Text(tee.ghinTeeSetID == nil ? "Entered by hand. Rounds from this tee cannot be posted to GHIN." : "From GHIN.")
                }
            }
            .navigationTitle(tee.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func change(_ course: Course, _ position: Int, _ edit: (inout TeeSet) -> Void) {
        var changed = course
        edit(&changed.tees[position])
        model.save(course: changed)
    }

    private func yardsBinding(_ course: Course, _ position: Int, _ number: Int) -> Binding<Int> {
        Binding(get: {
            let yards = course.tees[position].yards
            return number - 1 < yards.count ? yards[number - 1] : 0
        }, set: { value in
            change(course, position) { tee in
                while tee.yards.count < number { tee.yards.append(0) }
                tee.yards[number - 1] = max(0, value)
            }
        })
    }
}

/// Find the course in GHIN and copy its tees, ratings, pars and stroke indexes.
struct GHINLinkView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let course: Course
    @State private var name: String
    @State private var state: String
    @State private var hits: [GHINCourseHit] = []

    init(course: Course) {
        self.course = course
        _name = State(initialValue: course.name)
        _state = State(initialValue: course.state)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Course name", text: $name)
                    TextField("State (two letters)", text: $state)
                        .textInputAutocapitalization(.characters)
                    Button("Search GHIN") {
                        Task { hits = await model.ghinSearchCourses(name: name, state: state) }
                    }
                    .disabled(name.count < 3 || model.ghinAccount == nil)
                } footer: {
                    Text(model.ghinAccount == nil ? "Sign in to GHIN in the More tab first." : "GHIN's name for a course is often shorter than the one on the map. If nothing is found, try one distinctive word.")
                }
                if !hits.isEmpty {
                    Section("Choose the course") {
                        ForEach(hits) { hit in
                            Button {
                                Task {
                                    if await model.ghinLink(course: course, to: hit) != nil { dismiss() }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.name).foregroundStyle(.primary)
                                    Text([hit.city, hit.state].filter { !$0.isEmpty }.joined(separator: ", "))
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Link to GHIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .modifier(NoticeLayer())
    }
}

/// Place each hole's tee and green on the map by hand.
struct HoleEditorView: View {
    @EnvironmentObject var model: AppModel
    let courseID: UUID
    @State private var number = 1
    @State private var placingGreen = false
    @State private var frameToken = 0

    var body: some View {
        if let course = model.course(courseID) {
            let hole = course.hole(number)
            VStack(spacing: 0) {
                HoleMapView(hole: hole, features: course.features, pins: pins(hole), path: hole?.playingLine ?? [], measure: [],
                            fallbackCenter: course.location, showsUser: !model.isDemo, frameToken: frameToken + number * 1000,
                            onLongPress: { point in place(point, on: course) })
                VStack(spacing: 10) {
                    Picker("Hole", selection: $number) {
                        ForEach(course.holes) { item in
                            Text("Hole \(item.number)").tag(item.number)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Placing", selection: $placingGreen) {
                        Text("Tee").tag(false)
                        Text("Green").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Text(placingGreen ? "Long-press the green. A mapped green is picked up when you press on it." : "Long-press the tee you play from.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let hole = hole, let tee = hole.tee, let green = hole.greenCenter {
                        Text("Hole \(hole.number): \(Int(Geo.yards(tee, green).rounded())) yd tee to green")
                            .font(.footnote.weight(.semibold))
                    }
                }
                .padding(14)
            }
            .navigationTitle("Hole positions")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func pins(_ hole: Hole?) -> [MapPin] {
        var result: [MapPin] = []
        if let tee = hole?.tee { result.append(MapPin(id: "tee", coordinate: tee, kind: .teeMarker)) }
        if let green = hole?.greenCenter { result.append(MapPin(id: "flag", coordinate: green, kind: .flag)) }
        return result
    }

    private func place(_ point: Coordinate, on course: Course) {
        var changed = course
        if placingGreen {
            changed.setGreen(hole: number, at: point)
        } else {
            changed.setTee(hole: number, at: point)
        }
        model.save(course: changed)
        if !placingGreen {
            placingGreen = true
        } else if changed.hole(number)?.tee != nil, changed.hole(number + 1) != nil {
            // Tee and green are both set: move on to the next hole's tee.
            number += 1
            placingGreen = false
        }
    }
}
