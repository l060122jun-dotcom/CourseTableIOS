import Foundation

// MARK: - Course table

public struct CourseTable: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var semesterStartDate: Date
    public var totalWeeks: Int
    /// User-chosen "current week". Falls back to the calendar-derived week when nil.
    public var pinnedWeek: Int?
    public var timeZoneID: String
    public var hasWeekendCourses: Bool
    /// When true, courses whose week set excludes the selected week are still shown (dimmed).
    public var showCoursesOutsideSelectedWeek: Bool
    public var defaultReminderMinutes: Int?
    public var reminderStyle: ReminderStyle
    public var colorHex: String
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        semesterStartDate: Date,
        totalWeeks: Int,
        pinnedWeek: Int? = nil,
        timeZoneID: String = TimeZone.current.identifier,
        hasWeekendCourses: Bool = false,
        showCoursesOutsideSelectedWeek: Bool = false,
        defaultReminderMinutes: Int? = 30,
        reminderStyle: ReminderStyle = .notification,
        colorHex: String = "#0F77FF",
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.semesterStartDate = semesterStartDate
        self.totalWeeks = totalWeeks
        self.pinnedWeek = pinnedWeek
        self.timeZoneID = timeZoneID
        self.hasWeekendCourses = hasWeekendCourses
        self.showCoursesOutsideSelectedWeek = showCoursesOutsideSelectedWeek
        self.defaultReminderMinutes = defaultReminderMinutes
        self.reminderStyle = reminderStyle
        self.colorHex = colorHex
        self.isActive = isActive
    }
}

public enum ReminderStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case notification
    case alarm
    public var id: String { rawValue }
    public var label: String { self == .alarm ? "闹钟" : "通知" }
}

public struct Period: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var index: Int
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int

    public init(id: UUID = UUID(), index: Int, startMinuteOfDay: Int, endMinuteOfDay: Int) {
        self.id = id
        self.index = index
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
    }

    public init(index: Int, start: String, end: String) {
        self.init(index: index, startMinuteOfDay: Period.minutes(from: start) ?? 8 * 60, endMinuteOfDay: Period.minutes(from: end) ?? 9 * 60)
    }

    public static func minutes(from value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    public var startText: String { Period.text(from: startMinuteOfDay) }
    public var endText: String { Period.text(from: endMinuteOfDay) }

    public static func text(from minutes: Int) -> String {
        let value = max(0, min(1440, minutes))
        return String(format: "%02d:%02d", value / 60, value % 60)
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
    public var label: String { self == .period ? "按节次" : "自定义时间" }
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
    public init(startMinuteOfDay: Int, endMinuteOfDay: Int) {
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
    }
}

// MARK: - Semester / week helpers

public enum SemesterCalendar {
    /// Number of whole days between the semester start and the given date (start counts as day 0).
    public static func dayOffset(from semesterStart: Date, to date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: semesterStart)
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: target).day ?? 0
    }

    /// Natural week (1-based) for the given date, clamped to 1...totalWeeks.
    public static func naturalWeek(semesterStart: Date, date: Date = .now, totalWeeks: Int, calendar: Calendar = .current) -> Int {
        let offset = dayOffset(from: semesterStart, to: date, calendar: calendar)
        let raw = Int(floor(Double(offset) / 7.0)) + 1
        return min(max(raw, 1), max(1, totalWeeks))
    }

    /// Date of a specific (week, weekday). weekday is 1...7 starting Monday.
    public static func date(semesterStart: Date, week: Int, weekday: Int, calendar: Calendar = .current) -> Date? {
        let offset = (week - 1) * 7 + (weekday - 1)
        return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: semesterStart))
    }
}

// MARK: - Week-set utilities

public enum WeekPattern: String, CaseIterable, Identifiable, Sendable {
    case every
    case odd
    case even
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .every: return "每周"
        case .odd: return "单周"
        case .even: return "双周"
        }
    }

    public static func detect(from weeks: Set<Int>) -> WeekPattern {
        guard !weeks.isEmpty else { return .every }
        let sorted = weeks.sorted()
        if sorted.contains(where: { $0 % 2 == 0 }) && sorted.contains(where: { $0 % 2 != 0 }) { return .every }
        return sorted.first! % 2 == 0 ? .even : .odd
    }

    public static func weeks(range: ClosedRange<Int>, pattern: WeekPattern) -> Set<Int> {
        Set(range.filter { week in
            switch pattern {
            case .every: return true
            case .odd: return week % 2 == 1
            case .even: return week % 2 == 0
            }
        })
    }
}
