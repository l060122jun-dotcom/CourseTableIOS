import Foundation

public struct NormalizedRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
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

    public init(id: UUID = UUID(), text: String, bounds: NormalizedRect, recognitionConfidence: Double, proposedField: OCRField = .unknown, inferenceConfidence: Double = 0) {
        self.id = id; self.text = text; self.bounds = bounds; self.recognitionConfidence = recognitionConfidence; self.proposedField = proposedField; self.inferenceConfidence = inferenceConfidence
    }
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

    public init(id: UUID = UUID(), sourceImageHash: String, rawRecognizedText: String, blocks: [OCRBlock] = [], proposedCourses: [Course] = [], proposedMeetingRules: [MeetingRule] = [], warnings: [String] = [], createdAt: Date = .now) {
        self.id = id; self.sourceImageHash = sourceImageHash; self.rawRecognizedText = rawRecognizedText; self.blocks = blocks; self.proposedCourses = proposedCourses; self.proposedMeetingRules = proposedMeetingRules; self.warnings = warnings; self.createdAt = createdAt
    }
}
