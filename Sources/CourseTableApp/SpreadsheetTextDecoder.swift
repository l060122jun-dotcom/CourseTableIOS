import Foundation

/// Decodes CSV / TSV / plain-text spreadsheets, guessing the encoding (UTF-8,
/// UTF-16 with BOM, or GB18030 for Windows Excel exports) and normalising the
/// delimiter to tabs so downstream code sees a uniform grid.
enum SpreadsheetTextDecoder {

    static func decodeCSV(_ data: Data) -> String {
        let text = decodeText(data)
        return normalizeDelimiters(text)
    }

    /// Best-effort text decode across the encodings Chinese Excel commonly emits.
    static func decodeText(_ data: Data) -> String {
        // BOM sniffing first.
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            return String(decoding: data.dropFirst(3), as: UTF8.self)
        }
        if data.count >= 2, data[0] == 0xFF, data[1] == 0xFE {
            return decodeUTF16LE(Array(data.dropFirst(2)))
        }
        if data.count >= 2, data[0] == 0xFE, data[1] == 0xFF {
            return decodeUTF16BE(Array(data.dropFirst(2)))
        }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        // GB18030 / GBK common for legacy Chinese spreadsheets.
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let text = String(data: data, encoding: String.Encoding(rawValue: gb18030)) { return text }
        if let latin = String(data: data, encoding: .isoLatin1) { return latin }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeUTF16LE(_ bytes: [UInt8]) -> String {
        var units: [UInt16] = []
        units.reserveCapacity(bytes.count / 2)
        var index = 0
        while index + 1 < bytes.count {
            units.append(UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8))
            index += 2
        }
        return String(decoding: units, as: UTF16.self)
    }

    private static func decodeUTF16BE(_ data: Data) -> String {
        decodeUTF16BE(Array(data))
    }

    private static func decodeUTF16BE(_ bytes: [UInt8]) -> String {
        var units: [UInt16] = []
        units.reserveCapacity(bytes.count / 2)
        var index = 0
        while index + 1 < bytes.count {
            units.append((UInt16(bytes[index]) << 8) | UInt16(bytes[index + 1]))
            index += 2
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// Chooses the most likely delimiter per file and converts everything to tabs.
    static func normalizeDelimiters(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0) }
        guard !lines.isEmpty else { return text }

        // Legacy .xls (.docformat) yields NUL-separated ASCII; treat NUL as tab.
        let cleaned = text.replacingOccurrences(of: "\u{0}", with: "\t")
        let cleanedLines = cleaned.split(whereSeparator: \.isNewline).map { String($0) }

        // If tabs already dominate, keep as-is.
        let tabCount = cleanedLines.prefix(30).reduce(0) { $0 + $1.filter { $0 == "\t" }.count }
        if tabCount > 0 { return cleaned }

        let candidates: [Character] = [",", ";", "；", "，", "|"]
        var bestDelimiter: Character?
        var bestCount = 0
        for candidate in candidates {
            let count = cleanedLines.prefix(30).reduce(0) { $0 + $1.filter { $0 == candidate }.count }
            if count > bestCount { bestCount = count; bestDelimiter = candidate }
        }
        guard let delimiter = bestDelimiter, bestCount > 0 else { return cleaned }

        return cleanedLines.map { line in
            splitCSVLine(line, delimiter: delimiter).joined(separator: "\t")
        }.joined(separator: "\n")
    }

    private static func splitCSVLine(_ line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for character in line {
            if character == "\"" {
                inQuotes.toggle()
            } else if character == delimiter && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }
}
