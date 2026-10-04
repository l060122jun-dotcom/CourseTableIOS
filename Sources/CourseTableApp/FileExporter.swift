import Foundation
import CourseTableCore

/// Small helpers for reading and writing temporary files for the share sheet
/// and the document picker. Keeps the views free of file-system plumbing.
enum FileExporter {
    /// Canonical extension for the FlowClass schedule exchange file.
    static let scheduleExtension = "lcs"

    static func writeTemporary(name: String, ext: String, content: String) throws -> URL {
        try writeTemporary(name: name, ext: ext, data: Data(content.utf8))
    }

    static func writeTemporary(name: String, ext: String, data: Data) throws -> URL {
        let safe = sanitize(name).isEmpty ? "课表数据" : sanitize(name)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(safe).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func sanitize(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|\n\r")
        return value.components(separatedBy: invalid).joined(separator: "-").prefix(60).description
    }

    static func readText(at url: URL) throws -> String {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return String(decoding: data, as: UTF8.self)
    }

    static func readData(at url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }
}

// MARK: - Transfer bridge

/// Converts between the persisted document and the portable `.lcs` payload
/// defined in `Docs/课表文件格式规范.md`.
enum TransferBridge {
    static func encode(_ document: ScheduleDocument) throws -> Data {
        let payload = ScheduleTransfer(
            exportedAt: ISO8601DateFormatter().string(from: .now),
            tables: document.tables.map { stored in
                ScheduleTransfer.TablePayload(
                    name: stored.table.name,
                    semesterStart: ScheduleTransfer.isoDate(stored.table.semesterStartDate),
                    totalWeeks: stored.table.totalWeeks,
                    hasWeekendCourses: stored.table.hasWeekendCourses,
                    reminderMinutes: stored.table.defaultReminderMinutes,
                    reminderStyle: stored.table.reminderStyle.rawValue,
                    colorHex: stored.table.colorHex,
                    isActive: stored.id == document.activeTableID,
                    periods: stored.periods.map { ScheduleTransfer.PeriodPayload(index: $0.index, start: $0.startText, end: $0.endText) },
                    courses: stored.courses.flatMap { item -> [ScheduleTransfer.CoursePayload] in
                        item.rules.map { rule in
                            ScheduleTransfer.CoursePayload(
                                id: item.course.id.uuidString,
                                name: item.course.name,
                                teacher: item.course.teacher,
                                location: item.course.location,
                                notes: item.course.notes,
                                color: item.course.colorHex,
                                weekday: rule.weekday,
                                weeks: rule.weekSet.sorted(),
                                timingMode: rule.timingMode.rawValue,
                                startPeriod: rule.startPeriod,
                                endPeriod: rule.endPeriod,
                                customStart: rule.customStartMinute.map { Period.text(from: $0) },
                                customEnd: rule.customEndMinute.map { Period.text(from: $0) },
                                reminderMinutes: rule.reminderMinutes
                            )
                        }
                    }
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    static func decode(_ data: Data) throws -> ScheduleDocument {
        let payload = try JSONDecoder().decode(ScheduleTransfer.self, from: data)
        guard payload.schemaVersion <= ScheduleDocument.currentSchemaVersion else {
            throw TransferError.unsupportedVersion(payload.schemaVersion)
        }
        return try makeDocument(from: payload)
    }

    /// Builds a `ScheduleDocument` from a decoded payload, applying every
    /// clamp / default described in the spec.
    static func makeDocument(from payload: ScheduleTransfer) throws -> ScheduleDocument {
        var tables: [StoredTable] = []
        for (tableIndex, tablePayload) in payload.tables.enumerated() {
            let start = ScheduleTransfer.parseDate(tablePayload.semesterStart) ?? ScheduleDocument.mondayOfCurrentWeek()
            let totalWeeks = max(1, min(52, tablePayload.totalWeeks))
            let table = CourseTable(
                name: tablePayload.name.isEmpty ? "我的课程表" : tablePayload.name,
                semesterStartDate: start,
                totalWeeks: totalWeeks,
                hasWeekendCourses: tablePayload.hasWeekendCourses,
                defaultReminderMinutes: tablePayload.reminderMinutes ?? 30,
                reminderStyle: ReminderStyle(rawValue: tablePayload.reminderStyle) ?? .notification,
                colorHex: tablePayload.colorHex.isEmpty ? "#0F77FF" : tablePayload.colorHex,
                isActive: tablePayload.isActive || tableIndex == 0
            )
            let periods = tablePayload.periods.map { Period(index: $0.index, start: $0.start, end: $0.end) }
            let resolvedPeriods = periods.isEmpty ? ScheduleDocument.defaultPeriods : periods.sorted { $0.index < $1.index }

            // Group payload rows by course id so multi-rule courses recombine.
            var order: [String] = []
            var grouped: [String: [ScheduleTransfer.CoursePayload]] = [:]
            for row in tablePayload.courses {
                let key = row.id.isEmpty ? UUID().uuidString : row.id
                if grouped[key] == nil { order.append(key) }
                grouped[key, default: []].append(row)
            }

            let courses: [StoredCourse] = order.compactMap { key in
                guard let rows = grouped[key], let first = rows.first else { return nil }
                let courseID = UUID(uuidString: key) ?? UUID()
                let course = Course(
                    id: courseID,
                    courseTableID: table.id,
                    name: first.name,
                    teacher: first.teacher,
                    location: first.location,
                    notes: first.notes,
                    colorHex: first.color ?? "#0F77FF"
                )
                let rules = rows.map { row -> MeetingRule in
                    Self.makeRule(row, courseID: courseID, totalWeeks: totalWeeks)
                }
                return StoredCourse(course: course, rules: rules)
            }

            tables.append(StoredTable(table: table, periods: resolvedPeriods, courses: courses))
        }
        guard let first = tables.first else { throw TransferError.empty }
        if let activeIndex = tables.firstIndex(where: { $0.table.isActive }) {
            for i in tables.indices { tables[i].table.isActive = (i == activeIndex) }
            return ScheduleDocument(tables: tables, activeTableID: tables[activeIndex].id)
        }
        for i in tables.indices { tables[i].table.isActive = (i == 0) }
        return ScheduleDocument(tables: tables, activeTableID: first.id)
    }

    /// Normalises one payload row into a validated `MeetingRule`, correcting
    /// bad weekdays, empty/out-of-range week sets, and mismatched timing fields.
    static func makeRule(_ row: ScheduleTransfer.CoursePayload, courseID: UUID, totalWeeks: Int) -> MeetingRule {
        let weekday = min(max(row.weekday, 1), 7)
        let weeks = Set(row.weeks.filter { $0 >= 1 && $0 <= totalWeeks })
        let finalWeeks = weeks.isEmpty ? Set(1...max(1, totalWeeks)) : weeks

        let isCustom = row.timingMode == TimingMode.custom.rawValue
            || (row.customStart != nil && row.startPeriod == nil)
        if isCustom {
            return MeetingRule(
                courseID: courseID,
                weekday: weekday,
                weekSet: finalWeeks,
                customStartMinute: row.customStart.flatMap(Period.minutes(from:)) ?? 16 * 60 + 40,
                customEndMinute: row.customEnd.flatMap(Period.minutes(from:)) ?? 18 * 60 + 10,
                reminderMinutes: row.reminderMinutes
            )
        }
        let start = max(1, row.startPeriod ?? 1)
        return MeetingRule(
            courseID: courseID,
            weekday: weekday,
            weekSet: finalWeeks,
            startPeriod: start,
            endPeriod: max(start, row.endPeriod ?? start),
            reminderMinutes: row.reminderMinutes
        )
    }

    enum TransferError: LocalizedError {
        case empty
        case unsupportedVersion(Int)
        var errorDescription: String? {
            switch self {
            case .empty: return "文件中没有课程表数据。"
            case .unsupportedVersion(let v): return "该课表文件版本（\(v)）高于当前应用支持的版本。"
            }
        }
    }
}
