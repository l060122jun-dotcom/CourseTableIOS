import EventKit
import CourseTableCore

@MainActor
final class CalendarService: ObservableObject {
    private let store = EKEventStore()
    @Published private(set) var authorization: EKAuthorizationStatus = .notDetermined

    func requestAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            let granted = (try? await store.requestWriteOnlyAccessToEvents()) ?? false
            authorization = EKEventStore.authorizationStatus(for: .event)
            return granted
        } else {
            let granted = (try? await store.requestAccess(to: .event)) ?? false
            authorization = EKEventStore.authorizationStatus(for: .event)
            return granted
        }
    }

    func export(course: Course, occurrence: CalendarOccurrence, on date: Date, calendar: Calendar = .current) throws {
        let event = EKEvent(eventStore: store)
        event.title = course.name
        event.location = course.location
        event.notes = [course.teacher, course.notes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        event.startDate = calendar.date(byAdding: .minute, value: occurrence.startMinuteOfDay, to: calendar.startOfDay(for: date))
        event.endDate = calendar.date(byAdding: .minute, value: occurrence.endMinuteOfDay, to: calendar.startOfDay(for: date))
        event.calendar = store.defaultCalendarForNewEvents
        if let minutes = occurrence.reminderMinutes { event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutes * 60))) }
        try store.save(event, span: .thisEvent)
    }
}
