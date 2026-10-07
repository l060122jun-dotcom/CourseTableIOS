import Foundation
import WidgetKit
import CourseTableCore

enum WidgetPublisher {
    static func publish(_ document: ScheduleDocument) {
        guard let url = WidgetSchedule.url else { return }
        let stored = document.activeTable
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: stored.table.timeZoneID) ?? .current
        var lessons: [WidgetLesson] = []
        for item in stored.courses {
            for rule in item.rules {
                guard let time = try? MeetingRuleValidator.resolve(rule, periods: stored.periods) else { continue }
                for week in rule.weekSet.sorted() where week >= 1 && week <= stored.table.totalWeeks {
                    guard let day = SemesterCalendar.date(semesterStart: stored.table.semesterStartDate, week: week, weekday: rule.weekday, calendar: calendar),
                          let start = calendar.date(byAdding: .minute, value: time.startMinuteOfDay, to: day),
                          let end = calendar.date(byAdding: .minute, value: time.endMinuteOfDay, to: day) else { continue }
                    lessons.append(WidgetLesson(id: "\(rule.id)-\(week)", name: item.course.name, location: item.course.location, start: start, end: end))
                }
            }
        }
        let payload = WidgetSchedule(tableName: stored.table.name, lessons: lessons.sorted { $0.start < $1.start }, updatedAt: .now)
        do {
            try JSONEncoder().encode(payload).write(to: url, options: .atomic)
            WidgetCenter.shared.reloadTimelines(ofKind: "FlowClassToday")
        } catch {
            // App data remains authoritative; the next successful save retries.
        }
    }
}
