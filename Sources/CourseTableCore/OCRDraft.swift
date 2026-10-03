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

    public init(
        id: UUID = UUID(),
        text: String,
        bounds: NormalizedRect,
        recognitionConfidence: Double,
        proposedField: OCRField = .unknown,
        inferenceConfidence: Double = 0
    ) {
        self.id = id
        self.text = text
        self.bounds = bounds
        self.recognitionConfidence = recognitionConfidence
        self.proposedField = proposedField
        self.inferenceConfidence = inferenceConfidence
    }
}

/// One proposed course row produced by the OCR parser, before human review.
public struct OCRDraftCourse: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var teacher: String?
    public var location: String?
    public var weekday: Int
    public var inferredWeekExpression: String?

    public init(
        id: UUID = UUID(),
        name: String,
        teacher: String? = nil,
        location: String? = nil,
        weekday: Int = 1,
        inferredWeekExpression: String? = nil
    ) {
        self.id = id
        self.name = name
        self.teacher = teacher
        self.location = location
        self.weekday = weekday
        self.inferredWeekExpression = inferredWeekExpression
    }
}

/// The reviewable draft. Courses are never persisted straight from OCR.
public struct OCRDraft: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var rawText: String
    public var courses: [OCRDraftCourse]
    public var warnings: [String]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        rawText: String,
        courses: [OCRDraftCourse] = [],
        warnings: [String] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.rawText = rawText
        self.courses = courses
        self.warnings = warnings
        self.createdAt = createdAt
    }
}

// Backwards-compatible alias.
public typealias OCRImportDraft = OCRDraft
