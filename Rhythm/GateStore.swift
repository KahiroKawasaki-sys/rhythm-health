import Foundation
import Combine
import FamilyControls
import DeviceActivity
import UserNotifications
import UIKit

/// 開く前に目的を選ぶ仕組みの本体側。記録はApp Groupの共有領域に置き、外部へは送らない。
@MainActor final class GateStore: ObservableObject {
    static let shared = GateStore()

    @Published private(set) var config = GateConfig()
    @Published private(set) var events: [GateEvent] = []
    @Published private(set) var loadError: String?
    @Published var message: String?
    /// 通知のタップや rhythm://gate で目的選択画面を開く。
    @Published var isGatePresented = false
    @Published var harvestPending = false

    private let center = DeviceActivityCenter()

    var isEnabled: Bool { config.enabled }
    var settings: GateSettings { config.settings }
    var unlockedUntil: Date? { config.unlockedUntil.flatMap { $0 > .now ? $0 : nil } }

    /// Call while the app is in the foreground, when protected data is accessible.
    func load() {
        do {
            config = try GateFiles.loadConfig()
            events = try GateFiles.loadEvents()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        if GateShield.restoreIfDue() { config.unlockedUntil = nil }
    }

    // MARK: オン・オフ

    func enable(selection: FamilyActivitySelection) async {
        guard loadError == nil else { message = loadError; return }
        guard !selection.applicationTokens.isEmpty || !selection.webDomainTokens.isEmpty || !selection.categoryTokens.isEmpty else {
            message = "先に「アプリの分類」でSNSを選んでください。"; return
        }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        var next = config
        next.enabled = true
        next.selection = selection
        next.unlockedUntil = nil
        do {
            try GateFiles.saveConfig(next)
            config = next
            GateShield.apply(selection)
            try startDailyMonitoring(selection)
            message = granted ? "ひと呼吸の仕組みをオンにしました。" :
                "オンにしました。通知が許可されていないため、「理由を選んで開く」からRhythmを開けません。設定アプリで通知を許可してください。"
        } catch {
            message = "オンにできませんでした。\(error.localizedDescription)"
        }
    }

    /// 呼び出し側で本人認証と60秒の待機を済ませてから呼ぶ。
    func disable() {
        var next = config
        next.enabled = false
        next.unlockedUntil = nil
        do {
            try GateFiles.saveConfig(next)
            config = next
            GateShield.clear()
            center.stopMonitoring([.rhythmUnlock, .rhythmDaily])
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [harvestID])
            message = "ひと呼吸の仕組みをオフにしました。"
        } catch { message = "オフにできませんでした。\(error.localizedDescription)" }
    }

    /// SNSの選択を変えたとき、オン中なら遮断の対象も入れ替える。
    func selectionChanged(_ selection: FamilyActivitySelection) {
        guard config.enabled else { return }
        var next = config
        next.selection = selection
        do {
            try GateFiles.saveConfig(next)
            config = next
            if unlockedUntil == nil { GateShield.apply(selection) }
            try startDailyMonitoring(selection)
        } catch { message = "遮断の対象を更新できませんでした。\(error.localizedDescription)" }
    }

    func saveSettings(_ settings: GateSettings) throws {
        guard settings.isValid else { throw JournalStore.StoreError.message("解除時間と遊び予算を確認してください。") }
        var next = config
        next.settings = settings
        try GateFiles.saveConfig(next)
        config = next
    }

    // MARK: 目的を選んで開く

    func waitSeconds(for purpose: GatePurpose) -> Int {
        GateMath.waitSeconds(for: purpose, at: .now, events: events, settings: settings)
    }
    var budgetUsed: Int { GateMath.budgetUsed(on: .now, events) }
    var isOverBudget: Bool { GateMath.isOverBudget(on: .now, events, settings: settings) }
    var emergencyAvailable: Bool { GateMath.emergencyAvailable(on: .now, events) }
    var todayCounts: (opened: Int, stayedAway: Int) { GateMath.todayCounts(.now, events) }

    func stayAway() {
        record(GateEvent(date: .now, kind: .stayedAway))
    }

    /// 目的を記録して、決めた分だけ遮断を外す。終わりは監視拡張が戻す（本体の復帰時にも確認する）。
    @discardableResult
    func open(_ purpose: GatePurpose, note: String = "") -> Date? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if purpose == .work && trimmed.isEmpty { message = "何を調べるかを一言入れてください。"; return nil }
        let minutes = settings.minutes(for: purpose)
        guard record(GateEvent(date: .now, kind: .opened, purpose: purpose, minutes: minutes,
                               note: purpose == .work ? String(trimmed.prefix(80)) : nil)) else { return nil }
        let until = unlock(minutes: minutes)
        if purpose == .work, let until { scheduleHarvestQuestion(at: until) }
        return until
    }

    /// 1日1回だけ、待機なしで15分。遊び予算には計上しない。
    @discardableResult
    func openEmergency() -> Date? {
        guard emergencyAvailable else { message = "緊急の解除は1日1回までです。"; return nil }
        guard record(GateEvent(date: .now, kind: .emergency, minutes: GateMath.emergencyMinutes)) else { return nil }
        return unlock(minutes: GateMath.emergencyMinutes)
    }

    func recordHarvest(_ harvested: Bool) {
        if record(GateEvent(date: .now, kind: .harvest, harvested: harvested)) { harvestPending = false }
    }

    /// 本体の復帰時：解除時間を過ぎていれば遮断を戻す（監視拡張が動かなかった場合の保険）。
    func refresh() {
        guard loadError == nil else { return }
        if let latest = try? GateFiles.loadEvents() { events = latest }
        if GateShield.restoreIfDue() { config.unlockedUntil = nil }
    }

    private func unlock(minutes: Int) -> Date? {
        let window = GateMath.unlockWindow(from: .now, minutes: minutes)
        var next = config
        next.unlockedUntil = window.end
        do {
            try GateFiles.saveConfig(next)
            config = next
            center.stopMonitoring([.rhythmUnlock])
            let calendar = Calendar.current
            let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
            try center.startMonitoring(.rhythmUnlock, during: DeviceActivitySchedule(
                intervalStart: calendar.dateComponents(parts, from: window.start),
                intervalEnd: calendar.dateComponents(parts, from: window.end), repeats: false))
            GateShield.clear()
            return window.end
        } catch {
            // 再遮断の予約ができないときは外さない（外しっぱなしを防ぐ）。
            next.unlockedUntil = nil
            try? GateFiles.saveConfig(next)
            config = next
            message = "解除の予約ができなかったため、遮断を続けます。\(error.localizedDescription)"
            return nil
        }
    }

    private func startDailyMonitoring(_ selection: FamilyActivitySelection) throws {
        center.stopMonitoring([.rhythmDaily])
        let events = Dictionary(uniqueKeysWithValues: GateMath.reachLines.map { minutes in
            (DeviceActivityEvent.Name.reach(minutes), DeviceActivityEvent(applications: selection.applicationTokens,
                categories: selection.categoryTokens, webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: minutes)))
        })
        try center.startMonitoring(.rhythmDaily, during: DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0), intervalEnd: DateComponents(hour: 23, minute: 59), repeats: true),
            events: events)
    }

    @discardableResult
    private func record(_ event: GateEvent) -> Bool {
        guard loadError == nil else { message = loadError; return false }
        do { events = try GateFiles.append(event); return true }
        catch { message = "記録できませんでした。\(error.localizedDescription)"; return false }
    }

    // MARK: 通知

    private let harvestID = "rhythm.harvest.question"

    private func scheduleHarvestQuestion(at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "収穫あった？"
        content.body = "調べたかったことは見つかりましたか。"
        content.categoryIdentifier = GateShared.harvestCategory
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: harvestID, content: content, trigger: trigger))
    }

    nonisolated static func registerCategories() {
        let yes = UNNotificationAction(identifier: GateShared.harvestYes, title: "あった", options: [.authenticationRequired])
        let no = UNNotificationAction(identifier: GateShared.harvestNo, title: "なかった", options: [.authenticationRequired])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: GateShared.harvestCategory, actions: [yes, no], intentIdentifiers: [])
        ])
    }

    func handleNotification(category: String, action: String, route: String?) {
        if category == GateShared.harvestCategory {
            switch action {
            case GateShared.harvestYes: recordHarvest(true)
            case GateShared.harvestNo: recordHarvest(false)
            default: harvestPending = true
            }
        } else if route == GateShared.gateRoute {
            isGatePresented = true
        }
    }

    func handle(url: URL) {
        if url.scheme == GateShared.gateURL.scheme, url.host == GateShared.gateRoute { isGatePresented = true }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        GateStore.registerCategories()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let category = content.categoryIdentifier
        let action = response.actionIdentifier
        let route = content.userInfo["route"] as? String
        Task { @MainActor in
            GateStore.shared.handleNotification(category: category, action: action, route: route)
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
