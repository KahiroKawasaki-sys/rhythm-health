import SwiftUI

@main struct RhythmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var gate = GateStore.shared
    @StateObject private var journal = JournalStore()
    @StateObject private var health = HealthStore()
    @StateObject private var screen = ScreenTimeStore()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(journal).environmentObject(health).environmentObject(screen).environmentObject(gate)
                .background(Palette.background.ignoresSafeArea())
                .task { journal.load(); screen.loadSelection(); screen.updateStatus(); gate.load(); await health.refresh() }
                .sheet(isPresented: $gate.isGatePresented) { GateView().environmentObject(gate) }
                .tint(Palette.green).preferredColorScheme(.light)
                .onOpenURL { gate.handle(url: $0) }
                .onChange(of: phase) { _, next in
                    if next == .background { gate.isGatePresented = false }
                    guard next == .active else { return }
                    // 保護されたファイルを読めなかった場合は、端末の解除後にもう一度読む。
                    if journal.loadError != nil { journal.load() }
                    if screen.selectionError != nil { screen.loadSelection() }
                    if gate.loadError != nil { gate.load() }
                    screen.updateStatus(); gate.refresh()
                    Task { await health.refresh() }
                }
        }
    }
}

struct DaySelection: Identifiable {
    var date: Date
    var id: Date { date }
}

enum RootTab: Hashable { case today, review, history, settings }

struct RootView: View {
    @State private var editor: DaySelection?
    @State private var tab = RootTab.today
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                TodayView(openSettings: { tab = .settings }) { editor = DaySelection(date: Calendar.current.startOfDay(for: .now)) }
            }.tabItem { Label("今日", systemImage: "sun.max") }.tag(RootTab.today)
            NavigationStack { ReviewView() }.tabItem { Label("振り返り", systemImage: "chart.xyaxis.line") }.tag(RootTab.review)
            NavigationStack { HistoryView { editor = DaySelection(date: $0) } }
                .tabItem { Label("記録", systemImage: "book.closed") }.tag(RootTab.history)
            NavigationStack { SettingsView() }.tabItem { Label("設定", systemImage: "slider.horizontal.3") }.tag(RootTab.settings)
        }.sheet(item: $editor) { selection in
            NavigationStack { EntryView(day: selection.date) }
        }
    }
}
