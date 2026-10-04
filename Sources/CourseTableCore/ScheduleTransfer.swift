import Foundation

/// Portable, version-tolerant JSON payload used for backup and cross-device
/// migration. See `Docs/课表文件格式规范.md` for the canonical `.lcs` spec.
public struct ScheduleTransfer: Codable, Equatable, Sendable {
    /// File type marker so other apps (and the Android build) can recognise it.
    public static let formatIdentifier = "flowclass.schedule"

    public struct TablePayload: Codable, Equatable, Sendable {
        public var name: String
        public var semesterStart: String
        public var totalWeeks: Int
        public var hasWeekendCourses: Bool
        public var reminderMinutes: Int?
        public var reminderStyle: String
        public var colorHex: String
        public var isActive: Bool
        public var periods: [PeriodPayload]
        public var courses: [CoursePayload]

        public init(
            name: String,
            semesterStart: String,
            totalWeeks: Int,
            hasWeekendCourses: Bool,
            reminderMinutes: Int?,
            reminderStyle: String,
            colorHex: String,
            isActive: Bool = false,
            periods: [PeriodPayload],
            courses: [CoursePayload]
        ) {
            self.name = name
            self.semesterStart = semesterStart
            self.totalWeeks = totalWeeks
            self.hasWeekendCourses = hasWeekendCourses
            self.reminderMinutes = reminderMinutes
            self.reminderStyle = reminderStyle
            self.colorHex = colorHex
            self.isActive = isActive
            self.periods = periods
            self.courses = courses
        }
    }

    public struct PeriodPayload: Codable, Equatable, Sendable {
        public var index: Int
        public var start: String
        public var end: String

        public init(index: Int, start: String, end: String) {
            self.index = index
            self.start = start
            self.end = end
        }
    }

    public struct CoursePayload: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var teacher: String?
        public var location: String?
        public var notes: String?
        public var color: String?
        public var weekday: Int
        public var weeks: [Int]
        public var timingMode: String
        public var startPeriod: Int?
        public var endPeriod: Int?
        public var customStart: String?
        public var customEnd: String?
        public var reminderMinutes: Int?

        public init(
            id: String,
            name: String,
            teacher: String?,
            location: String?,
            notes: String?,
            color: String?,
            weekday: Int,
            weeks: [Int],
            timingMode: String,
            startPeriod: Int?,
            endPeriod: Int?,
            customStart: String?,
            customEnd: String?,
            reminderMinutes: Int?
        ) {
            self.id = id
            self.name = name
            self.teacher = teacher
            self.location = location
            self.notes = notes
            self.color = color
            self.weekday = weekday
            self.weeks = weeks
            self.timingMode = timingMode
            self.startPeriod = startPeriod
            self.endPeriod = endPeriod
            self.customStart = customStart
            self.customEnd = customEnd
            self.reminderMinutes = reminderMinutes
        }
    }

    public var schemaVersion: Int
    public var exportedAt: String
    public var tables: [TablePayload]
    /// File type marker; defaults to the canonical identifier. Decoded
    /// leniently so older backups without it still load.
    public var format: String?
    public var app: String?

    public init(schemaVersion: Int = 1, exportedAt: String, tables: [TablePayload], format: String? = ScheduleTransfer.formatIdentifier, app: String? = "流云课表") {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.tables = tables
        self.format = format
        self.app = app
    }

    /// True when this payload is (or claims to be) a FlowClass schedule file.
    public var isFlowClassFormat: Bool { format == nil || format == ScheduleTransfer.formatIdentifier }

    // MARK: - Encoding helpers

    public static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
