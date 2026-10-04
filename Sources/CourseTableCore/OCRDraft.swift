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

/// One proposed course row produced by OCR / AI parsing, before human review.
/// Carries enough fields to round-trip into the canonical schedule file.
public struct OCRDraftCourse: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var teacher: String?
    public var location: String?
    public var notes: String?
    public var color: String?
    public var weekday: Int
    public var weeks: [Int]?
    public var timingMode: String?
    public var startPeriod: Int?
    public var endPeriod: Int?
    public var customStart: String?
    public var customEnd: String?
    public var inferredWeekExpression: String?

    public init(
        id: UUID = UUID(),
        name: String,
        teacher: String? = nil,
        location: String? = nil,
        notes: String? = nil,
        color: String? = nil,
        weekday: Int = 1,
        weeks: [Int]? = nil,
        timingMode: String? = nil,
        startPeriod: Int? = nil,
        endPeriod: Int? = nil,
        customStart: String? = nil,
        customEnd: String? = nil,
        inferredWeekExpression: String? = nil
    ) {
        self.id = id
        self.name = name
        self.teacher = teacher
        self.location = location
        self.notes = notes
        self.color = color
        self.weekday = weekday
        self.weeks = weeks
        self.timingMode = timingMode
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
        self.customStart = customStart
        self.customEnd = customEnd
        self.inferredWeekExpression = inferredWeekExpression
    }
}

/// The reviewable draft. Courses are never persisted straight from OCR/AI.
public struct OCRDraft: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var rawText: String
    public var courses: [OCRDraftCourse]
    public var warnings: [String]
    /// Suggested term metadata parsed from the source (nil when unknown).
    public var suggestedTotalWeeks: Int?
    public var suggestedSemesterStart: String?
    public var suggestedTableName: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        rawText: String,
        courses: [OCRDraftCourse] = [],
        warnings: [String] = [],
        suggestedTotalWeeks: Int? = nil,
        suggestedSemesterStart: String? = nil,
        suggestedTableName: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.rawText = rawText
        self.courses = courses
        self.warnings = warnings
        self.suggestedTotalWeeks = suggestedTotalWeeks
        self.suggestedSemesterStart = suggestedSemesterStart
        self.suggestedTableName = suggestedTableName
        self.createdAt = createdAt
    }
}

// Backwards-compatible alias.
public typealias OCRImportDraft = OCRDraft
