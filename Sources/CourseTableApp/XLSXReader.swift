import Foundation

/// Minimal `.xlsx` reader that extracts a text grid (rows × columns) without
/// any third-party dependency. An xlsx is a zip of XML; we read the shared
/// string table and the first worksheet, resolve references, and rebuild the
/// grid honouring sparse `<c r="B3">` coordinates so column positions survive.
enum XLSXReader {
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

    static func read(data: Data) throws -> String {
        guard let zip = ZipArchive(data: data) else { throw XLSXError.notZip }
        let shared = zip.entry("xl/sharedStrings.xml").flatMap(parseSharedStrings) ?? []
        let sheetKey = zip.entries.keys.first(where: { $0 == "xl/worksheets/sheet1.xml" })
            ?? zip.entries.keys.filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }.sorted().first
        guard let key = sheetKey, let sheetData = zip.entry(key) else { throw XLSXError.noSheet }

        let rows = parseSheet(sheetData, sharedStrings: shared)
        guard !rows.isEmpty else { throw XLSXError.unreadable }
        return render(rows)
    }

    // MARK: Shared strings

    private static func parseSharedStrings(_ data: Data) -> [String] {
        guard let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }
        var result: [String] = []
        // Walk <si ...> ... </si> blocks in order. A self-closing <si/> is an
        // empty string but must still occupy an index so `t="s"` references
        // stay aligned.
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
        // Match every <row ...>...</row> and self-closing <row .../> so empty
        // separator rows keep their position (which encodes period index).
        let ns = xml as NSString
        guard let rowRegex = try? NSRegularExpression(pattern: "<row\\b[^>]*/>|<row\\b[^>]*>(.*?)</row>", options: [.dotMatchesLineSeparators]) else { return [] }
        for rowMatch in rowRegex.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            let innerRange = rowMatch.range(at: 1)
            if innerRange.location == NSNotFound {
                grid.append([])
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
                }
                row[column] = value.trimmingCharacters(in: .whitespacesAndNewlines)
                pendingColumn = column + 1
            }
            grid.append(row)
        }
        return grid
    }

    /// Splits a `<row>...</row>` body into individual cells. The self-closing
    /// alternative is listed first so a `<c .../>` is not swallowed by a later
    /// `.*?</c>` that belongs to a following cell.
    private static func cellSlices(in rowXML: String) -> [String] {
        matches(pattern: "<c\\b[^>]*/>|<c\\b[^>]*>.*?</c>", in: rowXML)
    }

    private static func attributes(in cellXML: String) -> [String: String] {
        var result: [String: String] = [:]
        // No capture groups so `matches` returns the whole `key="value"` pair.
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

    private static func matches(pattern: String, in text: String) -> [String] {
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

    /// Renders the grid as tab-separated lines, preserving empty cells so the
    /// model can infer weekday columns and period rows from position.
    private static func render(_ rows: [[String]]) -> String {
        rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
    }
}
