import Foundation
import UIKit
import CourseTableCore

/// Talks to an OpenAI-compatible chat-completions endpoint to turn a course
/// table image **or** an Excel sheet into a structured draft that matches the
/// canonical `.lcs` format. Nothing is written until the user confirms.
///
/// Configure the endpoint/key in `AIScheduleConfig` (or via Info.plist keys
/// `AIBaseURL`, `AIAPIKey`, `AIModel`).
struct AIScheduleConfig: Sendable {
    var baseURL: URL
    var apiKey: String
    var model: String

    /// The endpoint shipped with the app.
    static let `default` = AIScheduleConfig(
        baseURL: URL(string: Bundle.main.object(forInfoDictionaryKey: "AIBaseURL") as? String ?? "http://43.226.36.44:8317/v1")!,
        apiKey: Bundle.main.object(forInfoDictionaryKey: "AIAPIKey") as? String ?? "123456",
        model: Bundle.main.object(forInfoDictionaryKey: "AIModel") as? String ?? "codex/gpt-6-luna"
    )
}

enum AIScheduleError: LocalizedError {
    case notConfigured
    case badResponse
    case http(Int, String)
    case emptyResult
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "AI 识别服务未配置。"
        case .badResponse: return "AI 服务返回了无法解析的内容。"
        case .http(let code, let body): return "AI 服务错误（HTTP \(code)）：\(body.prefix(200))"
        case .emptyResult: return "AI 未识别到任何课程。"
        case .decoding(let message): return "解析 AI 结果失败：\(message)"
        }
    }
}

final class AIScheduleService {
    private let config: AIScheduleConfig
    init(config: AIScheduleConfig = .default) { self.config = config }

    // MARK: Image

    func recognize(image: UIImage) async throws -> OCRDraft {
        guard let data = image.jpegData(compressionQuality: 0.8) else { throw AIScheduleError.badResponse }
        let base64 = data.base64EncodedString()
        let userContent: [[String: Any]] = [
            ["type": "text", "text": "请识别这张课程表图片，按系统要求输出 JSON。"],
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
        ]
        let content = try await complete(userContent: userContent)
        return try parseDraft(from: content)
    }

    // MARK: Text (Excel / grid)

    func recognize(spreadsheetText: String) async throws -> OCRDraft {
        let userContent: [[String: Any]] = [
            ["type": "text", "text": "以下是从 Excel 课程表提取的单元格内容（制表符分隔，保留行列位置）。请按系统要求输出 JSON：\n\n\(spreadsheetText)"]
        ]
        let content = try await complete(userContent: userContent)
        return try parseDraft(from: content)
    }

    // MARK: Networking

    private func complete(userContent: [[String: Any]]) async throws -> String {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": config.model,
            "temperature": 0.1,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": userContent]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIScheduleError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIScheduleError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIScheduleError.badResponse
        }
        return content
    }

    // MARK: Parsing the model output

    /// The model is asked to emit a FlowClass-compatible object. We accept
    /// either `{ tables: [...] }`, a bare `[...]` of tables, or a bare course
    /// array, and coerce it into an `OCRDraft`.
    private func parseDraft(from content: String) throws -> OCRDraft {
        let cleaned = Self.extractJSON(from: content)
        guard let data = cleaned.data(using: .utf8) else { throw AIScheduleError.decoding("非法文本") }

        let draft: OCRDraft
        if let payload = try? JSONDecoder().decode(ScheduleTransfer.self, from: data),
           !payload.tables.isEmpty {
            draft = Self.draft(from: payload)
        } else if let tables = try? JSONDecoder().decode([ScheduleTransfer.TablePayload].self, from: data),
                  !tables.isEmpty {
            let payload = ScheduleTransfer(exportedAt: ISO8601DateFormatter().string(from: .now), tables: tables)
            draft = Self.draft(from: payload)
        } else if let courses = try? JSONDecoder().decode([ScheduleTransfer.CoursePayload].self, from: data),
                  !courses.isEmpty {
            let table = ScheduleTransfer.TablePayload(
                name: "识别结果",
                semesterStart: ScheduleTransfer.isoDate(ScheduleDocument.mondayOfCurrentWeek()),
                totalWeeks: 18,
                hasWeekendCourses: false,
                reminderMinutes: 30,
                reminderStyle: "notification",
                colorHex: "#0F77FF",
                periods: [],
                courses: courses
            )
            draft = Self.draft(from: ScheduleTransfer(exportedAt: ISO8601DateFormatter().string(from: .now), tables: [table]))
        } else {
            throw AIScheduleError.decoding("未匹配到课表结构")
        }
        guard !draft.courses.isEmpty else { throw AIScheduleError.emptyResult }
        return draft
    }

    private static func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }
        if let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]") {
            return String(trimmed[start...end])
        }
        return trimmed
    }

    /// Flattens a transfer payload into a reviewable draft (one row per rule).
    private static func draft(from payload: ScheduleTransfer) -> OCRDraft {
        var rows: [OCRDraftCourse] = []
        for table in payload.tables {
            for course in table.courses {
                rows.append(OCRDraftCourse(
                    name: course.name,
                    teacher: course.teacher,
                    location: course.location,
                    notes: course.notes,
                    color: course.color,
                    weekday: min(max(course.weekday, 1), 7),
                    weeks: course.weeks,
                    timingMode: course.timingMode,
                    startPeriod: course.startPeriod,
                    endPeriod: course.endPeriod,
                    customStart: course.customStart,
                    customEnd: course.customEnd
                ))
            }
        }
        let suggestedWeeks = payload.tables.first?.totalWeeks ?? 18
        let suggestedStart = payload.tables.first?.semesterStart ?? ScheduleTransfer.isoDate(ScheduleDocument.mondayOfCurrentWeek())
        var warnings: [String] = ["AI 识别结果需人工确认后才会写入课程表。"]
        if payload.tables.count > 1 { warnings.append("识别到 \(payload.tables.count) 张课程表，将合并为当前课程表导入。") }
        return OCRDraft(
            rawText: "AI 识别 · \(rows.count) 条 · 建议 \(suggestedWeeks) 周 · 起始 \(suggestedStart)",
            courses: rows,
            warnings: warnings
        )
    }

    // MARK: System prompt (kept in sync with Docs/课表文件格式规范.md)

    static let systemPrompt = """
    你是《流云课表》的课程表结构化助手。用户会给你一张课程表图片，或一段从 Excel 提取的单元格文本（制表符分隔）。请你识别其中的所有课程，并**只输出一个 JSON 对象**，不要输出任何解释文字、不要用 markdown 代码块包裹。

    输出必须是如下结构（流云课表文件格式 flowclass.schedule v1）：
    {
      "format": "flowclass.schedule",
      "schemaVersion": 1,
      "tables": [
        {
          "name": "课程表名称",
          "semesterStart": "YYYY-MM-DD",
          "totalWeeks": 18,
          "hasWeekendCourses": false,
          "reminderMinutes": 30,
          "reminderStyle": "notification",
          "colorHex": "#0F77FF",
          "isActive": true,
          "periods": [ { "index": 1, "start": "08:00", "end": "08:45" } ],
          "courses": [ CourseObject ]
        }
      ]
    }

    CourseObject 字段（每一行代表一个「上课时段」，同一门课若有多个时段要输出多条、共用同一 id）：
    {
      "id": "稳定的UUID字符串",
      "name": "课程名称",
      "teacher": "教师或null",
      "location": "教室或null",
      "notes": "备注或null",
      "color": "#RRGGBB或null",
      "weekday": 1,
      "weeks": [1,2,3,4,5],
      "timingMode": "period",
      "startPeriod": 1,
      "endPeriod": 2,
      "customStart": null,
      "customEnd": null,
      "reminderMinutes": 30
    }

    规则：
    1. weekday：1=周一 … 7=周日。
    2. timingMode 只能取 "period"（按节次上课，填 startPeriod/endPeriod，customStart/customEnd 必须为 null）或 "custom"（按具体时间上课，填 customStart/customEnd，格式 "HH:mm"，startPeriod/endPeriod 必须为 null）。两种模式的字段互斥。
    3. 节次时间 periods：若图片里行头有明确时间就用它；否则若行头是「第1节…第N节」，按常见大学节次给出合理默认时间（如 08:00-08:45, 08:50-09:35, 10:00-10:45, 10:50-11:35, 13:30-14:15, 14:20-15:05, 15:30-16:15, 16:20-17:05, 18:30-19:15, 19:20-20:05）。
    4. weeks：上课周次整数数组。识别「1-16周」「2-18周」展开为完整数组；「单周/odd」取奇数周；「双周/even」取偶数周。无法判断时，用 1 到 totalWeeks 的全周。
    5. 跨多行合并的大课：起止节次取合并单元格覆盖的最小与最大节次。
    6. 同一门课名（含教师/教室相同）在不同星期或不同节次的多个时段，复用同一个 id。
    7. 未提供的字段填 null；不要臆造教师或教室。
    8. totalWeeks：从「共X周」或最大周次推断，无法判断则填 18。semesterStart 无法判断时填最近的一个周一（YYYY-MM-DD）。
    9. 课程颜色可在 "#0F77FF,#3BA55D,#E84A8A,#F5A623,#8E5BF0,#00B8C4,#EF4B4B,#5C7CFA" 中循环选取，同一门课颜色一致。
    10. 只输出 JSON，确保是合法 JSON（不要注释、不要尾随逗号）。
    """
}
