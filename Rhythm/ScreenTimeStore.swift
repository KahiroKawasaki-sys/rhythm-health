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

    /// 振り返り：前の期間と今の期間を1日単位で。今日は含めない。
    func reviewFilter(_ period: ReviewPeriod) -> DeviceActivityFilter {
        let today = Calendar.current.startOfDay(for: .now)
        let start = HealthMath.comparisonDays(period).first ?? today
        return DeviceActivityFilter(segment: .daily(during: DateInterval(start: start, end: today)),
            users: .all, devices: .init([.iPhone]))
    }

    /// 振り返りのカレンダー：月曜始まりの5週間。今日以降は含めない。
    func calendarFilter(offset: Int) -> DeviceActivityFilter {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let days = HealthMath.calendarWeeks(offset: offset)
        let start = days.first ?? today
        let after = days.last.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? today
        return DeviceActivityFilter(segment: .daily(during: DateInterval(start: start, end: max(start, min(after, today)))),
            users: .all, devices: .init([.iPhone]))
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
