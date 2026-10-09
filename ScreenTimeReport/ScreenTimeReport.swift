import DeviceActivity
import SwiftUI
import Charts

@main struct RhythmReportExtension: DeviceActivityReportExtension {
    // Builder blocks above 10 scenes need iOS 17.4, so the scenes are split into groups.
    var body: some DeviceActivityReportScene {
        todayScenes
        chartScenes
        rowScenes
    }

    @DeviceActivityReportBuilder private var todayScenes: some DeviceActivityReportScene {
        TodayCardScene(context: .rhythmTodayCard7, compareDays: 7)
        TodayCardScene(context: .rhythmTodayCard30, compareDays: 30)
        DetailScene(context: .rhythmDetail(.today), range: .today)
        DetailScene(context: .rhythmDetail(.average7), range: .average7)
        DetailScene(context: .rhythmDetail(.average30), range: .average30)
        CalendarScene(context: .rhythmReviewCalendar(.sns), metric: .sns)
        CalendarScene(context: .rhythmReviewCalendar(.total), metric: .total)
    }

    @DeviceActivityReportBuilder private var chartScenes: some DeviceActivityReportScene {
        ReviewChartScene(context: .rhythmReviewChart(.sns, .week), metric: .sns, period: .week)
        ReviewChartScene(context: .rhythmReviewChart(.sns, .month), metric: .sns, period: .month)
        ReviewChartScene(context: .rhythmReviewChart(.sns, .quarter), metric: .sns, period: .quarter)
        ReviewChartScene(context: .rhythmReviewChart(.sns, .year), metric: .sns, period: .year)
        ReviewChartScene(context: .rhythmReviewChart(.total, .week), metric: .total, period: .week)
        ReviewChartScene(context: .rhythmReviewChart(.total, .month), metric: .total, period: .month)
        ReviewChartScene(context: .rhythmReviewChart(.total, .quarter), metric: .total, period: .quarter)
        ReviewChartScene(context: .rhythmReviewChart(.total, .year), metric: .total, period: .year)
    }

    @DeviceActivityReportBuilder private var rowScenes: some DeviceActivityReportScene {
        ReviewRowsScene(context: .rhythmReviewRows(.week), period: .week)
        ReviewRowsScene(context: .rhythmReviewRows(.month), period: .month)
        ReviewRowsScene(context: .rhythmReviewRows(.quarter), period: .quarter)
        ReviewRowsScene(context: .rhythmReviewRows(.year), period: .year)
    }
}

// MARK: 分類（拡張の中だけで使う）

/// 区間（時間・日）ごとの合計と4区分。区間の開始時刻がキー。
struct Classified {
    var total: [Date: Double] = [:]
    var parts: [ScreenCategory: [Date: Double]] = [:]
    /// SNSのアプリ・サイト名ごと（詳細画面だけで集める）。
    var snsItems: [String: [Date: Double]] = [:]

    func values(_ category: ScreenCategory) -> [Date: Double] { parts[category] ?? [:] }

    /// 記録のある日の値。記録はあるが使っていない区分は0。
    func daily(_ category: ScreenCategory?, calendar: Calendar = .current) -> [Date: Double] {
        let days = HealthMath.dailyTotals(total, calendar: calendar)
        guard let category else { return days }
        let sums = HealthMath.dailyTotals(values(category), calendar: calendar)
        var result: [Date: Double] = [:]
        for day in days.keys { result[day] = sums[day] ?? 0 }
        return result
    }
}

func loadCategories() -> (ScreenCategories, Bool) {
    do { return (try ScreenCategoryFiles.load() ?? ScreenCategories(), false) } catch { return (ScreenCategories(), true) }
}

/// 値は拡張の中だけで扱う。共有領域・ネットワークへは書き出さない（分類はApp Groupから読むだけ）。
func classify(_ data: DeviceActivityResults<DeviceActivityData>, _ categories: ScreenCategories,
              collectSNSItems: Bool = false) async -> Classified {
    var result = Classified()
    for await device in data {
        for await segment in device.activitySegments {
            let start = segment.dateInterval.start
            let segmentTotal = segment.totalActivityDuration / 60
            result.total[start, default: 0] += segmentTotal
            var classified = 0.0
            for await category in segment.categories {
                let token = category.category.token
                for await app in category.applications {
                    let kind = categories.classify(application: app.application.token, category: token)
                    guard kind != .other else { continue }
                    let minutes = app.totalActivityDuration / 60
                    result.parts[kind, default: [:]][start, default: 0] += minutes
                    classified += minutes
                    if collectSNSItems && kind == .sns {
                        let name = app.application.localizedDisplayName ?? "アプリ"
                        result.snsItems[name, default: [:]][start, default: 0] += minutes
                    }
                }
                for await domain in category.webDomains {
                    let kind = categories.classify(webDomain: domain.webDomain.token, category: token)
                    guard kind != .other else { continue }
                    let minutes = domain.totalActivityDuration / 60
                    result.parts[kind, default: [:]][start, default: 0] += minutes
                    classified += minutes
                    if collectSNSItems && kind == .sns {
                        let name = domain.webDomain.domain ?? "Webサイト"
                        result.snsItems[name, default: [:]][start, default: 0] += minutes
                    }
                }
            }
            result.parts[.other, default: [:]][start, default: 0] += max(0, segmentTotal - classified)
        }
    }
    return result
}

/// ゲートの記録（App Group）を読むだけ。読めなければ空。
func loadGateEvents() -> [GateEvent] {
    struct LogFile: Decodable { var version: Int; var events: [GateEvent] }
    guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ScreenCategoryFiles.appGroup),
          let data = try? Data(contentsOf: base.appendingPathComponent("Gate/events.json")),
          let log = try? JSONDecoder().decode(LogFile.self, from: data) else { return [] }
    return log.events
}

let rhythmGood = Color(red: 17/255, green: 90/255, blue: 54/255)
let rhythmBad = ScreenCategory.sns.color

/// SNSと合計は、多い＝朱／少ない＝緑。
struct DeltaChip: View {
    var delta: Double?
    var suffix: String
    var body: some View {
        if let delta {
            if abs(delta) < 1 {
                Text("± 変化なし").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            } else {
                let more: Bool = delta > 0
                let text: String = (more ? "↑ " : "↓ ") + HealthMath.shortDuration(abs(delta)) + " " + suffix
                Text(text).font(.caption.weight(.medium)).foregroundStyle(more ? rhythmBad : rhythmGood)
            }
        } else {
            Text("比べる記録がありません").font(.caption2).foregroundStyle(.secondary)
        }
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
struct TodayCardScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context
    let compareDays: Int
    let content: (TodayCardConfiguration) -> TodayCardView = { TodayCardView(configuration: $0) }

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TodayCardConfiguration {
        var configuration = TodayCardConfiguration(compareDays: compareDays)
        let (categories, failed) = loadCategories()
        configuration.categoryError = failed
        configuration.goal = categories.snsGoalMinutes
        configuration.hasSNS = !categories.sns.isEmptySelection
        let result = await classify(data, categories)

        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let elapsed = now.timeIntervalSince(today)
        configuration.asOf = now
        if HealthMath.totalsUntil(result.total, days: [today], elapsed: 86_400, calendar: calendar)[today] != nil {
            for kind in ScreenCategory.allCases {
                configuration.today[kind] = HealthMath.dailyTotals(result.values(kind), calendar: calendar)[today] ?? 0
            }
        }
        let past = (1...compareDays).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let recorded = Array(HealthMath.totalsUntil(result.total, days: past, elapsed: elapsed, calendar: calendar).keys)
        if !recorded.isEmpty {
            var average: [ScreenCategory: Double] = [:]
            for kind in ScreenCategory.allCases {
                let values = HealthMath.totalsUntil(result.values(kind), days: recorded, elapsed: elapsed, calendar: calendar)
                average[kind] = recorded.reduce(0) { $0 + (values[$1] ?? 0) } / Double(recorded.count)
            }
            configuration.average = average
            configuration.averageDays = recorded.count
        }

        // P2：最初にSNSを使った時（1時間単位）。P4：目標以下が続いた日数（記録のある日のみ、最大30日）。
        let sns = result.values(.sns)
        configuration.firstHour = HealthMath.firstHour(sns, on: today, calendar: calendar)
        let firsts = past.compactMap { HealthMath.firstHour(sns, on: $0, calendar: calendar) }
        configuration.averageFirstHour = firsts.isEmpty ? nil : Double(firsts.reduce(0, +)) / Double(firsts.count)
        configuration.streak = HealthMath.streak(result.daily(.sns, calendar: calendar), goal: Double(categories.snsGoalMinutes),
            today: today, limit: 30, calendar: calendar)
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

// MARK: 振り返り（上のグラフ）

struct StackPoint: Identifiable {
    var start: Date
    var category: ScreenCategory
    var value: Double
    var id: String { "\(start.timeIntervalSince1970)-\(category.rawValue)" }
}

struct ReviewChartConfiguration {
    var metric: ScreenMetric
    var period: ReviewPeriod
    var summary = PeriodSummary(average: nil, recordedDays: 0, totalDays: 0, delta: nil)
    var series: [SeriesPoint] = []
    var stacks: [StackPoint] = []
    var goal = 45
    var goalDays = 0
    var categoryError = false
}

/// 本体から「前の期間＋今の期間」を1日単位で受け取る。今日は含めない。
struct ReviewChartScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context
    let metric: ScreenMetric
    let period: ReviewPeriod
    let content: (ReviewChartConfiguration) -> ReviewChartView = { ReviewChartView(configuration: $0) }

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> ReviewChartConfiguration {
        var configuration = ReviewChartConfiguration(metric: metric, period: period)
        let (categories, failed) = loadCategories()
        configuration.categoryError = failed
        configuration.goal = categories.snsGoalMinutes
        let result = await classify(data, categories)
        let values = result.daily(metric == .sns ? .sns : nil)
        configuration.summary = HealthMath.periodSummary(values, period: period)
        configuration.series = HealthMath.series(values, period: period)
        if metric == .sns {
            let days = HealthMath.periodDays(period)
            configuration.goalDays = days.filter { (values[$0] ?? .infinity) <= Double(categories.snsGoalMinutes) }.count
        } else {
            var stacks: [StackPoint] = []
            for category in ScreenCategory.allCases {
                let series = HealthMath.series(result.daily(category), period: period)
                for point in series { stacks.append(StackPoint(start: point.start, category: category, value: point.value ?? 0)) }
            }
            configuration.stacks = stacks
        }
        return configuration
    }
}

struct ReviewChartView: View {
    let configuration: ReviewChartConfiguration
    private var unit: Calendar.Component {
        switch configuration.period {
        case .week, .month: return .day
        case .quarter: return .weekOfYear
        case .year: return .month
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if configuration.categoryError {
                Text("アプリの分類を読み込めませんでした。設定から選び直してください。").font(.caption).foregroundStyle(rhythmBad)
            }
            Text(configuration.summary.average.map { HealthMath.shortDuration($0) } ?? "記録なし")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
            DeltaChip(delta: configuration.summary.delta, suffix: configuration.period.comparisonLabel + "より")
            if configuration.summary.recordedDays == 0 {
                Text("この期間はApple側に記録がありません（0分ではありません）").font(.caption).foregroundStyle(.secondary)
            } else if configuration.metric == .sns {
                snsChart
            } else {
                stackChart
                legend
            }
            Text(foot).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var snsChart: some View {
        let points = configuration.series.filter { $0.value != nil }
        return Chart {
            ForEach(points) { point in
                BarMark(x: .value("日付", point.start, unit: unit), y: .value("分", point.value ?? 0))
                    .foregroundStyle(ScreenCategory.sns.color)
            }
            if let average = configuration.summary.average {
                RuleMark(y: .value("平均", average))
                    .foregroundStyle(Color.primary.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("平均 " + HealthMath.shortDuration(average)).font(.caption2)
                    }
            }
        }.frame(height: 150).chartYAxis { AxisMarks(position: .leading) }
            .chartXAxis { xAxis }
    }

    private var stackChart: some View {
        Chart {
            ForEach(configuration.stacks) { point in
                BarMark(x: .value("日付", point.start, unit: unit), y: .value("分", point.value))
                    .foregroundStyle(by: .value("区分", point.category.label))
            }
        }.frame(height: 150)
            .chartForegroundStyleScale(domain: ScreenCategory.allCases.map(\.label), range: ScreenCategory.allCases.map(\.color))
            .chartLegend(.hidden)
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXAxis { xAxis }
    }

    private var xAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
            AxisValueLabel(format: configuration.period == .year ? Date.FormatStyle.dateTime.month() : Date.FormatStyle.dateTime.month().day())
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(ScreenCategory.allCases) { kind in
                HStack(spacing: 4) { Circle().fill(kind.color).frame(width: 7, height: 7); Text(kind.label) }
            }
        }.font(.caption2)
    }

    private var foot: String {
        let summary = configuration.summary
        var parts: [String] = []
        if configuration.metric == .sns {
            parts.append("目標\(configuration.goal)分以下：\(configuration.goalDays)/\(summary.totalDays)日")
        }
        if configuration.period == .quarter { parts.append("週ごとの平均") }
        if configuration.period == .year { parts.append("月ごとの平均") }
        parts.append("記録\(summary.recordedDays)/\(summary.totalDays)日 · 昨日まで")
        return parts.joined(separator: " · ")
    }
}

// MARK: 振り返り（下の一覧のSNS・合計の2行）

struct ReviewRow {
    var metric: ScreenMetric
    var summary: PeriodSummary
    var series: [SeriesPoint]
}

struct ReviewRowsScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context
    let period: ReviewPeriod
    let content: ([ReviewRow]) -> ReviewRowsView = { ReviewRowsView(rows: $0) }

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> [ReviewRow] {
        let (categories, _) = loadCategories()
        let result = await classify(data, categories)
        return ScreenMetric.allCases.map { metric in
            let values = result.daily(metric == .sns ? .sns : nil)
            return ReviewRow(metric: metric, summary: HealthMath.periodSummary(values, period: period),
                series: HealthMath.series(values, period: period))
        }
    }
}

/// 本体が上に透明なボタンを重ねるため、1行の高さは ReviewRowsView.rowHeight に固定する。
struct ReviewRowsView: View {
    static let rowHeight: CGFloat = 64
    let rows: [ReviewRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.metric) { row in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle().fill(row.metric.color).frame(width: 8, height: 8)
                            Text(row.metric.label).font(.subheadline.weight(.semibold))
                        }
                        Text("1日平均 · 記録\(row.summary.recordedDays)/\(row.summary.totalDays)日").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(row.summary.average.map { HealthMath.shortDuration($0) } ?? "—").font(.subheadline.weight(.semibold))
                        DeltaChip(delta: row.summary.delta, suffix: "")
                    }
                    Sparkline(points: row.series, color: row.metric.color).frame(width: 60, height: 24)
                }
                .frame(height: Self.rowHeight)
                Divider()
            }
        }
    }
}

struct Sparkline: View {
    var points: [SeriesPoint]
    var color: Color
    var body: some View {
        Chart {
            ForEach(points.filter { $0.value != nil }) { point in
                LineMark(x: .value("日付", point.start), y: .value("値", point.value ?? 0)).foregroundStyle(color)
            }
        }.chartXAxis(.hidden).chartYAxis(.hidden)
    }
}

// MARK: 振り返り（カレンダー）

struct CalendarConfiguration {
    var metric: ScreenMetric
    var days: [Date] = []
    var values: [Date: Double] = [:]
    var goal = 45
}

/// 本体は5週間ごとの区切りで渡す。データの日付から表示中の5週間を割り出す。
struct CalendarScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context
    let metric: ScreenMetric
    let content: (CalendarConfiguration) -> ReviewCalendarView = { ReviewCalendarView(configuration: $0) }

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> CalendarConfiguration {
        let (categories, _) = loadCategories()
        let result = await classify(data, categories)
        let values = result.daily(metric == .sns ? .sns : nil)
        var configuration = CalendarConfiguration(metric: metric, values: values, goal: categories.snsGoalMinutes)
        if let latest = values.keys.max() {
            configuration.days = HealthMath.calendarWeeks(offset: HealthMath.calendarOffset(containing: latest))
        }
        return configuration
    }
}

struct ReviewCalendarView: View {
    let configuration: CalendarConfiguration
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if configuration.days.isEmpty {
                Text("この5週間はApple側に記録がありません").font(.subheadline)
                Text("0分という意味ではありません。").font(.caption).foregroundStyle(.secondary)
            } else {
                let today = Calendar.current.startOfDay(for: .now)
                let level = calendarLevels(configuration.days.compactMap { configuration.values[$0] })
                WeekdayHeader()
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(configuration.days, id: \.self) { day in
                        let value: Double? = configuration.values[day]
                        CalendarCell(day: day, value: value.map { HealthMath.shortDuration($0) }, level: value.map(level),
                            tint: configuration.metric.color, isFuture: day >= today,
                            goalMet: configuration.metric == .sns && (value.map { $0 <= Double(configuration.goal) } ?? false))
                    }
                }
                Text("濃いほど長い · 点線の日はApple側に記録なし · 今日はまだ途中なので含めません").font(.caption2).foregroundStyle(.secondary)
                if configuration.metric == .sns {
                    Text("緑の枠＝SNSが目標\(configuration.goal)分以下の日").font(.caption2).foregroundStyle(rhythmGood)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: スクリーンタイム詳細

struct HeatSlot: Identifiable {
    var weekday: Int   // 0=月 … 6=日
    var slot: Int      // 0=0〜3時 … 7=21〜24時
    var minutes: Double
    var id: Int { weekday * 8 + slot }
}

struct SNSItem: Identifiable {
    var name: String
    var minutes: Double
    var id: String { name }
}

struct DetailConfiguration {
    var range: DetailRange
    var categories: [ScreenCategory: Double] = [:]
    var snsItems: [SNSItem] = []
    var workMinutes: Double?
    var hourlyToday: [Double]?
    var hourlyAverage: [Double] = Array(repeating: 0, count: 24)
    var heat: [HeatSlot] = []
    var peak: HeatSlot?
    var hasData = false
    var total: Double { categories.values.reduce(0, +) }
}

/// 過去30日＋今日を1時間単位で受け取る（今日のカードと同じ範囲）。
struct DetailScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context
    let range: DetailRange
    let content: (DetailConfiguration) -> DetailView = { DetailView(configuration: $0) }

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> DetailConfiguration {
        let (categories, _) = loadCategories()
        let result = await classify(data, categories, collectSNSItems: true)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var configuration = DetailConfiguration(range: range)
        let recordedPast: [Date] = HealthMath.dailyTotals(result.total, calendar: calendar).keys
            .filter { $0 < today && $0 >= (calendar.date(byAdding: .day, value: -range.days, to: today) ?? today) }
        let days: [Date] = range == .today ? [today] : recordedPast
        configuration.hasData = range == .today ? HealthMath.dailyTotals(result.total)[today] != nil : !days.isEmpty
        guard configuration.hasData else { return configuration }
        let divisor = Double(max(days.count, 1))

        func mean(_ hourly: [Date: Double]) -> Double {
            let daily = HealthMath.dailyTotals(hourly, calendar: calendar)
            return days.reduce(0) { $0 + (daily[$1] ?? 0) } / divisor
        }
        for kind in ScreenCategory.allCases { configuration.categories[kind] = mean(result.values(kind)) }
        configuration.snsItems = result.snsItems.map { SNSItem(name: $0.key, minutes: mean($0.value)) }
            .filter { $0.minutes >= 0.5 }.sorted { $0.minutes > $1.minutes }

        // P5：ゲートで「仕事」を選んで解除した分（おおよそ）。ゲートの記録がなければ出さない。
        let events = loadGateEvents()
        if !events.isEmpty {
            configuration.workMinutes = days.reduce(0) { $0 + Double(GateMath.workMinutes(on: $1, events, calendar: calendar)) } / divisor
        }

        // 時間帯別：今日は今日の値と7日平均、平均のときはその期間の平均。
        let sns = result.values(.sns)
        func hourlyMean(over list: [Date]) -> [Double] {
            (0..<24).map { hour in
                let sum = list.reduce(0.0) { total, day in
                    total + (calendar.date(byAdding: .hour, value: hour, to: day).flatMap { sns[$0] } ?? 0)
                }
                return list.isEmpty ? 0 : sum / Double(list.count)
            }
        }
        if range == .today {
            configuration.hourlyToday = hourlyMean(over: [today])
            configuration.hourlyAverage = hourlyMean(over: recordedPast)
        } else {
            configuration.hourlyAverage = hourlyMean(over: days)
        }

        // P1：曜日×3時間の平均（直近30日）。
        let month = HealthMath.dailyTotals(result.total, calendar: calendar).keys.filter { $0 < today }
        var heat: [HeatSlot] = []
        for weekday in 0..<7 {
            let sameDays = month.filter { (calendar.component(.weekday, from: $0) + 5) % 7 == weekday }
            for slot in 0..<8 {
                var sum = 0.0
                for day in sameDays {
                    for hour in (slot * 3)..<(slot * 3 + 3) {
                        sum += calendar.date(byAdding: .hour, value: hour, to: day).flatMap { sns[$0] } ?? 0
                    }
                }
                heat.append(HeatSlot(weekday: weekday, slot: slot, minutes: sameDays.isEmpty ? 0 : sum / Double(sameDays.count)))
            }
        }
        configuration.heat = heat
        configuration.peak = heat.max { $0.minutes < $1.minutes }.flatMap { $0.minutes > 0 ? $0 : nil }
        return configuration
    }
}

struct DetailView: View {
    let configuration: DetailConfiguration
    private let weekdays = ["月", "火", "水", "木", "金", "土", "日"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !configuration.hasData {
                Text("表示できる利用データがありません").font(.subheadline)
                Text("Apple側に記録がない日は0分ではありません。").font(.caption).foregroundStyle(.secondary)
            } else {
                breakdown
                Divider()
                snsItems
                Divider()
                hourly
                Divider()
                heatmap
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var breakdown: some View {
        let total = configuration.total
        let sns = configuration.categories[.sns] ?? 0
        let maximum = max(configuration.categories.values.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("合計").font(.caption).foregroundStyle(.secondary)
                    Text(HealthMath.shortDuration(total)).font(.system(.largeTitle, design: .rounded).weight(.semibold))
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("うちSNS").font(.caption).foregroundStyle(.secondary)
                    Text(total > 0 ? "\(Int((sns / total * 100).rounded()))%" : "—").font(.title2.weight(.semibold))
                        .foregroundStyle(ScreenCategory.sns.color)
                }
            }
            ForEach(ScreenCategory.allCases) { kind in
                let value: Double = configuration.categories[kind] ?? 0
                HStack(spacing: 8) {
                    HStack(spacing: 4) { Circle().fill(kind.color).frame(width: 7, height: 7); Text(kind.label) }
                        .font(.caption.weight(kind == .sns ? .bold : .regular)).frame(width: 64, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule().fill(Color.secondary.opacity(0.12)).overlay(alignment: .leading) {
                            Capsule().fill(kind.color).frame(width: CGFloat(Double(proxy.size.width) * (value / maximum)))
                        }
                    }.frame(height: 10)
                    Text(HealthMath.shortDuration(value)).font(.caption.monospacedDigit()).frame(width: 70, alignment: .trailing)
                }
            }
        }
    }

    private var snsItems: some View {
        let sns = configuration.categories[.sns] ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SNSの内訳").font(.headline)
                Spacer()
                Text(HealthMath.shortDuration(sns)).font(.headline).foregroundStyle(ScreenCategory.sns.color)
            }
            if configuration.snsItems.isEmpty {
                Text("SNSの利用はありません").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(configuration.snsItems.prefix(6))) { item in
                HStack { Text(item.name).font(.subheadline); Spacer(); Text(HealthMath.shortDuration(item.minutes)).font(.subheadline.monospacedDigit()) }
            }
            if let work = configuration.workMinutes {
                Divider()
                HStack { Text("仕事目的で開いた").font(.subheadline); Spacer(); Text("約\(Int(work.rounded()))分").font(.subheadline) }
                HStack {
                    Text("それ以外").font(.subheadline); Spacer()
                    Text("約\(Int(max(0, sns - work).rounded()))分").font(.subheadline).foregroundStyle(ScreenCategory.sns.color)
                }
                Text("仕事目的はゲートで解除した時間から出すおおよその値です").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var hourly: some View {
        let peak = configuration.hourlyAverage.enumerated().max { $0.element < $1.element }
        return VStack(alignment: .leading, spacing: 6) {
            Text("SNSを見た時間帯").font(.headline)
            Chart {
                ForEach(0..<24, id: \.self) { hour in
                    BarMark(x: .value("時", hour), y: .value("平均", configuration.hourlyAverage[hour]))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    if let today = configuration.hourlyToday {
                        BarMark(x: .value("時", hour), y: .value("今日", today[hour]), width: .ratio(0.5))
                            .foregroundStyle(ScreenCategory.sns.color)
                    }
                }
            }.frame(height: 120)
                .chartXAxis { AxisMarks(values: [0, 6, 12, 18]) { value in AxisValueLabel { Text("\(value.as(Int.self) ?? 0)時") } } }
                .chartYAxis { AxisMarks(position: .leading) }
            Text(configuration.hourlyToday == nil ? "棒＝\(configuration.range.label)の1時間あたりの分" : "朱＝今日 · 薄い棒＝7日平均（1時間あたりの分）")
                .font(.caption2).foregroundStyle(.secondary)
            if let peak, peak.element > 0 {
                Text("平均で一番多いのは \(peak.offset)〜\(peak.offset + 1)時 です").font(.caption)
            }
        }
    }

    private var heatmap: some View {
        let maximum = max(configuration.heat.map(\.minutes).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack { Text("SNSが伸びやすい時間帯").font(.headline); Spacer(); Text("直近30日").font(.caption).foregroundStyle(.secondary) }
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    Text("").frame(width: 18)
                    ForEach(0..<8, id: \.self) { slot in Text("\(slot * 3)").font(.system(size: 9)).foregroundStyle(.secondary) }
                }
                ForEach(0..<7, id: \.self) { weekday in
                    GridRow {
                        Text(weekdays[weekday]).font(.caption2).foregroundStyle(.secondary).frame(width: 18)
                        ForEach(0..<8, id: \.self) { slot in
                            let minutes: Double = configuration.heat.first { $0.weekday == weekday && $0.slot == slot }?.minutes ?? 0
                            RoundedRectangle(cornerRadius: 3).fill(ScreenCategory.sns.color.opacity(0.06 + 0.88 * minutes / maximum))
                                .frame(height: 18)
                                .accessibilityLabel("\(weekdays[weekday])曜 \(slot * 3)時から \(Int(minutes.rounded()))分")
                        }
                    }
                }
            }
            if let peak = configuration.peak {
                Text("一番多いのは \(weekdays[peak.weekday])曜の\(peak.slot * 3)〜\(peak.slot * 3 + 3)時 です（平均\(Int(peak.minutes.rounded()))分）")
                    .font(.caption).foregroundStyle(ScreenCategory.sns.color)
            }
        }
    }
}
