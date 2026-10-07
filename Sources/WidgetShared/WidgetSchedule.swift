import Foundation

struct WidgetLesson: Codable, Identifiable {
    var id: String
    var name: String
    var location: String?
    var start: Date
    var end: Date
}

struct WidgetSchedule: Codable {
    static let group = "group.afb348e7f6c44a9e.1"
    static let filename = "widget-schedule.json"
    var tableName: String
    var lessons: [WidgetLesson]
    var updatedAt: Date

    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent(filename)
    }
    static func load() -> WidgetSchedule? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}
