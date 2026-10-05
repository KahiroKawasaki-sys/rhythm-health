# Rhythm — 日々のリズム

体重・睡眠・スクリーンタイムを振り返る、個人向けiPhoneアプリ。iOS 17以上、SwiftUI製。

**2026-10-04時点：ソース実装・Windows上の構文/設定確認・HTML画面設計確認まで。iOSビルド、署名、Appleとの接続、実機での動作は未検証。インストール用IPAは未作成です。**

2026-10-05追記：Apple Developerの有効化と、本体・スクリーンタイム表示拡張のApp ID登録（開発用権限）を完了。Xcode設定を登録IDに更新。配布用Family Controls権限はApple承認済み。本体・拡張のDistribution設定も保存確認済み。Xcode 26.6のクラウドMacで10テスト全件合格、本体と拡張の署名なしSimulatorビルド成功。検証したコードは5854201。署名・Simulator起動/描画・実機検証・配布は未実施。

検証結果: https://github.com/KahiroKawasaki-sys/rhythm-health/actions/runs/37289618379

## 入っている機能
1. 今日：その日の体重・睡眠・自動スクリーンタイム。
2. 振り返り：昨日までの7日/28日、平均、前期間との差、日別推移と記録日数。
3. 記録：手入力による補完、体調5段階、ひとことメモ、日付指定、編集、1日分削除。
4. 設定：Apple連携、睡眠/スマホの個人目標、集計方法とプライバシー説明。
5. 保護：Face ID/Touch ID/パスコード認証、背景移行時の画面保護、端末内保存、保存失敗時の保護。

## 最初に見る
- `Preview/index.html`：ブラウザで開く画面設計プレビュー。全数値はサンプル。入力内容は再読み込みで消えます。Apple連携は動作しません。
- `Rhythm.xcodeproj`：MacのXcodeで開くネイティブアプリ本体。
- `SPEC.md`：集計・欠測・手入力優先・エラー処理の仕様。
- `Documentation/QA.md`：実施済み検証と、Mac/実機で残る確認。
- `Documentation/INSTALL.md`：Windowsしかない場合を含む導入手順。

## 自動取得の条件と限界
体重と睡眠はAppleヘルスケアにすでにある記録を読み込みます。iPhoneだけで体重を測定する機能ではありません。睡眠はApple Watchや対応アプリ等が記録した睡眠区間が必要です。権限を許可した後、起動・復帰・更新操作で取得します。定時の背景同期は実装していません。

スクリーンタイムはAppleのDeviceActivityReport内で表示します。レポート拡張からメインアプリへ値を持ち出しません。そのため、体重・睡眠と同じ画面で比較できますが、3指標の自動相関計算、スクリーンタイムの独自保存・CSV出力はありません。対象は認可されたiPhone群で、複数のiPhoneがある場合は合計される可能性があります。

睡眠は前日正午から当日正午で区切り、睡眠中の区間を重複排除して合計します。Appleヘルスケアの独自集計と値が一致するとは限りません。交代勤務・昼寝はこの日付ルールにご注意ください。

記録は端末内のみ。手入力はバックアップ対象外なので、アプリ削除や端末交換で失われます。HealthKitの値は読み取り専用・メモリ内で扱い、Apple側のデータは変更しません。

## 開発者向け
外部パッケージ不要。Xcodeプロジェクトを同梱しています。

```sh
# Mac または Swift が使える環境で、純粋な集計ロジックのテスト
swift test

# Mac上で、集計テストと署名なしSimulatorビルド
bash scripts/verify-mac.sh
```

GitHub Actions用の手動実行ワークフローも `.github/workflows/verify-ios.yml` にあります。2026-10-05に本人の承認で非公開リポジトリへ保存済み。実行結果はGitHub Actionsを参照。無料枠と課金停止条件を確認してから手動実行します。

## Appleの仕様（確認：2026-10-04）
- [HealthKitの認可](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
- [睡眠の区分](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis)
- [スクリーンタイム専用レポートとデータ保護](https://developer.apple.com/documentation/deviceactivity/deviceactivityreport)
- [Family Controls配布権限の申請](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)

## 配布準備の更新（2026-10-05）
本体・拡張のFamily Controls (Distribution)有効化とApp Store Connectのアプリ登録を完了。実機向け署名なしRelease Archive検査も成功（7cff7e5）。署名・TestFlightアップロード・実機確認は未実施。App Store Connect APIは本人の同意後に利用申請を提出し、2026-10-05に承認を確認。本人の明示承認後、管理者キー「Rhythm GitHub TestFlight」を作成し、有効なキー1件を確認。秘密鍵のダウンロード・GitHubへの保管は未実施。詳細はDocumentation/INSTALL.md。
