import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI

extension DeviceActivityReport.Context {
    /// 今日の画面のスクリーンタイムカード。比べる基準（7日・30日平均）ごとに分ける。
    static let rhythmTodayCard7 = Self("rhythm.today.card.7")
    static let rhythmTodayCard30 = Self("rhythm.today.card.30")
    static func rhythmTodayCard(compareDays: Int) -> Self { compareDays == 30 ? .rhythmTodayCard30 : .rhythmTodayCard7 }
    /// 振り返りの上のグラフ（指標×期間）、下の一覧（期間）、カレンダー（指標）。
    static func rhythmReviewChart(_ metric: ScreenMetric, _ period: ReviewPeriod) -> Self {
        Self("rhythm.review.chart.\(metric.rawValue).\(period.rawValue)")
    }
    static func rhythmReviewRows(_ period: ReviewPeriod) -> Self { Self("rhythm.review.rows.\(period.rawValue)") }
    static func rhythmReviewCalendar(_ metric: ScreenMetric) -> Self { Self("rhythm.review.calendar.\(metric.rawValue)") }
    /// スクリーンタイム詳細（今日・7日平均・30日平均）。
    static func rhythmDetail(_ range: DetailRange) -> Self { Self("rhythm.detail.\(range.rawValue)") }
}

/// 振り返りで表示拡張が描くスクリーンタイムの指標。
enum ScreenMetric: String, CaseIterable, Identifiable {
    case sns, total
    var id: String { rawValue }
    var label: String { self == .sns ? "SNS" : "スクリーンタイム" }
    var color: Color { self == .sns ? ScreenCategory.sns.color : ScreenCategory.work.color }
}

/// スクリーンタイム詳細の期間。
enum DetailRange: String, CaseIterable, Identifiable {
    case today, average7, average30
    var id: String { rawValue }
    var label: String { ["今日", "7日平均", "30日平均"][Self.allCases.firstIndex(of: self)!] }
    /// 平均に使う日数。今日は時間帯別の比較に7日平均を使う。
    var days: Int { self == .average30 ? 30 : 7 }
}

/// スクリーンタイムの4区分。どれにも選ばれていないアプリは「その他」。
enum ScreenCategory: String, CaseIterable, Identifiable {
    case sns, video, work, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sns: return "SNS"
        case .video: return "動画"
        case .work: return "仕事"
        case .other: return "その他"
        }
    }
    var color: Color {
        switch self {
        case .sns: return Color(red: 207/255, green: 79/255, blue: 37/255)
        case .video: return Color(red: 122/255, green: 103/255, blue: 168/255)
        case .work: return Color(red: 61/255, green: 110/255, blue: 143/255)
        case .other: return Color(red: 184/255, green: 191/255, blue: 182/255)
        }
    }
}

/// アプリの分類とSNSの1日目標。表示拡張が読めるようApp Groupに置く。
/// 中身はAppleの識別子と分数の設定だけで、利用時間は含めない。
struct ScreenCategories: Codable {
    var version = 1
    var sns = FamilyActivitySelection()
    var video = FamilyActivitySelection()
    var work = FamilyActivitySelection()
    var snsGoalMinutes = 45

    static let goalRange = 5...240

    func selection(_ category: ScreenCategory) -> FamilyActivitySelection? {
        switch category {
        case .sns: return sns
        case .video: return video
        case .work: return work
        case .other: return nil
        }
    }

    /// 開く前のゲートの対象。YouTubeなどの動画はSNSに数えないが、ゲートには残す。
    var gateSelection: FamilyActivitySelection {
        var result = sns
        result.applicationTokens.formUnion(video.applicationTokens)
        result.webDomainTokens.formUnion(video.webDomainTokens)
        result.categoryTokens.formUnion(video.categoryTokens)
        return result
    }

    /// アプリ単位の選択を優先し、次にカテゴリ単位で判定する。SNS→動画→仕事の順。
    func classify(application: ApplicationToken?, category: ActivityCategoryToken?) -> ScreenCategory {
        let order: [ScreenCategory] = [.sns, .video, .work]
        if let application, let hit = order.first(where: { selection($0)!.applicationTokens.contains(application) }) { return hit }
        if let category, let hit = order.first(where: { selection($0)!.categoryTokens.contains(category) }) { return hit }
        return .other
    }

    func classify(webDomain: WebDomainToken?, category: ActivityCategoryToken?) -> ScreenCategory {
        let order: [ScreenCategory] = [.sns, .video, .work]
        if let webDomain, let hit = order.first(where: { selection($0)!.webDomainTokens.contains(webDomain) }) { return hit }
        if let category, let hit = order.first(where: { selection($0)!.categoryTokens.contains(category) }) { return hit }
        return .other
    }
}

extension FamilyActivitySelection {
    var isEmptySelection: Bool { applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty }
}

enum ScreenCategoryFiles {
    static let appGroup = "group.com.kawakahi.rhythm"

    enum FileError: LocalizedError {
        case noContainer, corrupt
        var errorDescription: String? {
            switch self {
            case .noContainer: return "共有領域（App Group）を開けませんでした。"
            case .corrupt: return "アプリの分類を読み込めませんでした。元の選択を守るため、保存を停止しています。"
            }
        }
    }

    private static func url() throws -> URL {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw FileError.noContainer
        }
        return base.appendingPathComponent("Screen", isDirectory: true).appendingPathComponent("categories.json")
    }

    /// まだ保存していなければnil。
    static func load() throws -> ScreenCategories? {
        let url = try url()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let saved = try? JSONDecoder().decode(ScreenCategories.self, from: Data(contentsOf: url)),
              saved.version == 1, ScreenCategories.goalRange.contains(saved.snsGoalMinutes) else { throw FileError.corrupt }
        return saved
    }

    /// 本体だけが書く。表示拡張は読むだけ。
    static func save(_ categories: ScreenCategories) throws {
        var folder = try url().deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
        }
        try JSONEncoder().encode(categories).write(to: try url(),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// 振り返りのカレンダーの1マス。本体（睡眠・歩数）と表示拡張（SNS・合計）で共用する。
/// levelがnilの日は記録なし（点線）、isFutureは今日以降（薄く）。
struct CalendarCell: View {
    let day: Date
    let value: String?
    let level: Double?
    let tint: Color
    var isFuture = false
    var goalMet = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7)
        let fill: Color = level.map { tint.opacity(0.12 + $0 * 0.78) } ?? Color.clear
        let ink: Color = (level ?? 0) > 0.58 ? .white : .primary
        let calendar = Calendar.current
        let showMonth = calendar.component(.day, from: day) == 1
        let dayText = showMonth ? day.formatted(.dateTime.month(.defaultDigits).day()) : day.formatted(.dateTime.day())
        return VStack(spacing: 1) {
            Text(dayText).font(.system(size: 10))
            if !isFuture { Text(value ?? "—").font(.system(size: 9, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6) }
        }
        .frame(maxWidth: .infinity, minHeight: 38)
        .foregroundStyle(ink)
        .background(fill, in: shape)
        .overlay(shape.strokeBorder(Color.secondary.opacity(level == nil && !isFuture ? 0.35 : 0), style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
        .overlay(shape.strokeBorder(Color(red: 17/255, green: 90/255, blue: 54/255), lineWidth: goalMet ? 2 : 0))
        .opacity(isFuture ? 0.35 : 1)
        .accessibilityElement()
        .accessibilityLabel(day.formatted(.dateTime.month().day()) + " " + (isFuture ? "" : (value ?? "記録なし")) + (goalMet ? "、目標以下" : ""))
    }
}

/// 月曜始まりの曜日見出し。
struct WeekdayHeader: View {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(["月", "火", "水", "木", "金", "土", "日"], id: \.self) { name in
                Text(name).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }
}

/// 値の最小〜最大で0〜1に直す（カレンダーの濃淡）。
func calendarLevels(_ values: [Double]) -> (Double) -> Double {
    let low = values.min() ?? 0, high = values.max() ?? 0
    return { value in high > low ? (value - low) / (high - low) : 0.5 }
}
