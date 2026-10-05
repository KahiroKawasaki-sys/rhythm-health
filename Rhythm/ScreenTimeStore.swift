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
}
