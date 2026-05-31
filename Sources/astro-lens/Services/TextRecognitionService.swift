import AppKit
import Vision

struct RecognizedText: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let confidence: VNConfidence
    let boundingBox: CGRect

    static func == (lhs: RecognizedText, rhs: RecognizedText) -> Bool {
        lhs.id == rhs.id &&
            lhs.text == rhs.text &&
            lhs.confidence == rhs.confidence &&
            lhs.boundingBox.equalTo(rhs.boundingBox)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(text)
        hasher.combine(confidence)
        hasher.combine(boundingBox.minX)
        hasher.combine(boundingBox.minY)
        hasher.combine(boundingBox.width)
        hasher.combine(boundingBox.height)
    }
}

struct TextRecognitionService {
    func recognize(in image: NSImage) async throws -> [RecognizedText] {
        guard let cgImage = image.cgImageForVision else {
            return []
        }

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.012

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            guard let observations = request.results else {
                return []
            }

            return observations.compactMap { observation in
                guard
                    let candidate = observation.topCandidates(1).first,
                    candidate.confidence >= 0.45
                else {
                    return nil
                }

                return RecognizedText(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    boundingBox: observation.boundingBox
                )
            }
            .sortedForReadingOrder()
        }.value
    }

    static func plainText(from observations: [RecognizedText]) -> String {
        observations
            .sortedForReadingOrder()
            .map(\.text)
            .joined(separator: "\n")
    }
}

private extension Array where Element == RecognizedText {
    func sortedForReadingOrder() -> [RecognizedText] {
        sorted { lhs, rhs in
            let verticalDistance = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
            if verticalDistance < 0.025 {
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }

            return lhs.boundingBox.midY > rhs.boundingBox.midY
        }
    }
}
