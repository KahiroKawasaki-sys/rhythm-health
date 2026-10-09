import DeviceActivity
import SwiftUI
import Charts

@main struct RhythmReportExtension: DeviceActivityReportExtension {
    // Builder blocks above 10 scenes need iOS 17.4, so the scenes are split into two groups.
    var body: some DeviceActivityReportScene {
        allScenes
        snsScenes
    }

    @DeviceActivityReportBuilder private var allScenes: some DeviceActivityReportScene {
        RhythmReportScene(context: .rhythmToday, period: nil, sns: false)
        RhythmReportScene(context: .rhythmWeek, period: .week, sns: false)
        RhythmReportScene(context: .rhythmMonth, period: .month, sns: false)
        RhythmReportScene(context: .rhythmQuarter, period: .quarter, sns: false)
        RhythmReportScene(context: .rhythmYear, period: .year, sns: false)
        RhythmReportScene(context: .rhythmMonthly, period: .monthly, sns: false)
        TodayCardScene(context: .rhythmTodayCard7, compareDays: 7)
        TodayCardScene(context: .rhythmTodayCard30, compareDays: 30)
    }

    @DeviceActivityReportBuilder private var snsScenes: some DeviceActivityReportScene {
        RhythmReportScene(context: .rhythmSNSWeek, period: .week, sns: true)
        RhythmReportScene(context: .rhythmSNSMonth, period: .month, sns: true)
        RhythmReportScene(context: .rhythmSNSQuarter, period: .quarter, sns: true)
        RhythmReportScene(context: .rhythmSNSYear, period: .year, sns: true)
        RhythmReportScene(context: .rhythmSNSMonthly, period: .monthly, sns: true)
        RhythmCalendarScene(context: .rhythmSNSCalendar, sns: true)
    }
}

struct ScreenDay: Identifiable {
    var day: Date
    var minutes: Double
    var segment: Int = 0
    var id: Date { day }
}

struct ScreenConfiguration {
    var days: [ScreenDay]
    var average: Double?
    var previousAverage: Double?
    var previousCount: Int
    var period: ReviewPeriod?
    var expectedDays: Int = 1
    var buckets: [PeriodBucket] = []
    var month: MonthComparison?
    var sns = false
}

/// Values stay exclusively inside the report extension. No shared defaults, files or networking.
func dailyMinutes(_ data: DeviceActivityResults<DeviceActivityData>, sns: Bool) async -> [Date: Double] {
    let calendar = Calendar.current
    var totals: [Date: Double] = [:]
    for await device in data {
        for await segment in device.activitySegments {
            let day = calendar.startOfDay(for: segment.dateInterval.start)
            guard sns else { totals[day, default: 0] += segment.totalActivityDuration / 60; continue }
            // The host filter limits results to the chosen apps and websites; confirm on a device that totals match.
            var seconds: TimeInterval = 0
            for await category in segment.categories {
                for await app in category.applications { seconds += app.totalActivityDuration }
                for await domain in category.webDomains { seconds += domain.totalActivityDuration }
            }
            totals[day, default: 0] += seconds / 60
        }
    }
    return totals
}

struct RhythmReportScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context
    let period: ReviewPeriod?
    let sns: Bool
    let content: (ScreenConfiguration) -> ScreenReportView = { ScreenReportView(configuration: $0) }

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> ScreenConfiguration {
        let totals = await dailyMinutes(data, sns: sns)
        guard let period else {
            let today = Calendar.current.startOfDay(for: .now)
            let values = totals[today].map { [ScreenDay(day: today, minutes: $0)] } ?? []
            return ScreenConfiguration(days: values, average: values.first?.minutes, previousAverage: nil, previousCount: 0, period: nil)
        }
        let requested = HealthMath.periodDays(period)
        var segment = 0
        let values = requested.compactMap { day -> ScreenDay? in
            guard let minutes = totals[day] else { segment += 1; return nil }
            return ScreenDay(day: day, minutes: minutes, segment: segment)
        }
        let older = HealthMath.comparisonDays(period).compactMap { totals[$0] }
        var configuration = ScreenConfiguration(days: values, average: HealthMath.average(values.map { Optional($0.minutes) }),
            previousAverage: HealthMath.average(older.map(Optional.some)), previousCount: older.count,
            period: period, expectedDays: requested.count, sns: sns)
        if period.isLong {
            configuration.buckets = HealthMath.buckets(totals, days: requested, unit: period == .quarter ? .week : .month)
        }
        if period == .monthly, let last = HealthMath.recentMonths(count: 2).first {
            configuration.month = HealthMath.monthComparison(totals, month: last)
        }
        return configuration
    }
}

struct ScreenReportView: View {
    let configuration: ScreenConfiguration
    private let green = Color(red: 17/255, green: 90/255, blue: 54/255)
    private var noData: String { configuration.sns ? "この期間のSNSの利用はApple側に記録なし" : "この期間の利用データはApple側に記録なし" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let period = configuration.period {
                if configuration.days.isEmpty {
                    Text(noData).font(.subheadline)
                    Text("Appleが保持している期間より前は表示できません。0分という意味ではありません。")
                        .font(.caption).foregroundStyle(.secondary)
                } else if period == .monthly, let month = configuration.month {
                    monthly(month)
                } else if let average = configuration.average {
                    Text(HealthMath.duration(Int(average.rounded()))).font(.system(.title, design: .rounded).weight(.semibold))
                    Text("1日平均 · データ \(configuration.days.count)/\(configuration.expectedDays)日").font(.caption).foregroundStyle(.secondary)
                    if let before = configuration.previousAverage {
                        Text(String(format: "%@より %+.0f分（比較 %d日分）", period.comparisonLabel, average - before, configuration.previousCount))
                            .font(.caption).foregroundStyle(green)
                    } else { Text("比較期間はApple側に記録なし").font(.caption).foregroundStyle(.secondary) }
                    if period.isLong { bucketChart(period) } else { dailyChart(period) }
                }
                Text("出典：Appleスクリーンタイム / 表示時に取得").font(.caption2).foregroundStyle(.secondary)
            } else if let today = configuration.average {
                Text(HealthMath.duration(Int(today.rounded()))).font(.system(.title, design: .rounded).weight(.semibold))
                Text("今日ここまで · 自動取得").font(.caption).foregroundStyle(.secondary)
                Text("出典：Appleスクリーンタイム / 表示時に取得").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("表示できる利用データがありません").font(.subheadline)
                Text("設定でスクリーンタイムを有効にして、iPhoneを利用した後に更新してください。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dailyChart(_ period: ReviewPeriod) -> some View {
        let days = HealthMath.periodDays(period)
        return VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(configuration.days) { day in
                    LineMark(x: .value("日付", day.day), y: .value("時間", day.minutes / 60),
                        series: .value("連続区間", day.segment)).foregroundStyle(green)
                    PointMark(x: .value("日付", day.day), y: .value("時間", day.minutes / 60)).foregroundStyle(green)
                }
            }.chartYScale(domain: 0...max(configuration.sns ? 3 : 8, (configuration.days.map(\.minutes).max() ?? 0) / 60 + 1))
                .chartXScale(domain: days.first!...days.last!)
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: period == .week ? 2 : 7)) { _ in
                    AxisValueLabel(format: .dateTime.month().day())
                } }.frame(height: 150)
            Text("日別の利用時間（時間）· 昨日まで\(days.count)日").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func bucketChart(_ period: ReviewPeriod) -> some View {
        let bars = configuration.buckets.filter { $0.average != nil }
        let weekly = period == .quarter
        return VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(bars) { bucket in
                    BarMark(x: .value(weekly ? "週" : "月", bucket.start, unit: weekly ? .weekOfYear : .month),
                        y: .value("時間", (bucket.average ?? 0) / 60))
                        .foregroundStyle(green.opacity(bucket.isPartial ? 0.4 : 1))
                        .annotation(position: .top) { Text("\(bucket.recordedDays)日").font(.system(size: 8)).foregroundStyle(.secondary) }
                }
            }.chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis { AxisMarks(values: .stride(by: weekly ? .weekOfYear : .month, count: 2)) { _ in
                    AxisValueLabel(format: weekly ? Date.FormatStyle.dateTime.month().day() : Date.FormatStyle.dateTime.month())
                } }.frame(height: 160)
            Text("\(weekly ? "週" : "月")平均の利用時間（時間）· 棒の上はデータのある日数 · 薄い棒は期間の途中")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func monthly(_ month: MonthComparison) -> some View {
        Text(month.month.start.formatted(.dateTime.year().month()) + "の1日平均").font(.caption).foregroundStyle(.secondary)
        Text(month.average.map { HealthMath.duration(Int($0.rounded())) } ?? "Apple側に記録なし")
            .font(.system(.title, design: .rounded).weight(.semibold))
        Text("データ \(month.recordedDays)日").font(.caption).foregroundStyle(.secondary)
        comparison("先月比", now: month.average, before: month.previousMonth, count: month.previousMonthRecorded)
        comparison("前年同月比", now: month.average, before: month.lastYear, count: month.lastYearRecorded)
        bucketChart(.monthly)
    }

    @ViewBuilder private func comparison(_ label: String, now: Double?, before: Double?, count: Int) -> some View {
        if let now, let before {
            Text(String(format: "%@ %+.0f分（比較 %d日分）", label, now - before, count)).font(.caption).foregroundStyle(green)
        } else { Text("\(label)：比較期間はApple側に記録なし").font(.caption).foregroundStyle(.secondary) }
    }
}

struct CalendarConfiguration {
    var month: DateInterval?
    var totals: [Date: Double]
    var sns: Bool
}

struct RhythmCalendarScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context
    let sns: Bool
    let content: (CalendarConfiguration) -> ScreenCalendarView = { ScreenCalendarView(configuration: $0) }

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> CalendarConfiguration {
        let totals = await dailyMinutes(data, sns: sns)
        // The host passes one month per filter, so any recorded day identifies the month.
        let month = totals.keys.min().flatMap { Calendar.current.dateInterval(of: .month, for: $0) }
        return CalendarConfiguration(month: month, totals: totals, sns: sns)
    }
}

struct ScreenCalendarView: View {
    let configuration: CalendarConfiguration
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let month = configuration.month {
                let maximum = configuration.totals.values.max() ?? 0
                let symbols = Calendar.current.veryShortWeekdaySymbols
                let first = Calendar.current.firstWeekday - 1
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(0..<7, id: \.self) { index in
                        Text(symbols[(first + index) % 7]).font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(Array(HealthMath.calendarGrid(month: month).enumerated()), id: \.offset) { _, day in
                        if let day {
                            let minutes: Double? = configuration.totals[day]
                            let value: String = minutes.map { HealthMath.duration(Int($0.rounded())) } ?? "Apple側に記録なし"
                            HeatCell(day: day, level: HealthMath.intensity(minutes, maximum: maximum), detail: value)
                        } else { Color.clear.frame(minHeight: 32) }
                    }
                }
                Text("濃いほど長い（この月の最長 \(HealthMath.duration(Int(maximum.rounded())))）· 無色はApple側に記録なし")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(configuration.sns ? "この月のSNSの利用はApple側に記録なし" : "この月の利用データはApple側に記録なし").font(.subheadline)
                Text("0分という意味ではありません。").font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: 今日の画面のスクリーンタイムカード

struct TodayCardConfiguration {
    var compareDays: Int
    var today: [ScreenCategory: Double] = [:]
    /// 過去N日の、同じ時刻までの平均（記録のある日だけ）。
    var average: [ScreenCategory: Double]?
    var averageDays = 0
    var asOf = Date.now
    var firstHour: Int?
    var averageFirstHour: Double?
    var streak = 0
    var goal = 45
    var hasSNS = false
    var categoryError = false
    var hasData: Bool { !today.isEmpty || average != nil }
    func total(_ values: [ScreenCategory: Double]) -> Double { values.values.reduce(0, +) }
}

/// 本体から1時間ごとの区間（過去30日＋今日）を受け取り、4区分に分けて今日と平均を比べる。
/// 値は拡張の中だけで扱い、外へは出さない（分類はApp Groupから読むだけ）。
struct TodayCardScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context
    let compareDays: Int
    let content: (TodayCardConfiguration) -> TodayCardView = { TodayCardView(configuration: $0) }

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TodayCardConfiguration {
        var configuration = TodayCardConfiguration(compareDays: compareDays)
        let categories: ScreenCategories
        do { categories = try ScreenCategoryFiles.load() ?? ScreenCategories() } catch {
            categories = ScreenCategories(); configuration.categoryError = true
        }
        configuration.goal = categories.snsGoalMinutes
        configuration.hasSNS = !categories.sns.isEmptySelection

        var hourly: [ScreenCategory: [Date: Double]] = [:]
        var total: [Date: Double] = [:]
        for await device in data {
            for await segment in device.activitySegments {
                let start = segment.dateInterval.start
                total[start, default: 0] += segment.totalActivityDuration / 60
                var classified = 0.0
                for await category in segment.categories {
                    let token = category.category.token
                    for await app in category.applications {
                        let kind = categories.classify(application: app.application.token, category: token)
                        guard kind != .other else { continue }
                        hourly[kind, default: [:]][start, default: 0] += app.totalActivityDuration / 60
                        classified += app.totalActivityDuration / 60
                    }
                    for await domain in category.webDomains {
                        let kind = categories.classify(webDomain: domain.webDomain.token, category: token)
                        guard kind != .other else { continue }
                        hourly[kind, default: [:]][start, default: 0] += domain.totalActivityDuration / 60
                        classified += domain.totalActivityDuration / 60
                    }
                }
                hourly[.other, default: [:]][start, default: 0] += max(0, segment.totalActivityDuration / 60 - classified)
            }
        }

        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let elapsed = now.timeIntervalSince(today)
        configuration.asOf = now
        if HealthMath.totalsUntil(total, days: [today], elapsed: 86_400, calendar: calendar)[today] != nil {
            for kind in ScreenCategory.allCases {
                configuration.today[kind] = HealthMath.totalsUntil(hourly[kind] ?? [:], days: [today], elapsed: 86_400,
                    calendar: calendar)[today] ?? 0
            }
        }
        let past = (1...compareDays).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let recorded = Array(HealthMath.totalsUntil(total, days: past, elapsed: elapsed, calendar: calendar).keys)
        if !recorded.isEmpty {
            var average: [ScreenCategory: Double] = [:]
            for kind in ScreenCategory.allCases {
                let values = HealthMath.totalsUntil(hourly[kind] ?? [:], days: recorded, elapsed: elapsed, calendar: calendar)
                average[kind] = recorded.reduce(0) { $0 + (values[$1] ?? 0) } / Double(recorded.count)
            }
            configuration.average = average
            configuration.averageDays = recorded.count
        }

        // P2：最初にSNSを使った時（1時間単位）。P4：目標以下が続いた日数（記録のある日のみ、最大30日）。
        let sns = hourly[.sns] ?? [:]
        configuration.firstHour = HealthMath.firstHour(sns, on: today, calendar: calendar)
        let firsts = past.compactMap { HealthMath.firstHour(sns, on: $0, calendar: calendar) }
        configuration.averageFirstHour = firsts.isEmpty ? nil : Double(firsts.reduce(0, +)) / Double(firsts.count)
        let snsDaily = HealthMath.dailyTotals(sns, calendar: calendar)
        let daily = Dictionary(uniqueKeysWithValues: HealthMath.dailyTotals(total, calendar: calendar).keys.map { ($0, snsDaily[$0] ?? 0) })
        configuration.streak = HealthMath.streak(daily, goal: Double(categories.snsGoalMinutes), today: today, limit: 30,
            calendar: calendar)
        return configuration
    }
}

struct TodayCardView: View {
    let configuration: TodayCardConfiguration
    private let good = Color(red: 17/255, green: 90/255, blue: 54/255)
    private let bad = ScreenCategory.sns.color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if configuration.categoryError {
                Text("アプリの分類を読み込めませんでした。設定から選び直してください。").font(.caption).foregroundStyle(bad)
            }
            if !configuration.hasData {
                Text("表示できる利用データがありません").font(.subheadline)
                Text("iPhoneを利用した後に更新してください。Apple側に記録がない日は0分ではありません。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                hero
                stack
                legend
                if let average = configuration.average {
                    compareBars(today: configuration.today[.sns] ?? 0, average: average[.sns] ?? 0)
                    Text("平均＝過去\(configuration.compareDays)日のうち記録のある\(configuration.averageDays)日の、同じ時刻（\(configuration.asOf.formatted(date: .omitted, time: .shortened))）までのSNS")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Divider()
                facts
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hero: some View {
        let sns = configuration.today[.sns] ?? 0
        let total = configuration.total(configuration.today)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle().fill(ScreenCategory.sns.color).frame(width: 7, height: 7)
                    Text(configuration.hasSNS ? "SNS" : "SNS（設定で未選択）")
                }.font(.caption).foregroundStyle(.secondary)
                Text(HealthMath.shortDuration(sns)).font(.system(.largeTitle, design: .rounded).weight(.semibold))
                chip(configuration.average.map { sns - ($0[.sns] ?? 0) })
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("合計").font(.caption).foregroundStyle(.secondary)
                Text(HealthMath.shortDuration(total)).font(.system(.title2, design: .rounded).weight(.semibold))
                chip(configuration.average.map { total - configuration.total($0) })
            }
        }
    }

    /// SNSと合計だけ、多い＝朱／少ない＝緑で示す。
    @ViewBuilder private func chip(_ delta: Double?) -> some View {
        if let delta {
            if abs(delta) < 1 {
                Text("± 平均と同じ").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            } else {
                let more = delta > 0
                Text("\(more ? "↑" : "↓") \(HealthMath.shortDuration(abs(delta))) 平均より\(more ? "多い" : "少ない")")
                    .font(.caption.weight(.medium)).foregroundStyle(more ? bad : good)
            }
        } else {
            Text("平均はまだありません").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var stack: some View {
        let total = max(configuration.total(configuration.today), 1)
        let parts = ScreenCategory.allCases.filter { (configuration.today[$0] ?? 0) > 0 }
        let gaps = Double(max(parts.count - 1, 0)) * 2
        let description = ScreenCategory.allCases.map { kind -> String in
            let minutes: Double = configuration.today[kind] ?? 0
            return kind.label + " " + HealthMath.shortDuration(minutes)
        }.joined(separator: "、")
        return GeometryReader { proxy in
            let usable: Double = Double(proxy.size.width) - gaps
            HStack(spacing: 2) {
                ForEach(parts) { kind in
                    let share: Double = (configuration.today[kind] ?? 0) / total
                    Rectangle().fill(kind.color).frame(width: CGFloat(max(2, usable * share)))
                }
            }
        }.frame(height: 10).background(Color.secondary.opacity(0.12)).clipShape(Capsule())
            .accessibilityElement()
            .accessibilityLabel("合計の内訳：" + description)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(ScreenCategory.allCases) { kind in
                HStack(spacing: 4) {
                    Circle().fill(kind.color).frame(width: 7, height: 7)
                    Text("\(kind.label) \(HealthMath.shortDuration(configuration.today[kind] ?? 0))")
                        .fontWeight(kind == .sns ? .semibold : .regular)
                }
            }
        }.font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
    }

    private func compareBars(today: Double, average: Double) -> some View {
        let maximum = max(today, average, 1) * 1.08
        return VStack(spacing: 6) {
            bar("今日", today, maximum, ScreenCategory.sns.color)
            bar("平均", average, maximum, Color.secondary.opacity(0.45))
        }
    }

    private func bar(_ label: String, _ value: Double, _ maximum: Double, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption2).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
            GeometryReader { proxy in
                Capsule().fill(Color.secondary.opacity(0.12))
                    .overlay(alignment: .leading) { Capsule().fill(color).frame(width: CGFloat(Double(proxy.size.width) * (value / maximum))) }
            }.frame(height: 8)
            Text(HealthMath.shortDuration(value)).font(.caption2.monospacedDigit()).frame(width: 64, alignment: .trailing)
        }
    }

    private var facts: some View {
        HStack(alignment: .top, spacing: 12) {
            fact("最初のSNS", configuration.firstHour.map { "\($0)時台" } ?? "まだなし",
                 configuration.averageFirstHour.map { String(format: "平均 %.1f時", $0) } ?? "")
            fact("目標\(configuration.goal)分以下", "\(configuration.streak)日連続", "昨日まで（最大30日）",
                 color: configuration.streak > 0 ? good : nil)
        }
    }

    private func fact(_ label: String, _ value: String, _ note: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(color ?? .primary)
            if !note.isEmpty { Text(note).font(.caption2).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
