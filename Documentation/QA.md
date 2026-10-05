# 確認状況 — 2026-10-04

## 実施したこと
- Swift 14ファイルをtree-sitter-swiftで構文解析：構文エラー0件。コンパイラによる型チェックではない。
- XcodeプロジェクトをOpenStep parserで解析：74オブジェクト、参照切れ0件。
- Info.plist、entitlements、Privacy ManifestのXML解析とSchemeのターゲット参照確認：合格。
- HTML画面設計プレビューをEdgeで表示：375px / 1280px。
- 4タブ、7/28日切替、体重/睡眠グラフ切替、サンプル入力反映、HTML文字列を含むメモの無害化、再読み込み時のサンプル破棄：合格。
- HTMLでの横はみ出し・JavaScript実行エラーなし。全体スクリーンショットと実寸の画面/部分表示を目視確認。
- 日本語ファイルはUTF-8で再読確認。初回の端末ログのみcp932出力で文字化けし、保存ファイル・画面に影響なし。再実行ではPython標準出力をUTF-8に指定。

## 未実施（完了扱いにしない）
- `swift test`（集計・保存形式に関する10テストケースを同梱、未実行）。
- Xcodeの型チェック・ビルド・実行、iOS SimulatorでのSwiftUI描画。
- 実機のHealthKit/FamilyControls許可・取得、レポート拡張の描画、保存先のファイル保護。
- 実機の認証、再起動後保存、取り消し、Dynamic Type/VoiceOver、時差移動。
- Apple申請、署名、TestFlight、App Store配布。

**WindowsにXcodeとiOS SDKがないため、画面プレビューの合格はiPhoneアプリの動作保証ではありません。** 残る試験項目は `INSTALL.md` に記載。
