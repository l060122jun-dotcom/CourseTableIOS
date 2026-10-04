import EventKit
import Foundation
import CourseTableCore

enum CalendarServiceError: LocalizedError {
    case accessDenied
    case noWritableCalendar
    case invalidSemesterDate

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "没有日历权限。请在“设置 > 隐私与安全性 > 日历”中允许流云课表访问。"
        case .noWritableCalendar:
            return "没有可写入的系统日历，请先在系统日历中创建或启用一个账户。"
        case .invalidSemesterDate:
            return "无法根据第一周日期计算课程日期，请检查课程表设置。"
        }
    }
}

/// Idempotent EventKit bridge. Creates one event per class occurrence,
/// remembers the EventKit identifier so re-exports update instead of
/// duplicating, and can remove only events this app created.
@MainActor
final class CalendarService {
    static let shared = CalendarService()

    struct ExportSummary {
        var created: Int
        var updated: Int
        var skipped: Int
        var allRecords: [CalendarExportRecord]
        var records: [CalendarExportRecord]
    }

    private let store = EKEventStore()

    func requestAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess, .writeOnly, .authorized:
            return
        case .denied, .restricted:
            throw CalendarServiceError.accessDenied
        case .notDetermined:
            let granted = try await store.requestFullAccessToEvents()
            guard granted else { throw CalendarServiceError.accessDenied }
        @unknown default:
            throw CalendarServiceError.accessDenied
        }
    }

    /// Writes every occurrence of the given rules, updating matches in place.
    func export(
        course: Course,
        rules: [MeetingRule],
        table: CourseTable,
        periods: [Period],
        existingRecords: [CalendarExportRecord]
    ) async throws -> ExportSummary {
        try await requestAccess()
        guard let destination = store.defaultCalendarForNewEvents else {
            throw CalendarServiceError.noWritableCalendar
        }

        var occurrences: [CalendarOccurrence] = []
        for rule in rules {
            occurrences.append(contentsOf: try CalendarOccurrenceFactory.makeOccurrences(course: course, rule: rule, periods: periods))
        }

        // Scope the sync to THIS course only. `occurrenceKey` begins with the
        // course id, so records belonging to other courses must be carried
        // through untouched — otherwise each per-course pass would see them as
        // stale and delete the events a previous pass just created.
        let coursePrefix = course.id.uuidString + "|"
        let mine = existingRecords.filter { $0.occurrenceKey.hasPrefix(coursePrefix) }
        let others = existingRecords.filter { !$0.occurrenceKey.hasPrefix(coursePrefix) }

        let plan = CalendarSyncPlanner.plan(occurrences: occurrences, existing: mine)
        var byKey = Dictionary(mine.map { ($0.occurrenceKey, $0) }, uniquingKeysWith: { first, _ in first })
        var created = 0
        var updated = 0
        var newRecords: [CalendarExportRecord] = []

        for occurrence in plan.toCreate + plan.toUpdate {
            let isUpdate = byKey[occurrence.occurrenceKey] != nil
            let existingEventID = byKey[occurrence.occurrenceKey]?.eventIdentifier
            let event = try eventFor(occurrence, course: course, table: table, existingEventID: existingEventID, store: store, destination: destination)
            try store.save(event, span: .thisEvent, commit: false)
            if isUpdate { updated += 1 } else { created += 1 }
            let record = CalendarExportRecord(
                id: byKey[occurrence.occurrenceKey]?.id ?? UUID(),
                occurrenceKey: occurrence.occurrenceKey,
                contentHash: occurrence.fingerprint,
                fingerprint: occurrence.fingerprint,
                eventIdentifier: event.eventIdentifier,
                lastExportedAt: .now
            )
            byKey[occurrence.occurrenceKey] = record
            newRecords.append(record)
        }

        // Remove stale events that this app created for THIS course only.
        for record in plan.toDeleteRecords {
            if let identifier = record.eventIdentifier, let event = store.event(withIdentifier: identifier) {
                try? store.remove(event, span: .thisEvent, commit: false)
            }
            byKey.removeValue(forKey: record.occurrenceKey)
        }

        try store.commit()

        return ExportSummary(
            created: created,
            updated: updated,
            skipped: plan.toSkip.count,
            allRecords: others + Array(byKey.values),
            records: newRecords
        )
    }

    /// Whole-table export with a pre-computed summary.
    func exportAll(
        table: CourseTable,
        periods: [Period],
        courses: [StoredCourse],
        existingRecords: [CalendarExportRecord]
    ) async throws -> ExportSummary {
        var allCreated = 0
        var allUpdated = 0
        var allSkipped = 0
        var records = existingRecords
        for stored in courses {
            let summary = try await export(
                course: stored.course,
                rules: stored.rules,
                table: table,
                periods: periods,
                existingRecords: records
            )
            allCreated += summary.created
            allUpdated += summary.updated
            allSkipped += summary.skipped
            records = summary.allRecords
        }
        return ExportSummary(created: allCreated, updated: allUpdated, skipped: allSkipped, allRecords: records, records: records)
    }

    private func eventFor(
        _ occurrence: CalendarOccurrence,
        course: Course,
        table: CourseTable,
        existingEventID: String?,
        store: EKEventStore,
        destination: EKCalendar
    ) throws -> EKEvent {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: table.timeZoneID) ?? .current
        guard let day = SemesterCalendar.date(
            semesterStart: table.semesterStartDate,
            week: occurrence.semesterWeek,
            weekday: occurrence.weekday,
            calendar: calendar
        ),
        let start = calendar.date(byAdding: .minute, value: occurrence.startMinuteOfDay, to: day),
        let end = calendar.date(byAdding: .minute, value: occurrence.endMinuteOfDay, to: day) else {
            throw CalendarServiceError.invalidSemesterDate
        }

        let event: EKEvent
        if let existingEventID, let match = store.event(withIdentifier: existingEventID) {
            event = match
        } else {
            event = EKEvent(eventStore: store)
        }
        event.title = course.name
        event.location = course.location
        let details = [course.teacher, course.notes]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        event.notes = (details + ["由流云课表导入 · \(table.name)"]).joined(separator: "\n")
        event.startDate = start
        event.endDate = end
        event.calendar = destination
        event.alarms?.forEach { event.removeAlarm($0) }
        let minutes = occurrence.reminderMinutes ?? table.defaultReminderMinutes
        if let minutes, minutes >= 0 {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes * 60)))
        }
        return event
    }
}
