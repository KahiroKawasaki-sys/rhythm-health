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
}
