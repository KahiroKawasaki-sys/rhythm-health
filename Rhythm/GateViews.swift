import SwiftUI
import LocalAuthentication

// MARK: 目的選択（通知のタップ・rhythm://gate から開く）

struct GateView: View {
    @EnvironmentObject private var gate: GateStore
    @Environment(\.dismiss) private var dismiss
    private enum Step: Equatable { case choose, work, waiting(GatePurpose), opened(Date), stayed }
    @State private var step: Step = .choose
    @State private var note = ""
    @State private var remaining = 0
    @State private var confirmEmergency = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) { content }
                    .padding(20).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
            .background(Palette.background)
            .navigationTitle("ひと呼吸").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }
        .onAppear { gate.refresh() }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .choose: choose
        case .work: work
        case .waiting(let purpose): waiting(purpose)
        case .opened(let until): opened(until)
        case .stayed: PraiseView(count: weekStayedAway) { dismiss() }
        }
        if let message = gate.message { Notice(text: message) }
    }

    private var weekStayedAway: Int {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        return gate.events.filter { $0.kind == .stayedAway && $0.date >= start }.count
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("開く前に、ひと呼吸").font(.system(.title2, design: .rounded).weight(.semibold))
            let counts = gate.todayCounts
            Text("今日 開いた\(counts.opened)回・やめた\(counts.stayedAway)回").font(.subheadline).foregroundStyle(Palette.secondary)
            HStack(spacing: 6) {
                Text("遊び予算 \(gate.budgetUsed)/\(gate.settings.dailyPlayBudget)分").font(.caption)
                if gate.isOverBudget {
                    Text("超過中").font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2).background(Color.orange, in: Capsule())
                }
            }
        }
    }

    private var stayAwayButton: some View {
        Button { gate.stayAway(); withAnimation { step = .stayed } } label: { Text("やめておく") }
    }

    @ViewBuilder private var choose: some View {
        header
        if !gate.isEnabled { Notice(text: "ひと呼吸の仕組みはオフです。設定からオンにできます。") }
        if let until = gate.unlockedUntil { Notice(text: "\(until.formatted(date: .omitted, time: .shortened))まで解除中です。") }
        if gate.harvestPending { HarvestCard() }
        Text("何のために開きますか？").font(.headline)
        ForEach(GatePurpose.allCases) { purpose in
            Button {
                withAnimation { step = purpose == .work ? .work : .waiting(purpose) }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(purpose.label).font(.headline).foregroundStyle(Palette.ink)
                        Text(detail(purpose)).font(.caption).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Palette.secondary)
                }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 16))
            }.disabled(!gate.isEnabled)
        }
        stayAwayButton.buttonStyle(PrimaryButtonStyle())
        if gate.emergencyAvailable && gate.isEnabled {
            Button("緊急（1日1回・待機なしで\(GateMath.emergencyMinutes)分）") { confirmEmergency = true }
                .font(.footnote).frame(maxWidth: .infinity)
                .confirmationDialog("今日の緊急解除を使いますか？", isPresented: $confirmEmergency, titleVisibility: .visible) {
                    Button("\(GateMath.emergencyMinutes)分開く") { if let until = gate.openEmergency() { step = .opened(until) } }
                } message: { Text("遊び予算には入りません。今日はもう使えなくなります。") }
        }
    }

    private func detail(_ purpose: GatePurpose) -> String {
        let minutes = gate.settings.minutes(for: purpose)
        switch purpose {
        case .work: return "\(minutes)分・予算に入れない・何を調べるか一言"
        case .play, .idle: return "\(minutes)分・深呼吸\(gate.waitSeconds(for: purpose))秒のあと"
        }
    }

    @ViewBuilder private var work: some View {
        header
        Text("何を調べる？").font(.headline)
        TextField("例：〇〇さんの投稿を確認", text: $note).textFieldStyle(.roundedBorder).submitLabel(.done)
        Button {
            if let until = gate.open(.work, note: note) { step = .opened(until) }
        } label: { Text("\(gate.settings.workMinutes)分開く") }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Text("終わるころに「収穫あった？」と通知します。").font(.caption).foregroundStyle(Palette.secondary)
        stayAwayButton.frame(maxWidth: .infinity)
        Button("目的を選び直す") { step = .choose }.font(.footnote).frame(maxWidth: .infinity)
    }

    @ViewBuilder private func waiting(_ purpose: GatePurpose) -> some View {
        header
        BreathingCircle()
            .frame(maxWidth: .infinity).padding(.vertical, 8)
        let minutes = gate.settings.minutes(for: purpose)
        let openButton = Button {
            if let until = gate.open(purpose) { step = .opened(until) }
        } label: { Text(remaining > 0 ? "あと\(remaining)秒" : "\(minutes)分開く") }.disabled(remaining > 0)
        if purpose == .idle {
            Text("なんとなく、なら今日はやめておきませんか。").font(.subheadline)
            stayAwayButton.buttonStyle(PrimaryButtonStyle())
            openButton.frame(maxWidth: .infinity)
        } else {
            openButton.buttonStyle(PrimaryButtonStyle())
            stayAwayButton.frame(maxWidth: .infinity)
        }
        if gate.isOverBudget { Text("遊び予算を超えているため、待機は60秒です。").font(.caption).foregroundStyle(Palette.secondary) }
        Button("目的を選び直す") { step = .choose }.font(.footnote).frame(maxWidth: .infinity)
            .task(id: step) {
                remaining = gate.waitSeconds(for: purpose)
                while remaining > 0 {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                    remaining -= 1
                }
            }
    }

    @ViewBuilder private func opened(_ until: Date) -> some View {
        Surface {
            Label("いってらっしゃい", systemImage: "leaf").font(.headline).foregroundStyle(Palette.green)
            Text("ホーム画面からアプリを開いてください。\(until.formatted(date: .omitted, time: .shortened))ごろ、もう一度ひと呼吸に戻ります。")
                .font(.subheadline)
            Text("戻る時刻は数分ずれることがあります。").font(.caption).foregroundStyle(Palette.secondary)
        }
        Button("閉じる") { dismiss() }.buttonStyle(PrimaryButtonStyle())
    }
}

/// 吸う4秒・吐く6秒の拡縮（MindGateから流用）。
struct BreathingCircle: View {
    @State private var expanded = false
    @State private var inhaling = true
    var body: some View {
        ZStack {
            Circle().fill(Palette.green.opacity(0.12)).frame(width: 200, height: 200)
            Circle().fill(Palette.green.opacity(0.35))
                .frame(width: 200, height: 200).scaleEffect(expanded ? 1 : 0.45)
            Text(inhaling ? "吸って…" : "吐いて…").font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
        }
        .accessibilityLabel(inhaling ? "息を吸う" : "息を吐く")
        .task {
            while !Task.isCancelled {
                inhaling = true
                withAnimation(.easeInOut(duration: 4)) { expanded = true }
                try? await Task.sleep(for: .seconds(4))
                inhaling = false
                withAnimation(.easeInOut(duration: 6)) { expanded = false }
                try? await Task.sleep(for: .seconds(6))
            }
        }
    }
}

/// 踏みとどまった後のほめる演出（MindGateから流用）。
struct PraiseView: View {
    var count: Int
    var close: () -> Void
    @State private var shown = 0
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "leaf.fill").font(.system(size: 48)).foregroundStyle(Palette.green)
            Text("+1 踏みとどまり！").font(.system(.title, design: .rounded).weight(.bold))
            Text("今週 \(shown)回目").font(.title3).contentTransition(.numericText(value: Double(shown)))
            Text("その時間は、あなたのものです。").foregroundStyle(Palette.secondary)
            Button("閉じる", action: close).buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .task {
            for value in 0...max(count, 0) {
                withAnimation(.snappy) { shown = value }
                try? await Task.sleep(for: .milliseconds(min(120, 900 / max(count, 1))))
            }
        }
    }
}

struct HarvestCard: View {
    @EnvironmentObject private var gate: GateStore
    var body: some View {
        Surface {
            SectionLabel(title: "収穫あった？", detail: "仕事・情報収集")
            HStack {
                Button("あった") { gate.recordHarvest(true) }.buttonStyle(.borderedProminent)
                Button("なかった") { gate.recordHarvest(false) }.buttonStyle(.bordered)
            }
        }
    }
}

// MARK: 設定

struct GateSettingsSection: View {
    @EnvironmentObject private var gate: GateStore
    @EnvironmentObject private var screen: ScreenTimeStore
    @State private var draft = GateSettings()
    @State private var saved = false
    @State private var disableCountdown: Int?
    @State private var authMessage: String?

    var body: some View {
        Section {
            if gate.isEnabled {
                Label("オン：選んだアプリとWebサイトを開くと、ひと呼吸の画面が出ます", systemImage: "leaf")
                    .foregroundStyle(Palette.green)
                if let until = gate.unlockedUntil { Text("\(until.formatted(date: .omitted, time: .shortened))まで解除中").font(.caption) }
                Button("目的を選ぶ画面を開く") { gate.isGatePresented = true }
                disableControls
            } else {
                Button { Task { await gate.enable(selection: screen.categories.gateSelection) } } label: {
                    Label("ひと呼吸の仕組みをオンにする", systemImage: "leaf")
                }.disabled(!screen.isAuthorized || !screen.hasSNSSelection || gate.loadError != nil)
                if !screen.hasSNSSelection { Text("先に上の「アプリの分類」でSNSを選んでください。").font(.caption).foregroundStyle(Palette.secondary) }
            }
            Stepper("仕事・情報収集 \(draft.workMinutes)分", value: $draft.workMinutes, in: GateSettings.minuteRange)
            Stepper("遊び \(draft.playMinutes)分", value: $draft.playMinutes, in: GateSettings.minuteRange)
            Stepper("なんとなく \(draft.idleMinutes)分", value: $draft.idleMinutes, in: GateSettings.minuteRange)
            Stepper("遊び予算 1日\(draft.dailyPlayBudget)分", value: $draft.dailyPlayBudget, in: GateSettings.budgetRange, step: 5)
            NavigationLink { GateHoursView() } label: {
                LabeledContent("ゲートを強める時間帯", value: gate.settings.strongHoursText)
            }
            Button("解除時間を保存") {
                // 時間帯は別の画面で保存するので、ここでは今の値を引き継ぐ。
                var next = draft
                next.strongHours = gate.settings.strongHours
                do { try gate.saveSettings(next); saved = true } catch { saved = false; gate.message = error.localizedDescription }
            }.disabled(draftUnchanged || gate.loadError != nil)
            if saved { Text("保存しました").font(.caption).foregroundStyle(Palette.green) }
            if let error = gate.loadError { Text(error).font(.caption).foregroundStyle(.red) }
            if let message = gate.message { Text(message).font(.caption) }
            if let authMessage { Text(authMessage).font(.caption).foregroundStyle(.red) }
        } header: { Text("開く前に、ひと呼吸") } footer: {
            Text("シールドの「理由を選んで開く」は通知でRhythmを開きます。通知を許可してください。待機は同じ日の遊び・なんとなくの回数に応じて5秒ずつ延び（最大60秒）、ゲートを強める時間帯は2倍です。記録はこのiPhoneの中にだけ保存し、外部へは送りません。")
        }
        .onAppear { draft = gate.settings }
        .onChange(of: draft) { _, _ in saved = false }
    }

    private var draftUnchanged: Bool {
        var current = draft
        current.strongHours = gate.settings.strongHours
        return current == gate.settings
    }

    @ViewBuilder private var disableControls: some View {
        if let seconds = disableCountdown {
            if seconds > 0 {
                Text("オフにできるまで あと\(seconds)秒").monospacedDigit()
                    .task {
                        try? await Task.sleep(for: .seconds(1))
                        if let current = disableCountdown, current > 0 { disableCountdown = current - 1 }
                    }
                    .id(seconds)
            } else {
                Button("オフにする", role: .destructive) { gate.disable(); disableCountdown = nil }
            }
            Button("やめる（オンのまま）") { disableCountdown = nil }
        } else {
            Button("オフにする（認証と60秒の待機）") { Task { await authenticateToDisable() } }.foregroundStyle(.red)
        }
    }

    private func authenticateToDisable() async {
        let context = LAContext()
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "ひと呼吸の仕組みをオフにします") else { return }
            authMessage = nil
            disableCountdown = GateMath.disableWaitSeconds
        } catch { authMessage = "認証できなかったため、オンのままにしました。" }
    }
}

// MARK: 振り返り

struct GateReviewCard: View {
    @EnvironmentObject private var gate: GateStore
    var period: ReviewPeriod

    var body: some View {
        let days = HealthMath.periodDays(period)
        let summary = GateMath.summary(gate.events, days: days)
        Surface {
            SectionLabel(title: "ひと呼吸", detail: "昨日まで\(period.dayCount)日")
            if gate.events.isEmpty {
                Text(gate.isEnabled ? "まだ記録がありません。" : "設定から「開く前に、ひと呼吸」をオンにすると、ここに記録が出ます。")
                    .font(.subheadline).foregroundStyle(Palette.secondary)
            } else {
                HStack(spacing: 12) {
                    stat("開いた", "\(summary.opened)回")
                    stat("踏みとどまった", "\(summary.stayedAway)回")
                }
                Text("目的：" + GatePurpose.allCases.map { "\($0.label) \(summary.byPurpose[$0] ?? 0)回" }.joined(separator: "・")
                     + (summary.emergencies > 0 ? "・緊急 \(summary.emergencies)回" : ""))
                    .font(.footnote)
                Text(summary.budgetDays == 0 ? "遊び予算：使った日はありません" :
                     "遊び予算：使った日の平均 \(summary.budgetMinutes / summary.budgetDays)分/日（\(summary.budgetDays)日）")
                    .font(.footnote)
                harvest
                reach(summary)
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Palette.secondary)
            Text(value).font(.system(.title2, design: .rounded).weight(.semibold))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var harvest: some View {
        let months = GateMath.monthlyHarvest(gate.events).suffix(3)
        if !months.isEmpty {
            Text("仕事の収穫率（月）：" + months.map { month in
                "\(month.month.formatted(.dateTime.month()))\(month.rate.map { " \(Int(($0 * 100).rounded()))%" } ?? "")（\(month.answered)回）"
            }.joined(separator: "・")).font(.footnote)
        }
    }

    @ViewBuilder private func reach(_ summary: GateSummary) -> some View {
        if !summary.reachByDay.isEmpty {
            let lines = GateMath.reachLines.reversed().map { line in
                (line, summary.reachByDay.values.filter { $0 == line }.count)
            }.filter { $0.1 > 0 }
            Text("SNSの到達ライン（おおよそ）：" + lines.map { "\($0.0)分以上 \($0.1)日" }.joined(separator: "・"))
                .font(.footnote)
            Text("記録はRhythmの監視で残したもので、Appleの保持期間に左右されません。iPhoneのロック中に越えた分は残らないことがあります。")
                .font(.caption).foregroundStyle(Palette.secondary)
        }
    }
}

// MARK: ゲートを強める時間帯（P1）

/// 待機を2倍にする時を1時間単位で選ぶ。スクリーンタイム詳細の濃淡表を見て決める。
struct GateHoursView: View {
    @EnvironmentObject private var gate: GateStore
    @Environment(\.dismiss) private var dismiss
    @State private var hours: Set<Int> = []
    @State private var error: String?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(0..<24, id: \.self) { hour in
                        let on = hours.contains(hour)
                        Button {
                            if on { hours.remove(hour) } else { hours.insert(hour) }
                        } label: {
                            Text("\(hour)時").font(.footnote.weight(on ? .semibold : .regular)).frame(maxWidth: .infinity, minHeight: 34)
                                .foregroundStyle(on ? Color.white : Palette.ink)
                                .background(on ? Palette.vermilion : Palette.background, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(hour)時から1時間")
                            .accessibilityValue(on ? "強める" : "通常")
                    }
                }.padding(.vertical, 4)
                LabeledContent("選んだ時間帯", value: GateSettings(strongHours: hours).strongHoursText)
            } footer: {
                Text("選んだ時間に遊び・なんとなくで開くと、待機が2倍になります（最大60秒）。仕事・情報収集は待ちません。")
            }
            Section {
                Button("夜22時〜朝9時に戻す") { hours = GateSettings.defaultStrongHours }
                Button("すべて外す", role: .destructive) { hours = [] }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }.navigationTitle("ゲートを強める時間帯").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var next = gate.settings
                        next.strongHours = hours
                        do { try gate.saveSettings(next); dismiss() } catch { self.error = error.localizedDescription }
                    }.disabled(hours == gate.settings.strongHours || gate.loadError != nil)
                }
            }
            .onAppear { hours = gate.settings.strongHours }
    }
}
