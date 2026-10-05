import SwiftUI

@main struct RhythmApp: App {
    @StateObject private var journal = JournalStore()
    @StateObject private var health = HealthStore()
    @StateObject private var screen = ScreenTimeStore()
    @StateObject private var lock = AppLock()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ZStack {
                Palette.background.ignoresSafeArea()
                if lock.isUnlocked {
                    RootView().environmentObject(journal).environmentObject(health).environmentObject(screen)
                        .task { journal.load(); screen.updateStatus(); await health.refresh() }
                } else {
                    VStack(spacing: 24) {
                        Image(systemName: "leaf").font(.system(size: 52)).foregroundStyle(Palette.green)
                        Text("Rhythm").font(.system(size: 38, weight: .semibold, design: .rounded))
                        Text("日々を知る。自分を整える。").foregroundStyle(Palette.secondary)
                        Button { Task { await lock.unlock() } } label: {
                            Label("記録を開く", systemImage: "lock.open")
                        }.buttonStyle(PrimaryButtonStyle()).disabled(lock.isAuthenticating)
                        if let message = lock.message { Notice(text: message) }
                        Text("あなたの記録は、このiPhoneの中に。").font(.caption).foregroundStyle(Palette.secondary)
                    }.padding(32).frame(maxWidth: 440)
                }
                // Hide snapshots immediately when the app becomes inactive.
                if phase != .active {
                    Palette.background.ignoresSafeArea()
                    Image(systemName: "leaf").font(.largeTitle).foregroundStyle(Palette.green)
                }
            }
            .tint(Palette.green).preferredColorScheme(.light)
            .task { await lock.unlock() }
            .onChange(of: phase) { _, next in
                if next == .background { lock.lock() }
                if next == .active {
                    Task {
                        if !lock.isUnlocked { await lock.unlock() }
                        else { screen.updateStatus(); await health.refresh() }
                    }
                }
            }
        }
    }
}

struct DaySelection: Identifiable {
    var date: Date
    var id: Date { date }
}

struct RootView: View {
    @State private var editor: DaySelection?
    var body: some View {
        TabView {
            NavigationStack { TodayView { editor = DaySelection(date: Calendar.current.startOfDay(for: .now)) } }
                .tabItem { Label("今日", systemImage: "sun.max") }
            NavigationStack { ReviewView() }.tabItem { Label("振り返り", systemImage: "chart.xyaxis.line") }
            NavigationStack { HistoryView { editor = DaySelection(date: $0) } }
                .tabItem { Label("記録", systemImage: "book.closed") }
            NavigationStack { SettingsView() }.tabItem { Label("設定", systemImage: "slider.horizontal.3") }
        }.sheet(item: $editor) { selection in
            NavigationStack { EntryView(day: selection.date) }
        }
    }
}
