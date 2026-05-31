import AppKit
import Vision

struct SensitiveTextMatch: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let confidence: VNConfidence
    let boundingBox: CGRect

    var redactionAnnotation: CaptureAnnotation {
        CaptureAnnotation(
            tool: .redact,
            start: CGPoint(x: boundingBox.minX, y: 1 - boundingBox.maxY),
            end: CGPoint(x: boundingBox.maxX, y: 1 - boundingBox.minY),
            text: "",
            stepNumber: 0
        )
    }

    static func == (lhs: SensitiveTextMatch, rhs: SensitiveTextMatch) -> Bool {
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

struct SensitiveTextDetectionService {
    private let textRecognitionService = TextRecognitionService()

    func detect(in image: NSImage) async throws -> [SensitiveTextMatch] {
        try await textRecognitionService.recognize(in: image)
            .filter { SensitivePatternMatcher.isSensitive($0.text) }
            .map { recognizedText in
                SensitiveTextMatch(
                    text: recognizedText.text,
                    confidence: recognizedText.confidence,
                    boundingBox: recognizedText.boundingBox.expandedBy(dx: 0.006, dy: 0.006)
                )
            }
    }
}

struct SensitiveTextReviewCache {
    private var matchesByCaptureID: [CaptureItem.ID: [SensitiveTextMatch]] = [:]

    func matches(for captureID: CaptureItem.ID) -> [SensitiveTextMatch]? {
        matchesByCaptureID[captureID]
    }

    mutating func store(_ matches: [SensitiveTextMatch], for captureID: CaptureItem.ID) {
        matchesByCaptureID[captureID] = matches
    }

    mutating func remove(captureID: CaptureItem.ID) {
        matchesByCaptureID.removeValue(forKey: captureID)
    }

    mutating func remove(captureIDs: [CaptureItem.ID]) {
        captureIDs.forEach { remove(captureID: $0) }
    }

    mutating func removeAll() {
        matchesByCaptureID.removeAll()
    }
}

enum SensitiveExportGuard {
    static func uncoveredMatches(in matches: [SensitiveTextMatch], annotations: [CaptureAnnotation]) -> [SensitiveTextMatch] {
        let redactionRects = annotations
            .filter { $0.tool == .redact }
            .map(\.normalizedRect)

        return matches.filter { match in
            let matchRect = match.redactionAnnotation.normalizedRect
            return !redactionRects.contains { redactionRect in
                redactionRect.covers(matchRect)
            }
        }
    }
}

enum SensitivePatternMatcher {
    private static let patterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: #"\b(?:\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b"#),
        try! NSRegularExpression(pattern: #"\b\d{3}[- ]?\d{2}[- ]?\d{4}\b"#),
        try! NSRegularExpression(pattern: #"\b(?:\d[ -]*?){13,19}\b"#),
        try! NSRegularExpression(pattern: #"\b(?:00D|005|006|500|501|701|003)[A-Za-z0-9]{12,15}\b"#),
        try! NSRegularExpression(pattern: #"\b(?:api[_-]?key|secret|token|password|passwd|pwd)\b\s*[:=]\s*\S+"#, options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: #"\b[A-Za-z0-9_\-]{24,}\.[A-Za-z0-9_\-]{16,}\.[A-Za-z0-9_\-]{16,}\b"#)
    ]

    static func isSensitive(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return patterns.contains { pattern in
            pattern.firstMatch(in: text, range: range) != nil
        }
    }
}

private extension CaptureAnnotation {
    var normalizedRect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}

private extension CGRect {
    func expandedBy(dx: CGFloat, dy: CGFloat) -> CGRect {
        let minX = max(self.minX - dx, 0)
        let minY = max(self.minY - dy, 0)
        let maxX = min(self.maxX + dx, 1)
        let maxY = min(self.maxY + dy, 1)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func covers(_ other: CGRect) -> Bool {
        let intersection = intersection(other)
        guard !intersection.isNull, other.width > 0, other.height > 0 else { return false }
        return (intersection.width * intersection.height) / (other.width * other.height) >= 0.92
    }
}
