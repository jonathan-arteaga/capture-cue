import AVFoundation
import Foundation

protocol VideoImporting: Sendable {
    func importVideo(from sourceURL: URL) async throws -> RecordedCapture
}

struct VideoImportService: VideoImporting, @unchecked Sendable {
    private let fileManager: FileManager
    private let importsDirectory: URL?

    init(fileManager: FileManager = .default, importsDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.importsDirectory = importsDirectory
    }

    func importVideo(from sourceURL: URL) async throws -> RecordedCapture {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw VideoImportServiceError.missingSource(sourceURL)
        }

        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            throw VideoImportServiceError.noVideoTrack
        }

        let duration = try await asset.load(.duration)
        let importedURL = try copyIntoImportsDirectory(sourceURL)

        return RecordedCapture(
            url: importedURL,
            createdAt: .now,
            duration: max(finiteSeconds(duration), 0.1),
            sourceTitle: sourceURL.deletingPathExtension().lastPathComponent,
            fileSize: importedURL.fileSize,
            interactionEvents: []
        )
    }

    private func copyIntoImportsDirectory(_ sourceURL: URL) throws -> URL {
        let directory = try resolvedImportsDirectory()
        let destinationURL = uniqueDestinationURL(for: sourceURL, in: directory)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func resolvedImportsDirectory() throws -> URL {
        if let importsDirectory {
            try fileManager.createDirectory(at: importsDirectory, withIntermediateDirectories: true)
            return importsDirectory
        }

        let moviesDirectory = fileManager.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        let directory = moviesDirectory.appending(path: "CaptureCue/Imports", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func uniqueDestinationURL(for sourceURL: URL, in directory: URL) -> URL {
        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent.safeFileName
        let timestamp = Int(Date.now.timeIntervalSince1970)
        var candidate = directory.appending(path: "\(baseName)-imported-\(timestamp).\(fileExtension)")
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(baseName)-imported-\(timestamp)-\(suffix).\(fileExtension)")
            suffix += 1
        }

        return candidate
    }

    private func finiteSeconds(_ time: CMTime) -> TimeInterval {
        let seconds = time.seconds
        guard seconds.isFinite, seconds > 0 else {
            return 0.1
        }
        return seconds
    }
}

enum VideoImportServiceError: LocalizedError {
    case missingSource(URL)
    case noVideoTrack

    var errorDescription: String? {
        switch self {
        case .missingSource(let url):
            "The video file is missing: \(url.lastPathComponent)"
        case .noVideoTrack:
            "Choose a movie file with a video track."
        }
    }
}

private extension URL {
    var fileSize: Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.size] as? Int64 ?? 0
    }
}
