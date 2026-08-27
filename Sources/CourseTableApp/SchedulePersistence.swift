import Foundation
import CourseTableCore

struct ScheduledCourse: Identifiable, Codable, Equatable {
    let id: UUID
    var course: Course
    var rule: MeetingRule

    init(id: UUID? = nil, course: Course, rule: MeetingRule) {
        self.id = id ?? course.id
        self.course = course
        self.rule = rule
    }
}

struct ScheduleDocument: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var table: CourseTable
    var periods: [Period]
    var courses: [ScheduledCourse]
    var calendarExports: [CalendarExportRecord]

    init(
        schemaVersion: Int = currentSchemaVersion,
        table: CourseTable,
        periods: [Period],
        courses: [ScheduledCourse] = [],
        calendarExports: [CalendarExportRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.table = table
        self.periods = periods
        self.courses = courses
        self.calendarExports = calendarExports
    }

    static func empty(now: Date = .now, calendar: Calendar = .current) -> ScheduleDocument {
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        return ScheduleDocument(
            table: CourseTable(
                name: "我的课程表",
                semesterStartDate: startOfWeek,
                totalWeeks: 18,
                defaultReminderMinutes: 30,
                isActive: true
            ),
            periods: defaultPeriods
        )
    }

    static var preview: ScheduleDocument {
        var document = empty(now: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 1)) ?? .now)
        document.table.name = "大三上"

        func item(_ name: String, weekday: Int, period: Int) -> ScheduledCourse {
            let course = Course(courseTableID: document.table.id, name: name)
            let rule = MeetingRule(
                courseID: course.id,
                weekday: weekday,
                weekSet: Set(1...document.table.totalWeeks),
                startPeriod: period,
                endPeriod: period,
                reminderMinutes: document.table.defaultReminderMinutes
            )
            return ScheduledCourse(course: course, rule: rule)
        }

        let experiment = Course(
            courseTableID: document.table.id,
            name: "实验（不规则）",
            location: "实验楼 B203",
            colorHex: "#E84A8A"
        )
        let experimentRule = MeetingRule(
            courseID: experiment.id,
            weekday: 4,
            weekSet: Set(1...document.table.totalWeeks),
            customStartMinute: 16 * 60 + 40,
            customEndMinute: 18 * 60 + 10,
            reminderMinutes: document.table.defaultReminderMinutes
        )
        document.courses = [
            item("高等数学", weekday: 1, period: 1),
            item("英语", weekday: 3, period: 2),
            item("数据结构", weekday: 2, period: 5),
            item("体育", weekday: 5, period: 7),
            ScheduledCourse(course: experiment, rule: experimentRule)
        ]
        return document
    }

    private static let defaultPeriods: [Period] = [
        Period(index: 1, startMinuteOfDay: 8 * 60, endMinuteOfDay: 9 * 60 + 45),
        Period(index: 2, startMinuteOfDay: 10 * 60, endMinuteOfDay: 10 * 60 + 45),
        Period(index: 3, startMinuteOfDay: 11 * 60, endMinuteOfDay: 11 * 60 + 45),
        Period(index: 4, startMinuteOfDay: 11 * 60 + 50, endMinuteOfDay: 12 * 60 + 35),
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

    private static var fileURL: URL {
        directoryURL.appendingPathComponent("courses.json")
    }

    static func load() -> Result<ScheduleDocument?, Error> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .success(nil)
        }

        do {
            let data = try Data(contentsOf: fileURL)
            if let document = try? JSONDecoder().decode(ScheduleDocument.self, from: data) {
                guard document.schemaVersion <= ScheduleDocument.currentSchemaVersion else {
                    throw ScheduleStoreError.unsupportedSchema(document.schemaVersion)
                }
                return .success(document)
            }

            // Version 0 stored only an array of course/rule pairs. Preserve it by
            // migrating every course into one explicit course table.
            let legacyCourses = try JSONDecoder().decode([ScheduledCourse].self, from: data)
            var migrated = ScheduleDocument.empty()
            migrated.courses = legacyCourses.map { item in
                var course = item.course
                course.courseTableID = migrated.table.id
                return ScheduledCourse(id: item.id, course: course, rule: item.rule)
            }
            return .success(migrated)
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
