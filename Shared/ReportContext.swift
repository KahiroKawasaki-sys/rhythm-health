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
