import XCTest
#if SWIFT_PACKAGE
@testable import RhythmCore
#else
@testable import Rhythm
#endif

final class HealthMathTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }
    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text + "+09:00")!
    }

    func testOverlappingWatchAndAppSleepIsNotDoubleCounted() {
        let from = date("2026-10-03T23:00:00"), to = date("2026-10-04T07:00:00")
        let spans = [SleepSpan(start: from, end: to),
            SleepSpan(start: date("2026-10-04T01:00:00"), end: date("2026-10-04T05:00:00"))]
        XCTAssertEqual(HealthMath.mergedDuration(spans, during: DateInterval(start: from, end: to)), 8 * 3600)
    }
    func testAwakeGapsAreNotCounted() {
        let from = date("2026-10-03T23:00:00"), to = date("2026-10-04T07:00:00")
        let spans = [SleepSpan(start: from, end: date("2026-10-04T02:00:00")),
            SleepSpan(start: date("2026-10-04T03:00:00"), end: to)]
        XCTAssertEqual(HealthMath.mergedDuration(spans, during: DateInterval(start: from, end: to)), 7 * 3600)
    }
    func testSleepBelongsToWakeDayAndIsClippedAtNoon() {
        let today = date("2026-10-04T00:00:00"), yesterday = date("2026-10-03T00:00:00")
        let spans = [SleepSpan(start: date("2026-10-03T23:00:00"), end: date("2026-10-04T07:00:00"))]
        let result = HealthMath.sleepByDay(spans, days: [yesterday, today], calendar: calendar)
        XCTAssertNil(result[yesterday]); XCTAssertEqual(result[today], 480)
        let clipped = HealthMath.sleepByDay([SleepSpan(start: date("2026-10-03T10:00:00"), end: date("2026-10-03T14:00:00"))], days: [today], calendar: calendar)
        XCTAssertEqual(clipped[today], 120)
    }
    func testLatestWeightWinsRegardlessOfQueryOrder() {
        let a = TimedWeight(date: date("2026-10-04T08:00:00"), kilograms: 69)
        let b = TimedWeight(date: date("2026-10-04T20:00:00"), kilograms: 70)
        XCTAssertEqual(HealthMath.latestWeights([b, a], calendar: calendar)[date("2026-10-04T00:00:00")], 70)
    }
    func testMissingValuesAreNotZeroAndRealZeroCounts() {
        XCTAssertEqual(HealthMath.average([nil, 6, 8]), 7)
        XCTAssertEqual(HealthMath.average([0, 10]), 5)
        XCTAssertNil(HealthMath.average([nil, nil]))
    }
    func testComparisonExcludesTodayAndHasEqualPeriods() {
        let days = HealthMath.completedDays(count: 14, now: date("2026-10-04T15:00:00"), calendar: calendar)
        XCTAssertEqual(days.count, 14)
        XCTAssertEqual(days.first, date("2026-09-20T00:00:00"))
        XCTAssertEqual(days.last, date("2026-10-03T00:00:00"))
    }
    func testManualOverridesOnlyPresentFieldsAndClearingRestoresHealth() {
        let day = date("2026-10-04T00:00:00")
        let manual = DayRecord(day: day, weight: 66, note: "テスト")
        let row = HealthMath.resolve(days: [day], weights: [day: 70], sleep: [day: 450], manual: [manual])[0]
        XCTAssertEqual(row.weight, 66); XCTAssertEqual(row.sleepMinutes, 450)
        XCTAssertEqual(row.weightSource, "手入力"); XCTAssertEqual(row.sleepSource, "Apple Health")
        XCTAssertEqual(HealthMath.resolve(days: [day], weights: [day: 70], sleep: [:], manual: [])[0].weight, 70)
    }
    func testInvalidNumbersAndFutureDatesAreRejected() {
        let day = date("2026-10-04T00:00:00"), now = date("2026-10-04T12:00:00")
        XCTAssertNotNil(HealthMath.validate(DayRecord(day: day, weight: .nan), now: now, calendar: calendar))
        XCTAssertNotNil(HealthMath.validate(DayRecord(day: day, sleepMinutes: 1441), now: now, calendar: calendar))
        XCTAssertNotNil(HealthMath.validate(DayRecord(day: day, screenMinutes: -1), now: now, calendar: calendar))
        XCTAssertNotNil(HealthMath.validate(DayRecord(day: date("2026-10-05T00:00:00")), now: now, calendar: calendar))
        XCTAssertNil(HealthMath.validate(DayRecord(day: day, weight: 68, screenMinutes: 0), now: now, calendar: calendar))
    }
    func testRecordRoundTripsWithoutLosingJapaneseNotes() throws {
        let record = DayRecord(day: date("2026-10-04T00:00:00"), weight: 68.4, sleepMinutes: 420, screenMinutes: 90, mood: 4, note: "朝すっきり。")
        XCTAssertEqual(try JSONDecoder().decode(DayRecord.self, from: JSONEncoder().encode(record)), record)
    }
    func testDaylightSavingUsesCalendarNotFixed24Hours() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = ISO8601DateFormatter().date(from: "2026-03-10T12:00:00-07:00")!
        let days = HealthMath.completedDays(count: 3, now: now, calendar: c)
        XCTAssertEqual(days.map { c.component(.day, from: $0) }, [7, 8, 9])
        XCTAssertEqual(days.map { c.component(.hour, from: $0) }, [0, 0, 0])
    }

    // MARK: v1.1 長期の振り返り
    private var now: Date { date("2026-10-04T15:00:00") }
    private var yesterday: Date { date("2026-10-03T00:00:00") }

    func testPeriodDaysCoverRequestedLengthAndEndYesterday() {
        let year = HealthMath.periodDays(.year, now: now, calendar: calendar)
        XCTAssertEqual(year.count, 365); XCTAssertEqual(year.last, yesterday)
        XCTAssertEqual(HealthMath.periodDays(.quarter, now: now, calendar: calendar).count, 90)
        XCTAssertEqual(HealthMath.periodDays(.month, now: now, calendar: calendar).count, 30)
    }
    func testComparisonIsTheAdjacentEarlierPeriod() {
        for period in ReviewPeriod.allCases {
            let current = HealthMath.periodDays(period, now: now, calendar: calendar)
            let before = HealthMath.comparisonDays(period, now: now, calendar: calendar)
            XCTAssertEqual(before.count, current.count)
            XCTAssertEqual(calendar.date(byAdding: .day, value: 1, to: before.last!), current.first)
        }
    }
    func testFetchStartCoversComparisonAndMovingAverage() {
        XCTAssertEqual(HealthMath.fetchStart(.week, now: now, calendar: calendar), date("2026-09-13T00:00:00"))
        XCTAssertLessThan(HealthMath.fetchStart(.year, now: now, calendar: calendar), date("2024-10-04T00:00:00"))
    }
    func testMovingAverageNeedsThreeRecordsAndIgnoresLaterDays() {
        let d = { (day: Int) in self.date(String(format: "2026-09-%02dT00:00:00", day)) }
        XCTAssertNil(HealthMath.movingAverage([d(1): 70, d(3): 72], on: [d(3)], calendar: calendar)[d(3)])
        let three = HealthMath.movingAverage([d(1): 70, d(3): 72, d(5): 74, d(9): 100], on: [d(5), d(8)], calendar: calendar)
        XCTAssertEqual(three[d(5)], 72)
        XCTAssertNil(three[d(8)])
    }
    func testBucketsCountRecordedDaysAndMarkPartialPeriods() {
        let days = HealthMath.days(from: date("2026-09-20T00:00:00"), through: date("2026-10-03T00:00:00"), calendar: calendar)
        let values: [Date: Double] = [date("2026-09-21T00:00:00"): 6, date("2026-09-22T00:00:00"): 8, date("2026-10-01T00:00:00"): 7]
        let months = HealthMath.buckets(values, days: days, unit: .month, calendar: calendar)
        XCTAssertEqual(months.count, 2)
        XCTAssertEqual(months[0].average, 7); XCTAssertEqual(months[0].recordedDays, 2); XCTAssertEqual(months[0].totalDays, 11)
        XCTAssertTrue(months[0].isPartial); XCTAssertTrue(months[1].isPartial)
        var sundayFirst = calendar; sundayFirst.firstWeekday = 1
        let weeks = HealthMath.buckets(values, days: days, unit: .week, calendar: sundayFirst)
        XCTAssertEqual(weeks.map(\.totalDays), [7, 7])
        XCTAssertFalse(weeks[0].isPartial)
        XCTAssertNil(HealthMath.buckets([:], days: days, unit: .week, calendar: calendar)[0].average)
    }
    func testMonthComparisonUsesPreviousMonthAndSameMonthLastYear() {
        let october = calendar.dateInterval(of: .month, for: now)!
        let values: [Date: Double] = [date("2026-10-01T00:00:00"): 7, date("2026-10-04T00:00:00"): 99,
            date("2026-09-10T00:00:00"): 6, date("2025-10-15T00:00:00"): 5]
        let result = HealthMath.monthComparison(values, month: october, now: now, calendar: calendar)
        XCTAssertEqual(result.average, 7); XCTAssertEqual(result.recordedDays, 1)
        XCTAssertEqual(result.previousMonth, 6); XCTAssertEqual(result.lastYear, 5); XCTAssertEqual(result.lastYearRecorded, 1)
    }
    func testRecentMonthsEndWithCurrentMonth() {
        let months = HealthMath.recentMonths(count: 12, now: now, calendar: calendar)
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months.first?.start, date("2025-11-01T00:00:00")); XCTAssertEqual(months.last?.start, date("2026-10-01T00:00:00"))
    }
    func testCalendarGridPadsToFirstWeekday() {
        var c = calendar; c.firstWeekday = 1
        let october = c.dateInterval(of: .month, for: now)!
        let grid = HealthMath.calendarGrid(month: october, calendar: c)
        XCTAssertEqual(grid.prefix(4).compactMap { $0 }.count, 0)
        XCTAssertEqual(grid[4], date("2026-10-01T00:00:00")); XCTAssertEqual(grid.count, 4 + 31)
        c.firstWeekday = 2
        XCTAssertEqual(HealthMath.calendarGrid(month: october, calendar: c).prefix(while: { $0 == nil }).count, 3)
    }
    func testIntensityKeepsMissingDaysUncolored() {
        XCTAssertNil(HealthMath.intensity(nil, maximum: 10))
        XCTAssertEqual(HealthMath.intensity(0, maximum: 10), 0)
        XCTAssertEqual(HealthMath.intensity(15, maximum: 10), 1)
        XCTAssertEqual(HealthMath.intensity(5, maximum: 0), 0)
    }

    func testCalendarWeeksAreMondayFirstAndEndOnTheWeekOfYesterday() {
        // 2026-10-04は日曜。昨日（10/3 土）を含む週は10/4（日）で終わる。
        let weeks = HealthMath.calendarWeeks(offset: 0, now: now, calendar: calendar)
        XCTAssertEqual(weeks.count, 35)
        XCTAssertEqual(weeks.last, date("2026-10-04T00:00:00"))
        XCTAssertEqual(weeks.first, date("2026-08-31T00:00:00"))
        XCTAssertEqual(calendar.component(.weekday, from: weeks.first!), 2)
        XCTAssertEqual(HealthMath.calendarWeeks(offset: 1, now: now, calendar: calendar).last, date("2026-08-30T00:00:00"))
        XCTAssertEqual(HealthMath.calendarOffset(containing: date("2026-08-31T00:00:00"), now: now, calendar: calendar), 0)
        XCTAssertEqual(HealthMath.calendarOffset(containing: date("2026-08-30T00:00:00"), now: now, calendar: calendar), 1)
    }
    func testSeriesAndSummaryCompareWithPreviousPeriod() {
        let week = HealthMath.periodDays(.week, now: now, calendar: calendar)
        let before = HealthMath.comparisonDays(.week, now: now, calendar: calendar)
        var values: [Date: Double] = [:]
        for day in week.prefix(3) { values[day] = 60 }
        for day in before.prefix(2) { values[day] = 40 }
        let summary = HealthMath.periodSummary(values, period: .week, now: now, calendar: calendar)
        XCTAssertEqual(summary.average, 60); XCTAssertEqual(summary.recordedDays, 3); XCTAssertEqual(summary.delta, 20)
        let series = HealthMath.series(values, period: .week, now: now, calendar: calendar)
        XCTAssertEqual(series.count, 7); XCTAssertEqual(series.compactMap(\.value).count, 3)
        XCTAssertNil(HealthMath.periodSummary([:], period: .year, now: now, calendar: calendar).delta)
    }
    func testTotalsUntilProratesCurrentHourAndSkipsDaysWithoutData() {
        let day = date("2026-10-08T00:00:00"), empty = date("2026-10-07T00:00:00")
        let hourly = [date("2026-10-08T07:00:00"): 10.0, date("2026-10-08T14:00:00"): 30, date("2026-10-08T20:00:00"): 50]
        // 14:30まで → 7時台10分 + 14時台30分の半分
        let result = HealthMath.totalsUntil(hourly, days: [day, empty], elapsed: 14.5 * 3600, calendar: calendar)
        XCTAssertEqual(result[day], 25)
        XCTAssertNil(result[empty])
        // 値が夜にしかない日も、記録がある日として0を返す
        let late = HealthMath.totalsUntil([date("2026-10-08T20:00:00"): 50], days: [day], elapsed: 9 * 3600, calendar: calendar)
        XCTAssertEqual(late[day], 0)
    }
    func testDailyTotalsAndFirstHour() {
        let hourly = [date("2026-10-08T07:00:00"): 0.0, date("2026-10-08T09:00:00"): 12, date("2026-10-08T21:00:00"): 8]
        XCTAssertEqual(HealthMath.dailyTotals(hourly, calendar: calendar)[date("2026-10-08T00:00:00")], 20)
        XCTAssertEqual(HealthMath.firstHour(hourly, on: date("2026-10-08T00:00:00"), calendar: calendar), 9)
        XCTAssertNil(HealthMath.firstHour(hourly, on: date("2026-10-09T00:00:00"), calendar: calendar))
    }
    func testStreakStopsAtMissingOrOverGoalDay() {
        let today = date("2026-10-09T00:00:00")
        let daily = [date("2026-10-08T00:00:00"): 40.0, date("2026-10-07T00:00:00"): 45, date("2026-10-06T00:00:00"): 46,
                     date("2026-10-05T00:00:00"): 10]
        XCTAssertEqual(HealthMath.streak(daily, goal: 45, today: today, limit: 30, calendar: calendar), 2)
        XCTAssertEqual(HealthMath.streak(daily, goal: 45, today: today, limit: 1, calendar: calendar), 1)
        XCTAssertEqual(HealthMath.streak([date("2026-10-07T00:00:00"): 1], goal: 45, today: today, limit: 30, calendar: calendar), 0)
    }
    func testShortDuration() {
        XCTAssertEqual(HealthMath.shortDuration(45), "45分")
        XCTAssertEqual(HealthMath.shortDuration(65), "1時間05分")
    }
}
