# iPhoneへ入れるまで

## 現在の状態
Windowsにソースと画面プレビューを作成済み。iPhone用バイナリ、署名、配布URLはまだありません。HTMLをiPhoneへ送ってもAppleの自動連携は動作しません。

## Apple登録の進捗（2026-10-05）
Apple Developer有効化と、本体・表示拡張の2件のApp ID登録を確認済み。開発用の必要権限を設定済み。配布用権限は申請受付済み・審査待ち。Mac上の集計テストと署名なしSimulatorビルドは成功。次は配布用権限の付与確認、署名・実機確認。

## 配布準備の現行手順（2026-10-05確認）
Appleの現行フォームは開発者アカウント単位。登録済みの氏名・メール・Team IDと利用条件を表示し、Get Entitlementで取得を申し込む。説明文やBundle IDを入力する欄は今回の画面にはない。本人の明示承認後、2026-10-05に送信済み。Appleの受付完了画面で審査後に連絡される旨を確認。現在は審査待ちで、権限付与済みとは扱わない。

公式フォーム: https://developer.apple.com/contact/request/family-controls-distribution

取得後は本体と拡張それぞれで配布用権限の利用可否を確認し、署名用プロファイルに反映する。開発用権限の登録だけでTestFlight配布可能とは扱わない。

ビルド候補は本人のGitHubアカウント配下の非公開rhythm-healthリポジトリ。2026-10-05に本人がソースの外部転送・非公開リポジトリ作成を承認済み。既存のVerify iOS sourceは手動実行、1回20分上限、読み取り権限のみで単体テストと署名なしSimulatorビルドを行う。健康実データ・Apple認証情報・証明書は転送しない。無料枠と超過課金の停止条件を確認してから実行し、有料利用は別途承認を得る。非公開リポジトリ https://github.com/KahiroKawasaki-sys/rhythm-health を作成し、ソースを保存済み。2026-10-05に無料枠0/2,000分使用、Actions予算0ドル・Stop usage Yesを確認。ビルド結果は以下の検証履歴とGitHub Actionsを参照。

## Windowsのみの場合（今回の前提）
1. Apple Developer Program有効化済み。再購入・再登録は不要。アカウント情報をチャットに貼らない。
2. クラウドMac上のXcode環境か、Macを持つ開発担当者を用意する。契約、費用発生、外部へのソース転送は別途明示承認してから行う。
3. 以下のMac手順でソースをビルドする。まずは署名なしビルドとテストを通す。
4. Family Controlsの配布権限についてAppleの公式手順で申請する。本体とScreenTimeReport拡張に必要な権限・プロファイルをそろえる。申請が通る時期・可否はApple次第。
5. 本人の承認後、署名したアプリをApp Store Connectへアップロードし、TestFlightで本人のiPhoneへ配布する。
6. 実機で下記の確認を行い、問題を修正してから普段使いにする。

単にWeb版へ置き換えると、このアプリで必要なAppleの自動連携は実現できません。そのためネイティブ構成を維持しています。

## Mac上の開発担当者向け
1. iOS 17以降のSDKを持つ対応Xcodeを用意し、`Rhythm.xcodeproj` を開く。最新の実機OSに対応するXcodeを使う。
2. `bash scripts/verify-mac.sh` を実行。テスト失敗やコンパイルエラーを修正する。2026-10-05にクラウドMacのXcode 26.6で10テストと署名なしSimulatorビルドを完了。変更したコードは同じ手順で再検証する。
3. 各ターゲットのSigning & Capabilitiesで自分のTeamを選択する。
4. 登録済みBundle IDは本体 `com.kawakahi.rhythm`、拡張 `com.kawakahi.rhythm.ScreenTimeReport`。Xcode側も設定済み。テスト用は `com.kawakahi.rhythm.tests`（Appleへの登録対象外）。Team IDはソースに保存せず、ビルド環境で指定する。
5. 本体：HealthKit、Family Controls、Data Protection（Complete）。拡張：Family Controls。entitlementsは同梱済み。App Groupsは使わない。
6. iPhoneのパスコードを有効にする。開発用実機では必要に応じてデベロッパモードを有効にする。
7. Scheme `Rhythm` を選択してビルド・起動。Simulatorの画面表示だけではHealthKit/Screen Timeの受入試験に合格としない。
8. 実機でアプリのロックを解除し、体重・睡眠・スクリーンタイムをそれぞれ許可する。読み取りを拒否した場合、データなしと区別できないというApple仕様に注意。
9. TestFlight等で配布する場合は配布用Family Controls権限・証明書・プロファイルを確認し、Archive/Validateを通してから、本人の承認後にアップロードする。

## 必須の実機確認
1. 既存の体重と睡眠を取得できる。権限を拒否/後から取り消しても、許可済みと誤表示しない。
2. 同日の体重が複数ある場合は最新値。睡眠は重複時間を二重に数えず、就床/覚醒を除く。
3. 今日と7日/28日のスクリーンタイムが表示される。表示対象の端末・期間が想定どおり。
4. 手入力を保存→終了→再起動して保持される。手入力を空に戻すとHealthKitの値に戻る。
5. 1日削除は確認付きで、Apple Healthの記録は削除されない。
6. Face ID/Touch ID/パスコード、認証キャンセル、背景化、アプリ切替のプレビュー保護。
7. 保存エラー/破損ファイル時に成功扱いしない。原本を上書きしない。
8. 7/28日平均、欠測、0分、未来日、全角入力、深夜跨ぎ、時差/夏時間。
9. 小さいiPhone、大きい文字サイズ、VoiceOver、キーボード表示中でも保存/キャンセル可能。
10. Appleの画面と数値を比較。睡眠の日付の区切りがApple側の見せ方と異なる点を確認。

## 配布申請用説明のたたき台
Rhythm is a personal digital-wellbeing app for an individual user. It uses individual Family Controls authorization to display the user's own iPhone activity in a DeviceActivityReport extension. The report helps the user reflect on screen time alongside their sleep and body-mass records. Screen Time data remains within the report extension; the app does not export it to the containing app, a shared container, an analytics service, or a server. The app does not use this data for advertising or share it with other people.

この文面は未送信の補足説明用。2026-10-05に確認した現行フォームには説明文の入力欄がないため、Appleから追加説明を求められた場合のみ使用する。

## 検証履歴（2026-10-05）
- 初回368cc2a：10テスト合格。共有レポート定義にSwiftUIのimportがなく、拡張のコンパイルで停止。
- 修正版5854201：SwiftUIのimportを追加。同じ手順を再実行し、10テスト合格・本体と拡張の署名なしSimulatorビルド成功（ジョブ2分14秒）。
- 実行結果: https://github.com/KahiroKawasaki-sys/rhythm-health/actions/runs/37289618379
- 影響は未配布の開発ソースのみ。健康実データへの影響なし。CIの手動検証を配布前の必須手順として継続する。
- Simulatorの起動・画面確認、iPhone実機の権限とデータ取得、署名、TestFlightは未実施。
