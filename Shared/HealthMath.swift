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
