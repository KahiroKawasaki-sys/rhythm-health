import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI

extension DeviceActivityReport.Context {
    static let rhythmToday = Self("rhythm.today")
    static let rhythmWeek = Self("rhythm.week")
    static let rhythmMonth = Self("rhythm.month")
    static let rhythmQuarter = Self("rhythm.quarter")
    static let rhythmYear = Self("rhythm.year")
    static let rhythmMonthly = Self("rhythm.monthly")
    static let rhythmSNSWeek = Self("rhythm.sns.week")
    static let rhythmSNSMonth = Self("rhythm.sns.month")
    static let rhythmSNSQuarter = Self("rhythm.sns.quarter")
    static let rhythmSNSYear = Self("rhythm.sns.year")
    static let rhythmSNSMonthly = Self("rhythm.sns.monthly")
    static let rhythmSNSCalendar = Self("rhythm.sns.calendar")
    /// 今日の画面のスクリーンタイムカード。比べる基準（7日・30日平均）ごとに分ける。
    static let rhythmTodayCard7 = Self("rhythm.today.card.7")
    static let rhythmTodayCard30 = Self("rhythm.today.card.30")
    static func rhythmTodayCard(compareDays: Int) -> Self { compareDays == 30 ? .rhythmTodayCard30 : .rhythmTodayCard7 }
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

/// カレンダーの1マス。本体（睡眠）と表示拡張（SNS）で共用する。levelがnilの日は無色。
struct HeatCell: View {
    let day: Date
    let level: Double?
    let detail: String

    var body: some View {
        let tint = Color(red: 17/255, green: 90/255, blue: 54/255)
        let fill: Color = level.map { tint.opacity(0.12 + $0 * 0.88) } ?? Color.clear
        let ink: Color = (level ?? 0) > 0.6 ? Color.white : Color.primary
        let border: Color = Color.secondary.opacity(level == nil ? 0.3 : 0)
        let shape = RoundedRectangle(cornerRadius: 6)
        let label: String = day.formatted(.dateTime.month().day()) + " " + detail
        return Text(day.formatted(.dateTime.day()))
            .font(.caption2)
            .frame(maxWidth: .infinity, minHeight: 32)
            .foregroundStyle(ink)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(border, style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
            .accessibilityLabel(label)
    }
}

extension ReviewPeriod {
    func reportContext(sns: Bool) -> DeviceActivityReport.Context {
        switch self {
        case .week: return sns ? .rhythmSNSWeek : .rhythmWeek
        case .month: return sns ? .rhythmSNSMonth : .rhythmMonth
        case .quarter: return sns ? .rhythmSNSQuarter : .rhythmQuarter
        case .year: return sns ? .rhythmSNSYear : .rhythmYear
        case .monthly: return sns ? .rhythmSNSMonthly : .rhythmMonthly
        }
    }
}
