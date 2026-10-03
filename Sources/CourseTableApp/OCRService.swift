import Foundation
import Vision
import UIKit
import CourseTableCore

enum OCRServiceError: Error, LocalizedError {
    case invalidImage
    case noText

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法读取所选图片。"
        case .noText: return "未识别到文字，请换一张更清晰的课表截图。"
        }
    }
}

/// On-device OCR via Vision. Never uploads the image and never writes courses
/// directly — it only produces a reviewable draft.
final class OCRService {
    func recognize(image: UIImage) async throws -> OCRDraft {
        guard let cgImage = image.cgImage else { throw OCRServiceError.invalidImage }
        let blocks = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[OCRBlock], Error>) in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let blocks = observations.compactMap { observation -> OCRBlock? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let box = observation.boundingBox
                    return OCRBlock(
                        text: candidate.string,
                        bounds: NormalizedRect(x: box.minX, y: box.minY, width: box.width, height: box.height),
                        recognitionConfidence: Double(candidate.confidence)
                    )
                }
                continuation.resume(returning: blocks)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
        guard !blocks.isEmpty else { throw OCRServiceError.noText }
        return OCRParser.parse(blocks: blocks)
    }
}

/// Heuristic parser turning OCR blocks into a coarse weekly grid draft:
/// recognises weekday headers, period rows and course-name cells. Kept in the
/// app layer because it is inherently approximate and always user-reviewed.
enum OCRParser {
    static let weekdayTokens: [(String, Int)] = [
        ("周一", 1), ("星期一", 1), ("礼拜一", 1),
        ("周二", 2), ("星期二", 2), ("礼拜二", 2),
        ("周三", 3), ("星期三", 3), ("礼拜三", 3),
        ("周四", 4), ("星期四", 4), ("礼拜四", 4),
        ("周五", 5), ("星期五", 5), ("礼拜五", 5),
        ("周六", 6), ("星期六", 6), ("礼拜六", 6),
        ("周日", 7), ("周天", 7), ("星期日", 7), ("星期天", 7)
    ]

    static func parse(blocks: [OCRBlock]) -> OCRDraft {
        let rawText = blocks.map(\.text).joined(separator: "\n")
        let sorted = blocks.sorted { $0.bounds.y > $1.bounds.y }

        // Try to detect header columns (weekdays) by their normalised x-center.
        var columnDays: [Int: CGFloat] = [:]
        for block in sorted {
            for (token, day) in weekdayTokens where block.text.contains(token) {
                let center = CGFloat(block.bounds.x + block.bounds.width / 2)
                columnDays[day] = center
                break
            }
        }

        var rows: [OCRDraftCourse] = []
        let weekdayTokensFlat = weekdayTokens.map(\.0)
        for block in sorted {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2, text.count <= 40 else { continue }
            guard !weekdayTokensFlat.contains(where: { text.contains($0) }) else { continue }
            // Skip obvious noise rows.
            guard !text.allSatisfy({ $0.isNumber }) else { continue }

            let center = CGFloat(block.bounds.x + block.bounds.width / 2)
            var weekday = 1
            if !columnDays.isEmpty {
                weekday = columnDays.min(by: { abs($0.value - center) < abs($1.value - center) })?.key ?? 1
            }
            let field = classify(text)
            rows.append(OCRDraftCourse(
                name: field.name,
                teacher: field.teacher,
                location: field.location,
                weekday: weekday,
                inferredWeekExpression: field.weeks
            ))
        }

        var warnings: [String] = ["识别结果需人工确认后才会写入课程表。"]
        if columnDays.isEmpty { warnings.append("未识别到星期表头，星期已默认设为周一，请手动核对。") }
        if rows.isEmpty { warnings.append("未解析出课程条目，可在下方手动补充。") }

        return OCRDraft(rawText: rawText, courses: rows, warnings: warnings)
    }

    private struct Classified {
        var name: String
        var teacher: String?
        var location: String?
        var weeks: String?
    }

    private static func classify(_ text: String) -> Classified {
        var name = text
        var teacher: String?
        var location: String?
        var weeks: String?

        if let range = text.range(of: #"\d+[-—~,，\d]*周"#, options: .regularExpression) {
            weeks = String(text[range])
            name = name.replacingOccurrences(of: String(text[range]), with: "")
        }
        for marker in ["老师", "教师", "教授"] {
            if let range = name.range(of: marker) {
                let prefix = name[..<range.lowerBound]
                teacher = String(prefix.suffix(6)).trimmingCharacters(in: .whitespaces)
                name = name.replacingOccurrences(of: String(prefix.suffix(6)) + marker, with: "")
            }
        }
        for marker in ["楼", "教室", "室", "机房"] {
            if name.contains(marker), let range = name.range(of: marker) {
                location = String(name.prefix(through: range.upperBound)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Classified(name: name.isEmpty ? text : name, teacher: teacher, location: location, weeks: weeks)
    }
}
