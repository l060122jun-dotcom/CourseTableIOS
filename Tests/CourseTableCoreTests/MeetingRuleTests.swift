import XCTest
@testable import CourseTableCore

final class MeetingRuleTests: XCTestCase {
    private let courseID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let periods = [
        Period(index: 1, startMinuteOfDay: 480, endMinuteOfDay: 525),
        Period(index: 2, startMinuteOfDay: 530, endMinuteOfDay: 575),
        Period(index: 3, startMinuteOfDay: 600, endMinuteOfDay: 645)
    ]

    private var table: CourseTable {
        CourseTable(
            name: "测试学期",
            semesterStartDate: Date(timeIntervalSince1970: 0),
            totalWeeks: 18
        )
    }

    func testValidCustomTimeResolvesExactly() throws {
        let rule = MeetingRule(
            courseID: courseID,
            weekday: 2,
            weekSet: [1, 2],
            customStartMinute: 550,
            customEndMinute: 625
        )
        try MeetingRuleValidator.validate(rule, in: table, periods: periods)
        XCTAssertEqual(
            try MeetingRuleValidator.resolve(rule, periods: periods),
            ResolvedMeetingTime(startMinuteOfDay: 550, endMinuteOfDay: 625)
        )
    }

    func testCustomStartEqualToEndFails() {
        let rule = MeetingRule(
            courseID: courseID,
            weekday: 2,
            weekSet: [1],
            customStartMinute: 600,
            customEndMinute: 600
        )
        XCTAssertThrowsError(try MeetingRuleValidator.validate(rule, in: table, periods: periods)) {
            XCTAssertEqual($0 as? MeetingRuleValidationError, .invalidCustomTime)
        }
    }

    func testCustomStartAfterEndFails() {
        let rule = MeetingRule(
            courseID: courseID,
            weekday: 2,
            weekSet: [1],
            customStartMinute: 700,
            customEndMinute: 600
        )
        XCTAssertThrowsError(try MeetingRuleValidator.validate(rule, in: table, periods: periods))
    }

    func testFullDayBoundaryIsAccepted() throws {
        let rule = MeetingRule(
            courseID: courseID,
            weekday: 2,
            weekSet: [1],
            customStartMinute: 0,
            customEndMinute: 1440
        )
        try MeetingRuleValidator.validate(rule, in: table, periods: periods)
    }

    func testCustomStartAtTwentyFourHundredFails() {
        let rule = MeetingRule(
            courseID: courseID,
            weekday: 2,
            weekSet: [1],
            customStartMinute: 1440,
            customEndMinute: 1441
        )
        XCTAssertThrowsError(try MeetingRuleValidator.validate(rule, in: table, periods: periods))
    }

    func testMissingCustomEndFails() {
        var rule = MeetingRule(
            courseID: courseID,
            weekday: 2,
            weekSet: [1],
            customStartMinute: 600,
            customEndMinute: 660
        )
        rule.customEndMinute = nil
        XCTAssertThrowsError(try MeetingRuleValidator.validate(rule, in: table, periods: periods)) {
            XCTAssertEqual($0 as? MeetingRuleValidationError, .missingCustomTime)
        }
    }

    func testInvalidPeriodOrderFails() {
        let rule = MeetingRule(
            courseID: courseID,
            weekday: 2,
            weekSet: [1],
            startPeriod: 3,
            endPeriod: 1
        )
        XCTAssertThrowsError(try MeetingRuleValidator.validate(rule, in: table, periods: periods)) {
            XCTAssertEqual($0 as? MeetingRuleValidationError, .invalidPeriodRange)
        }
    }

    func testSwitchingTimingModeClearsInactiveFields() {
        var rule = MeetingRule(
            courseID: courseID,
            weekday: 2,
            weekSet: [1],
            startPeriod: 1,
            endPeriod: 2
        )
        rule.useCustomTime(startMinute: 610, endMinute: 700)
        XCTAssertNil(rule.startPeriod)
        XCTAssertNil(rule.endPeriod)

        rule.usePeriods(start: 2, end: 3)
        XCTAssertNil(rule.customStartMinute)
        XCTAssertNil(rule.customEndMinute)
    }

    func testPeriodAndCustomRulesResolveIndependently() throws {
        let periodRule = MeetingRule(
            courseID: courseID,
            weekday: 3,
            weekSet: [1],
            startPeriod: 1,
            endPeriod: 2
        )
        let customRule = MeetingRule(
            courseID: courseID,
            weekday: 5,
            weekSet: [1],
            customStartMinute: 615,
            customEndMinute: 700
        )
        XCTAssertEqual(
            try MeetingRuleValidator.resolve(periodRule, periods: periods),
            ResolvedMeetingTime(startMinuteOfDay: 480, endMinuteOfDay: 575)
        )
        XCTAssertEqual(
            try MeetingRuleValidator.resolve(customRule, periods: periods),
            ResolvedMeetingTime(startMinuteOfDay: 615, endMinuteOfDay: 700)
        )
    }

    func testFingerprintIncludesCustomTimesAndIsStable() throws {
        let ruleID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let first = MeetingRule(
            id: ruleID,
            courseID: courseID,
            weekday: 4,
            weekSet: [2],
            customStartMinute: 610,
            customEndMinute: 700
        )
        let changed = MeetingRule(
            id: ruleID,
            courseID: courseID,
            weekday: 4,
            weekSet: [2],
            customStartMinute: 620,
            customEndMinute: 700
        )
        let firstFingerprint = try XCTUnwrap(
            CalendarOccurrenceFactory.makeOccurrences(for: first, periods: periods).first?.fingerprint
        )
        let repeatedFingerprint = try XCTUnwrap(
            CalendarOccurrenceFactory.makeOccurrences(for: first, periods: periods).first?.fingerprint
        )
        let changedFingerprint = try XCTUnwrap(
            CalendarOccurrenceFactory.makeOccurrences(for: changed, periods: periods).first?.fingerprint
        )
        XCTAssertEqual(firstFingerprint, repeatedFingerprint)
        XCTAssertNotEqual(firstFingerprint, changedFingerprint)
    }
}
