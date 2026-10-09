import FamilyControls
import DeviceActivity
import Foundation
import Combine

@MainActor final class ScreenTimeStore: ObservableObject {
    @Published private(set) var isAuthorized = false
    @Published var message: String?
    @Published var refreshID = UUID()

    func updateStatus() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        refreshID = UUID()
    }

    func connect() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            updateStatus()
            message = isAuthorized ? nil : "スクリーンタイムの許可を確認してください。"
        } catch { message = "接続できませんでした。実機のスクリーンタイム設定とアプリの権限を確認してください。\(error.localizedDescription)" }
    }

    func filter(days: Int?) -> DeviceActivityFilter {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = days.map { calendar.date(byAdding: .day, value: -2 * $0, to: today)! } ?? today
        let end = days == nil ? Date.now : today
        return DeviceActivityFilter(segment: .daily(during: DateInterval(start: start, end: end)),
            users: .all, devices: .init([.iPhone]))
    }

    /// 表示期間と比較期間をまとめて渡す。当日の途中データは含めない。
    func filter(period: ReviewPeriod, sns: Bool) -> DeviceActivityFilter {
        let today = Calendar.current.startOfDay(for: .now)
        // fetchStart includes 7 extra days for the weight moving average; screen time does not need them.
        let start = Calendar.current.date(byAdding: .day, value: 7, to: HealthMath.fetchStart(period)) ?? today
        return filter(DateInterval(start: start, end: today), sns: sns)
    }

    func calendarFilter(month: DateInterval, sns: Bool) -> DeviceActivityFilter {
        let today = Calendar.current.startOfDay(for: .now)
        return filter(DateInterval(start: month.start, end: max(month.start, min(month.end, today))), sns: sns)
    }

    private func filter(_ interval: DateInterval, sns: Bool) -> DeviceActivityFilter {
        guard sns else { return DeviceActivityFilter(segment: .daily(during: interval), users: .all, devices: .init([.iPhone])) }
        return DeviceActivityFilter(segment: .daily(during: interval), users: .all, devices: .init([.iPhone]),
            applications: snsSelection.applicationTokens, categories: snsSelection.categoryTokens,
            webDomains: snsSelection.webDomainTokens)
    }

    /// 今日のカード用。過去30日と今日を1時間単位で渡す（同じ時刻までの平均と連続日数に使う）。
    func todayFilter() -> DeviceActivityFilter {
        let today = Calendar.current.startOfDay(for: .now)
        let start = Calendar.current.date(byAdding: .day, value: -30, to: today) ?? today
        return DeviceActivityFilter(segment: .hourly(during: DateInterval(start: start, end: .now)),
            users: .all, devices: .init([.iPhone]))
    }

    // MARK: アプリの分類（SNS・動画・仕事）とSNSの目標。表示拡張が読めるようApp Groupに保存
    @Published private(set) var categories = ScreenCategories()
    @Published private(set) var selectionError: String?
    /// v1.1まではSNSの選択だけを本体の領域に保存していた。初回に分類へ移す。
    private let legacyURL = URL.applicationSupportDirectory.appendingPathComponent("Rhythm", isDirectory: true)
        .appendingPathComponent("sns-selection.json")

    var snsSelection: FamilyActivitySelection { categories.sns }
    var hasSNSSelection: Bool { !categories.sns.isEmptySelection }

    func loadSelection() {
        do {
            if let saved = try ScreenCategoryFiles.load() {
                categories = saved
            } else {
                var next = ScreenCategories()
                if FileManager.default.fileExists(atPath: legacyURL.path) {
                    next.sns = try JSONDecoder().decode(FamilyActivitySelection.self, from: Data(contentsOf: legacyURL))
                    try ScreenCategoryFiles.save(next)
                }
                categories = next
            }
            selectionError = nil
        } catch {
            categories = ScreenCategories()
            selectionError = "アプリの分類を読み込めませんでした。元の選択を守るため、保存を停止しています。アプリを閉じて、端末を解除してから再度お試しください。"
        }
    }

    func saveCategories(_ next: ScreenCategories) throws {
        if let selectionError { throw JournalStore.StoreError.message(selectionError) }
        guard ScreenCategories.goalRange.contains(next.snsGoalMinutes) else { throw JournalStore.StoreError.message("SNSの目標を確認してください。") }
        try ScreenCategoryFiles.save(next)
        categories = next
        refreshID = UUID()
    }
}
