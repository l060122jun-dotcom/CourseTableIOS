import Foundation

public struct CourseTable: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var semesterStartDate: Date
    public var totalWeeks: Int
    public var timeZoneID: String
    public var hasWeekendCourses: Bool
    public var showCoursesOutsideSelectedWeek: Bool
    public var defaultReminderMinutes: Int?
    public var colorHex: String
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        semesterStartDate: Date,
        totalWeeks: Int,
        timeZoneID: String = TimeZone.current.identifier,
        hasWeekendCourses: Bool = false,
        showCoursesOutsideSelectedWeek: Bool = false,
        defaultReminderMinutes: Int? = nil,
        colorHex: String = "#0F77FF",
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.semesterStartDate = semesterStartDate
        self.totalWeeks = totalWeeks
        self.timeZoneID = timeZoneID
        self.hasWeekendCourses = hasWeekendCourses
        self.showCoursesOutsideSelectedWeek = showCoursesOutsideSelectedWeek
        self.defaultReminderMinutes = defaultReminderMinutes
        self.colorHex = colorHex
        self.isActive = isActive
    }
}
public struct Period: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var index: Int
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int

    public init(
        id: UUID = UUID(),
        index: Int,
        startMinuteOfDay: Int,
        endMinuteOfDay: Int
    ) {
        self.id = id
        self.index = index
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
    }
}

public struct Course: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var courseTableID: UUID
    public var name: String
    public var teacher: String?
    public var location: String?
    public var notes: String?
    public var colorHex: String

    public init(
        id: UUID = UUID(),
        courseTableID: UUID,
        name: String,
        teacher: String? = nil,
        location: String? = nil,
        notes: String? = nil,
        colorHex: String = "#0F77FF"
    ) {
        self.id = id
        self.courseTableID = courseTableID
        self.name = name
        self.teacher = teacher
        self.location = location
        self.notes = notes
        self.colorHex = colorHex
    }
}

public enum TimingMode: String, Codable, CaseIterable, Sendable {
    case period
    case custom
}

public struct MeetingRule: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var courseID: UUID
    public var weekday: Int
    public var weekSet: Set<Int>
    public var timingMode: TimingMode
    public var startPeriod: Int?
    public var endPeriod: Int?
    public var customStartMinute: Int?
    public var customEndMinute: Int?
    public var reminderMinutes: Int?

    public init(
        id: UUID = UUID(),
        courseID: UUID,
        weekday: Int,
        weekSet: Set<Int>,
        startPeriod: Int,
        endPeriod: Int,
        reminderMinutes: Int? = nil
    ) {
        self.id = id
        self.courseID = courseID
        self.weekday = weekday
        self.weekSet = weekSet
        self.timingMode = .period
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
        self.customStartMinute = nil
        self.customEndMinute = nil
        self.reminderMinutes = reminderMinutes
    }

    public init(
        id: UUID = UUID(),
        courseID: UUID,
        weekday: Int,
        weekSet: Set<Int>,
        customStartMinute: Int,
        customEndMinute: Int,
        reminderMinutes: Int? = nil
    ) {
        self.id = id
        self.courseID = courseID
        self.weekday = weekday
        self.weekSet = weekSet
        self.timingMode = .custom
        self.startPeriod = nil
        self.endPeriod = nil
        self.customStartMinute = customStartMinute
        self.customEndMinute = customEndMinute
        self.reminderMinutes = reminderMinutes
    }

    public mutating func usePeriods(start: Int, end: Int) {
        timingMode = .period
        startPeriod = start
        endPeriod = end
        customStartMinute = nil
        customEndMinute = nil
    }

    public mutating func useCustomTime(startMinute: Int, endMinute: Int) {
        timingMode = .custom
        startPeriod = nil
        endPeriod = nil
        customStartMinute = startMinute
        customEndMinute = endMinute
    }
}

public struct ResolvedMeetingTime: Equatable, Sendable {
    public let startMinuteOfDay: Int
    public let endMinuteOfDay: Int
}
