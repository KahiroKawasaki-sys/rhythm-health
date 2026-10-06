import Foundation

struct TimedWeight: Sendable {
    var date: Date
    var kilograms: Double
}

struct SleepSpan: Sendable {
    var start: Date
    var end: Date
}

struct DayRecord: Codable, Identifiable, Equatable {
    var day: Date
    var weight: Double?
    var sleepMinutes: Int?
    var screenMinutes: Int?
    var mood: Int?
    var note: String = ""
    var id: Date { day }
    var isEmpty: Bool {
        weight == nil && sleepMinutes == nil && screenMinutes == nil && mood == nil && note.isEmpty
    }
}

struct DailyHealth: Identifiable {
    var day: Date
    var weight: Double?
    var sleepMinutes: Int?
    var weightSource: String = "Apple Health"
    var sleepSource: String = "Apple Health"
    var id: Date { day }
}

struct PersonalGoals: Codable {
    // Personal starting values, not medical recommendations.
    var sleepMinutes: Int = 450
    var screenMinutes: Int = 180
}

enum HealthMath {
    static func completedDays(count: Int, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (1...count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    static func latestWeights(_ samples: [TimedWeight], calendar: Calendar = .current) -> [Date: Double] {
        var latest: [Date: TimedWeight] = [:]
        for sample in samples where sample.kilograms.isFinite && sample.kilograms > 0 {
            let day = calendar.startOfDay(for: sample.date)
            if latest[day].map({ $0.date < sample.date }) ?? true { latest[day] = sample }
        }
        return latest.mapValues(\.kilograms)
    }

    static func mergedDuration(_ samples: [SleepSpan], during window: DateInterval) -> TimeInterval {
        let ranges = samples.compactMap { sample -> SleepSpan? in
            let start = max(sample.start, window.start)
            let end = min(sample.end, window.end)
            return start < end ? SleepSpan(start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
        guard var current = ranges.first else { return 0 }
        var total: TimeInterval = 0
        for next in ranges.dropFirst() {
            if next.start <= current.end { current.end = max(current.end, next.end) }
            else { total += current.end.timeIntervalSince(current.start); current = next }
        }
        return total + current.end.timeIntervalSince(current.start)
    }

    static func sleepByDay(_ samples: [SleepSpan], days: [Date], calendar: Calendar = .current) -> [Date: Int] {
        var result: [Date: Int] = [:]
        for day in days {
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
            let previousNoon = calendar.date(byAdding: .day, value: -1, to: noon)!
            let duration = mergedDuration(samples, during: DateInterval(start: previousNoon, end: noon))
            if duration > 0 { result[day] = Int((duration / 60).rounded()) }
        }
        return result
    }

    static func resolve(days: [Date], weights: [Date: Double], sleep: [Date: Int], manual: [DayRecord]) -> [DailyHealth] {
        let records = Dictionary(manual.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        return days.map { day in
            let override = records[day]
            return DailyHealth(day: day, weight: override?.weight ?? weights[day],
                sleepMinutes: override?.sleepMinutes ?? sleep[day],
                weightSource: override?.weight == nil ? "Apple Health" : "手入力",
                sleepSource: override?.sleepMinutes == nil ? "Apple Health" : "手入力")
        }
    }

    static func average(_ values: [Double?]) -> Double? {
        let present = values.compactMap { $0 }.filter(\.isFinite)
        guard !present.isEmpty else { return nil }
        return present.reduce(0, +) / Double(present.count)
    }

    static func validate(_ record: DayRecord, now: Date = .now, calendar: Calendar = .current) -> String? {
        if record.day > calendar.startOfDay(for: now) { return "未来の日付には記録できません。" }
        if let v = record.weight, !v.isFinite || !(20...400).contains(v) { return "体重は20〜400kgで入力してください。" }
        if let v = record.sleepMinutes, !(0...1440).contains(v) { return "睡眠は0分〜24時間で入力してください。" }
        if let v = record.screenMinutes, !(0...1440).contains(v) { return "スマホ時間は0分〜24時間で入力してください。" }
        if let v = record.mood, !(1...5).contains(v) { return "体調は1〜5で選んでください。" }
        if record.note.count > 500 { return "メモは500文字以内にしてください。" }
        return nil
    }

    static func duration(_ minutes: Int?) -> String {
        guard let minutes else { return "未記録" }
        return "\(minutes / 60)時間\(minutes % 60)分"
    }
}

enum ReviewPeriod: String, CaseIterable, Identifiable, Codable {
    case week, month, quarter, year, monthly
    var id: String { rawValue }
    var label: String { ["7日", "28日", "3か月", "1年", "月別"][Self.allCases.firstIndex(of: self)!] }
    var dayCount: Int? { [7, 28, 90, 365, nil][Self.allCases.firstIndex(of: self)!] }
    var comparisonLabel: String {
        if self == .year { return "前年同期間" }
        if self == .monthly { return "先月" }
        return "前の\(dayCount ?? 0)日"
    }
    /// 90日以上は日々の値より平均の形で見せる。
    var isLong: Bool { self == .quarter || self == .year || self == .monthly }
}

struct PeriodBucket: Identifiable, Equatable {
    var start: Date
    var average: Double?
    var recordedDays: Int
    var totalDays: Int
    var isPartial: Bool
    var id: Date { start }
}

struct MonthComparison: Equatable {
    var month: DateInterval
    var average: Double?
    var recordedDays: Int
    var previousMonth: Double?
    var previousMonthRecorded: Int
    var lastYear: Double?
    var lastYearRecorded: Int
}

enum BucketUnit { case week, month }

extension HealthMath {
    static func days(from start: Date, through end: Date, calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day <= last {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// 今月を最後に古い順。
    static func recentMonths(count: Int = 12, now: Date = .now, calendar: Calendar = .current) -> [DateInterval] {
        (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: now).flatMap { calendar.dateInterval(of: .month, for: $0) }
        }
    }

    /// 区間のうち今日より前の日。当日の途中データは含めない。
    static func completedDays(in interval: DateInterval, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        let end = min(interval.end, calendar.startOfDay(for: now))
        guard interval.start < end, let last = calendar.date(byAdding: .day, value: -1, to: end) else { return [] }
        return days(from: interval.start, through: last, calendar: calendar)
    }

    static func periodDays(_ period: ReviewPeriod, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        if let count = period.dayCount { return completedDays(count: count, now: now, calendar: calendar) }
        guard let first = recentMonths(count: 12, now: now, calendar: calendar).first else { return [] }
        return completedDays(in: DateInterval(start: first.start, end: now), now: now, calendar: calendar)
    }

    /// 7・28・90日は直前の同日数、1年は前年同期間、月別は月ごとに比べるので空。
    static func comparisonDays(_ period: ReviewPeriod, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        switch period {
        case .monthly: return []
        case .year:
            let shifted = periodDays(.year, now: now, calendar: calendar).compactMap {
                calendar.date(byAdding: .year, value: -1, to: $0).map { calendar.startOfDay(for: $0) }
            }
            return Array(Set(shifted)).sorted()
        default:
            let count = period.dayCount ?? 0
            return Array(completedDays(count: count * 2, now: now, calendar: calendar).prefix(count))
        }
    }

    /// 表示・比較・7日移動平均・睡眠の前日正午窓に必要な最古の日。
    static func fetchStart(_ period: ReviewPeriod, now: Date = .now, calendar: Calendar = .current) -> Date {
        var earliest = calendar.startOfDay(for: now)
        if period == .monthly {
            let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? earliest
            earliest = calendar.date(byAdding: .month, value: -13, to: thisMonth) ?? thisMonth
        } else if let first = (periodDays(period, now: now, calendar: calendar) + comparisonDays(period, now: now, calendar: calendar)).min() {
            earliest = first
        }
        return calendar.date(byAdding: .day, value: -7, to: earliest) ?? earliest
    }

    static func monthComparison(_ values: [Date: Double], month: DateInterval, now: Date = .now, calendar: Calendar = .current) -> MonthComparison {
        func summary(_ interval: DateInterval?) -> (average: Double?, count: Int) {
            guard let interval else { return (nil, 0) }
            let present = completedDays(in: interval, now: now, calendar: calendar).compactMap { values[$0] }
            return (average(present.map(Optional.some)), present.count)
        }
        func shifted(_ component: Calendar.Component) -> DateInterval? {
            calendar.date(byAdding: component, value: -1, to: month.start).flatMap { calendar.dateInterval(of: .month, for: $0) }
        }
        let current = summary(month), previous = summary(shifted(.month)), lastYear = summary(shifted(.year))
        return MonthComparison(month: month, average: current.average, recordedDays: current.count,
            previousMonth: previous.average, previousMonthRecorded: previous.count,
            lastYear: lastYear.average, lastYearRecorded: lastYear.count)
    }

    /// 当日を含む過去window日の記録の平均。記録がminimumCount未満の日は欠測。
    static func movingAverage(_ values: [Date: Double], on days: [Date], window: Int = 7, minimumCount: Int = 3,
                              calendar: Calendar = .current) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for day in days {
            let present = (0..<window).compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: day).flatMap { values[calendar.startOfDay(for: $0)] }
            }.filter(\.isFinite)
            if present.count >= minimumCount { result[day] = present.reduce(0, +) / Double(present.count) }
        }
        return result
    }

    static func buckets(_ values: [Date: Double], days: [Date], unit: BucketUnit, calendar: Calendar = .current) -> [PeriodBucket] {
        let component: Calendar.Component = unit == .week ? .weekOfYear : .month
        var groups: [Date: (interval: DateInterval, days: [Date])] = [:]
        for day in days {
            guard let interval = calendar.dateInterval(of: component, for: day) else { continue }
            groups[interval.start, default: (interval, [])].days.append(day)
        }
        return groups.values.map { group in
            let present = group.days.compactMap { values[$0] }
            let full = completedDays(in: group.interval, now: .distantFuture, calendar: calendar).count
            return PeriodBucket(start: group.interval.start, average: average(present.map(Optional.some)),
                recordedDays: present.count, totalDays: group.days.count, isPartial: group.days.count < full)
        }.sorted { $0.start < $1.start }
    }

    /// 月初の曜日まで nil を詰めた1か月分のマス。末尾は埋めない。
    static func calendarGrid(month: DateInterval, calendar: Calendar = .current) -> [Date?] {
        let leading = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + completedDays(in: month, now: .distantFuture, calendar: calendar).map(Optional.some)
    }

    /// カレンダーの濃淡。未記録はnilのまま返し、0扱いしない。
    static func intensity(_ value: Double?, maximum: Double) -> Double? {
        guard let value else { return nil }
        guard maximum > 0 else { return 0 }
        return min(max(value / maximum, 0), 1)
    }
}
