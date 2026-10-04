import Foundation

/// Turns an arbitrary spreadsheet into a single text blob that an LLM can read
/// reliably. It is intentionally *layout-agnostic*: it never requires a
/// specific header, column order, or sheet name.
///
/// Strategy (first that yields a timetable-shaped result wins, but every
/// candidate text is concatenated so the model sees the whole picture):
///   1. Weekly grid with a detected weekday header row  → "<n>周 第X-Y节 | 内容".
///   2. Any grid containing weekday/time tokens in cells → flattened, one row per line.
///   3. Pure fallback: every non-empty cell, row by row, with its坐标.
///
/// All sheets are considered; the most timetable-like one is placed first.
enum TimetableTextExtractor {

    // MARK: Public entry

    /// Extracts the best-effort text description of a `.xlsx` workbook.
    static func extract(from data: Data) throws -> String {
        let sheets = try XLSXReader.readSheets(data: data)
        return extract(sheets: sheets)
    }

    static func extract(sheets: [XLSXReader.Sheet]) -> String {
        // Rank sheets by how timetable-like they look.
        let ranked = sheets.enumerated().sorted { lhs, rhs in
            score(lhs.element.rows) > score(rhs.element.rows)
        }
        var blocks: [String] = []
        for (index, sheet) in ranked {
            let grid = normalize(sheet.rows)
            guard !grid.isEmpty else { continue }
            let label = "【工作表 \(index + 1)】"
            if let structured = structuredGridText(from: grid) {
                blocks.append("\(label)\n\(structured)")
            } else if let flattened = flattenedText(from: grid) {
                blocks.append("\(label)\n\(flattened)")
            } else {
                blocks.append("\(label)\n\(coordinateText(from: grid))")
            }
        }
        return blocks.joined(separator: "\n\n")
    }

    // MARK: Scoring

    private static func score(_ rows: [[String]]) -> Int {
        var value = 0
        for row in rows {
            for cell in row {
                let text = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                if Weekdays.match(text) != nil { value += 6 }
                if isTimeLike(text) { value += 4 }
                if PeriodPattern.parse(text) != nil { value += 4 }
                if containsWeekExpression(text) { value += 3 }
                if text.contains("楼") || text.contains("教室") || text.contains("室") { value += 2 }
                value += 1
            }
        }
        return value
    }

    // MARK: Normalization

    /// Drops fully-empty trailing rows/columns and trims each cell.
    private static func normalize(_ rows: [[String]]) -> [[String]] {
        let cleaned = rows.map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
        var result = cleaned
        while let last = result.last, last.allSatisfy({ $0.isEmpty }) { result.removeLast() }
        let maxColumns = result.map(\.count).max() ?? 0
        return result.map { row in
            var row = row
            while row.count < maxColumns { row.append("") }
            return row
        }
    }

    // MARK: Strategy 1 — weekly grid

    /// Detects a weekday header row + period column and emits unambiguous lines.
    static func structuredGridText(from grid: [[String]]) -> String? {
        var headerRowIndex = -1
        var dayColumn: [Int: Int] = [:]

        for (rowIndex, row) in grid.enumerated() {
            var found: [Int: Int] = [:]
            for (column, cell) in row.enumerated() {
                if let day = Weekdays.match(cell) { found[day] = column }
            }
            if found.count >= 3 { headerRowIndex = rowIndex; dayColumn = found; break }
        }
        guard headerRowIndex >= 0 else { return nil }

        let minDayColumn = dayColumn.values.min() ?? 0
        var lines: [String] = []
        for row in grid[(headerRowIndex + 1)...] {
            // Period label: the nearest non-empty cell to the left of the days.
            var periodLabel: String?
            for column in stride(from: min(minDayColumn, row.count) - 1, through: 0, by: -1) where !row[column].isEmpty {
                if PeriodPattern.parse(row[column]) != nil { periodLabel = row[column]; break }
            }
            if periodLabel == nil {
                for column in 0..<min(minDayColumn, row.count) where !row[column].isEmpty {
                    periodLabel = row[column]; break
                }
            }
            let period = periodLabel.flatMap(PeriodPattern.parse)
            for (day, column) in dayColumn.sorted(by: { $0.key < $1.key }) {
                guard column < row.count else { continue }
                let content = flatten(row[column])
                guard !content.isEmpty else { continue }
                if let period {
                    lines.append("\(day)周 第\(period.start)-\(period.end)节 | \(content)")
                } else {
                    lines.append("\(day)周 | \(content)")
                }
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    // MARK: Strategy 2 — flattened rows with weekday/time hints

    private static func flattenedText(from grid: [[String]]) -> String? {
        var lines: [String] = []
        for row in grid {
            let cells = row.filter { !$0.isEmpty }
            guard !cells.isEmpty else { continue }
            let joined = cells.map(flatten).joined(separator: " | ")
            if joined.count > 1 { lines.append(joined) }
        }
        guard lines.contains(where: { containsWeekExpression($0) || isTimeLike($0) || Weekdays.match($0) != nil }) else { return nil }
        return lines.joined(separator: "\n")
    }

    // MARK: Strategy 3 — coordinate dump

    private static func coordinateText(from grid: [[String]]) -> String {
        var lines: [String] = []
        for (rowIndex, row) in grid.enumerated() {
            for (column, cell) in row.enumerated() where !cell.isEmpty {
                lines.append("R\(rowIndex + 1)C\(column + 1): \(flatten(cell))")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Helpers

    private static func flatten(_ value: String) -> String {
        value.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    private static func isTimeLike(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "\\d{1,2}\\s*[:：]\\s*\\d{2}") else { return false }
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    private static func containsWeekExpression(_ text: String) -> Bool {
        text.contains("周") || text.lowercased().contains("week")
    }
}

// MARK: - Shared token recognisers

/// Recognises a weekday from a cell in many scripts.
enum Weekdays {
    static let aliases: [(String, Int)] = [
        ("周一", 1), ("星期一", 1), ("礼拜一", 1), ("一", 1), ("monday", 1), ("mon", 1),
        ("周二", 2), ("星期二", 2), ("礼拜二", 2), ("二", 2), ("tuesday", 2), ("tue", 2),
        ("周三", 3), ("星期三", 3), ("礼拜三", 3), ("三", 3), ("wednesday", 3), ("wed", 3),
        ("周四", 4), ("星期四", 4), ("礼拜四", 4), ("四", 4), ("thursday", 4), ("thu", 4),
        ("周五", 5), ("星期五", 5), ("礼拜五", 5), ("五", 5), ("friday", 5), ("fri", 5),
        ("周六", 6), ("星期六", 6), ("礼拜六", 6), ("六", 6), ("saturday", 6), ("sat", 6),
        ("周日", 7), ("周天", 7), ("星期日", 7), ("星期天", 7), ("日", 7), ("天", 7), ("sunday", 7), ("sun", 7)
    ]

    /// Full-string match only (a cell that *is* a weekday), to avoid false hits.
    static func match(_ raw: String) -> Int? {
        let normalized = raw.replacingOccurrences(of: " ", with: "").lowercased()
        guard !normalized.isEmpty, normalized.count <= 8 else { return nil }
        // Prefer longest alias to disambiguate "一" vs "周一".
        for (token, day) in aliases where normalized == token { return day }
        return nil
    }
}

/// Recognises a period label: "第1-2节", "1-2节", "第3节", "1、2节", "5-6".
enum PeriodPattern {
    static func parse(_ raw: String) -> (start: Int, end: Int)? {
        let text = raw.replacingOccurrences(of: " ", with: "")
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        // Range like 1-2 / 1~2 / 1至2.
        if let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*[-—~至到]\\s*(\\d+)"),
           let match = regex.firstMatch(in: text, range: full),
           let a = Int(ns.substring(with: match.range(at: 1))),
           let b = Int(ns.substring(with: match.range(at: 2))),
           (1...20).contains(a), (1...20).contains(b) {
            return (min(a, b), max(a, b))
        }
        // Single "第3节" / "3".
        if let regex = try? NSRegularExpression(pattern: "第?(\\d+)节?"),
           let match = regex.firstMatch(in: text, range: full),
           let value = Int(ns.substring(with: match.range(at: 1))),
           (1...20).contains(value) {
            return (value, value)
        }
        return nil
    }
}
