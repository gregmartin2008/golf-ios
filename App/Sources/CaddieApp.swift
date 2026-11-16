import CaddieCore
import SwiftUI

@main
struct CaddieApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Theme.green)
        }
    }
}

/// The five tabs, or one screen with sample content when launched for a screenshot.
struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let screen = model.demoScreen {
                DemoScreen(name: screen)
            } else {
                tabs(selected: 0)
            }
        }
        .alert("Caddie", isPresented: noticeShown) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
        .overlay {
            if model.isBusy {
                ProgressView()
                    .controlSize(.large)
                    .padding(24)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var noticeShown: Binding<Bool> {
        Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })
    }

    func tabs(selected: Int) -> some View {
        MainTabs(selection: selected)
    }
}

struct MainTabs: View {
    @State var selection: Int

    var body: some View {
        TabView(selection: $selection) {
            PlayTab()
                .tabItem { Label("Play", systemImage: "flag.fill") }
                .tag(0)
            RoundsTab()
                .tabItem { Label("Rounds", systemImage: "list.bullet.rectangle") }
                .tag(1)
            StatsTab()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                .tag(2)
            CoursesTab()
                .tabItem { Label("Courses", systemImage: "map.fill") }
                .tag(3)
            MoreTab()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(4)
        }
    }
}

/// One screen opened directly with the sample content, for the build's screenshots.
struct DemoScreen: View {
    @EnvironmentObject var model: AppModel
    let name: String

    var body: some View {
        switch name {
        case "hole", "putts":
            if let round = model.activeRound {
                NavigationStack { HoleScreen(round: round) }
            } else {
                MainTabs(selection: 0)
            }
        case "summary", "round":
            if let round = model.roundsNewestFirst.first(where: { $0.status == .finished }) {
                NavigationStack { RoundSummaryView(roundID: round.id) }
            } else {
                MainTabs(selection: 1)
            }
        case "rounds":
            MainTabs(selection: 1)
        case "stats":
            MainTabs(selection: 2)
        case "courses":
            MainTabs(selection: 3)
        case "course":
            if let course = model.courses.first {
                NavigationStack { CourseDetailView(courseID: course.id) }
            } else {
                MainTabs(selection: 3)
            }
        case "editor":
            if let course = model.courses.first {
                NavigationStack { HoleEditorView(courseID: course.id) }
            } else {
                MainTabs(selection: 3)
            }
        case "handicap":
            NavigationStack { HandicapView() }
        case "ghin":
            NavigationStack { GHINView() }
        case "bag":
            NavigationStack { BagView() }
        default:
            MainTabs(selection: 0)
        }
    }
}
