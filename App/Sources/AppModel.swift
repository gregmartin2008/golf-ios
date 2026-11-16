import CaddieCore
import Foundation
import SwiftUI

/// The app's state: the courses, rounds, bag and settings, and everything that changes them.
@MainActor
final class AppModel: ObservableObject {
    @Published var courses: [Course] = []
    @Published var rounds: [Round] = []
    @Published var bag: [Club] = Club.standardBag
    @Published var settings = CaddieCore.Settings()
    /// A short message for the user (a failure, or a result), shown as an alert.
    @Published var notice: String?
    @Published var isBusy = false

    /// Set when the app was launched to show one screen with made-up content.
    let demoScreen: String?
    private let store: Store?
    private let ghin = GHINClient()

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        var demo: String?
        if let flag = arguments.firstIndex(of: "-demo"), flag + 1 < arguments.count {
            demo = arguments[flag + 1]
        }
        demoScreen = demo
        if demo != nil {
            // Made-up content, kept in memory only.
            store = nil
            apply(DemoData.library())
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let made = Store(folder: documents.appendingPathComponent("Caddie", isDirectory: true))
            store = made
            apply(made.load())
        }
    }

    var isDemo: Bool { demoScreen != nil }

    private func apply(_ library: Library) {
        courses = library.courses
        rounds = library.rounds
        bag = library.bag
        settings = library.settings
    }

    var library: Library {
        Library(courses: courses, rounds: rounds, bag: bag, settings: settings)
    }

    // MARK: Courses

    func course(_ id: UUID?) -> Course? {
        guard let id = id else { return nil }
        return courses.first { $0.id == id }
    }

    func save(course: Course) {
        if let index = courses.firstIndex(where: { $0.id == course.id }) {
            courses[index] = course
        } else {
            courses.append(course)
        }
        courses.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        store?.save(courses: courses)
    }

    func delete(course: Course) {
        courses.removeAll { $0.id == course.id }
        store?.save(courses: courses)
    }

    // MARK: Rounds

    var activeRound: Round? {
        rounds.filter { $0.status == .inProgress && $0.source == .app }.max { $0.date < $1.date }
    }

    func round(_ id: UUID) -> Round? {
        rounds.first { $0.id == id }
    }

    func save(round: Round) {
        if let index = rounds.firstIndex(where: { $0.id == round.id }) {
            rounds[index] = round
        } else {
            rounds.append(round)
        }
        store?.save(rounds: rounds)
    }

    func delete(round: Round) {
        rounds.removeAll { $0.id == round.id }
        store?.save(rounds: rounds)
    }

    @discardableResult
    func startRound(course: Course, tee: TeeSet?, holeCount: Int, startHole: Int) -> Round {
        let round = Round.start(course: course, tee: tee, holeCount: holeCount, startHole: startHole,
                                handicapIndex: handicapIndex)
        save(round: round)
        return round
    }

    /// Rounds for the lists: newest first.
    var roundsNewestFirst: [Round] {
        rounds.sorted { $0.date > $1.date }
    }

    // MARK: Bag and settings

    func save(bag newBag: [Club]) {
        bag = newBag
        store?.save(bag: bag)
    }

    func saveSettings() {
        store?.save(settings: settings)
    }

    var clubNames: [String] {
        bag.filter { $0.inBag }.map { $0.name }
    }

    // MARK: Handicap

    var handicapReport: Handicap.Report {
        Handicap.report(rounds: rounds)
    }

    /// The index to play off: GHIN's when connected, else one typed in, else the app's estimate.
    var handicapIndex: Double? {
        if let value = settings.ghin?.handicapIndex { return value }
        if let value = settings.manualIndex { return value }
        return handicapReport.index
    }

    var handicapSource: String {
        if settings.ghin?.handicapIndex != nil { return "GHIN" }
        if settings.manualIndex != nil { return "Entered by you" }
        return "Estimate from rounds in Caddie"
    }

    // MARK: Statistics

    func stats(limit: Int?) -> StatsReport {
        Stats.report(rounds: Stats.eligible(rounds, limit: limit), courses: courses)
    }

    // MARK: Backup

    func backupFile() -> URL? {
        guard let data = Store.backupData(library) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let name = "Caddie backup \(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    func restore(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), var restored = Store.library(fromBackup: data) else {
            notice = "That file is not a Caddie backup."
            return
        }
        restored.settings.ghin = settings.ghin
        apply(restored)
        store?.save(library)
        notice = "Restored \(restored.rounds.count) rounds and \(restored.courses.count) courses."
    }

    // MARK: GHIN

    var ghinAccount: GHINAccount? { settings.ghin }

    private func ensureSignedIn() async throws {
        if ghin.isSignedIn { return }
        guard let account = settings.ghin, let password = Keychain.read(account: account.login) else {
            throw HTTPError(status: 401, message: "Sign in to GHIN in the More tab first.")
        }
        try await ghin.signIn(login: account.login, password: password)
    }

    /// Runs a piece of GHIN work, showing a spinner and turning a failure into a notice.
    private func withGHIN(_ work: () async throws -> Void) async {
        if isDemo {
            notice = "GHIN is not contacted while showing sample content."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await ensureSignedIn()
            try await work()
        } catch {
            notice = error.localizedDescription
        }
    }

    func ghinSignIn(login: String, password: String, ghinNumber: Int?) async {
        if isDemo { return }
        isBusy = true
        defer { isBusy = false }
        do {
            ghin.signOut()
            let golfer = try await ghin.signIn(login: login, password: password)
            Keychain.save(password, account: login)
            var number = golfer.ghinNumber ?? ghinNumber
            if number == nil, let typed = Int(login.trimmingCharacters(in: .whitespaces)) { number = typed }
            settings.ghin = GHINAccount(login: login, ghinNumber: number, name: golfer.name,
                                        handicapIndex: golfer.handicapIndex, lowIndex: golfer.lowIndex,
                                        clubName: golfer.clubName, lastSync: nil)
            saveSettings()
            if number == nil {
                notice = "Signed in, but GHIN did not say what your GHIN number is. Enter it and sign in again."
                return
            }
            try await syncGHIN()
        } catch {
            notice = error.localizedDescription
        }
    }

    func ghinSignOut() {
        if let account = settings.ghin { Keychain.delete(account: account.login) }
        ghin.signOut()
        settings.ghin = nil
        saveSettings()
    }

    func ghinRefresh() async {
        await withGHIN { try await self.syncGHIN() }
    }

    /// Reads the index and score history and files the scores as rounds.
    private func syncGHIN() async throws {
        guard var account = settings.ghin, let number = account.ghinNumber else { return }
        if let golfer = try? await ghin.golfer(ghinNumber: number) {
            if let value = golfer.handicapIndex { account.handicapIndex = value }
            if let value = golfer.lowIndex { account.lowIndex = value }
            if let value = golfer.name, !value.isEmpty { account.name = value }
            if let value = golfer.clubName, !value.isEmpty { account.clubName = value }
        }
        let scores = try await ghin.scores(ghinNumber: number, limit: 40)
        var changed = rounds
        // Scores that came from GHIN before are replaced by the fresh list.
        changed.removeAll { $0.source == .ghin }
        let postedHere = Set(changed.compactMap { $0.ghin.scoreID })
        let calendar = Calendar.current
        for score in scores {
            if postedHere.contains(score.id) { continue }
            // A round scored in Caddie and posted (here or in the GHIN app) is already in the list.
            let sameDay = changed.contains { round in
                round.source == .app && round.status == .finished
                    && calendar.isDate(round.date, inSameDayAs: score.playedAt)
                    && Handicap.adjustedGross(for: round) == score.adjustedGross
            }
            if sameDay { continue }
            changed.append(Round(
                courseName: score.courseName, teeName: score.teeName, rating: score.rating, slope: score.slope,
                par: 72, date: score.playedAt, holeCount: score.holes, holes: [], status: .finished, source: .ghin,
                imported: ImportedScore(adjustedGross: score.adjustedGross, differential: score.differential,
                                        ghinScoreID: score.id, scoreType: score.scoreType)))
        }
        rounds = changed
        store?.save(rounds: rounds)
        account.lastSync = Date()
        settings.ghin = account
        saveSettings()
    }

    func ghinSearchCourses(name: String, state: String) async -> [GHINCourseHit] {
        var hits: [GHINCourseHit] = []
        await withGHIN {
            hits = try await self.ghin.searchCourses(name: name, state: state)
            if hits.isEmpty { self.notice = "GHIN has no course by that name in that state." }
        }
        return hits
    }

    /// Copies GHIN's tees, ratings, pars and stroke indexes onto a course.
    func ghinLink(course: Course, to hit: GHINCourseHit) async -> Course? {
        var result: Course?
        await withGHIN {
            let details = try await self.ghin.courseDetails(id: hit.id)
            var updated = course
            updated.ghinCourseID = details.id
            if updated.city.isEmpty { updated.city = details.city }
            if updated.state.isEmpty { updated.state = details.state }
            if !details.tees.isEmpty { updated.tees = details.tees }
            for index in 0..<updated.holes.count {
                let number = updated.holes[index].number
                if number - 1 < details.pars.count, number >= 1 {
                    updated.holes[index].par = details.pars[number - 1]
                }
                if number - 1 < details.strokeIndexes.count, number >= 1 {
                    updated.holes[index].strokeIndex = details.strokeIndexes[number - 1]
                }
            }
            self.save(course: updated)
            result = updated
        }
        return result
    }

    /// What would be sent to GHIN for a round, or the reason it cannot be posted.
    func ghinPost(for round: Round) -> Result<GHINPost, PostProblem> {
        guard let account = settings.ghin, let golfer = account.ghinNumber else { return .failure(.notSignedIn) }
        guard round.status == .finished, round.isFullyScored else { return .failure(.notFinished) }
        guard let course = self.course(round.courseID), let courseID = course.ghinCourseID else { return .failure(.courseNotLinked) }
        guard let tee = course.tees.first(where: { $0.id == round.teeID }), let teeID = tee.ghinTeeSetID else {
            return .failure(.teeNotLinked)
        }
        let holes = round.holes.map { (number: $0.number, strokes: $0.strokes ?? 0) }
        return .success(GHINPost(golferID: golfer, courseID: courseID, teeSetID: teeID, playedAt: round.date,
                                 holeCount: round.holes.count, scoreType: "H", gender: settings.gender, holes: holes))
    }

    func ghinSend(_ post: GHINPost, for round: Round) async {
        await withGHIN {
            let id = try await self.ghin.post(post)
            var updated = round
            updated.ghin = GHINPostState(postedAt: Date(), scoreID: id, message: nil)
            self.save(round: updated)
            self.notice = "Posted to GHIN."
            try? await self.syncGHIN()
        }
    }
}

enum PostProblem: Error {
    case notSignedIn, notFinished, courseNotLinked, teeNotLinked

    var message: String {
        switch self {
        case .notSignedIn: return "Sign in to GHIN in the More tab to post scores."
        case .notFinished: return "Finish the round and score every hole before posting."
        case .courseNotLinked: return "Link this course to its GHIN course first (Courses, then the course, then Link to GHIN)."
        case .teeNotLinked: return "The tee this round was played from did not come from GHIN. Link the course to GHIN and choose a GHIN tee."
        }
    }
}
