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
        CourseTable(name: "测试学期", semesterStartDate: Date(timeIntervalSince1970: 0), totalWeeks: 18)
    }

    func testValidCustomTimeResolvesExactly() throws {
        let rule = MeetingRule(courseID: courseID, weekday: 2, weekSet: [1, 2], customStartMinute: 550, customEndMinute: 625)
        try MeetingRuleValidator.validate(rule, in: table, periods: periods)
        XCTAssertEqual(try MeetingRuleValidator.resolve(rule, periods: periods), ResolvedMeetingTime(startMinuteOfDay: 550, endMinuteOfDay: 625))
    }

    func testCustomStartEqualToEndFails() {
        let rule = MeetingRule(courseID: courseID, weekday: 2, weekSet: [1], customStartMinute: 600, customEndMinute: 600)
        XCTAssertThrowsError(try MeetingRuleValidator.validate(rule, in: table, periods: periods)) {
            XCTAssertEqual($0 as? MeetingRuleValidationError, .invalidCustomTime)
        }
    }

    func testCustomStartAfterEndFails() {
        let rule = MeetingRule(courseID: courseID, weekday: 2, weekSet: [1], customStartMinute: 700, customEndMinute: 600)
        XCTAssertThrowsError(try MeetingRuleValidator.validate(rule, in: table, periods: periods))
    }

    func testFullDayBoundaryIsAccepted() throws {
        let rule = MeetingRule(courseID: courseID, weekday: 2, weekSet: [1], customStartMinute: 0, customEndMinute: 1440)
        try MeetingRuleValidator.validate(rule, in: table, periods: periods)
    }

    func testInvalidPeriodOrderFails() {
        let rule = MeetingRule(courseID: courseID, weekday: 2, weekSet: [1], startPeriod: 3, endPeriod: 1)
        XCTAssertThrowsError(try MeetingRuleValidator.validate(rule, in: table, periods: periods)) {
            XCTAssertEqual($0 as? MeetingRuleValidationError, .invalidPeriodRange)
        }
    }

    func testSwitchingTimingModeClearsInactiveFields() {
        var rule = MeetingRule(courseID: courseID, weekday: 2, weekSet: [1], startPeriod: 1, endPeriod: 2)
        rule.useCustomTime(startMinute: 610, endMinute: 700)
        XCTAssertNil(rule.startPeriod)
        XCTAssertNil(rule.endPeriod)
        rule.usePeriods(start: 2, end: 3)
        XCTAssertNil(rule.customStartMinute)
        XCTAssertNil(rule.customEndMinute)
    }

    func testFingerprintStableAndChangesWithTimes() throws {
        let ruleID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let first = MeetingRule(id: ruleID, courseID: courseID, weekday: 4, weekSet: [2], customStartMinute: 610, customEndMinute: 700)
        let changed = MeetingRule(id: ruleID, courseID: courseID, weekday: 4, weekSet: [2], customStartMinute: 620, customEndMinute: 700)
        let firstFingerprint = try XCTUnwrap(CalendarOccurrenceFactory.makeOccurrences(for: first, periods: periods).first?.fingerprint)
        let repeatFingerprint = try XCTUnwrap(CalendarOccurrenceFactory.makeOccurrences(for: first, periods: periods).first?.fingerprint)
        let changedFingerprint = try XCTUnwrap(CalendarOccurrenceFactory.makeOccurrences(for: changed, periods: periods).first?.fingerprint)
        XCTAssertEqual(firstFingerprint, repeatFingerprint)
        XCTAssertNotEqual(firstFingerprint, changedFingerprint)
    }

    // MARK: New coverage

    func testNaturalWeekClampsToSemester() {
        let start = Date(timeIntervalSince1970: 0)
        let calendar = Calendar(identifier: .gregorian)
        XCTAssertEqual(SemesterCalendar.naturalWeek(semesterStart: start, date: start, totalWeeks: 18, calendar: calendar), 1)
        let week3 = calendar.date(byAdding: .day, value: 15, to: start)!
        XCTAssertEqual(SemesterCalendar.naturalWeek(semesterStart: start, date: week3, totalWeeks: 18, calendar: calendar), 3)
        let farFuture = calendar.date(byAdding: .day, value: 3650, to: start)!
        XCTAssertEqual(SemesterCalendar.naturalWeek(semesterStart: start, date: farFuture, totalWeeks: 18, calendar: calendar), 18)
    }

    func testWeekPatternOddEven() {
        XCTAssertEqual(WeekPattern.weeks(range: 1...10, pattern: .odd), [1, 3, 5, 7, 9])
        XCTAssertEqual(WeekPattern.weeks(range: 1...10, pattern: .even), [2, 4, 6, 8, 10])
        XCTAssertEqual(WeekPattern.weeks(range: 1...10, pattern: .every).count, 10)
    }

    func testPeriodTimeTextRoundTrip() {
        XCTAssertEqual(Period.text(from: 8 * 60 + 5), "08:05")
        XCTAssertEqual(Period.minutes(from: "13:30"), 810)
        XCTAssertNil(Period.minutes(from: "25:00"))
    }

    func testSyncPlannerDetectsCreateUpdateSkipDelete() {
        let rule = MeetingRule(courseID: courseID, weekday: 2, weekSet: [1, 2], startPeriod: 1, endPeriod: 2)
        let course = Course(id: courseID, courseTableID: UUID(), name: "数学")
        let occurrences = try! CalendarOccurrenceFactory.makeOccurrences(course: course, rule: rule, periods: periods)
        let firstOccurrence = occurrences[0]

        // No records -> both create.
        let emptyPlan = CalendarSyncPlanner.plan(occurrences: occurrences, existing: [])
        XCTAssertEqual(emptyPlan.toCreate.count, 2)
        XCTAssertEqual(emptyPlan.toUpdate.count, 0)

        // Matching record -> skip; stale record -> delete.
        let match = CalendarExportRecord(occurrenceKey: firstOccurrence.occurrenceKey, contentHash: firstOccurrence.fingerprint, fingerprint: firstOccurrence.fingerprint, eventIdentifier: "evt-1")
        let stale = CalendarExportRecord(occurrenceKey: "old|key", contentHash: "x", fingerprint: "x", eventIdentifier: "evt-old")
        let plan = CalendarSyncPlanner.plan(occurrences: occurrences, existing: [match, stale])
        XCTAssertEqual(plan.toSkip.count, 1)
        XCTAssertEqual(plan.toCreate.count, 1)
        XCTAssertEqual(plan.toDeleteRecords.count, 1)
        XCTAssertEqual(plan.toDeleteRecords.first?.eventIdentifier, "evt-old")
    }

    func testICSGeneratorProducesFoldedCalendar() throws {
        let table = CourseTable(name: "测试", semesterStartDate: Date(timeIntervalSince1970: 0), totalWeeks: 4, defaultReminderMinutes: 30)
        let course = Course(id: courseID, courseTableID: UUID(), name: "高等数学", teacher: "张老师", location: "A101")
        let rule = MeetingRule(courseID: courseID, weekday: 1, weekSet: [1, 2], startPeriod: 1, endPeriod: 1, reminderMinutes: 30)
        let ics = try ICSGenerator.generate(courses: [course], rulesByCourse: [courseID: [rule]], table: table, periods: periods)
        XCTAssertTrue(ics.contains("BEGIN:VCALENDAR"))
        XCTAssertTrue(ics.contains("BEGIN:VEVENT"))
        XCTAssertTrue(ics.contains("SUMMARY:高等数学"))
        XCTAssertTrue(ics.contains("TRIGGER:-PT30M"))
        XCTAssertTrue(ics.hasSuffix("\r\n"))
        // Two weeks -> two events.
        XCTAssertEqual(ics.components(separatedBy: "BEGIN:VEVENT").count - 1, 2)
    }

    func testICSGeneratorRejectsEmpty() {
        let table = CourseTable(name: "空", semesterStartDate: Date(timeIntervalSince1970: 0), totalWeeks: 4)
        XCTAssertThrowsError(try ICSGenerator.generate(courses: [], rulesByCourse: [:], table: table, periods: periods))
    }
}
