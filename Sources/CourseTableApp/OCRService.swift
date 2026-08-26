import Foundation
import Vision
import UIKit
import CourseTableCore

enum OCRServiceError: Error { case invalidImage }

final class OCRService {
    func recognize(image: UIImage) async throws -> OCRImportDraft {
        guard let cgImage = image.cgImage else { throw OCRServiceError.invalidImage }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let blocks = observations.compactMap { observation -> OCRBlock? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let box = observation.boundingBox
                    return OCRBlock(text: candidate.string, bounds: NormalizedRect(x: box.minX, y: box.minY, width: box.width, height: box.height), recognitionConfidence: Double(candidate.confidence))
                }
                let text = blocks.map(\.text).joined(separator: "\n")
                let draft = OCRImportDraft(sourceImageHash: Self.imageHash(cgImage), rawRecognizedText: text, blocks: blocks, warnings: ["识别结果需要人工确认后才会创建课程和日历提醒。"])
                continuation.resume(returning: draft)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func imageHash(_ image: CGImage) -> String { "\(image.width)x\(image.height)" }
}
