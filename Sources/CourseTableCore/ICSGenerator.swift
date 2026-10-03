import Foundation

/// RFC 5545 (iCalendar) generator, mirroring the WeChat mini program `ics.js`
/// so exported files stay identical across platforms.
public enum ICSGenerator {

    public static func generate(
        courses: [Course],
        rulesByCourse: [UUID: [MeetingRule]],
        table: CourseTable,
        periods: [Period],
        now: Date = .now
    ) throws -> String {
        guard !courses.isEmpty else { throw ICSError.empty }

        let semantic = schedule(courses: courses, rulesByCourse: rulesByCourse, table: table, periods: periods)
        guard !semantic.isEmpty else { throw ICSError.empty }

        let stamp = formatUTC(now)
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "PRODID:-//CourseTable//Course Schedule//ZH-CN",
            "VERSION:2.0",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "X-WR-TIMEZONE:Asia/Shanghai",
            "X-WR-CALNAME:\(escape(table.name.isEmpty ? "课程表" : table.name))"
        ]

        for item in semantic {
            let times = item.times
            let dayOffset = (item.week - 1) * 7 + item.weekday - 1
            let start = utcDate(base: table.semesterStartDate, dayOffset: dayOffset, minutes: times.start)
            var end = utcDate(base: table.semesterStartDate, dayOffset: dayOffset, minutes: times.end)
            if end <= start { end = end.addingTimeInterval(24 * 60 * 60) }

            var lines2: [String] = [
                "BEGIN:VEVENT",
                "UID:\(safe(item.course.id.uuidString))-w\(item.week)@coursetable.local",
                "DTSTAMP:\(stamp)",
                "DTSTART:\(formatUTC(start))",
                "DTEND:\(formatUTC(end))",
                "SUMMARY:\(escape(item.course.name.isEmpty ? "未命名课程" : item.course.name))",
                "LOCATION:\(escape(item.course.location ?? ""))"
            ]
            let description = [item.course.teacher.map { "教师：\($0)" }, item.course.notes]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if !description.isEmpty { lines2.append("DESCRIPTION:\(escape(description))") }
            lines2.append("CATEGORIES:\(escape("课程"))")

            let reminderValue = item.reminderMinutes ?? table.defaultReminderMinutes
            if let minutes = reminderValue, minutes >= 0 {
                let clamped = max(0, min(10080, minutes))
                let action = table.reminderStyle == .alarm ? "AUDIO" : "DISPLAY"
                lines2.append("BEGIN:VALARM")
                lines2.append("TRIGGER:-PT\(clamped)M")
                lines2.append("ACTION:\(action)")
                if action == "DISPLAY" { lines2.append("DESCRIPTION:\(escape(item.course.name.isEmpty ? "课程提醒" : item.course.name))") }
                lines2.append("END:VALARM")
            }
            lines2.append("END:VEVENT")
            lines.append(contentsOf: lines2)
        }

        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    public enum ICSError: LocalizedError {
        case empty
        case badSemester
        case badTime(String)
        case missingPeriod(String)

        public var errorDescription: String? {
            switch self {
            case .empty: return "没有可导出的课程"
            case .badSemester: return "请先在设置中填写正确的第一周日期"
            case .badTime(let name): return "\(name)时间格式不正确"
            case .missingPeriod(let name): return "\(name)缺少对应节次时间"
            }
        }
    }

    // MARK: - Semantics

    public struct SemanticEvent: Equatable, Sendable {
        public let course: Course
        public let week: Int
        public let weekday: Int
        public let times: ResolvedMeetingTime
        public let reminderMinutes: Int?
    }

    public static func schedule(
        courses: [Course],
        rulesByCourse: [UUID: [MeetingRule]],
        table: CourseTable,
        periods: [Period]
    ) -> [SemanticEvent] {
        var result: [SemanticEvent] = []
        for course in courses {
            for rule in rulesByCourse[course.id] ?? [] {
                guard let times = try? MeetingRuleValidator.resolve(rule, periods: periods) else { continue }
                for week in rule.weekSet.sorted() where week >= 1 && week <= table.totalWeeks {
                    result.append(SemanticEvent(
                        course: course,
                        week: week,
                        weekday: rule.weekday,
                        times: times,
                        reminderMinutes: rule.reminderMinutes
                    ))
                }
            }
        }
        return result
    }

    // MARK: - Formatting helpers

    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
    }

    static func safe(_ value: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        let normalized = String(value.map { allowed.contains($0) ? $0 : "-" })
        return String(normalized.prefix(80))
    }

    static func utf8ByteCount(_ character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first else { return 1 }
        switch scalar.value {
        case 0...0x7F: return 1
        case 0x80...0x7FF: return 2
        case 0x800...0xFFFF: return 3
        default: return 4
        }
    }

    /// Fold a content line at 75 UTF-8 octets (RFC 5545 §3.1).
    static func fold(_ line: String) -> String {
        var output: [String] = []
        var part = ""
        var bytes = 0
        for character in line {
            let size = utf8ByteCount(character)
            if !part.isEmpty, bytes + size > 75 {
                output.append(part)
                part = " " + String(character)
                bytes = 1 + size
            } else {
                part.append(character)
                bytes += size
            }
        }
        output.append(part)
        return output.joined(separator: "\r\n")
    }

    static func formatUTC(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    /// Builds an absolute UTC date from a Shanghai wall-clock time on a given day offset.
    static func utcDate(base: Date, dayOffset: Int, minutes: Int) -> Date {
        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let day = shanghai.date(byAdding: .day, value: dayOffset, to: shanghai.startOfDay(for: base)) ?? base
        let withMinutes = shanghai.date(byAdding: .minute, value: minutes, to: day) ?? day
        return withMinutes
    }
}
