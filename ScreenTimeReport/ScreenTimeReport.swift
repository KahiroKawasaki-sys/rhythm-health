import DeviceActivity
import SwiftUI
import Charts

@main struct RhythmReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        RhythmReportScene(context: .rhythmToday, days: nil)
        RhythmReportScene(context: .rhythmWeek, days: 7)
        RhythmReportScene(context: .rhythmMonth, days: 28)
    }
}

struct ScreenDay: Identifiable {
    var day: Date
    var minutes: Double
    var segment: Int = 0
    var id: Date { day }
}

struct ScreenConfiguration {
    var days: [ScreenDay]
    var average: Double?
    var previousAverage: Double?
    var previousCount: Int
    var period: Int?
}

struct RhythmReportScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context
    let days: Int?
    let content: (ScreenConfiguration) -> ScreenReportView = { ScreenReportView(configuration: $0) }

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> ScreenConfiguration {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var totals: [Date: Double] = [:]
        // Values stay exclusively inside the report extension. No shared defaults, files or networking.
        for await device in data {
            for await segment in device.activitySegments {
                let day = calendar.startOfDay(for: segment.dateInterval.start)
                totals[day, default: 0] += segment.totalActivityDuration / 60
            }
        }
        let requested = days.map { HealthMath.completedDays(count: $0) } ?? [today]
        var segment = 0
        let values = requested.compactMap { day -> ScreenDay? in
            guard let minutes = totals[day] else { segment += 1; return nil }
            return ScreenDay(day: day, minutes: minutes, segment: segment)
        }
        let olderDays = days.map { Array(HealthMath.completedDays(count: $0 * 2).prefix($0)) } ?? []
        let older = olderDays.compactMap { totals[$0] }
        return ScreenConfiguration(days: values, average: HealthMath.average(values.map { Optional($0.minutes) }),
            previousAverage: HealthMath.average(older.map(Optional.some)), previousCount: older.count, period: days)
    }
}

struct ScreenReportView: View {
    let configuration: ScreenConfiguration
    private let green = Color(red: 17/255, green: 90/255, blue: 54/255)
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let average = configuration.average {
                Text(HealthMath.duration(Int(average.rounded()))).font(.system(.title, design: .rounded).weight(.semibold))
                if let period = configuration.period {
                    Text("1日平均 · データ \(configuration.days.count)/\(period)日").font(.caption).foregroundStyle(.secondary)
                    if let before = configuration.previousAverage {
                        Text(String(format: "前の%d日より %+.0f分（比較 %d日分）", period, average - before, configuration.previousCount))
                            .font(.caption).foregroundStyle(green)
                    }
                    Chart {
                        ForEach(configuration.days) { day in
                            LineMark(x: .value("日付", day.day), y: .value("時間", day.minutes / 60),
                                series: .value("連続区間", day.segment)).foregroundStyle(green)
                            PointMark(x: .value("日付", day.day), y: .value("時間", day.minutes / 60)).foregroundStyle(green)
                        }
                    }.chartYScale(domain: 0...max(8, (configuration.days.map(\.minutes).max() ?? 0) / 60 + 1))
                        .chartXScale(domain: HealthMath.completedDays(count: period).first!...HealthMath.completedDays(count: period).last!)
                        .chartYAxis { AxisMarks(position: .leading) }
                        .chartXAxis { AxisMarks(values: .stride(by: .day, count: period == 7 ? 2 : 7)) { _ in
                            AxisValueLabel(format: .dateTime.month().day())
                        } }.frame(height: 150)
                    Text("日別の利用時間（時間）· 昨日まで\(period)日").font(.caption2).foregroundStyle(.secondary)
                } else { Text("今日ここまで · 自動取得").font(.caption).foregroundStyle(.secondary) }
                Text("出典：Appleスクリーンタイム / 表示時に取得").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("表示できる利用データがありません").font(.subheadline)
                Text("設定でスクリーンタイムを有効にして、iPhoneを利用した後に更新してください。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
