import Foundation
import SwiftUI
import CourseTableCore
import UIKit

@main
struct CourseTableApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(GlassPalette.accent)
        }
    }
}

// MARK: - App model

/// Single source of truth for the whole app. Owns the persisted document,
/// the active table, and every mutation. Views stay thin.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var document: ScheduleDocument
    @Published var storageLocked: Bool
    @Published var storageMessage: String?

    private let demoMode: Bool
    private let saveQueue = DispatchQueue(label: "com.codex.coursetable.save", qos: .utility)
    private var pendingSave: DispatchWorkItem?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        demoMode = arguments.contains("--demo-data") || arguments.contains(where: { $0.hasPrefix("--screen=") })
        if demoMode {
            document = .preview
            storageLocked = false
            return
        }
        switch ScheduleStore.load() {
        case .success(let stored):
            document = stored ?? .empty()
            storageLocked = false
        case .failure(let error):
            document = .empty()
            storageLocked = true
            storageMessage = error.localizedDescription
        }
    }

    // MARK: Derived

    var active: StoredTable { document.activeTable }
    var table: CourseTable { document.activeTable.table }
    var periods: [Period] { document.activeTable.periods }
    var courses: [StoredCourse] { document.activeTable.courses }

    var currentWeek: Int {
        if let pinned = table.pinnedWeek { return min(max(pinned, 1), table.totalWeeks) }
        return SemesterCalendar.naturalWeek(semesterStart: table.semesterStartDate, totalWeeks: table.totalWeeks)
    }

    var weekdayCount: Int { table.hasWeekendCourses ? 7 : 5 }

    // MARK: Persistence

    private func persist() {
        guard !demoMode, !storageLocked else { return }
        // Debounce so rapid changes (e.g. scrubbing weeks) don't hammer the disk,
        // and encode/write off the main thread so UI frames never block.
        let snapshot = document
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            do {
                let data = try JSONEncoder().encode(snapshot)
                try ScheduleStore.write(data)
            } catch {
                DispatchQueue.main.async { self?.storageMessage = "保存课程失败：\(error.localizedDescription)" }
            }
        }
        pendingSave = work
        saveQueue.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func mutate(_ change: (inout ScheduleDocument) -> Void) {
        change(&document)
        persist()
    }

    // MARK: Table management

    func setActiveTable(_ id: UUID) {
        mutate { doc in
            guard let index = doc.tables.firstIndex(where: { $0.id == id }) else { return }
            for i in doc.tables.indices { doc.tables[i].table.isActive = (i == index) }
            doc.activeTableID = id
        }
    }

    func addTable(named name: String, semesterStart: Date, totalWeeks: Int) {
        let table = CourseTable(
            name: name.isEmpty ? "新课程表" : name,
            semesterStartDate: semesterStart,
            totalWeeks: totalWeeks,
            defaultReminderMinutes: 30,
            isActive: true
        )
        mutate { doc in
            for i in doc.tables.indices { doc.tables[i].table.isActive = false }
            doc.tables.append(StoredTable(table: table, periods: ScheduleDocument.defaultPeriods))
            doc.activeTableID = table.id
        }
    }

    func deleteTable(_ id: UUID) {
        mutate { doc in
            guard doc.tables.count > 1 else { return }
            doc.tables.removeAll { $0.id == id }
            if doc.activeTableID == id, let first = doc.tables.first {
                doc.activeTableID = first.id
                doc.tables[0].table.isActive = true
            }
        }
    }

    // MARK: Table settings

    func updateTable(_ transform: (inout CourseTable) -> Void) {
        mutate { doc in
            guard let index = doc.tables.firstIndex(where: { $0.id == doc.activeTableID }) else { return }
            transform(&doc.tables[index].table)
        }
    }

    func setPeriods(_ periods: [Period]) {
        mutate { doc in
            guard let index = doc.tables.firstIndex(where: { $0.id == doc.activeTableID }) else { return }
            doc.tables[index].periods = periods.sorted { $0.index < $1.index }
        }
    }

    func setCurrentWeek(_ week: Int) {
        updateTable { $0.pinnedWeek = min(max(week, 1), $0.totalWeeks) }
    }

    func resetWeekToToday() {
        updateTable { $0.pinnedWeek = nil }
    }

    // MARK: Course CRUD

    func upsertCourse(_ course: Course, rules: [MeetingRule]) {
        mutate { doc in
            guard let index = doc.tables.firstIndex(where: { $0.id == doc.activeTableID }) else { return }
            var updatedRules = rules.map { rule -> MeetingRule in
                var rule = rule
                rule.courseID = course.id
                return rule
            }
            if let existing = doc.tables[index].courses.firstIndex(where: { $0.course.id == course.id }) {
                doc.tables[index].courses[existing] = StoredCourse(id: course.id, course: course, rules: updatedRules)
            } else {
                doc.tables[index].courses.append(StoredCourse(course: course, rules: updatedRules))
            }
        }
    }

    func deleteCourse(_ id: UUID) {
        mutate { doc in
            guard let index = doc.tables.firstIndex(where: { $0.id == doc.activeTableID }) else { return }
            doc.tables[index].courses.removeAll { $0.course.id == id }
        }
    }

    func importCourses(_ incoming: [StoredCourse]) {
        mutate { doc in
            guard let index = doc.tables.firstIndex(where: { $0.id == doc.activeTableID }) else { return }
            let existingIDs = Set(doc.tables[index].courses.map { $0.course.id })
            let filtered = incoming.filter { !existingIDs.contains($0.course.id) }
            doc.tables[index].courses.append(contentsOf: filtered)
        }
    }

    // MARK: Calendar export records

    func replaceCalendarExports(_ records: [CalendarExportRecord]) {
        mutate { $0.calendarExports = records }
    }

    func appendCalendarExports(_ records: [CalendarExportRecord]) {
        mutate { doc in
            for record in records {
                doc.calendarExports.removeAll { $0.occurrenceKey == record.occurrenceKey }
                doc.calendarExports.append(record)
            }
        }
    }

    // MARK: Storage recovery

    func recoverStorage() {
        do {
            _ = try ScheduleStore.backUpUnreadableFile()
            storageLocked = false
            document = .empty()
            try ScheduleStore.save(document)
            storageMessage = nil
        } catch {
            storageMessage = "无法备份原数据：\(error.localizedDescription)"
        }
    }

    // MARK: Full document replace (import)

    func replaceDocument(_ newDocument: ScheduleDocument) {
        document = newDocument
        persist()
    }
}
