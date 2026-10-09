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

/// 振り返りの期間。どれも昨日までで、前の同じ長さの期間と比べる。
enum ReviewPeriod: String, CaseIterable, Identifiable, Codable {
    case week, month, quarter, year
    var id: String { rawValue }
    var label: String { ["週", "月", "3か月", "年"][Self.allCases.firstIndex(of: self)!] }
    var dayCount: Int { [7, 30, 90, 365][Self.allCases.firstIndex(of: self)!] }
    var comparisonLabel: String { ["前の7日", "前の30日", "前の3か月", "前の1年"][Self.allCases.firstIndex(of: self)!] }
    /// 3か月は週平均、1年は月平均の棒で見せる。
    var isLong: Bool { self == .quarter || self == .year }
    var bucketUnit: BucketUnit { self == .year ? .month : .week }
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

struct SeriesPoint: Identifiable, Equatable {
    var start: Date
    var value: Double?
    var id: Date { start }
}

struct PeriodSummary: Equatable {
    var average: Double?
    var recordedDays: Int
    var totalDays: Int
    var delta: Double?
}

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
        completedDays(count: period.dayCount, now: now, calendar: calendar)
    }

    /// 直前の同じ日数。
    static func comparisonDays(_ period: ReviewPeriod, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        Array(completedDays(count: period.dayCount * 2, now: now, calendar: calendar).prefix(period.dayCount))
    }

    /// 表示・比較・7日移動平均・睡眠の前日正午窓に必要な最古の日。
    static func fetchStart(_ period: ReviewPeriod, now: Date = .now, calendar: Calendar = .current) -> Date {
        let earliest = comparisonDays(period, now: now, calendar: calendar).first ?? calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -7, to: earliest) ?? earliest
    }

    /// 振り返りのカレンダー。月曜始まりの5週間（35日）。offset 0は昨日を含む週で終わり、1ずつ35日前へ。
    static func calendarWeeks(offset: Int, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return [] }
        // weekday: 1=日曜。その週の日曜まで進める。
        let toSunday = (8 - calendar.component(.weekday, from: yesterday)) % 7
        guard let lastSunday = calendar.date(byAdding: .day, value: toSunday - 35 * offset, to: yesterday) else { return [] }
        return (0..<35).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: lastSunday) }
    }

    /// その日を含むカレンダーの offset。表示拡張は受け取ったデータの日付から表示中の5週間を割り出す。
    static func calendarOffset(containing day: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        guard let last = calendarWeeks(offset: 0, now: now, calendar: calendar).last,
              let distance = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: last).day, distance >= 0 else { return 0 }
        return distance / 35
    }

    /// 期間のグラフ用の系列。週・月は日ごと、3か月は週平均、1年は月平均。値のない区間はnil。
    static func series(_ values: [Date: Double], period: ReviewPeriod, now: Date = .now, calendar: Calendar = .current) -> [SeriesPoint] {
        let days = periodDays(period, now: now, calendar: calendar)
        guard period.isLong else { return days.map { SeriesPoint(start: $0, value: values[$0]) } }
        return buckets(values, days: days, unit: period.bucketUnit, calendar: calendar).map { SeriesPoint(start: $0.start, value: $0.average) }
    }

    /// 期間の1日平均と、前の同じ長さの期間との差。
    static func periodSummary(_ values: [Date: Double], period: ReviewPeriod, now: Date = .now, calendar: Calendar = .current) -> PeriodSummary {
        let current = periodDays(period, now: now, calendar: calendar).compactMap { values[$0] }
        let previous = comparisonDays(period, now: now, calendar: calendar).compactMap { values[$0] }
        let mean = Self.average(current.map(Optional.some))
        let before = Self.average(previous.map(Optional.some))
        var delta: Double?
        if let mean, let before { delta = mean - before }
        return PeriodSummary(average: mean, recordedDays: current.count, totalDays: period.dayCount, delta: delta)
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

// MARK: 今日の画面（同じ時刻までの比較・連続日数）
extension HealthMath {
    /// 1時間ごとの値（開始時刻→値）から、各日の0時からelapsed秒までの合計。途中の1時間は按分する。
    /// その日に1件も値がない日は「記録なし」として結果に含めない（0扱いしない）。
    static func totalsUntil(_ hourly: [Date: Double], days: [Date], elapsed: TimeInterval,
                            calendar: Calendar = .current) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for day in days {
            var total = 0.0
            var seen = false
            for hour in 0..<24 {
                guard let start = calendar.date(byAdding: .hour, value: hour, to: day), let value = hourly[start] else { continue }
                seen = true
                total += value * min(max((elapsed - Double(hour) * 3600) / 3600, 0), 1)
            }
            if seen { result[day] = total }
        }
        return result
    }

    /// 1時間ごとの値を日ごとに合計する。
    static func dailyTotals(_ hourly: [Date: Double], calendar: Calendar = .current) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for (start, value) in hourly { result[calendar.startOfDay(for: start), default: 0] += value }
        return result
    }

    /// 今日の前日から遡り、値が目標以下の日が続いた日数。記録のない日か目標を超えた日で止まる。
    static func streak(_ daily: [Date: Double], goal: Double, today: Date, limit: Int, calendar: Calendar = .current) -> Int {
        var count = 0
        var day = calendar.startOfDay(for: today)
        while count < limit {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day),
                  let value = daily[previous], value <= goal else { break }
            count += 1
            day = previous
        }
        return count
    }

    /// その日の中で最初に値が出た時（0〜23時）。
    static func firstHour(_ hourly: [Date: Double], on day: Date, calendar: Calendar = .current) -> Int? {
        let start = calendar.startOfDay(for: day)
        return (0..<24).first { hour in
            calendar.date(byAdding: .hour, value: hour, to: start).flatMap { hourly[$0] }.map { $0 > 0 } ?? false
        }
    }

    /// 1時間未満は「45分」、それ以上は「1時間05分」。
    static func shortDuration(_ minutes: Double) -> String {
        let value = Int(minutes.rounded())
        return value < 60 ? "\(value)分" : "\(value / 60)時間" + String(format: "%02d分", value % 60)
    }
}
