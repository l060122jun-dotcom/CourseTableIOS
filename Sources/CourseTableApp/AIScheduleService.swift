import Foundation
import UIKit
import CourseTableCore

/// Talks to an OpenAI-compatible chat-completions endpoint to turn a course
/// table image **or** an Excel sheet into a structured draft that matches the
/// canonical `.lcs` format. Nothing is written until the user confirms.
///
/// Endpoint/key/model come from `AIScheduleConfig`, which reads Info.plist
/// (`AIBaseURL` / `AIAPIKey` / `AIModel`) and can be overridden at runtime.
struct AIScheduleConfig: Sendable {
    var baseURL: URL
    var apiKey: String
    var model: String

    static var `default`: AIScheduleConfig {
        let info = Bundle.main.infoDictionary ?? [:]
        let urlString = (info["AIBaseURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (info["AIAPIKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (info["AIModel"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIScheduleConfig(
            baseURL: URL(string: (urlString?.isEmpty == false ? urlString! : "http://43.226.36.44:8317/v1"))!,
            apiKey: (key?.isEmpty == false ? key! : "123456"),
            model: (model?.isEmpty == false ? model! : "codex/gpt-6-luna")
        )
    }
}

enum AIScheduleError: LocalizedError {
    case badResponse
    case http(Int, String)
    case emptyResult
    case decoding(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .badResponse: return "AI 服务返回了无法解析的内容。"
        case .http(let code, let body): return "AI 服务错误（HTTP \(code)）：\(body.prefix(180))"
        case .emptyResult: return "AI 未识别到任何课程。"
        case .decoding(let message): return "解析 AI 结果失败：\(message)"
        case .cancelled: return "已取消识别。"
        }
    }
}

final class AIScheduleService {
    private let config: AIScheduleConfig
    init(config: AIScheduleConfig = .default) { self.config = config }

    // MARK: Image

    func recognize(image: UIImage) async throws -> OCRDraft {
        // Downscale large screenshots so the base64 payload stays within the
        // gateway's request-size limit (and speeds up the round trip).
        let prepared = ImagePreparer.prepare(image)
        guard let data = prepared.jpegData(compressionQuality: 0.72) else { throw AIScheduleError.badResponse }
        let base64 = data.base64EncodedString()
        let userContent: [[String: Any]] = [
            ["type": "text", "text": "请识别这张课程表图片，按系统要求只输出 JSON。"],
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
        ]
        let content = try await complete(userContent: userContent)
        return try AIResultParser.parse(content)
    }

    // MARK: Text (Excel / pasted grid)

    func recognize(spreadsheetText: String) async throws -> OCRDraft {
        let userContent: [[String: Any]] = [
            ["type": "text", "text": """
            以下是从 Excel 课程表解析出的内容，每行格式为「星期几 周 第X-Y节 | 单元格原文」。
            星期用数字表示：1=周一, 2=周二, 3=周三, 4=周四, 5=周五, 6=周六, 7=周日。
            请严格按行首的星期数字设置 weekday，按「第X-Y节」设置 startPeriod/endPeriod，从单元格原文中提取课程名、教师、周次、教室。只输出 JSON：

            \(spreadsheetText)
            """]
        ]
        let content = try await complete(userContent: userContent)
        return try AIResultParser.parse(content)
    }

    /// Connectivity check used by the settings screen.
    func healthCheck() async throws -> String {
        let userContent: [[String: Any]] = [["type": "text", "text": "回复两个字：正常"]]
        let content = try await complete(userContent: userContent, temperature: 0)
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Networking

    private func complete(userContent: [[String: Any]], temperature: Double = 0.1) async throws -> String {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": config.model,
            "temperature": temperature,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": userContent]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIScheduleError.http(-1, "网络请求失败：\(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else { throw AIScheduleError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIScheduleError.http(http.statusCode, String(decoding: data, as: UTF8.self))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"],
              let content = Self.messageText(message) else {
            throw AIScheduleError.badResponse
        }
        return content
    }

    /// `message.content` is a String for most gateways but can be an array of
    /// content parts for others; handle both.
    private static func messageText(_ message: Any) -> String? {
        guard let dict = message as? [String: Any] else { return nil }
        if let text = dict["content"] as? String, !text.isEmpty { return text }
        if let parts = dict["content"] as? [[String: Any]] {
            let joined = parts.compactMap { part -> String? in
                if let text = part["text"] as? String { return text }
                if let text = (part["text"] as? [String: Any])?["value"] as? String { return text }
                return nil
            }.joined()
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    // MARK: System prompt (kept in sync with Docs/课表文件格式规范.md)

    static let systemPrompt = """
    你是《流云课表》的课程表结构化助手。用户会给你一张课程表图片，或一段从 Excel 提取的单元格文本（制表符分隔，保留行列位置）。请识别所有课程，并**只输出一个 JSON 对象**，不要解释文字，不要 markdown 代码块。

    输出结构（flowclass.schedule v1）：
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

    CourseObject（每一行代表一个"上课时段"；同一门课多个时段就输出多条）：
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
    1. weekday：1=周一 … 7=周日。**必须严格依据输入中标注的星期/日期，不要自己想当然**。Excel 输入每行以「N周」开头时，N 就是 weekday。
    2. timingMode 只能取 "period"（填 startPeriod/endPeriod，另两个为 null）或 "custom"（填 customStart/customEnd，格式 "HH:mm"，另两个为 null）。字段互斥。
    3. periods：若图片/表格行头有明确时间就用它；否则按常见大学节次给默认值（08:00-08:45, 08:50-09:35, 10:00-10:45, 10:50-11:35, 13:30-14:15, 14:20-15:05, 15:30-16:15, 16:20-17:05, 18:30-19:15, 19:20-20:05）。
    4. weeks 必须是**整数数组**（如 [1,2,3]），不要写成字符串。把"1-16周"展开为完整数组；"单周/odd"取奇数周；"双周/even"取偶数周。判断不了就用 1..totalWeeks。
    5. 合并单元格的大课：起止节次取覆盖的最小与最大节次。
    6. 同一门课（名称/教师/教室相同）在不同星期或节次的多个时段，复用同一 id。
    7. 单元格里若形如"课程名\\n[教师]\\n[周次][教室]\\n第X-Y节"，则：课程名=第一行；教师=第一个 [..]；周次=含"周"的 [..]（如 [1-16周]）；教室=含"楼/室"的 [..]（去掉外层方括号）。不要臆造。
    8. 未提供的字段填 null。
    9. totalWeeks 无法判断填 18；semesterStart 无法判断填最近的周一（YYYY-MM-DD）。
    10. 颜色可在 ["#0F77FF","#3BA55D","#E84A8A","#F5A623","#8E5BF0","#00B8C4","#EF4B4B","#5C7CFA"] 中循环取，同一门课一致。
    11. 只输出合法 JSON（无注释、无尾随逗号），且顶层必须是 {"format":"flowclass.schedule","schemaVersion":1,"tables":[...]}，不要加额外包裹层。
    12. 如果内容里确实没有任何课程信息，输出 {"tables":[]}，不要输出 error 字段。
    """
}

/// Reduces oversized photos before upload.
enum ImagePreparer {
    static func prepare(_ image: UIImage, maxDimension: CGFloat = 1600) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
