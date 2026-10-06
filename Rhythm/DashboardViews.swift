import SwiftUI
import Charts
import DeviceActivity

struct TodayView: View {
    @EnvironmentObject private var journal: JournalStore
    @EnvironmentObject private var health: HealthStore
    @EnvironmentObject private var screen: ScreenTimeStore
    var addEntry: () -> Void
    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var data: DailyHealth {
        HealthMath.resolve(days: [today], weights: health.weights, sleep: health.sleep, manual: journal.records)[0]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(Date.now.formatted(.dateTime.month().day().weekday(.wide))).font(.subheadline).foregroundStyle(Palette.secondary)
                    Text("今日のリズム").font(.largeTitle.bold())
                    Text("小さな記録から、心地よい毎日へ。").font(.subheadline).foregroundStyle(Palette.secondary)
                }
                Surface(background: Color(red: 231/255, green: 237/255, blue: 227/255)) {
                    HStack {
                        Label("あなたのペースで", systemImage: "leaf").font(.headline)
                        Spacer()
                        Image(systemName: "sparkle").foregroundStyle(Palette.green)
                    }
                    Text("まずは、今日の自分を知ろう。")
                    Text("数字も、体感も。少しずつ記録すると、自分の変化が見えてきます。")
                        .font(.footnote).foregroundStyle(Palette.secondary)
                }
                SectionLabel(title: "今日の記録", detail: "\(today.formatted(.dateTime.month().day()))")
                MetricTile(title: "体重", icon: "scalemass", value: data.weight.map { String(format: "%.1f", $0) } ?? "—",
                    unit: "kg", detail: data.weight == nil ? "データがありません" : data.weightSource)
                MetricTile(title: "睡眠", icon: "moon", value: data.sleepMinutes.map { HealthMath.duration($0) } ?? "—",
                    unit: "", detail: data.sleepMinutes == nil ? "前日正午から今日正午の睡眠" : "\(data.sleepSource) · 個人目標 \(HealthMath.duration(journal.goals.sleepMinutes))")
                ScreenReportCard(period: nil)
                Button(action: addEntry) { Label("今日の記録・体調を入力", systemImage: "plus") }.buttonStyle(PrimaryButtonStyle())
                if let error = journal.loadError { Notice(text: error) }
                if !health.hasRequested {
                    Surface {
                        Label("自動で記録をつなごう", systemImage: "heart.text.clipboard").font(.headline)
                        Text("Appleヘルスケアの体重・睡眠を読み込みます。対応体重計やApple Watchなどが保存した記録を使えます。")
                            .font(.footnote).foregroundStyle(Palette.secondary)
                        Button("Appleヘルスケアに接続") { Task { await health.connect() } }.buttonStyle(.bordered)
                    }
                }
                if let message = health.message { Notice(text: message) }
                if let sync = health.lastSync {
                    Text("ヘルスケア取得 \(sync.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(Palette.secondary)
                }
                Text("下に引っぱると最新の記録を取得します。")
                    .font(.caption).foregroundStyle(Palette.secondary)
            }.padding(20).frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
        }.background(Palette.background).toolbar {
            ToolbarItem(placement: .topBarLeading) { Text("rhythm").font(.title3.weight(.semibold)).foregroundStyle(Palette.green) }
            ToolbarItem(placement: .topBarTrailing) {
                if health.isLoading { ProgressView() }
                else { Button("更新", systemImage: "arrow.clockwise") { Task { await health.refresh(); screen.updateStatus() } } }
            }
        }.refreshable { await health.refresh(); screen.updateStatus() }
    }
}

struct MetricTile: View {
    var title: String
    var icon: String
    var value: String
    var unit: String
    var detail: String
    var body: some View {
        Surface {
            Label(title, systemImage: icon).font(.subheadline.weight(.medium)).foregroundStyle(Palette.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.system(.largeTitle, design: .rounded).weight(.semibold)).contentTransition(.numericText())
                Text(unit).font(.subheadline).foregroundStyle(Palette.secondary)
            }
            Text(detail).font(.caption).foregroundStyle(Palette.secondary)
        }
    }
}

struct ScreenReportCard: View {
    @EnvironmentObject private var screen: ScreenTimeStore
    @EnvironmentObject private var journal: JournalStore
    @ScaledMetric(relativeTo: .body) private var reportHeight = 380.0
    @ScaledMetric(relativeTo: .body) private var longHeight = 470.0
    @ScaledMetric(relativeTo: .body) private var todayHeight = 140.0
    var period: ReviewPeriod?
    var sns = false
    private var context: DeviceActivityReport.Context { period?.reportContext(sns: sns) ?? .rhythmToday }
    private var height: Double {
        guard let period else { return todayHeight }
        return period.isLong ? longHeight : reportHeight
    }
    var body: some View {
        Surface {
            Label(sns ? "SNSの時間" : "スクリーンタイム", systemImage: sns ? "bubble.left.and.bubble.right" : "iphone").font(.headline)
            if screen.isAuthorized && sns && !screen.hasSNSSelection {
                Text("SNSだけの時間も、見えるように。").font(.subheadline)
                Text("設定タブの「SNSとして数えるアプリ」でX・Instagram・YouTubeを選ぶと、ここに表示します。")
                    .font(.footnote).foregroundStyle(Palette.secondary)
            } else if screen.isAuthorized {
                DeviceActivityReport(context, filter: period.map { screen.filter(period: $0, sns: sns) } ?? screen.filter(days: nil))
                    .id("\(context.rawValue)-\(screen.refreshID)")
                    .frame(height: height)
                if !sns {
                    Text("個人目標 \(HealthMath.duration(journal.goals.screenMinutes)) / 日")
                        .font(.caption).foregroundStyle(Palette.secondary)
                }
                Text(sns ? "設定で選んだアプリとWebサイトの合計。値はAppleの専用レポート内だけで集計します。"
                    : "Apple提供のiPhone利用時間。表示に時間がかかる場合は更新してください。")
                    .font(.caption2).foregroundStyle(Palette.secondary)
            } else {
                Text("スマホとの距離も、見えるように。").font(.subheadline)
                Text("接続するとiPhoneの利用時間を自動で表示します。")
                    .font(.footnote).foregroundStyle(Palette.secondary)
                Button("スクリーンタイムに接続") { Task { await screen.connect() } }.buttonStyle(.bordered)
            }
            if let message = screen.message { Notice(text: message) }
        }
    }
}

enum HealthMetric: String, CaseIterable {
    case sleep = "睡眠", weight = "体重"
    var unit: String { self == .weight ? "kg" : "時間" }
    func value(_ day: DailyHealth) -> Double? {
        self == .weight ? day.weight : day.sleepMinutes.map { Double($0) / 60 }
    }
}

struct HealthPoint: Identifiable {
    var date: Date
    var value: Double
    var segment: Int
    var id: Date { date }
}

struct ReviewData {
    var current: [DailyHealth]
    var previous: [DailyHealth]
    var sleep: [Date: Double]
    var weight: [Date: Double]
    var mood: [Date: Double]
    func values(_ metric: HealthMetric) -> [Date: Double] { metric == .weight ? weight : sleep }
}

struct ReviewView: View {
    @EnvironmentObject private var journal: JournalStore
    @EnvironmentObject private var health: HealthStore
    @State private var period: ReviewPeriod = .week
    @State private var metric: HealthMetric = .sleep

    private func makeData() -> ReviewData {
        // Covers the chosen period, its comparison and the monthly view (incl. the same month last year).
        let start = min(HealthMath.fetchStart(period), HealthMath.fetchStart(.monthly))
        let all = HealthMath.resolve(days: HealthMath.completedDays(in: DateInterval(start: start, end: .now)),
            weights: health.weights, sleep: health.sleep, manual: journal.records)
        let byDay = Dictionary(all.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        func table(_ metric: HealthMetric) -> [Date: Double] {
            Dictionary(all.compactMap { row in metric.value(row).map { (row.day, $0) } }, uniquingKeysWith: { _, last in last })
        }
        return ReviewData(current: HealthMath.periodDays(period).compactMap { byDay[$0] },
            previous: HealthMath.comparisonDays(period).compactMap { byDay[$0] },
            sleep: table(.sleep), weight: table(.weight),
            mood: Dictionary(journal.records.compactMap { record in record.mood.map { (record.day, Double($0)) } },
                uniquingKeysWith: { _, last in last }))
    }
    private func average(_ metric: HealthMetric, rows: [DailyHealth]) -> Double? {
        HealthMath.average(rows.map { metric.value($0) })
    }
    private func insight(_ current: [DailyHealth]) -> String {
        let sleepCount = current.filter { $0.sleepMinutes != nil }.count
        guard sleepCount >= 3, let avg = average(.sleep, rows: current) else {
            return "記録がたまると、期間の平均や変化を振り返れます。まずは3日分、睡眠と体調を残してみましょう。"
        }
        let target = Double(journal.goals.sleepMinutes) / 60
        let difference = Int((abs(avg - target) * 60).rounded())
        if avg < target {
            return "記録のある\(sleepCount)日間の睡眠は、個人目標より平均\(difference)分短めでした。眠りが短かった日のメモを見返してみましょう。"
        }
        return "記録のある\(sleepCount)日間の平均睡眠は、個人目標に届いています。調子がよかった日の過ごし方をメモに残しておきましょう。"
    }
    private var rangeText: String {
        let days = HealthMath.periodDays(period)
        guard let first = days.first, let last = days.last else { return "" }
        let style: Date.FormatStyle = period == .week || period == .month ? .dateTime.month().day() : .dateTime.year().month().day()
        return "\(first.formatted(style)) 〜 \(last.formatted(style)) · 昨日まで" + (period == .monthly ? "（今月は途中）" : "")
    }

    var body: some View {
        let data = makeData()
        let count = HealthMath.periodDays(period).count
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("少し離れて、見えてくる。").font(.subheadline).foregroundStyle(Palette.secondary)
                Picker("期間", selection: $period) {
                    ForEach(ReviewPeriod.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                HStack {
                    Text(rangeText).font(.caption).foregroundStyle(Palette.secondary)
                    if health.isLoading { Spacer(); ProgressView().controlSize(.small) }
                }
                if period == .monthly, let last = HealthMath.recentMonths(count: 2).first {
                    MonthSummaryCard(title: "睡眠", unit: "時間", comparison: HealthMath.monthComparison(data.sleep, month: last))
                    MonthSummaryCard(title: "体重", unit: "kg", comparison: HealthMath.monthComparison(data.weight, month: last))
                    MonthSummaryCard(title: "体調", unit: "/5", comparison: HealthMath.monthComparison(data.mood, month: last))
                } else {
                    ForEach(HealthMetric.allCases, id: \.self) { type in
                        Surface {
                            SectionLabel(title: "平均\(type.rawValue)", detail: "記録 \(data.current.filter { type.value($0) != nil }.count)/\(count)日")
                            Text(average(type, rows: data.current).map { String(format: "%.1f %@", $0, type.unit) } ?? "まだ記録がありません")
                                .font(.system(.title, design: .rounded).weight(.semibold))
                            if let now = average(type, rows: data.current), let before = average(type, rows: data.previous) {
                                Text(String(format: "%@より %+.1f %@", period.comparisonLabel, now - before, type.unit))
                                    .font(.subheadline).foregroundStyle(Palette.green)
                                Text("比較期間の記録 \(data.previous.filter { type.value($0) != nil }.count)/\(data.previous.count)日")
                                    .font(.caption).foregroundStyle(Palette.secondary)
                            } else { Text("比較する記録がそろうと変化を表示します").font(.caption).foregroundStyle(Palette.secondary) }
                        }
                    }
                }
                Surface {
                    SectionLabel(title: period.isLong ? "長い目で見た変化" : "日ごとの変化")
                    Picker("表示する記録", selection: $metric) {
                        ForEach(HealthMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    if period.isLong {
                        LongTrend(period: period, metric: metric, days: HealthMath.periodDays(period),
                            values: data.values(metric), target: journal.goals.sleepMinutes)
                    } else {
                        HealthTrend(rows: data.current, metric: metric, target: journal.goals.sleepMinutes)
                    }
                    if period == .monthly {
                        MonthlyTable(months: HealthMath.recentMonths(), sleep: data.sleep, weight: data.weight, mood: data.mood)
                    }
                }
                SleepCalendarCard(sleep: data.sleep, target: journal.goals.sleepMinutes)
                Group {
                    ScreenReportCard(period: period)
                    ScreenReportCard(period: period, sns: true)
                    ScreenCalendarCard()
                }
                Surface {
                    Label("数字から、ひとつ気づく", systemImage: "leaf").font(.headline)
                    Text(insight(data.current)).font(.subheadline).lineSpacing(5)
                    Text("記録日数が違う期間の平均は、単純には比較できません。健康状態の診断ではありません。")
                        .font(.caption).foregroundStyle(Palette.secondary)
                }
                Group {
                    Text("出典：Appleヘルスケア・手入力。欠測日は平均から除外。")
                        .font(.caption).foregroundStyle(Palette.secondary)
                    if let sync = health.lastSync { Text("取得 \(sync.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Palette.secondary) }
                    if let message = health.message { Notice(text: message) }
                }
            }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(Palette.background).navigationTitle("振り返り")
            .task(id: period) { await health.ensureLoaded(period) }
    }
}

struct HealthTrend: View {
    var rows: [DailyHealth]
    var metric: HealthMetric
    var target: Int
    private var points: [HealthPoint] {
        var segment = 0
        return rows.compactMap { row in
            guard let value = metric.value(row) else { segment += 1; return nil }
            return HealthPoint(date: row.day, value: value, segment: segment)
        }
    }
    private var bounds: ClosedRange<Double> {
        let values = points.map(\.value)
        if metric == .weight { return max(0, (values.min() ?? 50) - 1)...((values.max() ?? 80) + 1) }
        return 0...max(10, max((values.max() ?? 0) + 1, Double(target) / 60 + 1))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(metric.rawValue)の推移（\(metric.unit)）").font(.caption).foregroundStyle(Palette.secondary)
            if points.isEmpty {
                ContentUnavailableView("まだ記録がありません", systemImage: "chart.xyaxis.line",
                    description: Text("ヘルスケアを接続するか、記録を入力してください。"))
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("日付", point.date), y: .value(metric.rawValue, point.value),
                            series: .value("連続区間", point.segment)).foregroundStyle(Palette.green)
                        PointMark(x: .value("日付", point.date), y: .value(metric.rawValue, point.value))
                            .foregroundStyle(Palette.green).symbolSize(24)
                    }
                    if metric == .sleep {
                        RuleMark(y: .value("個人目標", Double(target) / 60))
                            .foregroundStyle(.gray).lineStyle(StrokeStyle(dash: [4, 4]))
                    }
                }.frame(height: 180).chartYScale(domain: bounds)
                    .chartXScale(domain: rows.first!.day...rows.last!.day)
                    .chartYAxis { AxisMarks(position: .leading) }
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: rows.count > 7 ? 7 : 2)) { _ in
                        AxisValueLabel(format: .dateTime.month().day())
                    } }
                    .accessibilityLabel("\(metric.rawValue)の日別推移。下の記録一覧でも値を確認できます。")
                Text(metric == .weight ? "縦軸は0始まりではありません。" : "破線：自分で設定した睡眠目標")
                    .font(.caption2).foregroundStyle(Palette.secondary)
                DisclosureGroup("日別の数値・出典を見る") {
                    ForEach(rows) { row in
                        HStack {
                            Text(row.day.formatted(.dateTime.month().day()))
                            Spacer()
                            Text(metric.value(row).map { String(format: "%.1f %@", $0, metric.unit) } ?? "未記録")
                            Text(metric.value(row) == nil ? "" : (metric == .weight ? row.weightSource : row.sleepSource))
                                .foregroundStyle(Palette.secondary)
                        }.font(.caption).padding(.vertical, 4)
                    }
                }.font(.footnote)
            }
        }
    }
}

struct MonthSummaryCard: View {
    var title: String
    var unit: String
    var comparison: MonthComparison
    private var isScore: Bool { unit == "/5" }
    private func format(_ value: Double) -> String { String(format: isScore ? "%.1f%@" : "%.1f %@", value, unit) }
    var body: some View {
        Surface {
            SectionLabel(title: "\(comparison.month.start.formatted(.dateTime.month()))の平均\(title)", detail: "記録 \(comparison.recordedDays)日")
            Text(comparison.average.map(format) ?? "まだ記録がありません").font(.system(.title, design: .rounded).weight(.semibold))
            row("先月比", before: comparison.previousMonth, count: comparison.previousMonthRecorded)
            row("前年同月比", before: comparison.lastYear, count: comparison.lastYearRecorded)
        }
    }
    @ViewBuilder private func row(_ label: String, before: Double?, count: Int) -> some View {
        if let now = comparison.average, let before {
            Text(String(format: "%@ %+.1f%@（比較期間の記録 %d日）", label, now - before, isScore ? "" : " " + unit, count))
                .font(.caption).foregroundStyle(Palette.green)
        } else { Text("\(label)：比較する記録がありません").font(.caption).foregroundStyle(Palette.secondary) }
    }
}

struct LongTrend: View {
    var period: ReviewPeriod
    var metric: HealthMetric
    var days: [Date]
    var values: [Date: Double]
    var target: Int
    private var unit: BucketUnit { period == .quarter ? .week : .month }
    private var movingPoints: [HealthPoint] {
        let average = HealthMath.movingAverage(values, on: days)
        var segment = 0
        return days.compactMap { day in
            guard let value = average[day] else { segment += 1; return nil }
            return HealthPoint(date: day, value: value, segment: segment)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !days.contains(where: { values[$0] != nil }) {
                ContentUnavailableView("この期間の記録がありません", systemImage: "chart.xyaxis.line",
                    description: Text("ヘルスケアを接続するか、記録を入力してください。"))
            } else if metric == .weight { weightChart } else { sleepChart }
        }
    }

    private var weightChart: some View {
        let recorded = days.filter { values[$0] != nil }
        let all = recorded.compactMap { values[$0] }
        return VStack(alignment: .leading, spacing: 8) {
            Text("体重の推移（kg）").font(.caption).foregroundStyle(Palette.secondary)
            Chart {
                ForEach(recorded, id: \.self) { day in
                    PointMark(x: .value("日付", day), y: .value("体重", values[day] ?? 0))
                        .foregroundStyle(Palette.green.opacity(0.25)).symbolSize(12)
                }
                ForEach(movingPoints) { point in
                    LineMark(x: .value("日付", point.date), y: .value("7日移動平均", point.value),
                        series: .value("連続区間", point.segment)).foregroundStyle(Palette.green).lineStyle(StrokeStyle(lineWidth: 2.5))
                }
            }.frame(height: 190)
                .chartYScale(domain: max(0, (all.min() ?? 50) - 1)...((all.max() ?? 80) + 1))
                .chartXScale(domain: days.first!...days.last!)
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: period == .quarter ? 1 : 2)) { _ in
                    AxisValueLabel(format: .dateTime.month())
                } }
                .accessibilityLabel("体重の7日移動平均と日々の値。月別の一覧でも値を確認できます。")
            Text("線：7日移動平均（記録3件未満の日は表示なし）· 薄い点：日々の値 · 縦軸は0始まりではありません。")
                .font(.caption2).foregroundStyle(Palette.secondary)
        }
    }

    private var sleepChart: some View {
        let bars = HealthMath.buckets(values, days: days, unit: unit).filter { $0.average != nil }
        let weekly = unit == .week
        return VStack(alignment: .leading, spacing: 8) {
            Text("睡眠の\(weekly ? "週" : "月")平均（時間）").font(.caption).foregroundStyle(Palette.secondary)
            Chart {
                ForEach(bars) { bucket in
                    BarMark(x: .value(weekly ? "週" : "月", bucket.start, unit: weekly ? .weekOfYear : .month),
                        y: .value("睡眠", bucket.average ?? 0))
                        .foregroundStyle(Palette.green.opacity(bucket.isPartial ? 0.4 : 1))
                        .annotation(position: .top) {
                            Text("\(bucket.recordedDays)日").font(.system(size: 8)).foregroundStyle(Palette.secondary)
                        }
                }
                RuleMark(y: .value("個人目標", Double(target) / 60))
                    .foregroundStyle(.gray).lineStyle(StrokeStyle(dash: [4, 4]))
            }.frame(height: 190)
                .chartYScale(domain: 0...max(10, Double(target) / 60 + 1))
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis { AxisMarks(values: .stride(by: weekly ? .weekOfYear : .month, count: 2)) { _ in
                    AxisValueLabel(format: weekly ? Date.FormatStyle.dateTime.month().day() : Date.FormatStyle.dateTime.month())
                } }
                .accessibilityLabel("睡眠の\(weekly ? "週" : "月")平均。棒の上は記録日数。")
            Text("棒の上は記録日数 · 薄い棒は期間の途中 · 破線：自分で設定した睡眠目標")
                .font(.caption2).foregroundStyle(Palette.secondary)
        }
    }
}

struct MonthlyTable: View {
    var months: [DateInterval]
    var sleep: [Date: Double]
    var weight: [Date: Double]
    var mood: [Date: Double]
    private func summary(_ values: [Date: Double], _ days: [Date]) -> (average: Double?, count: Int) {
        let present = days.compactMap { values[$0] }
        return (HealthMath.average(present.map(Optional.some)), present.count)
    }
    private func text(_ value: Double?, _ format: String) -> String { value.map { String(format: format, $0) } ?? "未記録" }
    var body: some View {
        DisclosureGroup("月別の数値を見る") {
            ForEach(months.reversed(), id: \.start) { month in
                let days = HealthMath.completedDays(in: month)
                let s = summary(sleep, days), w = summary(weight, days), m = summary(mood, days)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(month.start.formatted(.dateTime.year().month())).fontWeight(.medium)
                        Spacer()
                        Text("睡眠の記録 \(s.count)/\(days.count)日").foregroundStyle(Palette.secondary)
                    }
                    Text("睡眠 \(text(s.average, "%.1f時間")) · 体重 \(text(w.average, "%.1fkg")) · 体調 \(text(m.average, "%.1f/5"))")
                }.font(.caption).padding(.vertical, 4)
            }
        }.font(.footnote)
    }
}

struct MonthStepper: View {
    @Binding var index: Int
    var months: [DateInterval]
    var body: some View {
        HStack {
            Button { index -= 1 } label: { Image(systemName: "chevron.left") }
                .disabled(index <= 0).accessibilityLabel("前の月")
            Spacer()
            Text(months[index].start.formatted(.dateTime.year().month())).font(.subheadline.weight(.medium))
            Spacer()
            Button { index += 1 } label: { Image(systemName: "chevron.right") }
                .disabled(index >= months.count - 1).accessibilityLabel("次の月")
        }.buttonStyle(.borderless)
    }
}

struct SleepCalendarCard: View {
    @EnvironmentObject private var health: HealthStore
    var sleep: [Date: Double]
    var target: Int
    @State private var index = 11
    private let months = HealthMath.recentMonths()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    var body: some View {
        let month = months[index]
        let maximum = Double(target) / 60 * 1.2
        let recorded = HealthMath.completedDays(in: month).filter { sleep[$0] != nil }.count
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let first = Calendar.current.firstWeekday - 1
        Surface {
            SectionLabel(title: "睡眠カレンダー", detail: "記録 \(recorded)日")
            MonthStepper(index: $index, months: months)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<7, id: \.self) { offset in
                    Text(symbols[(first + offset) % 7]).font(.caption2).foregroundStyle(Palette.secondary)
                }
                ForEach(Array(HealthMath.calendarGrid(month: month).enumerated()), id: \.offset) { _, day in
                    if let day {
                        let hours: Double? = sleep[day]
                        let value: String = hours.map { "睡眠" + HealthMath.duration(Int(($0 * 60).rounded())) } ?? "未記録"
                        HeatCell(day: day, level: HealthMath.intensity(hours, maximum: maximum), detail: value)
                    } else { Color.clear.frame(minHeight: 32) }
                }
            }
            Text("濃いほど長い（個人目標の1.2倍で最も濃い）· 無色は未記録（0ではありません）")
                .font(.caption2).foregroundStyle(Palette.secondary)
        }.onChange(of: index) { _, _ in Task { await health.ensureLoaded(.monthly) } }
    }
}

struct ScreenCalendarCard: View {
    @EnvironmentObject private var screen: ScreenTimeStore
    @ScaledMetric(relativeTo: .body) private var height = 320.0
    @State private var index = 11
    private let months = HealthMath.recentMonths()
    var body: some View {
        if screen.isAuthorized && screen.hasSNSSelection {
            Surface {
                SectionLabel(title: "SNSカレンダー")
                MonthStepper(index: $index, months: months)
                DeviceActivityReport(.rhythmSNSCalendar, filter: screen.calendarFilter(month: months[index], sns: true))
                    .id("sns-calendar-\(index)-\(screen.refreshID)").frame(height: height)
                Text("SNSの1日の合計を色の濃さで表示。値はAppleの専用レポート内だけで扱います。")
                    .font(.caption2).foregroundStyle(Palette.secondary)
            }
        }
    }
}
