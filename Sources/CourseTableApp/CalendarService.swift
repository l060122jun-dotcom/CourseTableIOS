import EventKit
import CourseTableCore

enum CalendarServiceError: LocalizedError {
    case accessDenied
    case noWritableCalendar
    case invalidSemesterDate

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "没有日历写入权限。请在“设置 > 隐私与安全性 > 日历”中允许课程表写入。"
        case .noWritableCalendar:
            return "没有可写入的 Apple 日历，请先在系统日历中创建或启用一个日历账户。"
        case .invalidSemesterDate:
            return "无法根据学期开始日期计算课程日期，请检查课程表设置。"
        }
    }
}

@MainActor
final class CalendarService: ObservableObject {
    private let store = EKEventStore()
    @Published private(set) var authorization: EKAuthorizationStatus = .notDetermined

    init() {
        refreshAuthorization()
    }

    func refreshAuthorization() {
        authorization = EKEventStore.authorizationStatus(for: .event)
    }

    func requestWriteAccess() async throws {
        refreshAuthorization()
        switch authorization {
        case .writeOnly, .fullAccess, .authorized:
            return
        case .denied, .restricted:
            throw CalendarServiceError.accessDenied
        case .notDetermined:
            let granted = try await store.requestWriteOnlyAccessToEvents()
            refreshAuthorization()
            guard granted else { throw CalendarServiceError.accessDenied }
        @unknown default:
            throw CalendarServiceError.accessDenied
        }
    }

    /// Exports every selected semester week for one course rule. This is an
    /// explicit user action and never runs automatically after OCR.
    func exportCourse(
        course: Course,
        rule: MeetingRule,
        table: CourseTable,
        periods: [Period]
    ) async throws -> Int {
        try await requestWriteAccess()
        guard let destination = store.defaultCalendarForNewEvents else {
            throw CalendarServiceError.noWritableCalendar
        }

        let occurrences = try CalendarOccurrenceFactory.makeOccurrences(for: rule, periods: periods)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: table.timeZoneID) ?? .current
        let semesterStart = calendar.startOfDay(for: table.semesterStartDate)

        for occurrence in occurrences {
            let dayOffset = (occurrence.semesterWeek - 1) * 7 + (occurrence.weekday - 1)
            guard let courseDay = calendar.date(byAdding: .day, value: dayOffset, to: semesterStart),
                  let startDate = calendar.date(byAdding: .minute, value: occurrence.startMinuteOfDay, to: courseDay),
                  let endDate = calendar.date(byAdding: .minute, value: occurrence.endMinuteOfDay, to: courseDay)
            else {
                throw CalendarServiceError.invalidSemesterDate
            }

            let event = EKEvent(eventStore: store)
            event.title = course.name
            event.location = course.location
            let details = [course.teacher, course.notes]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            event.notes = (details + ["由课程表 App 导入"]).joined(separator: "\n")
            event.startDate = startDate
            event.endDate = endDate
            event.calendar = destination
            if let minutes = occurrence.reminderMinutes ?? table.defaultReminderMinutes {
                event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes * 60)))
            }
            try store.save(event, span: .thisEvent, commit: false)
        }
        try store.commit()
        return occurrences.count
    }
}
