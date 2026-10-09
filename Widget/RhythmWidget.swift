import WidgetKit
import SwiftUI

/// ホーム画面のウィジェット。ゲートの記録（App Group）から今日の回数と遊び予算の残りを出す。
/// SNSの利用時間はAppleの仕組みで表示拡張の外へ出せないため、ここでは扱わない。
@main struct RhythmWidgetBundle: WidgetBundle {
    var body: some Widget { GateWidget() }
}

struct GateEntry: TimelineEntry {
    var date: Date
    /// nil はiPhoneのロック中などで記録を読めなかったとき。
    var snapshot: GateDaySnapshot?
    var enabled: Bool
    var options: WidgetOptions
}

struct GateProvider: TimelineProvider {
    func placeholder(in context: Context) -> GateEntry {
        GateEntry(date: .now, snapshot: GateDaySnapshot(attempts: 6, stayedAway: 3, budgetUsed: 12, budget: 30),
            enabled: true, options: WidgetOptions())
    }

    func getSnapshot(in context: Context, completion: @escaping (GateEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GateEntry>) -> Void) {
        let entry = load()
        // 記録が増えると本体・拡張が描き直しを頼む。日付の切り替わりと、念のため30分ごとにも読み直す。
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        let next = min(midnight, Date.now.addingTimeInterval(30 * 60))
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private struct ConfigFile: Decodable {
        var enabled: Bool
        var settings: GateSettings
    }
    private struct LogFile: Decodable {
        var events: [GateEvent]
    }

    private func load() -> GateEntry {
        let options = WidgetOptions.load()
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetOptions.appGroup) else {
            return GateEntry(date: .now, snapshot: nil, enabled: false, options: options)
        }
        let folder = base.appendingPathComponent("Gate", isDirectory: true)
        let config = (try? Data(contentsOf: folder.appendingPathComponent("config.json")))
            .flatMap { try? JSONDecoder().decode(ConfigFile.self, from: $0) }
        let eventsURL = folder.appendingPathComponent("events.json")
        var events: [GateEvent]? = []
        if FileManager.default.fileExists(atPath: eventsURL.path) {
            // 記録は完全保護なので、ロック中は読めない。
            events = (try? Data(contentsOf: eventsURL)).flatMap { try? JSONDecoder().decode(LogFile.self, from: $0) }?.events
        }
        guard let events else { return GateEntry(date: .now, snapshot: nil, enabled: config?.enabled ?? false, options: options) }
        let snapshot = GateDaySnapshot.make(.now, events, settings: config?.settings ?? GateSettings())
        return GateEntry(date: .now, snapshot: snapshot, enabled: config?.enabled ?? false, options: options)
    }
}

struct GateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetOptions.kind, provider: GateProvider()) { entry in
            GateWidgetView(entry: entry).containerBackground(Color(red: 245/255, green: 246/255, blue: 242/255), for: .widget)
        }
        .configurationDisplayName("ひと呼吸")
        .description("今日、SNSを開く前に踏みとどまった回数と、遊び予算の残り。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct GateWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GateEntry
    private let green = Color(red: 17/255, green: 90/255, blue: 54/255)
    private let ink = Color(red: 26/255, green: 41/255, blue: 35/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "leaf.fill").foregroundStyle(green)
                Text("ひと呼吸 · 今日").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            if let snapshot = entry.snapshot {
                if family == .systemSmall { small(snapshot) } else { medium(snapshot) }
            } else {
                Spacer()
                Text("iPhoneのロックを解除すると更新します").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            if !entry.enabled {
                Text("設定でゲートをオンにすると記録されます").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func small(_ snapshot: GateDaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            Text("遊び予算の残り").font(.caption2).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(snapshot.budgetLeft)").font(.system(size: 34, weight: .semibold, design: .rounded)).foregroundStyle(ink)
                Text("/\(snapshot.budget)分").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(snapshot.budgetLeft), total: Double(max(snapshot.budget, 1))).tint(green)
            Text("踏みとどまった \(snapshot.stayedAway)回").font(.caption.weight(.medium)).foregroundStyle(green)
        }
    }

    private func medium(_ snapshot: GateDaySnapshot) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            if entry.options.showsStayedAway { stat("踏みとどまった", "\(snapshot.stayedAway)", "回", color: green) }
            if entry.options.showsAttempts { stat("開こうとした", "\(snapshot.attempts)", "回", color: ink) }
            if entry.options.showsBudget { stat("遊び予算の残り", "\(snapshot.budgetLeft)", "/\(snapshot.budget)分", color: ink) }
            if !entry.options.showsStayedAway && !entry.options.showsAttempts && !entry.options.showsBudget {
                Text("Rhythmの設定で表示する項目を選んでください").font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func stat(_ label: String, _ value: String, _ unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(color)
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
