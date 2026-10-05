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
                ScreenReportCard(days: nil)
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
    @ScaledMetric(relativeTo: .body) private var todayHeight = 140.0
    var days: Int?
    private var context: DeviceActivityReport.Context {
        days == nil ? .rhythmToday : (days == 7 ? .rhythmWeek : .rhythmMonth)
    }
    var body: some View {
        Surface {
            Label("スクリーンタイム", systemImage: "iphone").font(.headline)
            if screen.isAuthorized {
                DeviceActivityReport(context, filter: screen.filter(days: days))
                    .id("\(context.rawValue)-\(screen.refreshID)")
                    .frame(height: days == nil ? todayHeight : reportHeight)
                Text("個人目標 \(HealthMath.duration(journal.goals.screenMinutes)) / 日")
                    .font(.caption).foregroundStyle(Palette.secondary)
                Text("Apple提供のiPhone利用時間。表示に時間がかかる場合は更新してください。")
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

struct ReviewView: View {
    @EnvironmentObject private var journal: JournalStore
    @EnvironmentObject private var health: HealthStore
    @State private var count = 7
    @State private var metric: HealthMetric = .sleep
    private var days: [Date] { HealthMath.completedDays(count: count * 2) }
    private var resolved: [DailyHealth] {
        HealthMath.resolve(days: days, weights: health.weights, sleep: health.sleep, manual: journal.records)
    }
    private var current: [DailyHealth] { Array(resolved.suffix(count)) }
    private var previous: [DailyHealth] { Array(resolved.prefix(count)) }
    private func average(_ metric: HealthMetric, rows: [DailyHealth]) -> Double? {
        HealthMath.average(rows.map { metric.value($0) })
    }
    private var insight: String {
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("少し離れて、見えてくる。").font(.subheadline).foregroundStyle(Palette.secondary)
                Picker("期間", selection: $count) { Text("7日間").tag(7); Text("28日間").tag(28) }.pickerStyle(.segmented)
                Text("\(current.first!.day.formatted(.dateTime.month().day())) 〜 \(current.last!.day.formatted(.dateTime.month().day())) · 昨日まで")
                    .font(.caption).foregroundStyle(Palette.secondary)
                ForEach(HealthMetric.allCases, id: \.self) { type in
                    Surface {
                        SectionLabel(title: "平均\(type.rawValue)", detail: "記録 \(current.filter { type.value($0) != nil }.count)/\(count)日")
                        Text(average(type, rows: current).map { String(format: "%.1f %@", $0, type.unit) } ?? "まだ記録がありません")
                            .font(.system(.title, design: .rounded).weight(.semibold))
                        if let now = average(type, rows: current), let before = average(type, rows: previous) {
                            Text(String(format: "前の%d日より %+.1f %@", count, now - before, type.unit))
                                .font(.subheadline).foregroundStyle(Palette.green)
                            Text("比較期間の記録 \(previous.filter { type.value($0) != nil }.count)/\(count)日")
                                .font(.caption).foregroundStyle(Palette.secondary)
                        } else { Text("比較する記録がそろうと変化を表示します").font(.caption).foregroundStyle(Palette.secondary) }
                    }
                }
                Surface {
                    SectionLabel(title: "日ごとの変化")
                    Picker("表示する記録", selection: $metric) {
                        ForEach(HealthMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    HealthTrend(rows: current, metric: metric, target: journal.goals.sleepMinutes)
                }
                ScreenReportCard(days: count)
                Surface {
                    Label("数字から、ひとつ気づく", systemImage: "leaf").font(.headline)
                    Text(insight).font(.subheadline).lineSpacing(5)
                    Text("記録日数が違う期間の平均は、単純には比較できません。健康状態の診断ではありません。")
                        .font(.caption).foregroundStyle(Palette.secondary)
                }
                Text("出典：Appleヘルスケア・手入力。欠測日は平均から除外。")
                    .font(.caption).foregroundStyle(Palette.secondary)
                if let sync = health.lastSync { Text("取得 \(sync.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Palette.secondary) }
                if let message = health.message { Notice(text: message) }
            }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(Palette.background).navigationTitle("振り返り")
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
