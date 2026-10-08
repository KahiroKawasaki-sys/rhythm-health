# Rhythm v1.1 引き継ぎメモ（2026-10-06）

仕様の正本は `SPEC.md` の「v1.1 改修計画」。このメモは実装を始めるときの手順と注意点。

## 合意事項
- 振り返りの長期化（3か月・1年・月別、移動平均、カレンダー表示）
- SNS専用の集計（X・Instagram・YouTubeとそのWebドメイン）
- 開く前に目的を選ぶ仕組み（仕事15分・遊び10分・なんとなく5分、遊び予算30分/日、夜22時〜）
- MindGateはRhythmに統合して退役させる
- 作らないもの：夜SNSと睡眠の比較、週1回の提案

## フェーズ1（新しい権限は不要。すぐ着手できる）
**状況（2026-10-06）**：1〜6を実装済み。ブランチ `v1.1-phase1` で `verify-ios.yml` が成功（単体テスト20本＋シミュレータ向けビルド）。10/7にmainへ統合。Apple側の登録（App Group・Bundle ID 3つ・各App IDへのApp Group割り当て）を完了し、`testflight.yml`（upload=false）で本体＋拡張4つの配布署名・プロファイル・権限・App Groupの検査が成功。同日、ビルド1.10.1をTestFlightへアップロード（Apple検証・アップロード成功）。実機確認は未実施。
- SNSの集計方法：表示拡張で、フィルタ後の各カテゴリのアプリとWebサイトの利用時間を合計している。全体の合計と食い違わないかを実機で確認する。
- 表示拡張のカレンダーは、本体から1か月分のフィルタを渡し、記録のある最初の日から月を決める（データが1日もない月は「Apple側に記録なし」）。
- 全体用のスクリーンタイムカレンダーは作っていない（仕様どおり、カレンダーは睡眠とSNSのみ）。
1. `Shared/HealthMath.swift`：期間（90日・365日・月別）、7日移動平均、週平均・月平均、前年同期間の計算を追加し、テストを書く（`Tests/HealthMathTests.swift`）。
2. `Rhythm/HealthStore.swift`：取得範囲を選んだ期間と比較期間に広げる（現在は28日×2程度）。
3. `Rhythm/DashboardViews.swift`：`ReviewView` の期間ピッカー（現在は7日/28日の2択、163行目付近）を5択にし、長期のグラフとカレンダー表示を追加する。
4. `Shared/ReportContext.swift` と `ScreenTimeReport/ScreenTimeReport.swift`：長期とSNS用の表示を追加する。SNS用は、本体で対象アプリを絞り込んだDeviceActivityFilterを渡す。
5. `Rhythm/SettingsView.swift`：FamilyActivityPickerで対象アプリを選ぶ画面と、選択内容の保存（`JournalStore` と同じ保護方式）。
6. Webプレビュー（`Preview/index.html`）を更新し、375pxと1280pxで見た目を確認する。

## フェーズ2（目的選択の仕組み）
**状況（2026-10-07）**：コードとプロジェクト設定をブランチ `v1.1-phase2` に実装。`verify-ios.yml`（単体テスト28本＋シミュレータ向けビルド）と `archive-ios.yml`（署名なしの実機向けアーカイブで拡張3つの格納・バージョン一致を検査）が成功（Xcode 26.6）。10月7日にmainへ統合済み（06d805b、190515b）、Apple側の登録と署名検査後にビルド1.10.1をアップロード。10月8日に暗号化申告と本人用グループへの追加を完了し「テスト中」を確認。実機確認は未実施。手順は `INSTALL.md` の「v1.1フェーズ2のApple側作業」。
- 実装したもの
  - `Shared/GateMath.swift`：待機秒数・遊び予算・緊急解除・再遮断の区間（15分未満は開始を過去にずらす）・振り返りの集計。テストは `Tests/GateMathTests.swift`。
  - `Gate/GateShared.swift`：App Groupのファイル（設定＝最初のロック解除後に読める保護、記録＝完全保護、どちらもバックアップ対象外）、シールドのかけ外し、監視名、通知。本体と拡張3つで共有。
  - 拡張：`Monitor/`（解除の終わりに再遮断・到達ラインの記録）、`ShieldConfiguration/`（文言と今日の回数）、`ShieldAction/`（やめておく＝記録して閉じる／理由を選んで開く＝通知を出して閉じる）。3つとも旧NSExtension形式で `PlugIns` に格納。
  - 本体：`Rhythm/GateStore.swift`（オン・オフ、解除、通知の受け取り、rhythm://gate）、`Rhythm/GateViews.swift`（目的選択・深呼吸・ほめる演出・設定・振り返りカード）。
  - `scripts/distribute.py`・`archive-unsigned.sh`：拡張5つ分の署名・権限・App Groupの検査。
- 設計上の判断
  - 再遮断の予約に失敗したら、遮断を外さない（外しっぱなしを防ぐ）。本体の復帰時にも期限切れなら戻す。
  - 設定ファイルは監視拡張がロック中に読めるよう「最初のロック解除後」保護にした（中身はAppleの識別子と分数だけ）。目的・回数の記録は完全保護。
  - 到達ラインはロック中に越えると書けないため、記録できなかった分は残らない（画面に「おおよそ」と明記）。
  - Webプレビュー（`Preview/index.html`）はフェーズ2では未更新。
- **本人が先にやること**
  - Apple DeveloperでBundle IDを3つ登録する（例：`com.kawakahi.rhythm.Monitor`、`.ShieldConfiguration`、`.ShieldAction`）。
  - App Group `group.com.kawakahi.rhythm` を作り、本体と各拡張に付ける。
  - 新しいBundle IDそれぞれにFamily Controls配布権限を申請する。前回（10/04申請）は10/05に付与された。
- **実装**
  - Xcodeに拡張を3つ追加する（DeviceActivityMonitor、ShieldConfiguration、ShieldAction）。拡張の形式（ExtensionKitか旧NSExtensionか）は、拡張の種類ごとにAppleの資料で確認する。
  - 目的選択画面を作る。通知からの起動用にURLスキーム（例：`rhythm://gate`）を使う。
  - 通知の許可、記録の保存、振り返りへの指標追加。
- **配布ワークフロー**：`scripts/distribute.py` と `.github/workflows/testflight.yml` の署名検査を、新しい拡張と権限に対応させる（現在は本体と表示拡張の2つが前提）。
- **MindGateから流用するもの**（`dev/mindgate/docs/SPEC.md`）：深呼吸の動き（吸う4秒・吐く6秒の拡縮）、踏みとどまった後のほめる演出。

## 実機で確かめること（リスクの高い順）
1. 監視の最短間隔15分の制約：開始時刻を過去にずらす方法で、5分・10分後の再遮断が動くか。
2. シールド操作拡張からローカル通知を出せるか。通知のタップで目的選択画面が開くか。
3. スクリーンタイムが、Apple側でどこまで過去にさかのぼって取れるか（90日・1年）。
4. Safariのx.com等がシールドされるか。
5. 1年分のHealthKit取得の速さ。

## MindGateの退役（フェーズ2の実機確認が済んでから）
- iPhoneのショートカットのオートメーション（X・Instagram・YouTubeを開いたとき・閉じたとき）を本人が削除する。
- `dev/mindgate` のREADMEに退役を記載する。Vercelの公開（mindgate-theta.vercel.app）を止めるかは、その時点で本人に確認する。
- MindGateに残っている記録の移行は今回しない（必要なら別途相談）。
