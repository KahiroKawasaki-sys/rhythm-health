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

    static let minuteRange = 1...60
    static let budgetRange = 0...240

    var isValid: Bool {
        [workMinutes, playMinutes, idleMinutes].allSatisfy(Self.minuteRange.contains) && Self.budgetRange.contains(dailyPlayBudget)
    }

    func minutes(for purpose: GatePurpose) -> Int {
        switch purpose {
        case .work: return workMinutes
        case .play: return playMinutes
        case .idle: return idleMinutes
        }
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

    /// 夜（22:00〜翌4:00）と朝（4:00〜9:00）は待機を2倍にする。
    static func isQuietHours(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 22 || hour < 9
    }

    /// 待機秒数 = min(5 + n × 5, 60)。夜と朝は2倍（上限60）。予算超過中は60秒に固定。仕事は待機しない。
    static func waitSeconds(for purpose: GatePurpose, at date: Date, events: [GateEvent], settings: GateSettings,
                            calendar: Calendar = .current) -> Int {
        guard purpose.countsTowardBudget else { return 0 }
        if isOverBudget(on: date, events, settings: settings, calendar: calendar) { return maxWaitSeconds }
        let n = casualChoices(on: date, events, calendar: calendar)
        let base = min(5 + n * 5, maxWaitSeconds)
        return isQuietHours(date, calendar: calendar) ? min(base * 2, maxWaitSeconds) : base
    }

    static func emergencyAvailable(on day: Date, _ events: [GateEvent], calendar: Calendar = .current) -> Bool {
        !Self.events(on: day, events, calendar: calendar).contains { $0.kind == .emergency }
    }

    static func todayCounts(_ day: Date, _ events: [GateEvent], calendar: Calendar = .current) -> (opened: Int, stayedAway: Int) {
        let today = Self.events(on: day, events, calendar: calendar)
        return (today.filter { $0.kind == .opened || $0.kind == .emergency }.count, today.filter { $0.kind == .stayedAway }.count)
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
