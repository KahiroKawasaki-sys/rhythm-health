# 確認状況 — 2026-10-06

## Macでの検証（2026-10-05）
- Xcode 26.6（17F113）で5854201を検証。
- swift test：10件、失敗0件。
- 本体Rhythmと拡張RhythmScreenTime：署名なしiOS Simulatorビルド成功。
- 初回に判明したReportContext.swiftのSwiftUI import不足を修正し、再実行で成功を確認。
- Apple配布用権限：18:10（日本時間）の承認メールで付与を確認。本体と拡張のDistribution設定を保存・再表示で確認済み。
- 検証結果: https://github.com/KahiroKawasaki-sys/rhythm-health/actions/runs/37289618379

## Windowsで実施したこと（2026-10-04）
- Swift 14ファイルをtree-sitter-swiftで構文解析：構文エラー0件。コンパイラによる型チェックではない。
- XcodeプロジェクトをOpenStep parserで解析：74オブジェクト、参照切れ0件。
- Info.plist、entitlements、Privacy ManifestのXML解析とSchemeのターゲット参照確認：合格。
- HTML画面設計プレビューをEdgeで表示：375px / 1280px。
- 4タブ、7/28日切替、体重/睡眠グラフ切替、サンプル入力反映、HTML文字列を含むメモの無害化、再読み込み時のサンプル破棄：合格。
- HTMLでの横はみ出し・JavaScript実行エラーなし。全体スクリーンショットと実寸の画面/部分表示を目視確認。
- 日本語ファイルはUTF-8で再読確認。初回の端末ログのみcp932出力で文字化けし、保存ファイル・画面に影響なし。再実行ではPython標準出力をUTF-8に指定。

## 未実施（完了扱いにしない）
- iOS Simulatorでの起動・SwiftUI描画。
- 実機のHealthKit/FamilyControls許可・取得、レポート拡張の描画、保存先のファイル保護。
- 実機の認証、再起動後保存、取り消し、Dynamic Type/VoiceOver、時差移動。
- iPhoneへのTestFlightインストールと起動。App Store一般公開は対象外。

**Macのビルド成功は、実機での認可・データ取得や画面の動作保証ではありません。** 残る試験項目は `INSTALL.md` に記載。

## 配布向けRelease検証（2026-10-05）
7cff7e5で署名なしiPhoneOS Release Archive成功。本体と拡張を含み、Bundle ID・バージョン・プラットフォーム・実行ファイルの検査に合格。署名・端末へのインストールは未実施。
https://github.com/KahiroKawasaki-sys/rhythm-health/actions/runs/37311729232

## 署名・Apple受理（2026-10-06）
2026-10-06：バージョン1.0・ビルド1.8.1（a98508c）のiPhone向けビルド、Apple配布署名、本体・拡張の権限検査、Apple検証・アップロードが成功。TestFlightで「テスト中」を確認し、本人のみの内部グループへ配布済み。本人のテスター状態は「招待済み」。iPhone実機での表示・データ取得は未検証。
署名関連17テスト合格。秘密鍵形式、プロファイル、配布権限、ExtensionKitの構成、HealthKitの説明文を配布前に検査する。
https://github.com/KahiroKawasaki-sys/rhythm-health/actions/runs/37332782412
