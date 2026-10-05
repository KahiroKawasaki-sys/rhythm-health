import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var journal: JournalStore
    @EnvironmentObject private var health: HealthStore
    @EnvironmentObject private var screen: ScreenTimeStore
    @State private var sleepGoal = 450
    @State private var screenGoal = 180
    @State private var saved = false
    @State private var error: String?
    var body: some View {
        Form {
            Section("自動連携") {
                Button { Task { await health.connect() } } label: {
                    Label(health.hasRequested ? "ヘルスケアのアクセスを確認" : "Appleヘルスケアに接続", systemImage: "heart")
                }
                Text("体重・睡眠を読み取り専用で取得。起動・復帰・更新操作で反映します。読み取り拒否とデータなしはアプリから区別できません。")
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
                Text("体重：その日の最新値。手入力がある日は手入力を優先。")
                Text("睡眠：前日正午〜当日正午に含まれる睡眠。覚醒・就床は除き、重複区間は1回だけ数えます。昼寝や交代勤務は日付の区切りにご注意ください。")
                Text("平均：昨日までの7日/28日。記録のない日は除外します。記録日数が異なる期間の比較は目安です。")
                Text("スマホ：Appleの専用レポート内に自動表示。複数のiPhoneが含まれる場合があります。手入力とは合算しません。")
            }.font(.footnote)
            Section("あなたの記録は、このiPhoneの中に") {
                Label("Face ID・Touch ID・パスコードで保護", systemImage: "lock.shield")
                Text("アカウント登録・広告・外部サーバーへの送信はありません。手入力は端末内に保存し、ヘルスケアの読取値は開いている間だけ扱います。")
                Text("手入力はバックアップ対象外です。アプリの削除・端末交換で失われます。Appleヘルスケア側の記録はそのまま残ります。")
                Text("このアプリは生活記録の振り返りを支えるもので、病気の診断や治療判断は行いません。")
            }.font(.footnote)
            Section { Text("Rhythm 1.0 · 日々のリズム").foregroundStyle(Palette.secondary) }
        }.navigationTitle("設定").onAppear { sleepGoal = journal.goals.sleepMinutes; screenGoal = journal.goals.screenMinutes }
            .onChange(of: sleepGoal) { _, _ in saved = false }
            .onChange(of: screenGoal) { _, _ in saved = false }
    }
}
