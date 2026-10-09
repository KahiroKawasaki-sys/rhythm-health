import SwiftUI
import Charts
import DeviceActivity

/// 振り返りの5指標。SNSと合計は表示拡張が描き、睡眠・体重・歩数は本体が描く。
enum ReviewMetric: String, CaseIterable, Identifiable {
    case sns, total, sleep, weight, steps
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sns: return "SNS"
        case .total: return "スクリーンタイム"
        case .sleep: return "睡眠"
        case .weight: return "体重"
        case .steps: return "歩数"
        }
    }
    var screen: ScreenMetric? {
        switch self {
        case .sns: return .sns
        case .total: return .total
        default: return nil
        }
    }
    var hasCalendar: Bool { self != .weight }
    var color: Color { screen?.color ?? Palette.green }

    func format(_ value: Double) -> String {
        switch self {
        case .weight: return String(format: "%.1fkg", value)
        case .steps: return value.formatted(.number.precision(.fractionLength(0))) + "歩"
        default: return HealthMath.shortDuration(value)
        }
    }
    func shortFormat(_ value: Double) -> String {
        switch self {
        case .weight: return String(format: "%.1f", value)
        case .steps: return String(format: "%.1fk", value / 1000)
        default: return HealthMath.shortDuration(value)
        }
    }
    /// 変化なしとみなす幅。
    var threshold: Double {
        switch self {
        case .weight: return 0.05
        case .steps: return 50
        default: return 1
        }
    }
}

struct ReviewView: View {
    @EnvironmentObject private var journal: JournalStore
    @EnvironmentObject private var health: HealthStore
    @EnvironmentObject private var screen: ScreenTimeStore
    @State private var period: ReviewPeriod = .month
    @State private var metric: ReviewMetric = .sns
    @State private var showsCalendar = false
    @State private var calendarOffset = 0
    @ScaledMetric(relativeTo: .body) private var chartHeight = 310.0
    @ScaledMetric(relativeTo: .body) private var calendarHeight = 360.0

    /// 本体で扱う指標の日ごとの値（記録のない日は含めない）。
    private func values(_ metric: ReviewMetric) -> [Date: Double] {
        switch metric {
        case .steps: return health.stepsDaily
        case .sleep, .weight:
            let start = min(HealthMath.fetchStart(period), HealthMath.calendarWeeks(offset: calendarOffset).first ?? .now)
            let rows = HealthMath.resolve(days: HealthMath.completedDays(in: DateInterval(start: start, end: .now)),
                weights: health.weights, sleep: health.sleep, manual: journal.records)
            var result: [Date: Double] = [:]
            for row in rows {
                if metric == .sleep, let minutes = row.sleepMinutes { result[row.day] = Double(minutes) }
                if metric == .weight, let weight = row.weight { result[row.day] = weight }
            }
            return result
        default: return [:]
        }
    }

    private var rangeText: String {
        let days = HealthMath.periodDays(period)
        guard let first = days.first, let last = days.last else { return "" }
        let style: Date.FormatStyle = period == .year ? .dateTime.year().month().day() : .dateTime.month().day()
        return "\(first.formatted(style)) 〜 \(last.formatted(style)) · 昨日まで · \(period.comparisonLabel)と比較"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("期間", selection: $period) {
                    ForEach(ReviewPeriod.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                HStack {
                    Text(rangeText).font(.caption).foregroundStyle(Palette.secondary)
                    if health.isLoading { Spacer(); ProgressView().controlSize(.small) }
                }
                topCard
                metricList
                GateReviewCard(period: period)
                Text("出典：Appleヘルスケア・手入力・Appleスクリーンタイム。記録のない日は平均から除き、0扱いしません。")
                    .font(.caption).foregroundStyle(Palette.secondary)
                if let message = health.message { Notice(text: message) }
            }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(Palette.background).navigationTitle("振り返り")
            .task(id: period) { await health.ensureLoaded(period) }
            .onChange(of: calendarOffset) { _, offset in
                if let first = HealthMath.calendarWeeks(offset: offset).first { Task { await health.ensureLoaded(from: first) } }
            }
    }

    // MARK: 上：選んだ指標のグラフ1枚

    private var topCard: some View {
        Surface {
            HStack {
                Circle().fill(metric.color).frame(width: 9, height: 9)
                Text("\(metric.label) · 1日平均").font(.subheadline.weight(.medium))
                Spacer()
                if metric.hasCalendar {
                    Picker("表示", selection: $showsCalendar) {
                        Text("グラフ").tag(false)
                        Text("カレンダー").tag(true)
                    }.pickerStyle(.segmented).frame(width: 170)
                }
            }
            if showsCalendar && metric.hasCalendar { calendarNavigator }
            topContent
        }
    }

    @ViewBuilder private var topContent: some View {
        let calendarMode = showsCalendar && metric.hasCalendar
        if let screenMetric = metric.screen {
            if !screen.isAuthorized {
                Text("スクリーンタイムに接続すると表示します。").font(.subheadline)
                Button("スクリーンタイムに接続") { Task { await screen.connect() } }.buttonStyle(.bordered)
            } else if calendarMode {
                DeviceActivityReport(.rhythmReviewCalendar(screenMetric), filter: screen.calendarFilter(offset: calendarOffset))
                    .id("calendar-\(screenMetric.rawValue)-\(calendarOffset)-\(screen.refreshID)")
                    .frame(height: calendarHeight)
            } else {
                DeviceActivityReport(.rhythmReviewChart(screenMetric, period), filter: screen.reviewFilter(period))
                    .id("chart-\(screenMetric.rawValue)-\(period.rawValue)-\(screen.refreshID)")
                    .frame(height: chartHeight)
            }
        } else if calendarMode {
            HostCalendar(metric: metric, values: values(metric), offset: calendarOffset)
        } else {
            HostChart(metric: metric, period: period, values: values(metric))
        }
    }

    private var calendarNavigator: some View {
        let days = HealthMath.calendarWeeks(offset: calendarOffset)
        let first: String = days.first?.formatted(.dateTime.month().day()) ?? ""
        let last: String = days.last?.formatted(.dateTime.month().day()) ?? ""
        return HStack {
            Button { calendarOffset += 1 } label: { Image(systemName: "chevron.left") }
                .disabled(calendarOffset >= 20).accessibilityLabel("前の5週間")
            Spacer()
            Text(first + " 〜 " + last).font(.subheadline.weight(.medium))
            Spacer()
            Button { calendarOffset -= 1 } label: { Image(systemName: "chevron.right") }
                .disabled(calendarOffset == 0).accessibilityLabel("次の5週間")
        }.buttonStyle(.borderless)
    }

    // MARK: 下：5指標の一覧。行をタップすると上が切り替わる

    private var metricList: some View {
        VStack(spacing: 0) {
            if screen.isAuthorized {
                DeviceActivityReport(.rhythmReviewRows(period), filter: screen.reviewFilter(period))
                    .id("rows-\(period.rawValue)-\(screen.refreshID)")
                    .frame(height: 130)
                    .overlay { screenRowButtons }
            }
            ForEach([ReviewMetric.sleep, .weight, .steps]) { item in
                Button { select(item) } label: {
                    HostMetricRow(metric: item, period: period, values: values(item), selected: metric == item)
                }.buttonStyle(.plain)
                Divider()
            }
        }.padding(.horizontal, 16).padding(.vertical, 4)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
    }

    /// 表示拡張の上に透明なボタンを重ねて、SNS・合計の行のタップを本体で受け取る。
    private var screenRowButtons: some View {
        VStack(spacing: 0) {
            ForEach([ReviewMetric.sns, .total]) { item in
                Button { select(item) } label: {
                    Rectangle().fill(metric == item ? Palette.green.opacity(0.06) : Color.clear).contentShape(Rectangle())
                }.buttonStyle(.plain).frame(height: 65)
                    .accessibilityLabel("\(item.label)を上のグラフに表示")
            }
        }
    }

    private func select(_ item: ReviewMetric) {
        metric = item
        if !item.hasCalendar { showsCalendar = false }
    }
}

// MARK: 本体側の指標（睡眠・体重・歩数）

struct HostMetricRow: View {
    var metric: ReviewMetric
    var period: ReviewPeriod
    var values: [Date: Double]
    var selected: Bool

    var body: some View {
        let summary = HealthMath.periodSummary(values, period: period)
        let series = HealthMath.series(values, period: period).filter { $0.value != nil }
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Circle().fill(metric.color).frame(width: 8, height: 8)
                    Text(metric.label).font(.subheadline.weight(.semibold))
                }
                Text("1日平均 · 記録\(summary.recordedDays)/\(summary.totalDays)日").font(.caption2).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(summary.average.map(metric.format) ?? "—").font(.subheadline.weight(.semibold))
                Text(deltaText(summary.delta)).font(.caption.weight(.medium)).foregroundStyle(Palette.secondary)
            }
            Chart {
                ForEach(series) { point in
                    LineMark(x: .value("日付", point.start), y: .value("値", point.value ?? 0)).foregroundStyle(metric.color)
                }
            }.chartXAxis(.hidden).chartYAxis(.hidden).frame(width: 60, height: 24)
        }.frame(height: 64).contentShape(Rectangle())
            .background(selected ? Palette.green.opacity(0.06) : Color.clear)
            .accessibilityElement(children: .combine)
            .accessibilityHint("上のグラフに表示")
    }

    private func deltaText(_ delta: Double?) -> String {
        guard let delta else { return "比べる記録なし" }
        if abs(delta) < metric.threshold { return "± 変化なし" }
        return (delta > 0 ? "↑ " : "↓ ") + metric.format(abs(delta))
    }
}

struct HostChart: View {
    var metric: ReviewMetric
    var period: ReviewPeriod
    var values: [Date: Double]

    private var unit: Calendar.Component {
        switch period {
        case .week, .month: return .day
        case .quarter: return .weekOfYear
        case .year: return .month
        }
    }

    var body: some View {
        let summary = HealthMath.periodSummary(values, period: period)
        let points = HealthMath.series(values, period: period).filter { $0.value != nil }
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.average.map(metric.format) ?? "記録なし").font(.system(.largeTitle, design: .rounded).weight(.semibold))
            Text(deltaText(summary.delta)).font(.caption.weight(.medium)).foregroundStyle(Palette.secondary)
            if points.isEmpty {
                Text("この期間の記録がありません").font(.subheadline).foregroundStyle(Palette.secondary)
            } else if metric == .weight {
                weightChart(points, average: summary.average)
            } else {
                barChart(points, average: summary.average)
            }
            Text(foot(summary)).font(.caption2).foregroundStyle(Palette.secondary)
        }
    }

    private func barChart(_ points: [SeriesPoint], average: Double?) -> some View {
        Chart {
            ForEach(points) { point in
                BarMark(x: .value("日付", point.start, unit: unit), y: .value(metric.label, point.value ?? 0))
                    .foregroundStyle(metric.color)
            }
            if let average {
                RuleMark(y: .value("平均", average)).foregroundStyle(Palette.ink.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) { Text("平均 " + metric.shortFormat(average)).font(.caption2) }
            }
        }.frame(height: 160)
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXAxis { axis }
            .accessibilityLabel("\(metric.label)の推移")
    }

    private func weightChart(_ points: [SeriesPoint], average: Double?) -> some View {
        let numbers = points.compactMap(\.value)
        let low: Double = (numbers.min() ?? 60) - 0.3
        let high: Double = (numbers.max() ?? 70) + 0.3
        return Chart {
            ForEach(points) { point in
                LineMark(x: .value("日付", point.start, unit: unit), y: .value("体重", point.value ?? 0)).foregroundStyle(Palette.green)
                PointMark(x: .value("日付", point.start, unit: unit), y: .value("体重", point.value ?? 0))
                    .foregroundStyle(Palette.green).symbolSize(20)
            }
            if let average {
                RuleMark(y: .value("平均", average)).foregroundStyle(Palette.ink.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }.frame(height: 160)
            .chartYScale(domain: low...high)
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXAxis { axis }
            .accessibilityLabel("体重の推移")
    }

    private var axis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
            AxisValueLabel(format: period == .year ? Date.FormatStyle.dateTime.month() : Date.FormatStyle.dateTime.month().day())
        }
    }

    private func deltaText(_ delta: Double?) -> String {
        guard let delta else { return "比べる記録がありません" }
        if abs(delta) < metric.threshold { return "± \(period.comparisonLabel)と変化なし" }
        return (delta > 0 ? "↑ " : "↓ ") + metric.format(abs(delta)) + " \(period.comparisonLabel)より"
    }

    private func foot(_ summary: PeriodSummary) -> String {
        var parts: [String] = []
        if period == .quarter { parts.append("週ごとの平均") }
        if period == .year { parts.append("月ごとの平均") }
        parts.append("記録\(summary.recordedDays)/\(summary.totalDays)日")
        if metric == .weight { parts.append("縦軸は0からではありません") }
        if metric == .sleep { parts.append("前日正午〜当日正午の睡眠") }
        return parts.joined(separator: " · ")
    }
}

struct HostCalendar: View {
    var metric: ReviewMetric
    var values: [Date: Double]
    var offset: Int
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let days = HealthMath.calendarWeeks(offset: offset)
        let today = Calendar.current.startOfDay(for: .now)
        let level = calendarLevels(days.filter { $0 < today }.compactMap { values[$0] })
        VStack(alignment: .leading, spacing: 8) {
            WeekdayHeader()
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let value: Double? = day < today ? values[day] : nil
                    CalendarCell(day: day, value: value.map(metric.shortFormat), level: value.map(level),
                        tint: metric.color, isFuture: day >= today)
                }
            }
            Text("濃いほど\(metric == .steps ? "多い" : "長い") · 点線の日は記録なし · 今日はまだ途中なので含めません")
                .font(.caption2).foregroundStyle(Palette.secondary)
        }
    }
}

// MARK: スクリーンタイム詳細（今日のカードから）

struct ScreenTimeDetailView: View {
    @EnvironmentObject private var screen: ScreenTimeStore
    @EnvironmentObject private var gate: GateStore
    @State private var range: DetailRange = .today
    @ScaledMetric(relativeTo: .body) private var height = 1040.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("期間", selection: $range) {
                    ForEach(DetailRange.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                Surface {
                    if screen.isAuthorized {
                        DeviceActivityReport(.rhythmDetail(range), filter: screen.todayFilter())
                            .id("detail-\(range.rawValue)-\(screen.refreshID)")
                            .frame(height: height)
                    } else {
                        Button("スクリーンタイムに接続") { Task { await screen.connect() } }.buttonStyle(.bordered)
                    }
                }
                Surface {
                    SectionLabel(title: "ゲートを強める時間帯", detail: gate.settings.strongHoursText)
                    Text("上の濃淡表で伸びやすい時間帯を見て、その時間のゲートの待機を2倍にできます。")
                        .font(.footnote).foregroundStyle(Palette.secondary)
                    NavigationLink { GateHoursView() } label: { Label("この時間帯のゲートを強める", systemImage: "clock") }
                }
                if range == .today && (gate.isEnabled || !gate.events.isEmpty) { gateRecord }
                Text("SNSの内訳のアプリ名は、Appleの専用画面の中だけで表示しています。").font(.caption).foregroundStyle(Palette.secondary)
            }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(Palette.background).navigationTitle("スクリーンタイム").navigationBarTitleDisplayMode(.inline)
    }

    private var gateRecord: some View {
        let events = GateMath.events(on: .now, gate.events)
        let counts = gate.todayCounts
        let purposes: String = GatePurpose.allCases.map { purpose in
            let count = events.filter { $0.kind == .opened && $0.purpose == purpose }.count
            return "\(purpose.label) \(count)"
        }.joined(separator: "・")
        return Surface {
            SectionLabel(title: "SNSゲートの記録", detail: "今日")
            row("開こうとした", "\(counts.opened + counts.stayedAway)回")
            row("やめておいた", "\(counts.stayedAway)回")
            row("目的を選んで開いた", purposes)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label).font(.subheadline); Spacer(); Text(value).font(.subheadline.weight(.medium)).multilineTextAlignment(.trailing) }
    }
}
