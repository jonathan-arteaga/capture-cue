import AppKit
import Foundation

@MainActor
struct CaptureLibraryService {
    nonisolated static var defaultLibraryDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("astro-lens", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
    }

    private let directory: URL
    private let indexURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(directory: URL = CaptureLibraryService.defaultLibraryDirectory) {
        self.directory = directory
        indexURL = directory.appendingPathComponent("index.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func loadCaptures() -> [CaptureItem] {
        guard
            let data = try? Data(contentsOf: indexURL),
            let index = try? decoder.decode(CaptureLibraryIndex.self, from: data)
        else {
            return []
        }

        return index.captures.compactMap { stored in
            let imageURL = directory.appendingPathComponent(stored.imageFilename)
            guard let image = NSImage(contentsOf: imageURL) else { return nil }

            return CaptureItem(
                id: stored.id,
                kind: stored.kind,
                createdAt: stored.createdAt,
                image: image,
                pixelSize: stored.pixelSize.cgSize,
                name: stored.name,
                isFavorite: stored.isFavorite ?? false,
                annotations: stored.annotations.map(\.captureAnnotation)
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func saveCaptures(_ captures: [CaptureItem]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let storedCaptures = try captures.map { capture in
            let imageFilename = "\(capture.id.uuidString).png"
            let imageURL = directory.appendingPathComponent(imageFilename)
            guard let pngData = capture.image.pngData() else {
                throw CocoaError(.fileWriteUnknown)
            }
            try pngData.write(to: imageURL, options: .atomic)

            return StoredCapture(
                id: capture.id,
                kind: capture.kind,
                createdAt: capture.createdAt,
                name: capture.name,
                isFavorite: capture.isFavorite,
                pixelSize: CodableSize(capture.pixelSize),
                imageFilename: imageFilename,
                annotations: capture.annotations.map(StoredAnnotation.init)
            )
        }

        try removeOrphanedImages(keeping: Set(storedCaptures.map(\.imageFilename)))
        let data = try encoder.encode(CaptureLibraryIndex(captures: storedCaptures))
        try data.write(to: indexURL, options: .atomic)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    private func removeOrphanedImages(keeping filenames: Set<String>) throws {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in urls where url.pathExtension.lowercased() == "png" && !filenames.contains(url.lastPathComponent) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

private struct CaptureLibraryIndex: Codable {
    var captures: [StoredCapture]
}

private struct StoredCapture: Codable {
    let id: UUID
    let kind: CaptureKind
    let createdAt: Date
    let name: String
    let isFavorite: Bool?
    let pixelSize: CodableSize
    let imageFilename: String
    let annotations: [StoredAnnotation]
}

private struct StoredAnnotation: Codable {
    let id: UUID
    let tool: AnnotationTool
    let start: CodablePoint
    let end: CodablePoint
    let text: String
    let stepNumber: Int

    init(_ annotation: CaptureAnnotation) {
        id = annotation.id
        tool = annotation.tool
        start = CodablePoint(annotation.start)
        end = CodablePoint(annotation.end)
        text = annotation.text
        stepNumber = annotation.stepNumber
    }

    var captureAnnotation: CaptureAnnotation {
        CaptureAnnotation(
            id: id,
            tool: tool,
            start: start.cgPoint,
            end: end.cgPoint,
            text: text,
            stepNumber: stepNumber
        )
    }
}

private struct CodablePoint: Codable {
    let x: CGFloat
    let y: CGFloat

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

private struct CodableSize: Codable {
    let width: CGFloat
    let height: CGFloat

    init(_ size: CGSize) {
        width = size.width
        height = size.height
    }

    var cgSize: CGSize {
        CGSize(width: width, height: height)
    }
}
