import Foundation

public struct NormalizedRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
}
public enum OCRField: String, Codable, Sendable {
    case unknown
    case weekday
    case period
    case time
    case courseName
    case teacher
    case location
    case weekExpression
}

public struct OCRBlock: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    public var bounds: NormalizedRect
    public var recognitionConfidence: Double
    public var proposedField: OCRField
    public var inferenceConfidence: Double
}

public struct OCRImportDraft: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var sourceImageHash: String
    public var rawRecognizedText: String
    public var blocks: [OCRBlock]
    public var proposedCourses: [Course]
    public var proposedMeetingRules: [MeetingRule]
    public var warnings: [String]
    public var createdAt: Date
}
