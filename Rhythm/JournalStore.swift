import Foundation
import Combine

private struct JournalEnvelope: Codable {
    var version = 1
    var records: [DayRecord] = []
    var goals = PersonalGoals()
}

@MainActor final class JournalStore: ObservableObject {
    @Published private(set) var records: [DayRecord] = []
    @Published private(set) var goals = PersonalGoals()
    @Published private(set) var loadError: String?
    private let url: URL

    init() {
        url = URL.applicationSupportDirectory.appendingPathComponent("Rhythm", isDirectory: true).appendingPathComponent("journal.json")
        // Loading happens once the app is in the foreground, when protected data is accessible.
    }

    func load() {
        do {
            guard FileManager.default.fileExists(atPath: url.path) else { records = []; goals = PersonalGoals(); loadError = nil; return }
            let saved = try JSONDecoder().decode(JournalEnvelope.self, from: Data(contentsOf: url))
            guard saved.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
            guard saved.records.allSatisfy({ HealthMath.validate($0) == nil }),
                  (60...960).contains(saved.goals.sleepMinutes), (0...1440).contains(saved.goals.screenMinutes) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            records = saved.records
            goals = saved.goals
            loadError = nil
        } catch {
            loadError = "記録を読み込めませんでした。元の記録を守るため、保存を停止しています。アプリを閉じて、端末を解除してから再度お試しください。"
        }
    }

    func upsert(_ record: DayRecord) throws {
        if let message = HealthMath.validate(record) { throw StoreError.message(message) }
        var next = records.filter { $0.day != record.day }
        if !record.isEmpty { next.append(record) }
        try persist(records: next, goals: goals)
        records = next.sorted { $0.day > $1.day }
    }

    func delete(day: Date) throws {
        let next = records.filter { $0.day != day }
        try persist(records: next, goals: goals)
        records = next
    }

    func saveGoals(_ next: PersonalGoals) throws {
        guard (60...960).contains(next.sleepMinutes), (0...1440).contains(next.screenMinutes) else {
            throw StoreError.message("目標値を確認してください。")
        }
        try persist(records: records, goals: next)
        goals = next
    }

    private func persist(records: [DayRecord], goals: PersonalGoals) throws {
        guard loadError == nil else { throw StoreError.message(loadError!) }
        var folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let data = try JSONEncoder().encode(JournalEnvelope(records: records, goals: goals))
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    enum StoreError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
}
