import Foundation
import FamilyControls
import ManagedSettings
import DeviceActivity
import UserNotifications

/// 本体と3つの拡張（監視・シールド表示・シールド操作）で共有する部品。
enum GateShared {
    static let appGroup = "group.com.kawakahi.rhythm"
    static let gateRoute = "gate"
    static let gateURL = URL(string: "rhythm://gate")!
    static let gateRequestID = "rhythm.gate.request"
    static let harvestCategory = "rhythm.harvest"
    static let harvestYes = "rhythm.harvest.yes"
    static let harvestNo = "rhythm.harvest.no"
}

extension ManagedSettingsStore.Name {
    static let rhythmGate = Self("rhythm.gate")
}

extension DeviceActivityName {
    /// 解除の終わりに再遮断するための監視。
    static let rhythmUnlock = Self("rhythm.unlock")
    /// 対象アプリの合計が到達ラインを越えたかを日ごとに見る監視。
    static let rhythmDaily = Self("rhythm.daily")
}

extension DeviceActivityEvent.Name {
    static func reach(_ minutes: Int) -> Self { Self("reach.\(minutes)") }
    var reachMinutes: Int? {
        guard rawValue.hasPrefix("reach.") else { return nil }
        return Int(rawValue.dropFirst("reach.".count))
    }
}

/// 遮断の設定。監視拡張がiPhoneのロック中にも再遮断できるよう、最初のロック解除後は読める保護にする。
/// 中身はAppleの識別子と分数の設定だけで、利用時間や目的の記録は含めない。
struct GateConfig: Codable {
    var version = 1
    var enabled = false
    var selection = FamilyActivitySelection()
    var settings = GateSettings()
    var unlockedUntil: Date?
}

private struct GateLog: Codable {
    var version = 1
    var events: [GateEvent] = []
}

enum GateFiles {
    enum FileError: LocalizedError {
        case noContainer, corrupt
        var errorDescription: String? {
            switch self {
            case .noContainer: return "共有領域（App Group）を開けませんでした。"
            case .corrupt: return "ひと呼吸の記録を読み込めませんでした。元の記録を守るため、保存を停止しています。"
            }
        }
    }

    /// 記録は2年分を残す（1年表示の前年比較に足りる長さ）。
    static let retentionDays = 800

    private static func folder() throws -> URL {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GateShared.appGroup) else {
            throw FileError.noContainer
        }
        var folder = base.appendingPathComponent("Gate", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
        }
        return folder
    }
    private static func configURL() throws -> URL { try folder().appendingPathComponent("config.json") }
    private static func logURL() throws -> URL { try folder().appendingPathComponent("events.json") }

    static func loadConfig() throws -> GateConfig {
        let url = try configURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return GateConfig() }
        guard let config = try? JSONDecoder().decode(GateConfig.self, from: coordinatedRead(url)),
              config.version == 1, config.settings.isValid else { throw FileError.corrupt }
        return config
    }

    static func saveConfig(_ config: GateConfig) throws {
        let data = try JSONEncoder().encode(config)
        try coordinatedWrite(try configURL()) { _ in data }
    }

    static func loadEvents() throws -> [GateEvent] {
        let url = try logURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try decodeLog(coordinatedRead(url)).events
    }

    /// 本体と拡張が同時に書いても失わないよう、読み込みと書き込みを1回の協調操作で行う。
    @discardableResult
    static func append(_ event: GateEvent, unless skip: (([GateEvent]) -> Bool)? = nil) throws -> [GateEvent] {
        guard GateMath.validate(event) else { throw FileError.corrupt }
        var result: [GateEvent] = []
        try coordinatedWrite(try logURL()) { existing in
            var log = try existing.map { try decodeLog($0) } ?? GateLog()
            if skip?(log.events) == true { result = log.events; return nil }
            let cutoff = Date.now.addingTimeInterval(-Double(retentionDays) * 86_400)
            log.events = log.events.filter { $0.date >= cutoff } + [event]
            result = log.events
            return try JSONEncoder().encode(log)
        }
        return result
    }

    private static func decodeLog(_ data: Data) throws -> GateLog {
        guard let log = try? JSONDecoder().decode(GateLog.self, from: data), log.version == 1,
              log.events.allSatisfy(GateMath.validate) else { throw FileError.corrupt }
        return log
    }

    private static func coordinatedRead(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(FileError.corrupt)
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// `transform` が nil を返したら書き込まない。記録は完全保護、設定は最初のロック解除後に読める保護で書く。
    private static func coordinatedWrite(_ url: URL, _ transform: (Data?) throws -> Data?) throws {
        let protection: Data.WritingOptions = url.lastPathComponent == "events.json"
            ? .completeFileProtection : .completeFileProtectionUntilFirstUserAuthentication
        var coordinationError: NSError?
        var failure: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { url in
            do {
                let existing = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
                if let next = try transform(existing) { try next.write(to: url, options: [.atomic, protection]) }
            } catch { failure = error }
        }
        if let coordinationError { throw coordinationError }
        if let failure { throw failure }
    }
}

enum GateShield {
    static func apply(_ selection: FamilyActivitySelection) {
        let store = ManagedSettingsStore(named: .rhythmGate)
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
    }

    static func clear() {
        ManagedSettingsStore(named: .rhythmGate).clearAllSettings()
    }

    /// 解除の終わり（監視拡張・本体の復帰時）に呼ぶ。新しい解除が続いているときは戻さない。
    @discardableResult
    static func restoreIfDue(now: Date = .now) -> Bool {
        guard var config = try? GateFiles.loadConfig(), config.enabled else { return false }
        if let until = config.unlockedUntil, until > now.addingTimeInterval(30) { return false }
        apply(config.selection)
        config.unlockedUntil = nil
        try? GateFiles.saveConfig(config)
        return true
    }
}

enum GateNotice {
    /// シールドから直接アプリは開けないため、通知のタップでRhythmの目的選択画面を開く。
    static func postGateRequest(completion: @escaping () -> Void) {
        let content = UNMutableNotificationContent()
        content.title = "開く理由を選びましょう"
        content.body = "ここをタップすると、Rhythmで目的を選べます。"
        content.userInfo = ["route": GateShared.gateRoute]
        let request = UNNotificationRequest(identifier: GateShared.gateRequestID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in completion() }
    }
}
