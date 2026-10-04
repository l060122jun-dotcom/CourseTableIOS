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
            return String(decoding: data.dropFirst(2), as: UTF16.self)
        }
        if data.count >= 2, data[0] == 0xFE, data[1] == 0xFF {
            return decodeUTF16BE(data.dropFirst(2))
        }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        // GB18030 / GBK common for legacy Chinese spreadsheets.
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let text = String(data: data, encoding: String.Encoding(rawValue: gb18030)) { return text }
        if let latin = String(data: data, encoding: .isoLatin1) { return latin }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeUTF16BE(_ data: Data) -> String {
        var bytes = [UInt8](data)
        // Swap to little-endian, then decode.
        var index = 0
        while index + 1 < bytes.count {
            bytes.swapAt(index, index + 1)
            index += 2
        }
        return String(decoding: bytes, as: UTF16.self)
    }

    /// Chooses the most likely delimiter per file and converts everything to tabs.
    static func normalizeDelimiters(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0) }
        guard !lines.isEmpty else { return text }
        let sample = lines.prefix(30).joined(separator: "\n")

        // Legacy .xls (.docformat) yields NUL-separated ASCII; strip control chars.
        let cleaned = sample.replacingOccurrences(of: "\u{0}", with: "\t")

        let candidates: [(Character, Int)] = [("\t", 0), (",", 0), (";", 0), ("；", 0), ("，", 0)]
        var counts: [Int] = Array(repeating: 0, count: candidates.count)
        for (lineIndex, line) in lines.prefix(30).enumerated() {
            _ = lineIndex
            for (index, candidate) in candidates.enumerated() {
                counts[index] += line.filter { $0 == candidate.0 }.count
            }
        }
        let tabCount = cleaned.filter { $0 == "\t" }.count
        if tabCount >= counts.first!.count { return cleaned }

        guard let best = counts.enumerated().max(by: { $0.element < $1.element }), best.element > 0 else {
            return cleaned
        }
        let delimiter = candidates[best.offset].0
        if delimiter == "\t" { return cleaned }

        // Split each line on the delimiter (naive CSV: no embedded quotes here).
        return lines.map { line in
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
