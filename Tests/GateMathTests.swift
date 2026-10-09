import XCTest
#if SWIFT_PACKAGE
@testable import RhythmCore
#else
@testable import Rhythm
#endif

final class GateMathTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }
    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text + "+09:00")!
    }
    private func opened(_ text: String, _ purpose: GatePurpose, _ minutes: Int) -> GateEvent {
        GateEvent(date: date(text), kind: .opened, purpose: purpose, minutes: minutes)
    }

    func testWaitGrowsWithCasualChoicesAndIgnoresWork() {
        let settings = GateSettings()
        let noon = date("2026-10-07T12:00:00")
        XCTAssertEqual(GateMath.waitSeconds(for: .play, at: noon, events: [], settings: settings, calendar: calendar), 5)
        let events = [opened("2026-10-07T10:00:00", .play, 1), opened("2026-10-07T11:00:00", .idle, 1),
                      opened("2026-10-07T11:30:00", .work, 15), opened("2026-10-06T20:00:00", .play, 1)]
        // 仕事と前日の分は数えない。n=2 → 15秒
        XCTAssertEqual(GateMath.waitSeconds(for: .idle, at: noon, events: events, settings: settings, calendar: calendar), 15)
        XCTAssertEqual(GateMath.waitSeconds(for: .work, at: noon, events: events, settings: settings, calendar: calendar), 0)
    }

    func testWaitIsCappedAndDoubledInQuietHours() {
        var settings = GateSettings()
        settings.dailyPlayBudget = 240
        let many = (0..<20).map { opened(String(format: "2026-10-07T09:%02d:00", $0), .play, 1) }
        XCTAssertEqual(GateMath.waitSeconds(for: .play, at: date("2026-10-07T12:00:00"), events: many, settings: settings, calendar: calendar), 60)
        let two = [opened("2026-10-07T21:00:00", .play, 1), opened("2026-10-07T21:30:00", .play, 1)]
        XCTAssertEqual(GateMath.waitSeconds(for: .play, at: date("2026-10-07T22:00:00"), events: two, settings: settings, calendar: calendar), 30)
        XCTAssertEqual(GateMath.waitSeconds(for: .play, at: date("2026-10-07T08:59:00"), events: [], settings: settings, calendar: calendar), 10)
        XCTAssertEqual(GateMath.waitSeconds(for: .play, at: date("2026-10-07T09:00:00"), events: [], settings: settings, calendar: calendar), 5)
    }

    func testBudgetCountsUnlockedMinutesAndFixesWaitWhenExceeded() {
        let settings = GateSettings()
        let events = [opened("2026-10-07T10:00:00", .play, 10), opened("2026-10-07T11:00:00", .idle, 5),
                      opened("2026-10-07T12:00:00", .work, 15),
                      GateEvent(date: date("2026-10-07T13:00:00"), kind: .emergency, minutes: 15),
                      opened("2026-10-07T14:00:00", .play, 10)]
        XCTAssertEqual(GateMath.budgetUsed(on: date("2026-10-07T20:00:00"), events, calendar: calendar), 25)
        XCTAssertFalse(GateMath.isOverBudget(on: date("2026-10-07T20:00:00"), events, settings: settings, calendar: calendar))
        let over = events + [opened("2026-10-07T15:00:00", .idle, 5)]
        XCTAssertTrue(GateMath.isOverBudget(on: date("2026-10-07T20:00:00"), over, settings: settings, calendar: calendar))
        XCTAssertEqual(GateMath.waitSeconds(for: .play, at: date("2026-10-07T20:00:00"), events: over, settings: settings, calendar: calendar), 60)
    }

    func testEmergencyOncePerDay() {
        let used = [GateEvent(date: date("2026-10-07T13:00:00"), kind: .emergency, minutes: 15)]
        XCTAssertFalse(GateMath.emergencyAvailable(on: date("2026-10-07T23:59:00"), used, calendar: calendar))
        XCTAssertTrue(GateMath.emergencyAvailable(on: date("2026-10-08T00:00:00"), used, calendar: calendar))
    }

    func testShortUnlockShiftsMonitorStartIntoThePast() {
        let now = date("2026-10-07T12:00:00")
        let short = GateMath.unlockWindow(from: now, minutes: 5)
        XCTAssertEqual(short.end, date("2026-10-07T12:05:00"))
        XCTAssertEqual(short.start, date("2026-10-07T11:50:00"))
        let long = GateMath.unlockWindow(from: now, minutes: 15)
        XCTAssertEqual(long.start, now)
        XCTAssertEqual(long.duration, 15 * 60)
    }

    func testSummaryAndMonthlyHarvest() {
        let events = [opened("2026-10-05T10:00:00", .work, 15), opened("2026-10-05T11:00:00", .play, 10),
                      opened("2026-10-06T11:00:00", .idle, 5),
                      GateEvent(date: date("2026-10-06T12:00:00"), kind: .stayedAway),
                      GateEvent(date: date("2026-10-06T12:30:00"), kind: .stayedAway),
                      GateEvent(date: date("2026-10-05T10:15:00"), kind: .harvest, harvested: true),
                      GateEvent(date: date("2026-09-20T10:15:00"), kind: .harvest, harvested: false),
                      GateEvent(date: date("2026-10-06T20:00:00"), kind: .reach, minutes: 30),
                      GateEvent(date: date("2026-10-06T21:00:00"), kind: .reach, minutes: 60),
                      opened("2026-10-07T11:00:00", .play, 10)]
        let days = [date("2026-10-05T00:00:00"), date("2026-10-06T00:00:00")]
        let summary = GateMath.summary(events, days: days, calendar: calendar)
        XCTAssertEqual(summary.opened, 3)
        XCTAssertEqual(summary.stayedAway, 2)
        XCTAssertEqual(summary.byPurpose, [.work: 1, .play: 1, .idle: 1])
        XCTAssertEqual(summary.budgetMinutes, 15)
        XCTAssertEqual(summary.budgetDays, 2)
        XCTAssertEqual(summary.harvestRate, 1)
        XCTAssertEqual(summary.reachByDay, [date("2026-10-06T00:00:00"): 60])
        let months = GateMath.monthlyHarvest(events, calendar: calendar)
        XCTAssertEqual(months.map(\.answered), [1, 1])
        XCTAssertEqual(months.map(\.rate), [0, 1])
    }

    func testReachIsRecordedOncePerLinePerDay() {
        let events = [GateEvent(date: date("2026-10-07T10:00:00"), kind: .reach, minutes: 15)]
        XCTAssertFalse(GateMath.shouldRecordReach(15, at: date("2026-10-07T18:00:00"), events, calendar: calendar))
        XCTAssertTrue(GateMath.shouldRecordReach(30, at: date("2026-10-07T18:00:00"), events, calendar: calendar))
        XCTAssertTrue(GateMath.shouldRecordReach(15, at: date("2026-10-08T01:00:00"), events, calendar: calendar))
        XCTAssertFalse(GateMath.shouldRecordReach(45, at: date("2026-10-08T01:00:00"), [], calendar: calendar))
    }

    func testValidationRejectsBrokenEvents() {
        XCTAssertTrue(GateMath.validate(opened("2026-10-07T10:00:00", .play, 10)))
        XCTAssertFalse(GateMath.validate(GateEvent(date: .now, kind: .opened, minutes: 10)))
        XCTAssertFalse(GateMath.validate(opened("2026-10-07T10:00:00", .play, 0)))
        XCTAssertFalse(GateMath.validate(GateEvent(date: .now, kind: .reach, minutes: 45)))
        XCTAssertFalse(GateMath.validate(GateEvent(date: .now, kind: .harvest)))
        XCTAssertFalse(GateMath.validate(GateEvent(date: .now, kind: .emergency, minutes: 30)))
        XCTAssertFalse(GateSettings(workMinutes: 0).isValid)
    }

    func testWorkMinutesAndDailyAverages() {
        let events = [opened("2026-10-07T10:00:00", .work, 15), opened("2026-10-07T11:00:00", .play, 10),
                      GateEvent(date: date("2026-10-07T12:00:00"), kind: .stayedAway),
                      opened("2026-10-08T09:00:00", .work, 20)]
        XCTAssertEqual(GateMath.workMinutes(on: date("2026-10-07T00:00:00"), events, calendar: calendar), 15)
        let days = [date("2026-10-06T00:00:00"), date("2026-10-07T00:00:00"), date("2026-10-08T00:00:00")]
        // 10/6は最初の記録より前なので数えない。開こうとした 3回+1回、踏みとどまった 1回+0回
        let average = GateMath.dailyAverages(days, events, calendar: calendar)
        XCTAssertEqual(average?.attempts, 2)
        XCTAssertEqual(average?.stayedAway, 0.5)
        XCTAssertNil(GateMath.dailyAverages(days, [], calendar: calendar))
    }

    func testStrongHoursAreConfigurableAndOldSettingsDecode() throws {
        var settings = GateSettings()
        let morning = date("2026-10-07T07:00:00"), evening = date("2026-10-07T21:30:00")
        XCTAssertEqual(GateMath.waitSeconds(for: .play, at: morning, events: [], settings: settings, calendar: calendar), 10)
        XCTAssertEqual(GateMath.waitSeconds(for: .play, at: evening, events: [], settings: settings, calendar: calendar), 5)
        settings.strongHours = [21]
        XCTAssertEqual(GateMath.waitSeconds(for: .play, at: evening, events: [], settings: settings, calendar: calendar), 10)
        XCTAssertEqual(GateMath.waitSeconds(for: .play, at: morning, events: [], settings: settings, calendar: calendar), 5)
        let old = #"{"workMinutes":15,"playMinutes":10,"idleMinutes":5,"dailyPlayBudget":30}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(GateSettings.self, from: old).strongHours, GateSettings.defaultStrongHours)
        XCTAssertEqual(GateSettings().strongHoursText, "22〜翌9時")
        settings.strongHours = [4, 5, 21, 22, 23]
        XCTAssertEqual(settings.strongHoursText, "4〜6時・21〜24時")
        XCTAssertFalse(GateSettings(strongHours: [24]).isValid)
    }
}
