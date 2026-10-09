# Rhythm — 日々のリズム

体重・睡眠・スクリーンタイムを振り返る、個人向けiPhoneアプリ。iOS 17以上、SwiftUI製。

## このリポジトリについて
- **Windows PCしか持っていない状態で、Claude Codeと一緒に作ったiPhoneアプリ**です。Macを使わず、ビルド・テスト・署名・TestFlight配布はすべてGitHub ActionsのmacOS環境で行っています（`.github/workflows/`）。
- 2026-10-05に開発を始め、10-06にTestFlightで初回配布しました。以降も毎日改修しています。
- SNSを開く前に「仕事／遊び／なんとなく」から目的を選ばせ、使える時間を制限する仕組みを、Appleのスクリーンタイム関連API（Family Controls）で実装しています。
- 集計ロジックのテスト33本と、シミュレータ向けビルド・署名検査をCIで回しています。

**2026-10-08：バージョン1.0・ビルド1.11.1（0754411）を本人用TestFlightへ配布し、「テスト中」を確認。暗号化方式の申告をアプリへ組み込み、申告漏れを配布前に止める21項目の検査も通過した。長期の振り返り・SNS集計・目的選択を含む。iPhoneのTestFlightから更新する。更新後の実機動作は未検証。**

更新版の送信結果: https://github.com/KahiroKawasaki-sys/rhythm-health/actions/runs/37727447785
配布状況: https://appstoreconnect.apple.com/apps/6819279929/testflight

## 入っている機能
1. 今日：7日/30日平均との比較つきで、スクリーンタイム（SNS・動画・仕事・その他の4区分）・SNSゲート・睡眠・体重・歩数。カードの並び替えと表示・非表示。
2. 振り返り：週・月（30日）・3か月・年を前の同じ長さの期間と比較。選んだ指標のグラフ／5週間カレンダーと5指標の一覧。スクリーンタイム詳細（アプリ別・時間帯別・曜日×時間帯）。
7. ホーム画面ウィジェット：踏みとどまった回数・開こうとした回数・遊び予算の残り。
3. 記録：手入力による補完、ひとことメモ、日付指定、編集、1日分削除。
4. 設定：Apple連携、睡眠/スマホの個人目標、集計方法とプライバシー説明。
5. 目的選択：SNSを開く目的、深呼吸、遊び予算、通知からの起動、解除期限後の再遮断（実機での受入確認が必要）。
6. 保護：端末内保存（iOSのデータ保護）、保存失敗時の保護。v1.2で起動時のFace IDロックと背景移行時の目隠しは廃止。

## 最初に見る
- `Preview/index.html`：ブラウザで開く画面設計プレビュー。全数値はサンプル。入力内容は再読み込みで消えます。Apple連携は動作しません。
- `Rhythm.xcodeproj`：MacのXcodeで開くネイティブアプリ本体。
- `SPEC.md`：集計・欠測・手入力優先・エラー処理の仕様。
- `Documentation/QA.md`：実施済み検証と、Mac/実機で残る確認。
- `Documentation/INSTALL.md`：Windowsしかない場合を含む導入手順。

## 自動取得の条件と限界
体重・睡眠・歩数はAppleヘルスケアにすでにある記録を読み込みます。iPhoneだけで体重を測定する機能ではありません。睡眠はApple Watchや対応アプリ等が記録した睡眠区間が必要です。権限を許可した後、起動・復帰・更新操作で取得します。定時の背景同期は実装していません。

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

## 配布運用
Apple Developer、HealthKit、Family Controls配布権限、App Store Connect、本人用内部テストグループを設定済み。秘密情報は本人の承認で非公開リポジトリのGitHub Actions Secretsへ保管し、ソースには含めない。

`Sign and prepare TestFlight` はmainからの手動実行のみ。既定は署名検査、uploadを選ぶとAppleへ送信する。無料枠・予算0ドルの課金停止設定を維持する。署名関連の21テストは合格。Swift集計10テストとSimulatorビルドの履歴、実機で残る確認はDocumentation/QA.md、導入はDocumentation/INSTALL.mdを参照。
