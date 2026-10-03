import Foundation
import CourseTableCore

/// One persisted course plus its meeting rules. A course may have multiple
/// rules so a single subject can meet on several days/periods/weeks.
struct StoredCourse: Identifiable, Codable, Equatable {
    let id: UUID
    var course: Course
    var rules: [MeetingRule]

    init(id: UUID? = nil, course: Course, rules: [MeetingRule]) {
        self.id = id ?? course.id
        self.course = course
        self.rules = rules
    }

    init(id: UUID? = nil, course: Course, rule: MeetingRule) {
        self.init(id: id, course: course, rules: [rule])
    }

    var firstRule: MeetingRule? { rules.first }
}

/// A whole course table (semester) with its own periods and courses.
struct StoredTable: Identifiable, Codable, Equatable {
    let id: UUID
    var table: CourseTable
    var periods: [Period]
    var courses: [StoredCourse]

    init(id: UUID? = nil, table: CourseTable, periods: [Period], courses: [StoredCourse] = []) {
        self.id = id ?? table.id
        self.table = table
        self.periods = periods
        self.courses = courses
    }
}

struct ScheduleDocument: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var tables: [StoredTable]
    var activeTableID: UUID
    var calendarExports: [CalendarExportRecord]

    init(
        schemaVersion: Int = currentSchemaVersion,
        tables: [StoredTable],
        activeTableID: UUID,
        calendarExports: [CalendarExportRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.tables = tables
        self.activeTableID = activeTableID
        self.calendarExports = calendarExports
    }

    var activeTable: StoredTable {
        tables.first { $0.id == activeTableID } ?? tables.first ?? ScheduleDocument.emptyActive
    }

    mutating func updateActive(_ mutate: (inout StoredTable) -> Void) {
        guard let index = tables.firstIndex(where: { $0.id == activeTableID }) else { return }
        mutate(&tables[index])
    }

    static var emptyActive: StoredTable {
        StoredTable(table: CourseTable(name: "我的课程表", semesterStartDate: mondayOfCurrentWeek(), totalWeeks: 18, defaultReminderMinutes: 30, isActive: true), periods: defaultPeriods)
    }

    static func empty(now: Date = .now, calendar: Calendar = .current) -> ScheduleDocument {
        let active = StoredTable(
            table: CourseTable(
                name: "我的课程表",
                semesterStartDate: calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now),
                totalWeeks: 18,
                defaultReminderMinutes: 30,
                isActive: true
            ),
            periods: defaultPeriods
        )
        return ScheduleDocument(tables: [active], activeTableID: active.id)
    }

    static func mondayOfCurrentWeek(now: Date = .now, calendar: Calendar = .current) -> Date {
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        // Align to Monday, since the timetable grid is Monday-first.
        let weekday = calendar.component(.weekday, from: start)
        let offset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: start) ?? start
    }

    static var preview: ScheduleDocument {
        var doc = empty(now: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1)) ?? .now)
        var active = doc.activeTable
        active.table.name = "大三上"
        active.table.hasWeekendCourses = true

        func item(_ name: String, weekday: Int, rule: MeetingRule) -> StoredCourse {
            let course = Course(courseTableID: active.table.id, name: name)
            return StoredCourse(course: course, rules: [rule])
        }

        let experiment = Course(courseTableID: active.table.id, name: "实验（不规则）", teacher: "王老师", location: "实验楼 B203", colorHex: "#E84A8A")
        active.courses = [
            item("高等数学", weekday: 1, rule: MeetingRule(courseID: UUID(), weekday: 1, weekSet: Set(1...18), startPeriod: 1, endPeriod: 2, reminderMinutes: 30)),
            StoredCourse(course: Course(courseTableID: active.table.id, name: "数据结构", teacher: "李老师", location: "计算机楼 A301", colorHex: "#3BA55D"),
                         rules: [MeetingRule(courseID: UUID(), weekday: 2, weekSet: Set(1...18), startPeriod: 5, endPeriod: 6, reminderMinutes: 30),
                                 MeetingRule(courseID: UUID(), weekday: 4, weekSet: Set(1...18), startPeriod: 5, endPeriod: 6, reminderMinutes: 30)]),
            item("英语", weekday: 3, rule: MeetingRule(courseID: UUID(), weekday: 3, weekSet: WeekPattern.weeks(range: 1...18, pattern: .odd), startPeriod: 3, endPeriod: 4, reminderMinutes: 10)),
            item("体育", weekday: 5, rule: MeetingRule(courseID: UUID(), weekday: 5, weekSet: Set(1...18), startPeriod: 7, endPeriod: 8, reminderMinutes: nil)),
            item("马克思主义原理", weekday: 6, rule: MeetingRule(courseID: UUID(), weekday: 6, weekSet: Set(1...18), startPeriod: 9, endPeriod: 10, reminderMinutes: 30)),
            StoredCourse(course: experiment,
                         rules: [MeetingRule(courseID: experiment.id, weekday: 4, weekSet: Set(1...18), customStartMinute: 16 * 60 + 40, customEndMinute: 18 * 60 + 10, reminderMinutes: 30)])
        ]
        // Fix up rule.courseID to match the actual course ids for consistency.
        active.courses = active.courses.map { stored in
            var stored = stored
            stored.rules = stored.rules.map { rule in
                var rule = rule
                rule.courseID = stored.course.id
                return rule
            }
            return stored
        }
        doc.tables = [active]
        doc.activeTableID = active.id
        return doc
    }

    static let defaultPeriods: [Period] = [
        Period(index: 1, startMinuteOfDay: 8 * 60, endMinuteOfDay: 8 * 60 + 45),
        Period(index: 2, startMinuteOfDay: 8 * 60 + 50, endMinuteOfDay: 9 * 60 + 35),
        Period(index: 3, startMinuteOfDay: 10 * 60, endMinuteOfDay: 10 * 60 + 45),
        Period(index: 4, startMinuteOfDay: 10 * 60 + 50, endMinuteOfDay: 11 * 60 + 35),
        Period(index: 5, startMinuteOfDay: 13 * 60 + 30, endMinuteOfDay: 14 * 60 + 15),
        Period(index: 6, startMinuteOfDay: 14 * 60 + 20, endMinuteOfDay: 15 * 60 + 5),
        Period(index: 7, startMinuteOfDay: 15 * 60 + 30, endMinuteOfDay: 16 * 60 + 15),
        Period(index: 8, startMinuteOfDay: 16 * 60 + 20, endMinuteOfDay: 17 * 60 + 5),
        Period(index: 9, startMinuteOfDay: 18 * 60 + 30, endMinuteOfDay: 19 * 60 + 15),
        Period(index: 10, startMinuteOfDay: 19 * 60 + 20, endMinuteOfDay: 20 * 60 + 5)
    ]
}

enum ScheduleStoreError: LocalizedError {
    case unsupportedSchema(Int)
    case noStoredFileToRecover

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "课程数据版本 \(version) 高于当前应用支持的版本，已停止写入以保护原文件。"
        case .noStoredFileToRecover:
            return "没有找到需要恢复的课程数据文件。"
        }
    }
}

enum ScheduleStore {
    private static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CourseTable", isDirectory: true)
    }

    static var fileURL: URL { directoryURL.appendingPathComponent("courses.json") }

    static func load() -> Result<ScheduleDocument?, Error> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .success(nil) }
        do {
            let data = try Data(contentsOf: fileURL)
            if let document = try? JSONDecoder().decode(ScheduleDocument.self, from: data) {
                guard document.schemaVersion <= ScheduleDocument.currentSchemaVersion else {
                    throw ScheduleStoreError.unsupportedSchema(document.schemaVersion)
                }
                return .success(document)
            }
            return .success(try migrateLegacy(data))
        } catch {
            return .failure(error)
        }
    }

    static func save(_ document: ScheduleDocument) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let data = try JSONEncoder().encode(document)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: - Legacy migration

    private struct LegacyV1: Codable {
        var schemaVersion: Int
        var table: CourseTable
        var periods: [Period]
        var courses: [LegacyCourse]
        var calendarExports: [CalendarExportRecord]?
    }
    private struct LegacyCourse: Codable {
        let id: UUID
        var course: Course
        var rule: MeetingRule
    }

    private static func migrateLegacy(_ data: Data) throws -> ScheduleDocument {
        if let v1 = try? JSONDecoder().decode(LegacyV1.self, from: data) {
            let stored = StoredTable(
                table: v1.table,
                periods: v1.periods,
                courses: v1.courses.map { StoredCourse(id: $0.id, course: $0.course, rules: [$0.rule]) }
            )
            return ScheduleDocument(tables: [stored], activeTableID: stored.id, calendarExports: v1.calendarExports ?? [])
        }
        // Version 0 stored only an array of course/rule pairs.
        let legacy = try JSONDecoder().decode([LegacyCourse].self, from: data)
        var active = ScheduleDocument.emptyActive
        active.courses = legacy.map { item in
            var course = item.course
            course.courseTableID = active.table.id
            return StoredCourse(id: item.id, course: course, rules: [item.rule])
        }
        return ScheduleDocument(tables: [active], activeTableID: active.id)
    }

    @discardableResult
    static func backUpUnreadableFile() throws -> URL {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ScheduleStoreError.noStoredFileToRecover
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = directoryURL.appendingPathComponent("courses-unreadable-\(formatter.string(from: .now)).json")
        try FileManager.default.copyItem(at: fileURL, to: backup)
        return backup
    }
}
