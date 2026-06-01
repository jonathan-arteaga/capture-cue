import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError {
    case captureUnavailable
    case invalidSelection
    case windowUnavailable

    var errorDescription: String? {
        switch self {
        case .captureUnavailable:
            "CaptureCue could not capture the screen. Check Screen Recording permission in System Settings."
        case .invalidSelection:
            "The selected area was too small to capture."
        case .windowUnavailable:
            "CaptureCue could not find a frontmost window to capture."
        }
    }
}

struct ScreenCaptureDisplaySlice: Equatable {
    let displayFrame: CGRect
    let sourceRect: CGRect
    let destinationRect: CGRect
}

struct ScreenshotCaptureService {
    func captureMainDisplay() async throws -> NSImage {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw ScreenCaptureError.captureUnavailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: Self.ownApplicationWindows(in: content))
        let configuration = SCStreamConfiguration()
        configuration.width = CGDisplayPixelsWide(display.displayID)
        configuration.height = CGDisplayPixelsHigh(display.displayID)
        configuration.showsCursor = true
        configuration.capturesAudio = false
        configuration.captureResolution = .best

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
    }

    func captureAllDisplays() async throws -> NSImage {
        let content = try await SCShareableContent.current
        guard let desktopFrame = Self.desktopFrame(displayFrames: content.displays.map(\.frame)) else {
            throw ScreenCaptureError.captureUnavailable
        }

        let displaySlices = Self.displaySlices(for: desktopFrame, displays: content.displays)
        let excludedWindows = Self.ownApplicationWindows(in: content)
        guard !displaySlices.isEmpty else {
            throw ScreenCaptureError.captureUnavailable
        }

        if displaySlices.count == 1, let displaySlice = displaySlices.first {
            return try await captureDisplaySlice(displaySlice, excludingWindows: excludedWindows)
        }

        return try await stitchedImage(for: desktopFrame, displaySlices: displaySlices, excludingWindows: excludedWindows)
    }

    func captureMainDisplay(rect: CGRect) async throws -> NSImage {
        guard rect.width >= 8, rect.height >= 8 else {
            throw ScreenCaptureError.invalidSelection
        }

        let selectionRect = rect.integral
        let content = try await SCShareableContent.current
        let displaySlices = Self.displaySlices(for: selectionRect, displays: content.displays)
        let excludedWindows = Self.ownApplicationWindows(in: content)
        guard !displaySlices.isEmpty else {
            throw ScreenCaptureError.captureUnavailable
        }

        if displaySlices.count == 1, let displaySlice = displaySlices.first {
            return try await captureDisplaySlice(displaySlice, excludingWindows: excludedWindows)
        }

        return try await stitchedImage(for: selectionRect, displaySlices: displaySlices, excludingWindows: excludedWindows)
    }

    private func captureDisplaySlice(
        _ displaySlice: (display: SCDisplay, slice: ScreenCaptureDisplaySlice),
        excludingWindows: [SCWindow]
    ) async throws -> NSImage {
        let display = displaySlice.display
        let sourceRect = displaySlice.slice.sourceRect
        let localSourceRect = CGRect(
            x: sourceRect.minX - display.frame.minX,
            y: sourceRect.minY - display.frame.minY,
            width: sourceRect.width,
            height: sourceRect.height
        ).integral
        let scale = display.frame.width > 0 ? CGFloat(CGDisplayPixelsWide(display.displayID)) / display.frame.width : (NSScreen.main?.backingScaleFactor ?? 2)
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(localSourceRect.width * scale), 1)
        configuration.height = max(Int(localSourceRect.height * scale), 1)
        configuration.sourceRect = localSourceRect
        configuration.showsCursor = true
        configuration.capturesAudio = false
        configuration.captureResolution = .best

        let filter = SCContentFilter(display: display, excludingWindows: excludingWindows)
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return NSImage(cgImage: cgImage, size: sourceRect.size)
    }

    private func stitchedImage(
        for selectionRect: CGRect,
        displaySlices: [(display: SCDisplay, slice: ScreenCaptureDisplaySlice)],
        excludingWindows: [SCWindow]
    ) async throws -> NSImage {
        var segments: [(image: NSImage, destinationRect: CGRect)] = []
        for displaySlice in displaySlices {
            let segment = try await captureDisplaySlice(displaySlice, excludingWindows: excludingWindows)
            segments.append((segment, displaySlice.slice.destinationRect))
        }

        let image = NSImage(size: selectionRect.size)
        image.lockFocus()

        for segment in segments {
            segment.image.draw(in: segment.destinationRect)
        }

        image.unlockFocus()
        return image
    }

    func captureFrontmostWindow() async throws -> NSImage {
        guard let candidate = try await availableWindows().first else {
            throw ScreenCaptureError.windowUnavailable
        }

        return try await captureWindow(id: candidate.id)
    }

    func availableWindows() async throws -> [CaptureWindowCandidate] {
        let content = try await SCShareableContent.current
        let appPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        return content.windows
            .filter { window in
                guard let app = window.owningApplication else { return false }
                return app.processID != appPID
                    && window.isOnScreen
                    && window.windowLayer == 0
                    && window.frame.width >= 160
                    && window.frame.height >= 120
            }
            .map { window in
                CaptureWindowCandidate(
                    id: window.windowID,
                    title: window.title ?? "",
                    appName: window.owningApplication?.applicationName ?? "Window",
                    frame: window.frame
                )
            }
            .sorted { lhs, rhs in
                let leftArea = lhs.frame.width * lhs.frame.height
                let rightArea = rhs.frame.width * rhs.frame.height
                return leftArea > rightArea
            }
    }

    func captureWindow(id: CGWindowID) async throws -> NSImage {
        try await captureWindow(id: id, maxPixelWidth: nil)
    }

    func captureWindowThumbnail(id: CGWindowID) async throws -> NSImage {
        try await captureWindow(id: id, maxPixelWidth: 360)
    }

    private func captureWindow(id: CGWindowID, maxPixelWidth: CGFloat?) async throws -> NSImage {
        let content = try await SCShareableContent.current
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw ScreenCaptureError.windowUnavailable
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = filter.pointPixelScale > 0 ? CGFloat(filter.pointPixelScale) : (NSScreen.main?.backingScaleFactor ?? 2)
        let pixelWidth = max(window.frame.width * scale, 1)
        let pixelHeight = max(window.frame.height * scale, 1)
        let thumbnailScale = maxPixelWidth.map { min($0 / pixelWidth, 1) } ?? 1
        configuration.width = max(Int(pixelWidth * thumbnailScale), 1)
        configuration.height = max(Int(pixelHeight * thumbnailScale), 1)
        configuration.scalesToFit = false
        configuration.preservesAspectRatio = true
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.ignoreShadowsSingleWindow = false
        configuration.captureResolution = .best

        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
    }

    static func displaySlices(for selectionRect: CGRect, displayFrames: [CGRect]) -> [ScreenCaptureDisplaySlice] {
        let selectionRect = selectionRect.integral
        return displayFrames.compactMap { displayFrame in
            let sourceRect = selectionRect.intersection(displayFrame).integral
            guard sourceRect.width >= 1, sourceRect.height >= 1 else { return nil }

            return ScreenCaptureDisplaySlice(
                displayFrame: displayFrame,
                sourceRect: sourceRect,
                destinationRect: CGRect(
                    x: sourceRect.minX - selectionRect.minX,
                    y: sourceRect.minY - selectionRect.minY,
                    width: sourceRect.width,
                    height: sourceRect.height
                )
            )
        }
    }

    static func desktopFrame(displayFrames: [CGRect]) -> CGRect? {
        guard let firstFrame = displayFrames.first else { return nil }
        return displayFrames.dropFirst().reduce(firstFrame) { partialResult, displayFrame in
            partialResult.union(displayFrame)
        }
        .integral
    }

    private static func displaySlices(
        for selectionRect: CGRect,
        displays: [SCDisplay]
    ) -> [(display: SCDisplay, slice: ScreenCaptureDisplaySlice)] {
        let slices = displaySlices(for: selectionRect, displayFrames: displays.map(\.frame))
        return slices.compactMap { slice in
            guard let display = displays.first(where: { $0.frame == slice.displayFrame }) else {
                return nil
            }

            return (display, slice)
        }
    }

    private static func ownApplicationWindows(in content: SCShareableContent) -> [SCWindow] {
        let appPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        return content.windows.filter { window in
            window.owningApplication?.processID == appPID
        }
    }
}
