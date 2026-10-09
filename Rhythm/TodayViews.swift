import SwiftUI
import Charts
import DeviceActivity

/// 今日の画面のカード。並び順と表示・非表示はこの端末のUserDefaultsにだけ保存する。
enum TodayCard: String, CaseIterable, Identifiable {
    case screen, gate, sleep, weight, steps
    var id: String { rawValue }
    var title: String {
        switch self {
        case .screen: return "スクリーンタイム（SNS）"
        case .gate: return "SNSゲート"
        case .sleep: return "睡眠"
        case .weight: return "体重"
        case .steps: return "歩数"
        }
    }

    /// 保存値から並び順を復元する。知らない値は捨て、足りないカードは末尾に足す。
    static func order(from saved: String) -> [TodayCard] {
        var result: [TodayCard] = []
        for card in saved.split(separator: ",").compactMap({ TodayCard(rawValue: String($0)) }) where !result.contains(card) {
            result.append(card)
        }
        return result + allCases.filter { !result.contains($0) }
    }
    static func hidden(from saved: String) -> Set<TodayCard> {
        Set(saved.split(separator: ",").compactMap { TodayCard(rawValue: String($0)) })
    }
    static func encode<S: Sequence>(_ cards: S) -> String where S.Element == TodayCard { cards.map(\.rawValue).joined(separator: ",") }
}

enum TodayKeys {
    static let order = "today.cardOrder"
    static let hidden = "today.cardHidden"
    /// 比べる基準の初期値（7または30）。設定で変える。
    static let compareDefault = "today.compareDefault"
}

struct TodayView: View {
    @EnvironmentObject private var journal: JournalStore
    @EnvironmentObject private var health: HealthStore
    @EnvironmentObject private var screen: ScreenTimeStore
    @EnvironmentObject private var gate: GateStore
    @AppStorage(TodayKeys.order) private var savedOrder = ""
    @AppStorage(TodayKeys.hidden) private var savedHidden = ""
    @AppStorage(TodayKeys.compareDefault) private var compareDefault = 7
    @State private var compare: Int?
    @State private var reordering = false
    var addEntry: () -> Void

    private var compareDays: Int { compare ?? compareDefault }
    private var visible: [TodayCard] {
        let hidden = TodayCard.hidden(from: savedHidden)
        return TodayCard.order(from: savedOrder).filter { !hidden.contains($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(Date.now.formatted(.dateTime.month().day().weekday(.wide))).font(.subheadline).foregroundStyle(Palette.secondary)
                Picker("比べる基準", selection: Binding(get: { compareDays }, set: { compare = $0 })) {
                    Text("7日平均と比べる").tag(7)
                    Text("30日平均と比べる").tag(30)
                }.pickerStyle(.segmented)
                ForEach(visible) { card in
                    switch card {
                    case .screen: TodayScreenCard(compareDays: compareDays)
                    case .gate: TodayGateCard(compareDays: compareDays)
                    case .sleep: TodaySleepCard(compareDays: compareDays)
                    case .weight: TodayWeightCard(compareDays: compareDays)
                    case .steps: TodayStepsCard(compareDays: compareDays)
                    }
                }
                let hidden = TodayCard.order(from: savedOrder).filter { TodayCard.hidden(from: savedHidden).contains($0) }
                if !hidden.isEmpty {
                    Text("非表示：" + hidden.map(\.title).joined(separator: "、")).font(.caption).foregroundStyle(Palette.secondary)
                }
                if let error = journal.loadError { Notice(text: error) }
                if !health.hasRequested {
                    Surface {
                        Label("ヘルスケアとつなぐ", systemImage: "heart.text.clipboard").font(.headline)
                        Text("Appleヘルスケアの体重・睡眠・歩数を読み取り専用で使います。")
                            .font(.footnote).foregroundStyle(Palette.secondary)
                        Button("Appleヘルスケアに接続") { Task { await health.connect() } }.buttonStyle(.bordered)
                    }
                }
                if let message = health.message { Notice(text: message) }
                if let sync = health.lastSync {
                    Text("ヘルスケア取得 \(sync.formatted(date: .omitted, time: .shortened)) · 下に引っぱると更新")
                        .font(.caption).foregroundStyle(Palette.secondary)
                }
            }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(Palette.background).navigationTitle("今日")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if health.isLoading { ProgressView() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("並び替え") { reordering = true }
                    Button("手入力", systemImage: "plus", action: addEntry)
                }
            }
            .refreshable { await health.refresh(); screen.updateStatus(); gate.refresh() }
            .sheet(isPresented: $reordering) { NavigationStack { ReorderSheet() } }
    }
}

// MARK: カード

struct TodayScreenCard: View {
    @EnvironmentObject private var screen: ScreenTimeStore
    @EnvironmentObject private var gate: GateStore
    @ScaledMetric(relativeTo: .body) private var height = 330.0
    var compareDays: Int

    var body: some View {
        Surface {
            SectionLabel(title: "スクリーンタイム", detail: "今日ここまで")
            if screen.isAuthorized {
                DeviceActivityReport(.rhythmTodayCard(compareDays: compareDays), filter: screen.todayFilter())
                    .id("today-\(compareDays)-\(screen.refreshID)")
                    .frame(height: height)
                if gate.isEnabled {
                    let work = GateMath.workMinutes(on: .now, gate.events)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("うち仕事目的").font(.caption2).foregroundStyle(Palette.secondary)
                        Text(work == 0 ? "なし" : "約\(work)分").font(.headline)
                        Text("ゲートで「仕事」を選んで開いた分（解除した時間で数えるおおよその値）")
                            .font(.caption2).foregroundStyle(Palette.secondary)
                    }
                }
                if !screen.hasSNSSelection {
                    Notice(text: "設定の「アプリの分類」でSNS・動画・仕事のアプリを選ぶと、内訳が分かれます。")
                }
            } else {
                Text("スマホとの距離も、見えるように。").font(.subheadline)
                Text("接続するとiPhoneの利用時間を自動で表示します。").font(.footnote).foregroundStyle(Palette.secondary)
                Button("スクリーンタイムに接続") { Task { await screen.connect() } }.buttonStyle(.bordered)
            }
            if let message = screen.message { Notice(text: message) }
        }
    }
}

struct TodayGateCard: View {
    @EnvironmentObject private var gate: GateStore
    var compareDays: Int

    var body: some View {
        Surface {
            SectionLabel(title: "SNSゲート", detail: "開く前に目的を選ぶ")
            if !gate.isEnabled && gate.events.isEmpty {
                Text("設定の「開く前に、ひと呼吸」をオンにすると、ここに回数が出ます。")
                    .font(.footnote).foregroundStyle(Palette.secondary)
            } else {
                let counts = gate.todayCounts
                let average = GateMath.dailyAverages(HealthMath.completedDays(count: compareDays), gate.events)
                let budget = gate.settings.dailyPlayBudget
                HStack(alignment: .top, spacing: 12) {
                    stat("開こうとした", "\(counts.opened + counts.stayedAway)回",
                         average.map { String(format: "平均 %.1f回", $0.attempts) })
                    stat("踏みとどまった", "\(counts.stayedAway)回",
                         average.map { String(format: "平均 %.1f回", $0.stayedAway) }, color: Palette.green)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("遊び予算").font(.caption2).foregroundStyle(Palette.secondary)
                        Text("\(gate.budgetUsed)/\(budget)分").font(.headline)
                        ProgressView(value: Double(min(gate.budgetUsed, budget)), total: Double(max(budget, 1)))
                            .tint(gate.isOverBudget ? Palette.vermilion : Palette.green)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ note: String?, color: Color = Palette.ink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(Palette.secondary)
            Text(value).font(.headline).foregroundStyle(color)
            if let note { Text(note).font(.caption2).foregroundStyle(Palette.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TodaySleepCard: View {
    @EnvironmentObject private var journal: JournalStore
    @EnvironmentObject private var health: HealthStore
    var compareDays: Int

    var body: some View {
        let today = Calendar.current.startOfDay(for: .now)
        let row = HealthMath.resolve(days: [today], weights: health.weights, sleep: health.sleep, manual: journal.records)[0]
        let past = HealthMath.resolve(days: HealthMath.completedDays(count: compareDays), weights: health.weights,
            sleep: health.sleep, manual: journal.records)
        let average = HealthMath.average(past.map { $0.sleepMinutes.map(Double.init) })
        Surface {
            SectionLabel(title: "睡眠（昨夜）", detail: row.sleepMinutes == nil ? "ヘルスケア" : row.sleepSource)
            if let minutes = row.sleepMinutes {
                HStack(alignment: .firstTextBaseline) {
                    BigValue(text: HealthMath.shortDuration(Double(minutes)))
                    Spacer()
                    NeutralDelta(delta: average.map { Double(minutes) - $0 }, threshold: 1) { HealthMath.shortDuration(abs($0)) }
                }
                if let average {
                    CompareBars(today: Double(minutes), average: average, label: { HealthMath.shortDuration($0) })
                    Text("平均＝過去\(compareDays)日のうち記録のある日").font(.caption2).foregroundStyle(Palette.secondary)
                }
            } else {
                Text("前日正午〜今日正午の睡眠はまだありません").font(.subheadline).foregroundStyle(Palette.secondary)
            }
        }
    }
}

struct TodayWeightCard: View {
    @EnvironmentObject private var journal: JournalStore
    @EnvironmentObject private var health: HealthStore
    var compareDays: Int

    private struct Point: Identifiable { var day: Date; var value: Double; var id: Date { day } }

    var body: some View {
        let today = Calendar.current.startOfDay(for: .now)
        let recent = HealthMath.resolve(days: HealthMath.completedDays(count: 13) + [today], weights: health.weights,
            sleep: health.sleep, manual: journal.records)
        let points = recent.compactMap { row in row.weight.map { Point(day: row.day, value: $0) } }
        let past = HealthMath.resolve(days: HealthMath.completedDays(count: compareDays), weights: health.weights,
            sleep: health.sleep, manual: journal.records)
        let average = HealthMath.average(past.map(\.weight))
        let latest = recent.last(where: { $0.weight != nil })
        Surface {
            SectionLabel(title: latest?.day == today ? "体重（今日）" : "体重（最新）",
                detail: latest.map { $0.day == today ? $0.weightSource : $0.day.formatted(.dateTime.month().day()) + "の記録" } ?? "ヘルスケア")
            if let latest, let weight = latest.weight {
                HStack(alignment: .firstTextBaseline) {
                    BigValue(text: String(format: "%.1f", weight), unit: "kg")
                    Spacer()
                    NeutralDelta(delta: average.map { weight - $0 }, threshold: 0.05) { String(format: "%.1fkg", abs($0)) }
                }
                let values = points.map(\.value) + (average.map { [$0] } ?? [])
                Chart {
                    if let average {
                        RuleMark(y: .value("平均", average)).foregroundStyle(Palette.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    ForEach(points) { point in
                        PointMark(x: .value("日付", point.day), y: .value("体重", point.value))
                            .foregroundStyle(point.day == latest.day ? Palette.green : Palette.secondary.opacity(0.5))
                            .symbolSize(point.day == latest.day ? 60 : 24)
                    }
                }.frame(height: 64)
                    .chartXScale(domain: recent.first!.day...today)
                    .chartYScale(domain: (values.min()! - 0.2)...(values.max()! + 0.2))
                    .chartXAxis(.hidden).chartYAxis(.hidden)
                    .accessibilityLabel("直近14日の体重の点と、\(compareDays)日平均の線")
                Text("点線＝\(compareDays)日平均\(average.map { String(format: " %.1fkg", $0) } ?? "（記録なし）") · 直近14日（縦軸は0からではありません）")
                    .font(.caption2).foregroundStyle(Palette.secondary)
            } else {
                Text("直近14日の記録がありません").font(.subheadline).foregroundStyle(Palette.secondary)
            }
        }
    }
}

struct TodayStepsCard: View {
    @EnvironmentObject private var health: HealthStore
    var compareDays: Int

    var body: some View {
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let current = HealthMath.dailyTotals(health.stepsHourly)[today]
        let past = HealthMath.totalsUntil(health.stepsHourly, days: HealthMath.completedDays(count: compareDays),
            elapsed: now.timeIntervalSince(today))
        let average = past.isEmpty ? nil : past.values.reduce(0, +) / Double(past.count)
        Surface {
            SectionLabel(title: "歩数（\(now.formatted(date: .omitted, time: .shortened))時点）", detail: "ヘルスケア")
            if current != nil || average != nil {
                let steps = current ?? 0
                HStack(alignment: .firstTextBaseline) {
                    BigValue(text: steps.formatted(.number.precision(.fractionLength(0))), unit: "歩")
                    Spacer()
                    NeutralDelta(delta: average.map { steps - $0 }, threshold: 50) { $0.magnitude.formatted(.number.precision(.fractionLength(0))) + "歩" }
                }
                if let average {
                    CompareBars(today: steps, average: average, label: { $0.formatted(.number.precision(.fractionLength(0))) })
                    Text("平均＝過去\(compareDays)日のうち記録のある\(past.count)日の、同じ時刻までの歩数")
                        .font(.caption2).foregroundStyle(Palette.secondary)
                }
            } else {
                Text("歩数の記録がありません。ヘルスケアで歩数の読み取りを許可しているか確認してください。")
                    .font(.footnote).foregroundStyle(Palette.secondary)
            }
        }
    }
}

// MARK: 部品

struct BigValue: View {
    var text: String
    var unit = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(text).font(.system(.largeTitle, design: .rounded).weight(.semibold)).contentTransition(.numericText())
            if !unit.isEmpty { Text(unit).font(.subheadline).foregroundStyle(Palette.secondary) }
        }
    }
}

/// 睡眠・体重・歩数は良し悪しを決めないので中立色で示す。
struct NeutralDelta: View {
    var delta: Double?
    var threshold: Double
    var format: (Double) -> String
    var body: some View {
        Group {
            if let delta {
                if abs(delta) < threshold { Text("± 平均と同じ") }
                else { Text("\(delta > 0 ? "↑" : "↓") \(format(delta)) 平均より\(delta > 0 ? "多い" : "少ない")") }
            } else { Text("平均はまだありません") }
        }.font(.caption.weight(.medium)).foregroundStyle(Palette.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Palette.background, in: Capsule())
    }
}

struct CompareBars: View {
    var today: Double
    var average: Double
    var label: (Double) -> String
    var body: some View {
        let maximum = max(today, average, 1) * 1.08
        VStack(spacing: 6) {
            bar("今日", today, maximum, Palette.green)
            bar("平均", average, maximum, Palette.secondary.opacity(0.45))
        }
    }
    private func bar(_ title: String, _ value: Double, _ maximum: Double, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption2).foregroundStyle(Palette.secondary).frame(width: 28, alignment: .leading)
            GeometryReader { proxy in
                Capsule().fill(Palette.background)
                    .overlay(alignment: .leading) { Capsule().fill(color).frame(width: proxy.size.width * value / maximum) }
            }.frame(height: 8)
            Text(label(value)).font(.caption2.monospacedDigit()).frame(width: 64, alignment: .trailing)
        }.accessibilityElement(children: .combine)
    }
}

// MARK: 並び替え

struct ReorderSheet: View {
    @AppStorage(TodayKeys.order) private var savedOrder = ""
    @AppStorage(TodayKeys.hidden) private var savedHidden = ""
    @Environment(\.dismiss) private var dismiss
    @State private var order: [TodayCard] = []
    @State private var hidden: Set<TodayCard> = []

    var body: some View {
        List {
            Section {
                ForEach(Array(order.enumerated()), id: \.element) { index, card in
                    HStack(spacing: 12) {
                        Toggle(card.title, isOn: Binding(get: { !hidden.contains(card) },
                            set: { shown in if shown { hidden.remove(card) } else { hidden.insert(card) } }))
                        Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0).accessibilityLabel("\(card.title)を上へ")
                        Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(index == order.count - 1).accessibilityLabel("\(card.title)を下へ")
                    }.buttonStyle(.borderless)
                }
            } footer: {
                Text("上下のボタンで順番、スイッチで表示・非表示を変えます。このiPhoneの中にだけ保存します。")
            }
            Section {
                Button("最初の並びに戻す") { order = TodayCard.allCases; hidden = [] }
            }
        }.navigationTitle("今日の画面を編集").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        savedOrder = TodayCard.encode(order)
                        savedHidden = TodayCard.encode(order.filter(hidden.contains))
                        dismiss()
                    }
                }
            }
            .onAppear {
                order = TodayCard.order(from: savedOrder)
                hidden = TodayCard.hidden(from: savedHidden)
            }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
    }
}
