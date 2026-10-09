import SwiftUI
import FamilyControls

struct SettingsView: View {
    @EnvironmentObject private var journal: JournalStore
    @EnvironmentObject private var health: HealthStore
    @EnvironmentObject private var screen: ScreenTimeStore
    @EnvironmentObject private var gate: GateStore
    @State private var sleepGoal = 450
    @State private var screenGoal = 180
    @State private var saved = false
    @State private var error: String?
    @AppStorage(TodayKeys.compareDefault) private var compareDefault = 7
    @State private var editing: ScreenCategory?
    @State private var picking = false
    @State private var draft = FamilyActivitySelection()
    @State private var selectionMessage: String?
    var body: some View {
        Form {
            Section("自動連携") {
                Button { Task { await health.connect() } } label: {
                    Label(health.hasRequested ? "ヘルスケアのアクセスを確認" : "Appleヘルスケアに接続", systemImage: "heart")
                }
                Text("体重・睡眠・歩数を読み取り専用で取得。起動・復帰・更新操作で反映します。読み取り拒否とデータなしはアプリから区別できません。")
                    .font(.footnote).foregroundStyle(Palette.secondary)
                Button { Task { await screen.connect() } } label: { Label("スクリーンタイムのアクセスを確認", systemImage: "iphone") }
                Text(screen.isAuthorized ? "スクリーンタイム：許可済み" : "スクリーンタイム：未接続")
                    .font(.caption).foregroundStyle(Palette.secondary)
                Button("iPhoneのアプリ設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Text("読み取り項目の変更は、ヘルスケアのプロフィール → アプリ → Rhythmから行います。画面名はiOSにより異なります。")
                    .font(.caption).foregroundStyle(Palette.secondary)
                if let message = health.message { Text(message).font(.caption) }
                if let message = screen.message { Text(message).font(.caption) }
            }
            Section {
                if screen.isAuthorized {
                    ForEach([ScreenCategory.sns, .video, .work]) { category in
                        Button { open(category) } label: {
                            HStack {
                                Circle().fill(category.color).frame(width: 9, height: 9)
                                Text(category.label).foregroundStyle(Palette.ink)
                                Spacer()
                                Text(count(category)).font(.caption).foregroundStyle(Palette.secondary)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.secondary)
                            }
                        }.disabled(screen.selectionError != nil)
                    }
                } else {
                    Button { Task { await screen.connect() } } label: { Label("先にスクリーンタイムに接続", systemImage: "iphone") }
                }
                if let message = screen.selectionError { Text(message).font(.caption).foregroundStyle(.red) }
                if let selectionMessage { Text(selectionMessage).font(.caption).foregroundStyle(Palette.green) }
            } header: { Text("アプリの分類（スクリーンタイム）") } footer: {
                Text("SNS：X・Instagramなど（x.com・instagram.comも）／動画：YouTubeなど／仕事：Notion・Slack・Google Chatなど。どれにも入れていないアプリ（LINE・Chromeなど）は「その他」です。SNSと動画は開く前のゲートの対象です。Appleの仕組みにより、アプリ名はRhythmからは読み取れません。選択はこのiPhoneの中にだけ保存します。")
            }
            Section {
                Picker("開いたときの比較", selection: $compareDefault) {
                    Text("7日平均").tag(7)
                    Text("30日平均").tag(30)
                }
                Stepper("SNSの1日目標 \(screen.categories.snsGoalMinutes)分", value: Binding(
                    get: { screen.categories.snsGoalMinutes },
                    set: { value in
                        var next = screen.categories
                        next.snsGoalMinutes = value
                        do { try screen.saveCategories(next) } catch { screen.message = error.localizedDescription }
                    }), in: ScreenCategories.goalRange, step: 5)
                    .disabled(screen.selectionError != nil)
            } header: { Text("比べる基準") } footer: {
                Text("SNSの目標は、今日の画面の「目標以下の連続日数」に使います。")
            }
            GateSettingsSection()
            Section {
                Stepper("睡眠 \(HealthMath.duration(sleepGoal))", value: $sleepGoal, in: 60...960, step: 15)
                Stepper("スマホ \(HealthMath.duration(screenGoal))", value: $screenGoal, in: 0...1440, step: 15)
                Button("目標を保存") {
                    do { try journal.saveGoals(PersonalGoals(sleepMinutes: sleepGoal, screenMinutes: screenGoal)); saved = true; error = nil }
                    catch { self.error = error.localizedDescription; saved = false }
                }.disabled(journal.loadError != nil)
                if saved { Text("目標を保存しました").foregroundStyle(Palette.green) }
                if let error { Text(error).foregroundStyle(.red) }
            } header: { Text("自分で決める目標") } footer: {
                Text("初期値は仮の目標です。自分の暮らしに合わせて変更してください。医学的な推奨値ではありません。")
            }
            Section("数字の見方") {
                Text("今日：スクリーンタイムと歩数は、過去7日/30日のうち記録のある日の「同じ時刻まで」の平均と比べます。睡眠・体重は1日の値の平均です。")
                Text("最初のSNS：Appleの集計が1時間単位のため「7時台」のように表示します。連続日数は昨日から遡り、記録のない日で止まります（最大30日）。")
                Text("体重：その日の最新値。手入力がある日は手入力を優先。")
                Text("睡眠：前日正午〜当日正午に含まれる睡眠。覚醒・就床は除き、重複区間は1回だけ数えます。昼寝や交代勤務は日付の区切りにご注意ください。")
                Text("平均：昨日までの7日/28日/3か月/1年。記録のない日は除外します。記録日数が異なる期間の比較は目安です。")
                Text("比較：7日・28日・3か月は直前の同じ日数、1年は前年同期間、月別は先月比と前年同月比。")
                Text("長期：3か月は週平均、1年・月別は月平均。体重は3か月以上で7日移動平均（記録3件未満の日は欠測）。")
                Text("カレンダー：色が濃いほど長い。無色は未記録で、0ではありません。")
                Text("スマホ：Appleの専用レポート内に自動表示。複数のiPhoneが含まれる場合があります。手入力とは合算しません。")
            }.font(.footnote)
            Section("あなたの記録は、このiPhoneの中に") {
                Label("iPhoneのロックとデータ保護で守ります", systemImage: "lock.shield")
                Text("アカウント登録・広告・外部サーバーへの送信はありません。手入力は端末内に保存し、ヘルスケアの読取値は開いている間だけ扱います。")
                Text("手入力はバックアップ対象外です。アプリの削除・端末交換で失われます。Appleヘルスケア側の記録はそのまま残ります。")
                Text("このアプリは生活記録の振り返りを支えるもので、病気の診断や治療判断は行いません。")
            }.font(.footnote)
            Section { Text("Rhythm 1.2 · 日々のリズム").foregroundStyle(Palette.secondary) }
        }.navigationTitle("設定").onAppear { sleepGoal = journal.goals.sleepMinutes; screenGoal = journal.goals.screenMinutes }
            .familyActivityPicker(isPresented: $picking, selection: $draft)
            .onChange(of: picking) { _, open in
                guard !open, let category = editing else { return }
                editing = nil
                var next = screen.categories
                switch category {
                case .sns: next.sns = draft
                case .video: next.video = draft
                case .work: next.work = draft
                case .other: return
                }
                do {
                    try screen.saveCategories(next)
                    if category != .work { gate.selectionChanged(next.gateSelection) }
                    selectionMessage = "\(category.label)のアプリを保存しました"
                } catch { selectionMessage = nil; screen.message = error.localizedDescription }
            }
            .onChange(of: sleepGoal) { _, _ in saved = false }
            .onChange(of: screenGoal) { _, _ in saved = false }
    }

    private func open(_ category: ScreenCategory) {
        guard let selection = screen.categories.selection(category) else { return }
        draft = selection
        editing = category
        picking = true
    }

    private func count(_ category: ScreenCategory) -> String {
        guard let selection = screen.categories.selection(category), !selection.isEmptySelection else { return "未選択" }
        return "アプリ\(selection.applicationTokens.count)・サイト\(selection.webDomainTokens.count)・カテゴリ\(selection.categoryTokens.count)"
    }
}
