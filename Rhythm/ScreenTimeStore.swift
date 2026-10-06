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

    // MARK: SNSとして数えるアプリ（手入力と同じ保護方式で端末内に保存）
    @Published private(set) var snsSelection = FamilyActivitySelection()
    @Published private(set) var selectionError: String?
    private let selectionURL = URL.applicationSupportDirectory.appendingPathComponent("Rhythm", isDirectory: true)
        .appendingPathComponent("sns-selection.json")

    var hasSNSSelection: Bool {
        !snsSelection.applicationTokens.isEmpty || !snsSelection.categoryTokens.isEmpty || !snsSelection.webDomainTokens.isEmpty
    }

    /// Call only after device-owner authentication, when protected data is accessible.
    func loadSelection() {
        do {
            guard FileManager.default.fileExists(atPath: selectionURL.path) else {
                snsSelection = FamilyActivitySelection(); selectionError = nil; return
            }
            snsSelection = try JSONDecoder().decode(FamilyActivitySelection.self, from: Data(contentsOf: selectionURL))
            selectionError = nil
        } catch {
            snsSelection = FamilyActivitySelection()
            selectionError = "SNSの選択を読み込めませんでした。元の選択を守るため、保存を停止しています。アプリを閉じて、端末を解除してから再度お試しください。"
        }
    }

    func saveSelection(_ next: FamilyActivitySelection) throws {
        if let selectionError { throw JournalStore.StoreError.message(selectionError) }
        var folder = selectionURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        try JSONEncoder().encode(next).write(to: selectionURL, options: [.atomic, .completeFileProtection])
        snsSelection = next
        refreshID = UUID()
    }
}
