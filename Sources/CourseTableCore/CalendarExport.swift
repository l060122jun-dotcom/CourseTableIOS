import Foundation

public struct CalendarOccurrence: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let courseID: UUID
    public let meetingRuleID: UUID
    public let semesterWeek: Int
    public let weekday: Int
    public let startMinuteOfDay: Int
    public let endMinuteOfDay: Int
    public let reminderMinutes: Int?
    public let fingerprint: String
}
public enum CalendarOccurrenceFactory {
    public static func makeOccurrences(
        for rule: MeetingRule,
        periods: [Period]
    ) throws -> [CalendarOccurrence] {
        let time = try MeetingRuleValidator.resolve(rule, periods: periods)
        return rule.weekSet.sorted().map { week in
            let fingerprint = [
                rule.courseID.uuidString,
                rule.id.uuidString,
                String(week),
                String(rule.weekday),
                rule.timingMode.rawValue,
                String(time.startMinuteOfDay),
                String(time.endMinuteOfDay)
            ].joined(separator: "|")

            return CalendarOccurrence(
                id: UUID(),
                courseID: rule.courseID,
                meetingRuleID: rule.id,
                semesterWeek: week,
                weekday: rule.weekday,
                startMinuteOfDay: time.startMinuteOfDay,
                endMinuteOfDay: time.endMinuteOfDay,
                reminderMinutes: rule.reminderMinutes,
                fingerprint: fingerprint
            )
        }
    }
}

public struct CalendarExportRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var fingerprint: String
    public var eventIdentifier: String?
    public var lastExportedAt: Date
}
