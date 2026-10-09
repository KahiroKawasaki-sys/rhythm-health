import Foundation

/// 開く前に選ぶ目的。仕事は遊び予算に計上しない。
enum GatePurpose: String, Codable, CaseIterable, Identifiable, Sendable {
    case work, play, idle
    var id: String { rawValue }
    var label: String {
        switch self {
        case .work: return "仕事・情報収集"
        case .play: return "遊び"
        case .idle: return "なんとなく"
        }
    }
    var countsTowardBudget: Bool { self != .work }
}

/// ゲートの記録。スクリーンタイムの利用時間の値そのものは含めない（到達ラインだけを残す）。
struct GateEvent: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case stayedAway   // シールドまたは目的選択で「やめておく」
        case opened       // 目的を選んで解除
        case emergency    // 1日1回の緊急解除（予算外）
        case harvest      // 仕事の解除後の「収穫あった？」への回答
        case reach        // 対象アプリの合計が到達ラインを越えた（おおよその値）
    }
    var date: Date
    var kind: Kind
    var purpose: GatePurpose?
    /// opened・emergencyは解除した分数、reachは到達ラインの分数。
    var minutes: Int?
    /// 仕事のときの「何を調べる？」。端末内にだけ保存する。
    var note: String?
    var harvested: Bool?
}

struct GateSettings: Codable, Equatable, Sendable {
    var workMinutes = 15
    var playMinutes = 10
    var idleMinutes = 5
    var dailyPlayBudget = 30
    /// ゲートを強める（待機を2倍にする）時。0〜23時。初期値は夜22時〜朝9時（v1.1の固定値）。
    var strongHours: Set<Int> = Self.defaultStrongHours

    static let minuteRange = 1...60
    static let budgetRange = 0...240
    static let defaultStrongHours = Set(Array(22...23) + Array(0...8))

    var isValid: Bool {
        [workMinutes, playMinutes, idleMinutes].allSatisfy(Self.minuteRange.contains) && Self.budgetRange.contains(dailyPlayBudget)
            && strongHours.allSatisfy((0...23).contains)
    }

    func minutes(for purpose: GatePurpose) -> Int {
        switch purpose {
        case .work: return workMinutes
        case .play: return playMinutes
        case .idle: return idleMinutes
        }
    }
}

extension GateSettings {
    /// v1.1の設定ファイルには strongHours がないので、ないときは初期値を使う。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workMinutes = try container.decode(Int.self, forKey: .workMinutes)
        playMinutes = try container.decode(Int.self, forKey: .playMinutes)
        idleMinutes = try container.decode(Int.self, forKey: .idleMinutes)
        dailyPlayBudget = try container.decode(Int.self, forKey: .dailyPlayBudget)
        strongHours = try container.decodeIfPresent(Set<Int>.self, forKey: .strongHours) ?? Self.defaultStrongHours
    }

    /// 「22〜24時・0〜9時」のような表示。
    var strongHoursText: String {
        guard !strongHours.isEmpty else { return "なし" }
        guard strongHours.count < 24 else { return "終日" }
        let sorted = strongHours.sorted()
        var ranges: [(Int, Int)] = []
        for hour in sorted {
            if let last = ranges.last, last.1 == hour { ranges[ranges.count - 1].1 = hour + 1 } else { ranges.append((hour, hour + 1)) }
        }
        // 24時をまたぐ範囲（22〜24時と0〜9時）はつなげて「22〜翌9時」にする。
        if ranges.count > 1, ranges.first!.0 == 0, ranges.last!.1 == 24 {
            let first = ranges.removeFirst()
            ranges[ranges.count - 1].1 = first.1 + 24
        }
        return ranges.map { $0.1 > 24 ? "\($0.0)〜翌\($0.1 - 24)時" : "\($0.0)〜\($0.1)時" }.joined(separator: "・")
    }
}

struct GateSummary: Equatable {
    var opened = 0
    var stayedAway = 0
    var byPurpose: [GatePurpose: Int] = [:]
    var emergencies = 0
    /// 遊び・なんとなくで解除した分数の合計と、記録のある日数。
    var budgetMinutes = 0
    var budgetDays = 0
    var harvestYes = 0
    var harvestAnswered = 0
    /// 日ごとの最大到達ライン（分）。記録のない日は含めない。
    var reachByDay: [Date: Int] = [:]

    var harvestRate: Double? { harvestAnswered == 0 ? nil : Double(harvestYes) / Double(harvestAnswered) }
}

struct MonthlyHarvest: Equatable, Identifiable {
    var month: Date
    var yes: Int
    var answered: Int
    var id: Date { month }
    var rate: Double? { answered == 0 ? nil : Double(yes) / Double(answered) }
}

enum GateMath {
    static let reachLines = [15, 30, 60, 90, 120]
    static let maxWaitSeconds = 60
    static let emergencyMinutes = 15
    /// DeviceActivityの監視は15分より短い区間を受け付けない。
    static let minimumMonitorMinutes = 15
    static let disableWaitSeconds = 60

    static func events(on day: Date, _ events: [GateEvent], calendar: Calendar = .current) -> [GateEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events.filter { $0.date >= start && $0.date < end }
    }

    /// 同じ日の「遊び＋なんとなく」の選択回数。
    static func casualChoices(on day: Date, _ events: [GateEvent], calendar: Calendar = .current) -> Int {
        Self.events(on: day, events, calendar: calendar).filter { $0.kind == .opened && $0.purpose?.countsTowardBudget == true }.count
    }

    /// 遊び・なんとなくで解除した分数の合計（早く閉じても解除した分で数える）。
    static func budgetUsed(on day: Date, _ events: [GateEvent], calendar: Calendar = .current) -> Int {
        Self.events(on: day, events, calendar: calendar)
            .filter { $0.kind == .opened && $0.purpose?.countsTowardBudget == true }
            .reduce(0) { $0 + ($1.minutes ?? 0) }
    }

    static func isOverBudget(on day: Date, _ events: [GateEvent], settings: GateSettings, calendar: Calendar = .current) -> Bool {
        budgetUsed(on: day, events, calendar: calendar) >= settings.dailyPlayBudget
    }

    /// 設定でゲートを強めた時（初期値は夜22時〜朝9時）は待機を2倍にする。
    static func isStrongHours(_ date: Date, settings: GateSettings, calendar: Calendar = .current) -> Bool {
        settings.strongHours.contains(calendar.component(.hour, from: date))
    }

    /// 待機秒数 = min(5 + n × 5, 60)。ゲートを強めた時は2倍（上限60）。予算超過中は60秒に固定。仕事は待機しない。
    static func waitSeconds(for purpose: GatePurpose, at date: Date, events: [GateEvent], settings: GateSettings,
                            calendar: Calendar = .current) -> Int {
        guard purpose.countsTowardBudget else { return 0 }
        if isOverBudget(on: date, events, settings: settings, calendar: calendar) { return maxWaitSeconds }
        let n = casualChoices(on: date, events, calendar: calendar)
        let base = min(5 + n * 5, maxWaitSeconds)
        return isStrongHours(date, settings: settings, calendar: calendar) ? min(base * 2, maxWaitSeconds) : base
    }

    static func emergencyAvailable(on day: Date, _ events: [GateEvent], calendar: Calendar = .current) -> Bool {
        !Self.events(on: day, events, calendar: calendar).contains { $0.kind == .emergency }
    }

    static func todayCounts(_ day: Date, _ events: [GateEvent], calendar: Calendar = .current) -> (opened: Int, stayedAway: Int) {
        let today = Self.events(on: day, events, calendar: calendar)
        return (today.filter { $0.kind == .opened || $0.kind == .emergency }.count, today.filter { $0.kind == .stayedAway }.count)
    }

    /// その日に「仕事」で解除した分数の合計。実際に使った時間ではなく、解除した分で数える（おおよそ）。
    static func workMinutes(on day: Date, _ events: [GateEvent], calendar: Calendar = .current) -> Int {
        Self.events(on: day, events, calendar: calendar)
            .filter { $0.kind == .opened && $0.purpose == .work }
            .reduce(0) { $0 + ($1.minutes ?? 0) }
    }

    /// 開こうとした回数（開いた・緊急・やめておく）と踏みとどまった回数の1日平均。
    /// 最初の記録より前の日は数えない。対象の日がなければnil。
    static func dailyAverages(_ days: [Date], _ events: [GateEvent], calendar: Calendar = .current)
        -> (attempts: Double, stayedAway: Double)? {
        guard let first = events.map(\.date).min().map({ calendar.startOfDay(for: $0) }) else { return nil }
        let counted = days.filter { $0 >= first }
        guard !counted.isEmpty else { return nil }
        let totals = counted.map { todayCounts($0, events, calendar: calendar) }
        let attempts = totals.reduce(0) { $0 + $1.opened + $1.stayedAway }
        let stayed = totals.reduce(0) { $0 + $1.stayedAway }
        return (Double(attempts) / Double(counted.count), Double(stayed) / Double(counted.count))
    }

    /// 再遮断の監視区間。15分未満の解除は、開始を過去にずらして15分の区間にする（実機で要確認）。
    static func unlockWindow(from now: Date, minutes: Int) -> DateInterval {
        let end = now.addingTimeInterval(TimeInterval(minutes * 60))
        let length = TimeInterval(max(minutes, minimumMonitorMinutes) * 60)
        return DateInterval(start: end.addingTimeInterval(-length), end: end)
    }

    static func summary(_ events: [GateEvent], days: [Date], calendar: Calendar = .current) -> GateSummary {
        let wanted = Set(days.map { calendar.startOfDay(for: $0) })
        var result = GateSummary()
        var budgetDays = Set<Date>()
        for event in events {
            let day = calendar.startOfDay(for: event.date)
            guard wanted.contains(day) else { continue }
            switch event.kind {
            case .stayedAway: result.stayedAway += 1
            case .emergency: result.opened += 1; result.emergencies += 1
            case .opened:
                result.opened += 1
                if let purpose = event.purpose {
                    result.byPurpose[purpose, default: 0] += 1
                    if purpose.countsTowardBudget { result.budgetMinutes += event.minutes ?? 0; budgetDays.insert(day) }
                }
            case .harvest:
                guard let harvested = event.harvested else { continue }
                result.harvestAnswered += 1
                if harvested { result.harvestYes += 1 }
            case .reach:
                if let minutes = event.minutes { result.reachByDay[day] = max(result.reachByDay[day] ?? 0, minutes) }
            }
        }
        result.budgetDays = budgetDays.count
        return result
    }

    /// 仕事の収穫率（月ごと）。回答のない月は除く。
    static func monthlyHarvest(_ events: [GateEvent], calendar: Calendar = .current) -> [MonthlyHarvest] {
        var table: [Date: (yes: Int, answered: Int)] = [:]
        for event in events where event.kind == .harvest {
            guard let harvested = event.harvested, let month = calendar.dateInterval(of: .month, for: event.date)?.start else { continue }
            table[month, default: (0, 0)].answered += 1
            if harvested { table[month, default: (0, 0)].yes += 1 }
        }
        return table.map { MonthlyHarvest(month: $0.key, yes: $0.value.yes, answered: $0.value.answered) }.sorted { $0.month < $1.month }
    }

    /// 1つの到達ラインは1日1回だけ残す。
    static func shouldRecordReach(_ minutes: Int, at date: Date, _ events: [GateEvent], calendar: Calendar = .current) -> Bool {
        reachLines.contains(minutes) && !Self.events(on: date, events, calendar: calendar).contains { $0.kind == .reach && $0.minutes == minutes }
    }

    /// 記録の検証。壊れたファイルを上書きしないために読み込み時に使う。
    static func validate(_ event: GateEvent) -> Bool {
        switch event.kind {
        case .opened: return event.purpose != nil && (event.minutes.map(GateSettings.minuteRange.contains) ?? false)
        case .emergency: return event.minutes == emergencyMinutes
        case .harvest: return event.harvested != nil
        case .reach: return event.minutes.map(reachLines.contains) ?? false
        case .stayedAway: return true
        }
    }
}

// MARK: ホーム画面ウィジェット（P3）

/// ウィジェットに出す項目。App Groupに置き、本体が書いてウィジェットが読む。
/// SNSの分数はAppleの仕組みで出せないため、ゲートの記録から作れる項目だけ。
struct WidgetOptions: Codable, Equatable, Sendable {
    static let kind = "RhythmGate"
    static let appGroup = "group.com.kawakahi.rhythm"

    var showsStayedAway = true
    var showsAttempts = true
    var showsBudget = true

    private static func url() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("Widget", isDirectory: true).appendingPathComponent("options.json")
    }

    static func load() -> WidgetOptions {
        guard let url = url(), let data = try? Data(contentsOf: url),
              let options = try? JSONDecoder().decode(WidgetOptions.self, from: data) else { return WidgetOptions() }
        return options
    }

    func save() throws {
        guard let url = Self.url() else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// ウィジェットの1日分の値。
struct GateDaySnapshot: Equatable, Sendable {
    var attempts: Int
    var stayedAway: Int
    var budgetUsed: Int
    var budget: Int
    var budgetLeft: Int { max(0, budget - budgetUsed) }

    static func make(_ day: Date, _ events: [GateEvent], settings: GateSettings, calendar: Calendar = .current) -> GateDaySnapshot {
        let counts = GateMath.todayCounts(day, events, calendar: calendar)
        return GateDaySnapshot(attempts: counts.opened + counts.stayedAway, stayedAway: counts.stayedAway,
            budgetUsed: GateMath.budgetUsed(on: day, events, calendar: calendar), budget: settings.dailyPlayBudget)
    }
}
