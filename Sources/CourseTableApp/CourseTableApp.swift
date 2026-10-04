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
                .preferredColorScheme(model.appearance.colorScheme)
                .environment(\.glassOpacity, model.glassOpacity)
        }
    }
}

/// User-selectable appearance. `system` follows the device setting.
enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
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
    @Published var appearance: AppearanceMode
    @Published var glassOpacity: Double

    private static let appearanceKey = "liuyun.appearance"
    private static let glassOpacityKey = "liuyun.glassOpacity"

    private let demoMode: Bool
    private let saveQueue = DispatchQueue(label: "com.codex.coursetable.save", qos: .utility)
    private var pendingSave: DispatchWorkItem?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        demoMode = arguments.contains("--demo-data") || arguments.contains(where: { $0.hasPrefix("--screen=") })
        let storedAppearance = UserDefaults.standard.string(forKey: AppModel.appearanceKey)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
        appearance = storedAppearance
        let storedOpacity = UserDefaults.standard.object(forKey: AppModel.glassOpacityKey) as? Double
        glassOpacity = min(1.0, max(0.3, storedOpacity ?? 0.9))
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

    /// Creates a NEW course table from an AI/OCR review and makes it active.
    /// Imported content never overwrites an existing table.
    func addTable(
        named name: String,
        semesterStart: Date,
        totalWeeks: Int,
        periods: [Period],
        courses: [StoredCourse]
    ) {
        let table = CourseTable(
            name: name.isEmpty ? "新课程表" : name,
            semesterStartDate: semesterStart,
            totalWeeks: min(52, max(1, totalWeeks)),
            hasWeekendCourses: courses.contains { $0.rules.contains { $0.weekday > 5 } },
            defaultReminderMinutes: 30,
            isActive: true
        )
        let resolvedPeriods = periods.isEmpty ? ScheduleDocument.defaultPeriods : periods.sorted { $0.index < $1.index }
        let rebound = courses.map { stored -> StoredCourse in
            var course = stored.course
            course.courseTableID = table.id
            return StoredCourse(course: course, rules: stored.rules)
        }
        mutate { doc in
            for i in doc.tables.indices { doc.tables[i].table.isActive = false }
            doc.tables.append(StoredTable(table: table, periods: resolvedPeriods, courses: rebound))
            doc.activeTableID = table.id
        }
    }

    func deleteTable(_ id: UUID) {
        mutate { doc in
            doc.tables.removeAll { $0.id == id }
            if doc.tables.isEmpty {
                let fresh = CourseTable(
                    name: "我的课程表",
                    semesterStartDate: ScheduleDocument.mondayOfCurrentWeek(),
                    totalWeeks: 18,
                    isActive: true
                )
                doc.tables = [StoredTable(table: fresh, periods: ScheduleDocument.defaultPeriods)]
            }
            if !doc.tables.contains(where: { $0.id == doc.activeTableID }) {
                doc.activeTableID = doc.tables[0].id
            }
            for index in doc.tables.indices {
                doc.tables[index].table.isActive = (doc.tables[index].id == doc.activeTableID)
            }
        }
    }

    func renameTable(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate { doc in
            guard let index = doc.tables.firstIndex(where: { $0.id == id }) else { return }
            doc.tables[index].table.name = trimmed
        }
    }

    /// Appends imported tables as new course tables (never replaces existing
    /// ones) and makes the first imported table active.
    func importTables(_ incoming: [StoredTable], nameOverride: String?) {
        guard !incoming.isEmpty else { return }
        mutate { doc in
            for index in doc.tables.indices { doc.tables[index].table.isActive = false }
            var tables = incoming
            let base = nameOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            for index in tables.indices {
                tables[index].table.isActive = (index == 0)
                // A file that holds a single table takes the file name; a
                // multi-table file keeps its own meaningful names.
                if !base.isEmpty, tables.count == 1 {
                    tables[index].table.name = base
                }
            }
            doc.tables.append(contentsOf: tables)
            doc.activeTableID = tables[0].id
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

    func setAppearance(_ mode: AppearanceMode) {
        appearance = mode
        UserDefaults.standard.set(mode.rawValue, forKey: AppModel.appearanceKey)
    }

    func setGlassOpacity(_ value: Double) {
        let clamped = min(1.0, max(0.3, value))
        glassOpacity = clamped
        UserDefaults.standard.set(clamped, forKey: AppModel.glassOpacityKey)
    }

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
