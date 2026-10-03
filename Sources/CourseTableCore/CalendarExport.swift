import Foundation

/// One concrete class meeting: a specific course on a specific week/day.
public struct CalendarOccurrence: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let courseID: UUID
    public let meetingRuleID: UUID
    public let semesterWeek: Int
    public let weekday: Int
    public let startMinuteOfDay: Int
    public let endMinuteOfDay: Int
    public let reminderMinutes: Int?
    /// Stable across time/room edits — identity of "this class, this week".
    public let occurrenceKey: String
    /// Changes when the exported payload changes — drives update vs. skip.
    public let fingerprint: String
}

public enum CalendarOccurrenceFactory {
    public static func makeOccurrences(
        course: Course,
        rule: MeetingRule,
        periods: [Period]
    ) throws -> [CalendarOccurrence] {
        let time = try MeetingRuleValidator.resolve(rule, periods: periods)
        return rule.weekSet.sorted().map { week in
            let occurrenceKey = [
                course.id.uuidString,
                rule.id.uuidString,
                String(week),
                String(rule.weekday)
            ].joined(separator: "|")
            let fingerprint = [
                course.id.uuidString,
                rule.id.uuidString,
                String(week),
                String(rule.weekday),
                rule.timingMode.rawValue,
                String(time.startMinuteOfDay),
                String(time.endMinuteOfDay),
                course.name,
                course.location ?? "",
                course.teacher ?? "",
                String(rule.reminderMinutes ?? -1)
            ].joined(separator: "|")
            return CalendarOccurrence(
                id: UUID(),
                courseID: course.id,
                meetingRuleID: rule.id,
                semesterWeek: week,
                weekday: rule.weekday,
                startMinuteOfDay: time.startMinuteOfDay,
                endMinuteOfDay: time.endMinuteOfDay,
                reminderMinutes: rule.reminderMinutes,
                occurrenceKey: occurrenceKey,
                fingerprint: fingerprint
            )
        }
    }

    public static func makeOccurrences(
        for rule: MeetingRule,
        periods: [Period]
    ) throws -> [CalendarOccurrence] {
        // Backwards-compatible shim used by tests without a full Course value.
        let placeholder = Course(id: rule.courseID, courseTableID: UUID(), name: "")
        return try makeOccurrences(course: placeholder, rule: rule, periods: periods)
    }
}

public struct CalendarExportRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    /// Stable identity for one course rule occurrence; survives time/room edits.
    public var occurrenceKey: String
    /// Changes when the EventKit payload changes; decides whether to update.
    public var contentHash: String
    public var fingerprint: String
    public var eventIdentifier: String?
    public var lastExportedAt: Date

    public init(
        id: UUID = UUID(),
        occurrenceKey: String = "",
        contentHash: String = "",
        fingerprint: String,
        eventIdentifier: String? = nil,
        lastExportedAt: Date = .now
    ) {
        self.id = id
        self.occurrenceKey = occurrenceKey
        self.contentHash = contentHash
        self.fingerprint = fingerprint
        self.eventIdentifier = eventIdentifier
        self.lastExportedAt = lastExportedAt
    }
}

/// Result of a calendar synchronization pass, used to show a summary before
/// the user confirms.
public struct CalendarSyncPlan: Equatable, Sendable {
    public var toCreate: [CalendarOccurrence]
    public var toUpdate: [CalendarOccurrence]
    public var toSkip: [CalendarOccurrence]
    public var toDeleteRecords: [CalendarExportRecord]

    public init(toCreate: [CalendarOccurrence] = [], toUpdate: [CalendarOccurrence] = [], toSkip: [CalendarOccurrence] = [], toDeleteRecords: [CalendarExportRecord] = []) {
        self.toCreate = toCreate
        self.toUpdate = toUpdate
        self.toSkip = toSkip
        self.toDeleteRecords = toDeleteRecords
    }

    public var summary: String {
        "新增 \(toCreate.count) · 更新 \(toUpdate.count) · 跳过 \(toSkip.count) · 删除 \(toDeleteRecords.count)"
    }
}

public enum CalendarSyncPlanner {
    /// Computes an idempotent plan: creates new occurrences, updates changed
    /// ones, skips unchanged ones, and removes records whose occurrence no
    /// longer exists.
    public static func plan(
        occurrences: [CalendarOccurrence],
        existing: [CalendarExportRecord]
    ) -> CalendarSyncPlan {
        let existingByKey = Dictionary(existing.map { ($0.occurrenceKey, $0) }, uniquingKeysWith: { first, _ in first })
        let occurrenceKeys = Set(occurrences.map(\.occurrenceKey))

        var plan = CalendarSyncPlan()
        for occurrence in occurrences {
            if let record = existingByKey[occurrence.occurrenceKey] {
                if record.contentHash == occurrence.fingerprint || record.fingerprint == occurrence.fingerprint {
                    plan.toSkip.append(occurrence)
                } else {
                    plan.toUpdate.append(occurrence)
                }
            } else {
                plan.toCreate.append(occurrence)
            }
        }
        plan.toDeleteRecords = existing.filter { !occurrenceKeys.contains($0.occurrenceKey) }
        return plan
    }
}
