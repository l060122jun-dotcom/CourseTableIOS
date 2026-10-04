import Foundation

/// A spreadsheet reader for `.xlsx` that is deliberately format-agnostic:
/// it never assumes a particular header layout. It returns *every* sheet as a
/// dense text grid (with merged-cell values filled in), so a higher layer can
/// decide how to interpret the content.
enum XLSXReader {
    struct Sheet {
        var name: String
        var rows: [[String]]
    }

    enum XLSXError: LocalizedError {
        case notZip
        case noSheet
        case unreadable

        var errorDescription: String? {
            switch self {
            case .notZip: return "这不是有效的 Excel（.xlsx）文件。"
            case .noSheet: return "Excel 中没有找到工作表。"
            case .unreadable: return "无法读取 Excel 内容。"
            }
        }
    }

    /// All sheets, in workbook order, each as a dense grid.
    static func readSheets(data: Data) throws -> [Sheet] {
        guard let zip = ZipArchive(data: data) else { throw XLSXError.notZip }
        let shared = zip.entry("xl/sharedStrings.xml").flatMap(parseSharedStrings) ?? []

        let sheetKeys = zip.entries.keys
            .filter { $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") }
            .sorted { sheetNumber($0) < sheetNumber($1) }
        guard !sheetKeys.isEmpty else { throw XLSXError.noSheet }

        var sheets: [Sheet] = []
        for key in sheetKeys {
            guard let data = zip.entry(key) else { continue }
            var grid = parseSheet(data, sharedStrings: shared)
            grid = fillMergedCells(data, grid: grid)
            if grid.contains(where: { $0.contains(where: { !$0.isEmpty }) }) {
                sheets.append(Sheet(name: key, rows: grid))
            }
        }
        guard !sheets.isEmpty else { throw XLSXError.unreadable }
        return sheets
    }

    private static func sheetNumber(_ key: String) -> Int {
        let digits = key.compactMap { $0.isNumber ? $0 : nil }
        return Int(String(digits)) ?? 0
    }

    // MARK: Shared strings

    private static func parseSharedStrings(_ data: Data) -> [String] {
        guard let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }
        var result: [String] = []
        let ns = xml as NSString
        guard let regex = try? NSRegularExpression(pattern: "<si\\b[^>]*/>|<si\\b[^>]*>(.*?)</si>", options: [.dotMatchesLineSeparators]) else { return [] }
        for match in regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            let contentRange = match.range(at: 1)
            if contentRange.location == NSNotFound {
                result.append("")
            } else {
                let inner = ns.substring(with: contentRange)
                let texts = matches(pattern: "<t[^>]*>(.*?)</t>|<t[^>]*/>", in: inner)
                result.append(texts.map(decodeEntities).joined())
            }
        }
        return result
    }

    // MARK: Worksheet grid

    private static func parseSheet(_ data: Data, sharedStrings: [String]) -> [[String]] {
        guard let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }
        var grid: [[String]] = []
        let ns = xml as NSString
        guard let rowRegex = try? NSRegularExpression(pattern: "<row\\b[^>]*/>|<row\\b[^>]*>(.*?)</row>", options: [.dotMatchesLineSeparators]) else { return [] }
        var rowIndex = 0
        for rowMatch in rowRegex.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            let innerRange = rowMatch.range(at: 1)
            if innerRange.location == NSNotFound {
                grid.append([])
                rowIndex += 1
                continue
            }
            let rowXML = ns.substring(with: innerRange)
            var row: [String] = []
            var pendingColumn = 0
            for cellXML in cellSlices(in: rowXML) {
                let attrs = attributes(in: cellXML)
                let ref = attrs["r"] ?? ""
                let type = attrs["t"]
                let column = columnIndex(from: ref) ?? pendingColumn
                while row.count <= column { row.append("") }
                var value = ""
                if let inline = matches(pattern: "<is>(.*?)</is>", in: cellXML).first {
                    value = matches(pattern: "<t[^>]*>(.*?)</t>", in: inline).map(decodeEntities).joined()
                } else if let v = matches(pattern: "<v>(.*?)</v>", in: cellXML).first {
                    if type == "s", let index = Int(v), sharedStrings.indices.contains(index) {
                        value = sharedStrings[index]
                    } else {
                        value = decodeEntities(v)
                    }
                } else if let inlineT = matches(pattern: "<t[^>]*>(.*?)</t>", in: cellXML).first {
                    value = decodeEntities(inlineT)
                }
                row[column] = value.trimmingCharacters(in: .whitespacesAndNewlines)
                pendingColumn = column + 1
            }
            grid.append(row)
            rowIndex += 1
        }
        return grid
    }

    /// Expands `<mergeCell ref="B2:D4"/>` ranges so the anchor value appears in
    /// every covered cell — essential for merged timetable blocks.
    private static func fillMergedCells(_ data: Data, grid: [[String]]) -> [[String]] {
        guard let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return grid }
        var grid = grid
        for ref in matches(pattern: "<mergeCell ref=\"([A-Z]+\\d+:[A-Z]+\\d+)\"", in: xml) {
            let parts = ref.split(separator: ":")
            guard parts.count == 2,
                  let start = cellCoordinate(String(parts[0])),
                  let end = cellCoordinate(String(parts[1])) else { continue }
            guard grid.indices.contains(start.row), start.column < grid[start.row].count else { continue }
            let value = grid[start.row][start.column]
            guard !value.isEmpty else { continue }
            for row in start.row...max(start.row, end.row) {
                while grid.count <= row { grid.append([]) }
                for column in start.column...max(start.column, end.column) {
                    while grid[row].count <= column { grid[row].append("") }
                    if grid[row][column].isEmpty { grid[row][column] = value }
                }
            }
        }
        return grid
    }

    private static func cellCoordinate(_ ref: String) -> (row: Int, column: Int)? {
        guard let column = columnIndex(from: ref) else { return nil }
        let digits = ref.filter { $0.isNumber }
        guard let rowNumber = Int(digits) else { return nil }
        return (max(0, rowNumber - 1), column)
    }

    private static func cellSlices(in rowXML: String) -> [String] {
        matches(pattern: "<c\\b[^>]*/>|<c\\b[^>]*>.*?</c>", in: rowXML)
    }

    private static func attributes(in cellXML: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in matches(pattern: "[A-Za-z0-9_]+=\"[^\"]*\"", in: cellXML) {
            guard let equals = pair.firstIndex(of: "=") else { continue }
            let key = String(pair[..<equals])
            let value = String(pair[pair.index(after: equals)...].dropFirst().dropLast())
            result[key] = value
        }
        return result
    }

    private static func columnIndex(from ref: String) -> Int? {
        var value = 0
        var found = false
        for character in ref {
            guard let ascii = character.asciiValue, ascii >= 65, ascii <= 90 else { break }
            value = value * 26 + Int(ascii - 64)
            found = true
        }
        return found ? value - 1 : nil
    }

    // MARK: Regex + entities

    static func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            match.numberOfRanges > 1 ? ns.substring(with: match.range(at: 1)) : ns.substring(with: match.range)
        }
    }

    private static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
