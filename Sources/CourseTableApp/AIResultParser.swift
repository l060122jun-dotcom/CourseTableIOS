import Foundation
import CourseTableCore

/// Fault-tolerant decoder for whatever an OpenAI-compatible model returns.
///
/// Real models drift from the requested schema: they rename fields
/// (`day`/`weekday`/`周`), collapse sections into `sections: [1,2,3]`, omit
/// container keys, wrap values as strings, or return `{"error": ...}`.
/// This normaliser walks the raw JSON generically and maps every observed
/// variant onto the canonical `OCRDraft` used by the review screen.
enum AIResultParser {

    enum ParseError: LocalizedError {
        case noCourses
        case modelRefused(String)

        var errorDescription: String? {
            switch self {
            case .noCourses: return "AI 未从文件中识别到任何课程，请确认文件内容是否为课表。"
            case .modelRefused(let message): return message
            }
        }
    }

    /// Entry point: raw assistant text → draft. Throws a friendly error.
    static func parse(_ text: String) throws -> OCRDraft {
        let json = extractJSON(from: text)
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            throw ParseError.modelRefused("AI 返回的内容不是有效 JSON。")
        }
        return try parse(root: root)
    }

    static func parse(root: Any) throws -> OCRDraft {
        // Refusal shape: {"error": "..."} or {"message": "..."} with no courses.
        if let dict = root as? [String: Any],
           let error = (dict["error"] as? String) ?? (dict["message"] as? String),
           !containsCourses(dict) {
            throw ParseError.modelRefused("AI 无法识别：\(error)")
        }

        var rows: [OCRDraftCourse] = []
        var warnings: [String] = ["AI 识别结果需人工确认后才会写入课程表。"]
        var meta = Meta()

        for table in tableCandidates(from: root) {
            meta.merge(from: table)
            for course in courseCandidates(from: table) {
                rows.append(contentsOf: self.rows(from: course, meta: meta))
            }
        }

        // Some models return a flat course array without a tables wrapper.
        if rows.isEmpty {
            if let array = root as? [Any] {
                for case let course as [String: Any] in array {
                    rows.append(contentsOf: self.rows(from: course, meta: meta))
                }
            } else if let dict = root as? [String: Any] {
                // A single course object.
                if dict["name"] != nil || dict["courseName"] != nil || dict["课程名"] != nil {
                    rows.append(contentsOf: self.rows(from: dict, meta: meta))
                }
            }
        }

        rows.removeAll { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !rows.isEmpty else { throw ParseError.noCourses }

        // De-duplicate identical (name, weekday, period/time) rows that some
        // models emit when a course spans consecutive periods.
        rows = dedupe(rows)

        if meta.totalWeeks == nil { warnings.append("未识别到总周数，已按 18 周处理，可在下方修改。") }
        if meta.semesterStart == nil { warnings.append("未识别到开学日期，已按本学期第一个周一处理。") }

        let summary = "AI 识别 · \(rows.count) 条 · 建议 \(meta.totalWeeks ?? 18) 周 · 起始 \(meta.semesterStart ?? ScheduleTransfer.isoDate(ScheduleDocument.mondayOfCurrentWeek()))"
        return OCRDraft(
            rawText: summary,
            courses: rows,
            warnings: warnings,
            suggestedTotalWeeks: meta.totalWeeks,
            suggestedSemesterStart: meta.semesterStart,
            suggestedTableName: meta.tableName
        )
    }

    // MARK: - Metadata

    private struct Meta {
        var semesterStart: String?
        var totalWeeks: Int?
        var tableName: String?
        var hasWeekend: Bool?
        var reminderMinutes: Int?
        var reminderStyle: String?
        var colorHex: String?

        mutating func merge(from table: [String: Any]) {
            semesterStart = semesterStart ?? firstString(table, ["semesterStart", "startDate", "start", "termStart", "开学日期", "学期开始", "开始日期", "firstWeekStart"])
            totalWeeks = totalWeeks ?? firstInt(table, ["totalWeeks", "weeksCount", "weekCount", "总周数", "学期周数", "周数"])
            tableName = tableName ?? firstString(table, ["name", "tableName", "title", "名称", "课程表名称", "学期"])
            hasWeekend = hasWeekend ?? firstBool(table, ["hasWeekendCourses", "weekend", "hasWeekend", "周末有课"])
            reminderMinutes = reminderMinutes ?? firstInt(table, ["reminderMinutes", "defaultReminderMinutes", "提醒"])
            reminderStyle = reminderStyle ?? firstString(table, ["reminderStyle", "提醒方式"])
            colorHex = colorHex ?? firstString(table, ["colorHex", "color", "颜色"])
        }
    }

    // MARK: - Locating tables / courses

    private static func tableCandidates(from root: Any) -> [[String: Any]] {
        if let dict = root as? [String: Any] {
            if let tables = dict["tables"] as? [[String: Any]] { return tables }
            if let tables = dict["tables"] as? [Any] { return tables.compactMap { $0 as? [String: Any] } }
            if let data = dict["data"] as? [String: Any], let tables = data["tables"] as? [[String: Any]] { return tables }
            if let data = dict["data"] as? [[String: Any]] { return data }
            if let result = dict["result"] as? [String: Any] { return [result] }
            return [dict]
        }
        if let array = root as? [[String: Any]] {
            // Could be tables or a flat list of courses.
            let looksLikeTables = array.contains { $0["courses"] != nil || $0["periods"] != nil || $0["semesterStart"] != nil }
            return looksLikeTables ? array : [["courses": array]]
        }
        return []
    }

    private static func courseCandidates(from table: [String: Any]) -> [[String: Any]] {
        for key in ["courses", "courseList", "items", "lessons", "课程", "课程列表"] {
            if let list = table[key] as? [[String: Any]] { return list }
            if let list = table[key] as? [Any] { return list.compactMap { $0 as? [String: Any] } }
        }
        // A table object that is itself a single course.
        if table["name"] != nil || table["courseName"] != nil { return [table] }
        return []
    }

    private static func containsCourses(_ dict: [String: Any]) -> Bool {
        if let tables = dict["tables"] as? [Any], !tables.isEmpty { return true }
        if dict["courses"] != nil { return true }
        return false
    }

    // MARK: - One course object → one or more draft rows

    private static func rows(from course: [String: Any], meta: Meta) -> [OCRDraftCourse] {
        let name = firstString(course, ["name", "courseName", "course", "title", "课程", "课程名", "课程名称"]) ?? ""
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let teacher = firstString(course, ["teacher", "instructor", "教师", "老师", "任课教师"])
        let location = firstString(course, ["location", "room", "classroom", "place", "教室", "地点", "上课地点"])
        let notes = firstString(course, ["notes", "note", "remark", "备注"])
        let color = firstString(course, ["color", "colorHex", "颜色"])

        let weekdays = self.weekdays(from: course, meta: meta)
        let weeks = self.weeks(from: course, meta: meta)
        let customTimes = self.customTimes(from: course)

        var result: [OCRDraftCourse] = []
        for weekday in weekdays {
            if let custom = customTimes {
                result.append(OCRDraftCourse(
                    name: name, teacher: teacher, location: location, notes: notes, color: color,
                    weekday: weekday, weeks: weeks, timingMode: TimingMode.custom.rawValue,
                    startPeriod: nil, endPeriod: nil,
                    customStart: custom.0, customEnd: custom.1,
                    inferredWeekExpression: nil
                ))
                continue
            }
            let spans = self.periodSpans(from: course)
            if spans.isEmpty {
                // No timing given; default to period 1 so the row still imports.
                result.append(OCRDraftCourse(
                    name: name, teacher: teacher, location: location, notes: notes, color: color,
                    weekday: weekday, weeks: weeks, timingMode: TimingMode.period.rawValue,
                    startPeriod: 1, endPeriod: 1, customStart: nil, customEnd: nil
                ))
            } else {
                for span in spans {
                    result.append(OCRDraftCourse(
                        name: name, teacher: teacher, location: location, notes: notes, color: color,
                        weekday: weekday, weeks: weeks, timingMode: TimingMode.period.rawValue,
                        startPeriod: span.0, endPeriod: span.1, customStart: nil, customEnd: nil
                    ))
                }
            }
        }
        return result
    }

    // MARK: - Field extraction with alias tables

    private static func weekdays(from course: [String: Any], meta: Meta) -> [Int] {
        // Explicit list.
        for key in ["weekdays", "days", "dayOfWeek"] {
            if let list = course[key] as? [Any] {
                let mapped = list.compactMap { normalizeWeekday($0) }
                if !mapped.isEmpty { return Array(Set(mapped)).sorted() }
            }
        }
        // Single day under many names.
        for key in ["weekday", "day", "week", "weekDay", "星期", "周", "上课日"] {
            if let value = course[key], let day = normalizeWeekday(value) { return [day] }
        }
        return [1]
    }

    private static func normalizeWeekday(_ value: Any) -> Int? {
        if let number = intValue(value) {
            // Accept 0-based (0=Sunday) and 1-based (1=Monday) conventions.
            if (1...7).contains(number) { return number }
            if number == 0 { return 7 }
            return nil
        }
        if let text = value as? String {
            let tokens: [(String, Int)] = [
                ("一", 1), ("二", 2), ("三", 3), ("四", 4), ("五", 5), ("六", 6), ("日", 7), ("天", 7),
                ("mon", 1), ("tue", 2), ("wed", 3), ("thu", 4), ("fri", 5), ("sat", 6), ("sun", 7)
            ]
            let lower = text.lowercased()
            for (token, day) in tokens where lower.contains(token) { return day }
        }
        return nil
    }

    private static func weeks(from course: [String: Any], meta: Meta) -> [Int]? {
        let total = meta.totalWeeks ?? 18
        // Explicit array.
        for key in ["weeks", "weekList", "weekNumbers", "周次", "周"] {
            if let list = course[key] as? [Any] {
                let mapped = list.compactMap { intValue($0) }.filter { $0 >= 1 }
                if !mapped.isEmpty { return Array(Set(mapped)).sorted() }
            }
            // Range string like "1-16" or "1-16周单周".
            if let text = course[key] as? String, let parsed = parseWeekExpression(text, totalWeeks: total) {
                return parsed
            }
            if let number = intValue(course[key]) { return [number] }
        }
        // startWeek/endWeek.
        let start = firstInt(course, ["startWeek", "weekStart", "开始周"])
        let end = firstInt(course, ["endWeek", "weekEnd", "结束周"])
        if let start {
            let finish = end ?? total
            if start <= finish { return Array(start...finish).filter { $0 >= 1 } }
        }
        // Week pattern.
        for key in ["weekType", "weekPattern", "pattern", "周次模式", "单双周"] {
            if let text = course[key] as? String, let parsed = parseWeekExpression(text, totalWeeks: total) {
                return parsed
            }
        }
        return nil
    }

    /// Parses expressions like "1-16周", "1-16周单周", "2-14周双周", "1,3,5-9周", "odd", "even".
    static func parseWeekExpression(_ text: String, totalWeeks: Int) -> [Int]? {
        let lower = text.lowercased()
        var weeks = Set<Int>()
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        // 1) Ranges first, recording the digits they consume.
        var rangeCovered = IndexSet()
        if let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*[-—~至]\\s*(\\d+)") {
            for match in regex.matches(in: text, range: full) {
                if let a = Int(ns.substring(with: match.range(at: 1))),
                   let b = Int(ns.substring(with: match.range(at: 2))), a <= b {
                    for week in a...b where week >= 1 && week <= max(totalWeeks, b) { weeks.insert(week) }
                    rangeCovered.insert(integersIn: match.range.location..<(match.range.location + match.range.length))
                }
            }
        }
        // 2) Bare numbers not already part of a range (e.g. "1,3,5-9周").
        if let regex = try? NSRegularExpression(pattern: "\\d+") {
            for match in regex.matches(in: text, range: full) where !rangeCovered.contains(match.range.location) {
                if let value = Int(ns.substring(with: match.range)), value >= 1, value <= max(totalWeeks, 52) {
                    weeks.insert(value)
                }
            }
        }

        guard !weeks.isEmpty else {
            // Pattern words without numbers → apply to full semester.
            if lower.contains("单") || lower.contains("odd") { return Array(stride(from: 1, through: totalWeeks, by: 2)) }
            if lower.contains("双") || lower.contains("even") { return Array(stride(from: 2, through: totalWeeks, by: 2)) }
            return nil
        }
        var result = weeks.sorted()
        if lower.contains("单") || lower.contains("odd") { result = result.filter { $0 % 2 == 1 } }
        if lower.contains("双") || lower.contains("even") { result = result.filter { $0 % 2 == 0 } }
        return result.isEmpty ? nil : result
    }

    private static func periodSpans(from course: [String: Any]) -> [(Int, Int)] {
        // sections: [1,2,3,4] → contiguous spans.
        for key in ["sections", "periods", "periodList", "节次", "节"] {
            if let list = course[key] as? [Any] {
                let numbers = list.compactMap { intValue($0) }.filter { $0 >= 1 }.sorted()
                if !numbers.isEmpty { return contiguousSpans(numbers) }
            }
            if let text = course[key] as? String, let parsed = parsePeriodExpression(text) { return parsed }
        }
        let start = firstInt(course, ["startPeriod", "startSection", "start", "开始节次", "起始节次", "开始节"])
        let end = firstInt(course, ["endPeriod", "endSection", "end", "结束节次", "结束节"])
        if let start {
            let finish = max(start, end ?? start)
            return [(max(1, start), finish)]
        }
        return []
    }

    static func parsePeriodExpression(_ text: String) -> [(Int, Int)]? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var spans: [(Int, Int)] = []
        var rangeCovered = IndexSet()
        if let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*[-—~至]\\s*(\\d+)") {
            for match in regex.matches(in: text, range: full) {
                if let a = Int(ns.substring(with: match.range(at: 1))),
                   let b = Int(ns.substring(with: match.range(at: 2))) {
                    spans.append((max(1, min(a, b)), max(a, b)))
                    rangeCovered.insert(integersIn: match.range.location..<(match.range.location + match.range.length))
                }
            }
        }
        if let regex = try? NSRegularExpression(pattern: "\\d+") {
            let singles = regex.matches(in: text, range: full)
                .filter { !rangeCovered.contains($0.range.location) }
                .compactMap { Int(ns.substring(with: $0.range)) }
                .filter { $0 >= 1 }
            if !singles.isEmpty { spans.append(contentsOf: contiguousSpans(singles.sorted())) }
        }
        return spans.isEmpty ? nil : spans
    }

    private static func contiguousSpans(_ sorted: [Int]) -> [(Int, Int)] {
        guard let first = sorted.first else { return [] }
        var spans: [(Int, Int)] = []
        var start = first
        var previous = first
        for value in sorted.dropFirst() {
            if value == previous + 1 {
                previous = value
            } else {
                spans.append((start, previous))
                start = value
                previous = value
            }
        }
        spans.append((start, previous))
        return spans
    }

    private static func customTimes(from course: [String: Any]) -> (String, String)? {
        let start = firstString(course, ["customStart", "startTime", "timeStart", "开始时间", "起始时间"])
        let end = firstString(course, ["customEnd", "endTime", "timeEnd", "结束时间"])
        guard let start, let end, Period.minutes(from: normalizeTime(start)) != nil, Period.minutes(from: normalizeTime(end)) != nil else {
            return nil
        }
        return (normalizeTime(start), normalizeTime(end))
    }

    private static func normalizeTime(_ value: String) -> String {
        // "8:00" / "8：00" / "0800" / "8点" → "08:00"
        let cleaned = value.replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "点", with: ":")
            .trimmingCharacters(in: .whitespaces)
        if let regex = try? NSRegularExpression(pattern: "(\\d{1,2})\\s*[:\\-]\\s*(\\d{2})") {
            let ns = cleaned as NSString
            if let match = regex.firstMatch(in: cleaned, range: NSRange(location: 0, length: ns.length)),
               let hour = Int(ns.substring(with: match.range(at: 1))),
               let minute = Int(ns.substring(with: match.range(at: 2))) {
                return String(format: "%02d:%02d", hour, minute)
            }
        }
        if let regex = try? NSRegularExpression(pattern: "(\\d{1,2})"),
           let match = regex.firstMatch(in: cleaned, range: NSRange(location: 0, length: (cleaned as NSString).length)),
           let hour = Int((cleaned as NSString).substring(with: match.range(at: 1))) {
            return String(format: "%02d:00", hour)
        }
        return value
    }

    // MARK: - Generic value coercion

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? Double { return Int(number) }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if let number = Int(trimmed) { return number }
            if let match = try? NSRegularExpression(pattern: "\\d+"),
               let found = match.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) {
                return Int((trimmed as NSString).substring(with: found.range))
            }
        }
        return nil
    }

    private static func firstString(_ dict: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.trimmingCharacters(in: .whitespaces).isEmpty { return value }
            if let value = dict[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }

    private static func firstInt(_ dict: [String: Any], _ keys: [String]) -> Int? {
        for key in keys where dict[key] != nil { if let value = intValue(dict[key]) { return value } }
        return nil
    }

    private static func firstBool(_ dict: [String: Any], _ keys: [String]) -> Bool? {
        for key in keys {
            if let value = dict[key] as? Bool { return value }
            if let value = dict[key] as? String {
                let lower = value.lowercased()
                if ["true", "yes", "1", "是", "有"].contains(lower) { return true }
                if ["false", "no", "0", "否", "无"].contains(lower) { return false }
            }
            if let number = dict[key] as? NSNumber { return number.boolValue }
        }
        return nil
    }

    // MARK: - Helpers

    private static func dedupe(_ rows: [OCRDraftCourse]) -> [OCRDraftCourse] {
        var seen = Set<String>()
        var result: [OCRDraftCourse] = []
        for row in rows {
            let key = [row.name, String(row.weekday), row.timingMode ?? "",
                       String(row.startPeriod ?? -1), String(row.endPeriod ?? -1),
                       row.customStart ?? "", row.customEnd ?? "",
                       (row.weeks ?? []).map(String.init).joined(separator: ",")].joined(separator: "|")
            if seen.insert(key).inserted { result.append(row) }
        }
        return result
    }

    /// Strips markdown fences / prose and returns the outermost balanced JSON
    /// object or array (brace-matched, so trailing prose is not swept in).
    static func extractJSON(from text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fenceStart = trimmed.range(of: "```") {
            trimmed = String(trimmed[fenceStart.upperBound...])
            if let fenceEnd = trimmed.range(of: "```") { trimmed = String(trimmed[..<fenceEnd.lowerBound]) }
            trimmed = trimmed.replacingOccurrences(of: "json", with: "", options: [.caseInsensitive, .anchored])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Find the first opener and scan to its matching closer.
        guard let startIndex = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return trimmed }
        let opener = trimmed[startIndex]
        let closer: Character = opener == "{" ? "}" : "]"
        var depth = 0
        var inString = false
        var escaped = false
        var current = startIndex
        while current < trimmed.endIndex {
            let character = trimmed[current]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else {
                switch character {
                case "\"": inString = true
                case opener: depth += 1
                case closer:
                    depth -= 1
                    if depth == 0 { return String(trimmed[startIndex...current]) }
                default: break
                }
            }
            current = trimmed.index(after: current)
        }
        return trimmed
    }
}
