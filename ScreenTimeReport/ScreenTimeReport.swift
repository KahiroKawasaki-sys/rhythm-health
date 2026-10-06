import DeviceActivity
import SwiftUI
import Charts

@main struct RhythmReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        RhythmReportScene(context: .rhythmToday, period: nil, sns: false)
        RhythmReportScene(context: .rhythmWeek, period: .week, sns: false)
        RhythmReportScene(context: .rhythmMonth, period: .month, sns: false)
        RhythmReportScene(context: .rhythmQuarter, period: .quarter, sns: false)
        RhythmReportScene(context: .rhythmYear, period: .year, sns: false)
        RhythmReportScene(context: .rhythmMonthly, period: .monthly, sns: false)
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
    private let green = Color(red: 17/255, green: 90/255, blue: 54/255)
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
                            let level = HealthMath.intensity(configuration.totals[day], maximum: maximum)
                            Text(day.formatted(.dateTime.day())).font(.caption2)
                                .frame(maxWidth: .infinity, minHeight: 30)
                                .foregroundStyle((level ?? 0) > 0.6 ? Color.white : Color.primary)
                                .background(level.map { green.opacity(0.12 + $0 * 0.88) } ?? Color.clear, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(level == nil ? 0.3 : 0), style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                                .accessibilityLabel(day.formatted(.dateTime.month().day()) + " " + (configuration.totals[day].map { HealthMath.duration(Int($0.rounded())) } ?? "Apple側に記録なし"))
                        } else { Color.clear.frame(minHeight: 30) }
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
