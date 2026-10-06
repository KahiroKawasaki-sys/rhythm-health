import DeviceActivity
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
