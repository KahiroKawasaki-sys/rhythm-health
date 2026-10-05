# iPhoneへ入れるまで

## 現在の状態
2026-10-06：バージョン1.0・ビルド1.8.1（a98508c）のiPhone向けビルド、Apple配布署名、本体・拡張の権限検査、Apple検証・アップロードが成功。TestFlightで「テスト中」を確認し、本人のみの内部グループへ配布済み。本人のテスター状態は「招待済み」。iPhone実機での表示・データ取得は未検証。

処理結果: https://github.com/KahiroKawasaki-sys/rhythm-health/actions/runs/37332782412

## Apple登録の進捗（2026-10-05）
Apple Developer有効化と、本体・表示拡張の2件のApp ID登録を確認済み。開発用の必要権限を設定済み。配布用権限は2026-10-05 18:10（日本時間）にAppleから付与通知を受領。本体と拡張のFamily Controls (Distribution)を保存・再表示で確認済み。Mac上の集計テストと署名なしSimulatorビルドは成功。次は署名とTestFlight・実機確認。

## 配布権限取得の記録（2026-10-05）
Appleの現行フォームは開発者アカウント単位。登録済みの氏名・メール・Team IDと利用条件を表示し、Get Entitlementで取得を申し込む。説明文やBundle IDを入力する欄は今回の画面にはない。本人の明示承認後、2026-10-05に送信済み。Appleの受付完了画面で審査後に連絡される旨を確認。その後、18:10（日本時間）の承認メールでアカウントへの付与を確認。本体と拡張のDistribution設定も有効化済み。

公式フォーム: https://developer.apple.com/contact/request/family-controls-distribution

取得後は本体と拡張それぞれで配布用権限の利用可否を確認し、署名用プロファイルに反映する。開発用権限の登録だけでTestFlight配布可能とは扱わない。

ビルド候補は本人のGitHubアカウント配下の非公開rhythm-healthリポジトリ。2026-10-05に本人がソースの外部転送・非公開リポジトリ作成を承認済み。既存のVerify iOS sourceは手動実行、1回20分上限、読み取り権限のみで単体テストと署名なしSimulatorビルドを行う。健康実データ・Apple認証情報・証明書は転送しない。無料枠と超過課金の停止条件を確認してから実行し、有料利用は別途承認を得る。非公開リポジトリ https://github.com/KahiroKawasaki-sys/rhythm-health を作成し、ソースを保存済み。2026-10-05に無料枠0/2,000分使用、Actions予算0ドル・Stop usage Yesを確認。ビルド結果は以下の検証履歴とGitHub Actionsを参照。

## Windowsのみの場合（今回の前提）
1. Mac購入は不要。Apple Developer登録とGitHubのクラウドMacによるビルド・署名は完了している。
2. 本人のiPhoneに[AppleのTestFlight](https://apps.apple.com/jp/app/testflight/id899247664)を入れ、本人宛の招待メールの「View in TestFlight」からRhythmをインストールする。
3. アプリを開いて端末認証を解除し、設定からヘルスケアの体重・睡眠の読み取りとスクリーンタイムを許可する。
4. 既存データを更新して表示・数値を確認し、下記の実機確認へ進む。ヘルスケアに元データがない項目は手入力で補える。
5. 更新版は同じ手動ワークフローから配布する。第三者招待・App Store一般公開・有料枠の利用は今回の承認に含まれない。

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

## 署名・TestFlight準備の履歴（2026-10-05、当時の状態）
- App Store Connectの初回利用規約は本人の明示承認後に同意済み。
- 署名前の実機向けRelease Archive検証を追加。Prepare unsigned iOS releaseを手動実行する。成果物はGitHub内で1日保持し、IPAとは区別する。
- APIキーの発行状況は下記を参照。署名用証明書の作成・秘密情報の外部保管、およびTestFlightアップロードは未実施。秘密情報はチャットやGitに貼らない。

- Release Archive検証：7cff7e5で成功。本体と拡張のBundle ID、バージョン一致、iphoneosプラットフォーム、実行ファイルを確認。
- 結果: https://github.com/KahiroKawasaki-sys/rhythm-health/actions/runs/37311729232
- 初回のworkflow設定ではrunner.tempをジョブ直下で参照し検証エラーになった。ステップ内の設定へ移して再実行で成功。未配布・健康実データへの影響なし。
- Apple Developerの証明書一覧は未登録。署名用証明書の新規作成が必要。

- App Store Connectに「Rhythm - 日々のリズム」を登録済み。iOS、日本語、Bundle ID com.kawakahi.rhythm、SKU rhythm-health-ios。
- 管理画面: https://appstoreconnect.apple.com/apps/6819279929/distribution
- TestFlightはビルド未アップロード。App Store Connect APIは本人の明示承認後、内部開発・テスト用途に限定する追加条件へ同意して申請を提出。2026-10-05に管理画面で利用承認を確認。その後、本人が管理者権限の範囲を確認して明示承認し、チームキー「Rhythm GitHub TestFlight」を生成。キー名の表示と有効なキー1件を確認。秘密鍵のダウンロード・GitHubへの保管、証明書の作成は未実施。次は保管先を確定して、署名・TestFlight用の設定へ進む。


## GitHub署名設定（実行・アップロード成功）
`Sign and prepare TestFlight` は main ブランチから手動実行する。upload=false は署名と検査まで、upload=true は検査後にAppleへ送信する。外部保管とApple側の証明書・プロファイル作成、初回送信は本人の明示承認後に行う。App Store一般公開や第三者招待はこの処理に含まれない。

保存先は `KahiroKawasaki-sys/rhythm-health` の Settings → Secrets and variables → Actions → Repository secrets。
- `ASC_PRIVATE_KEY`: 発行した「Rhythm GitHub TestFlight」の秘密鍵（.p8）の全文。本人がGitHub画面へ直接入力する。チャット・Git・OneDriveに貼らず、エージェントは秘密鍵ファイルを読まない。
- `ASC_KEY_ID`: 同じキーのKey ID。
- `ASC_ISSUER_ID`: Apple APIチームキー画面のIssuer ID。
- `APPLE_TEAM_ID`: Apple DeveloperのMembership detailsで表示されるTeam ID。Issuer IDとは別。

キーはAppleアカウント全体への管理者権限を持つ。Repository secretsは、このリポジトリで実行されるワークフローから使用できるため、書き込み権限者による変更の影響を受ける。秘密鍵をソースに保存しない。実行中だけ一時ファイルに展開し、正常終了・処理エラー時に削除する。強制終了時もGitHubホストの一時実行環境とともに破棄される。署名済みIPA・証明書・ログのアーティファクト保存はしない。

現在は署名なしArchiveから一時ローカル署名を経て、Appleの配布用クラウド署名と両App IDのプロファイルを取得する。初期の通常Archive試行では開発用証明書が作成された可能性がある。上限エラー時は繰り返し実行せず、今回作成された証明書を特定してから対処する。既存証明書を自動失効しない。

承認とSecrets設定後、無料枠・課金停止条件を確認し、初回は署名検査を通す。実行エラーは解決してから先へ進める。Appleへの送信が成功しても、TestFlight画面で処理完了を確認するまでは利用可能とは扱わない。実機テストは上記の必須項目を実施する。

実装の参照: https://developer.apple.com/videos/play/wwdc2021/10204/
アップロード手順: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds


## 署名設定の履歴（2026-10-05 22:55 JST、当時の状態）
- 本人がGitHubへのキー・識別情報の保管、Apple側の証明書・署名設定作成、無料枠内での検証と本人向けTestFlightアップロードをまとめて明示承認済み。同じ範囲の承認は繰り返し求めない。
- 発行済み管理者キーの.p8ファイルは本人のDownloadsに保存済み。ブラウザーの完了通知はタイムアウトしたが、ファイルの存在・サイズ・保存時刻を確認した。中身は読んでいない。ダウンロードは再実行していない。
- GitHubのRepository secretsにASC_KEY_ID、ASC_ISSUER_ID、APPLE_TEAM_IDを保存し、一覧と保存成功表示を確認済み。値はソースに記録しない。
- ASC_PRIVATE_KEYだけ本人の直接入力待ち。GitHubの入力欄を開いて引き継ぎ済み。秘密鍵の内容をチャットや画面取得へ出さない。
- 次は保存済みの秘密情報名だけを確認し、無料枠・課金停止条件を確認後、署名ワークフローを実行する。配布成功後もAppleの処理結果と実機の動作を別々に確認する。


## 初回署名実行（2026-10-05、未配布）
本人が秘密鍵を保存した後、4つのSecretsの名前を確認。無料枠72.3/2,000分使用、Actions予算0ドル・Stop usage Yesを確認して実行した。
実行37320983390（616c144）は9つの検査テストに合格後、秘密鍵の形式チェックで停止。Appleへの接続、証明書作成、署名、アップロードには到達していない。保存値の中身は取得していないため、不一致の具体的な内容は未確認。本人へ.p8全文の再入力を依頼し、更新欄を開いた。
形式チェックは維持し、ファイル名・パスではなくBEGIN/ENDを含む全文が必要だとエラーに明記。Windowsのテキスト編集で付くBOMと改行だけは正規化する。架空の文字列による3テストを追加し、既存の9テストと合わせて検証する。
結果: https://github.com/KahiroKawasaki-sys/rhythm-health/actions/runs/37320983390

## 配布障害の修正と現在の結果（2026-10-06）
- 本人の秘密鍵再入力は完了。ヘッダーなしの鍵本文も厳格な形式検査後に復元する。OpenSSLの空パスワード指定を修正し、実際のApple認証成功を確認した。秘密鍵の中身をエージェントは取得していない。
- 登録済みiPhoneを要求する開発用署名を避け、署名なしArchiveと一時ローカル署名からApple配布署名へ進む方式で成功。
- スクリーンタイム拡張をExtensionKit形式・Extensionsへの格納に修正。HealthKitは読み取り専用を維持し、Apple検証が要求した利用説明キーを追加。
- 最終ビルドa98508c、1.8.1は17検査テスト、本体・拡張のビルド、配布署名・プロファイル・権限検査、Appleの検証とアップロードに成功。
- 形式・権限・説明文の不足を再発させないため、配布前の自動検査に追加した。影響は2026-10-05〜06の初回配布準備のみ。未配布のため利用者の健康記録への影響なし。
- 本人用内部グループは1人のみ。自動配布は無効。Apple処理完了と暗号化方式の設定後、1.8.1を手動追加し「テスト中」を確認。本人1人・ビルド1個・招待済みの状態。一般公開・第三者招待は行わない。
- 結果: https://github.com/KahiroKawasaki-sys/rhythm-health/actions/runs/37332782412

## 初回配布完了（2026-10-06）
バージョン1.0、ビルド1.8.1を本人のみの内部グループへ配布。Apple標準機能以外の暗号化アルゴリズムを実装していないことをソースで確認し、App Store Connectで該当回答を保存。Apple側の状態は「テスト中」、本人の状態は「招待済み」。TestFlightには90日の期限があるため、更新時は再ビルド・再配布する。
管理画面: https://appstoreconnect.apple.com/apps/6819279929/testflight
iPhoneへのインストール・実データ取得は本人の操作で確認する。
