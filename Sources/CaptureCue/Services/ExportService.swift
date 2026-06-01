import AppKit
@preconcurrency import AVFoundation
import Foundation
import QuartzCore

struct ExportService: Sendable {
    typealias ProgressHandler = @Sendable (ExportProgress) async -> Void

    func exportLatestRecording(
        from project: StudioProject,
        progressHandler: ProgressHandler? = nil
    ) async throws -> URL {
        await progressHandler?(.preparing)

        guard let clip = project.latestRecordingClip,
              let assetURL = clip.assetURL else {
            throw ExportServiceError.noRecording
        }

        guard FileManager.default.fileExists(atPath: assetURL.path) else {
            throw ExportServiceError.missingSource(assetURL)
        }

        await progressHandler?(ExportProgress(fraction: 0.08, stage: "Loading source media"))
        let asset = AVURLAsset(url: assetURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw ExportServiceError.noVideoTrack
        }

        let assetDuration = try await asset.load(.duration)
        let sourceTimeRange = sourceTimeRange(for: clip, assetDuration: assetDuration)
        let exportDuration = sourceTimeRange.duration
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let orientedSize = orientedVideoSize(naturalSize: naturalSize, preferredTransform: preferredTransform)
        let renderSize = project.exportPreset.renderSize
        let contentRect = contentRect(for: orientedSize, in: renderSize)

        await progressHandler?(ExportProgress(fraction: 0.2, stage: "Composing timeline"))
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportServiceError.compositionFailed
        }
        var presenterLayerInstruction: AVMutableVideoCompositionLayerInstruction?

        try compositionVideoTrack.insertTimeRange(
            sourceTimeRange,
            of: sourceVideoTrack,
            at: .zero
        )

        if let presenterURL = clip.presenterURL,
           FileManager.default.fileExists(atPath: presenterURL.path),
           let presenterInstruction = try await presenterInstruction(
                presenterURL: presenterURL,
                recordingClip: clip,
                composition: composition,
                duration: exportDuration,
                renderSize: renderSize
           ) {
            presenterLayerInstruction = presenterInstruction
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        for sourceAudioTrack in audioTracks {
            if let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                try? compositionAudioTrack.insertTimeRange(
                    sourceTimeRange,
                    of: sourceAudioTrack,
                    at: .zero
                )
            }
        }
        if let microphoneURL = clip.microphoneURL,
           FileManager.default.fileExists(atPath: microphoneURL.path) {
            try await addMicrophoneAudio(
                from: microphoneURL,
                to: composition,
                recordingClip: clip,
                duration: exportDuration
            )
        }

        await progressHandler?(ExportProgress(fraction: 0.42, stage: "Applying polish"))
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 60)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: exportDuration)
        instruction.backgroundColor = project.canvasStyle.backgroundColor.cgColor

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        let baseTransform = transform(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            contentRect: contentRect
        )
        layerInstruction.setTransform(baseTransform, at: .zero)
        applyZoomRamps(
            to: layerInstruction,
            project: project,
            recordingClip: clip,
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            contentRect: contentRect,
            baseTransform: baseTransform
        )

        if let presenterLayerInstruction {
            instruction.layerInstructions = [presenterLayerInstruction, layerInstruction]
        } else {
            instruction.layerInstructions = [layerInstruction]
        }
        videoComposition.instructions = [instruction]
        videoComposition.animationTool = animationTool(
            project: project,
            recordingClip: clip,
            renderSize: renderSize,
            contentRect: contentRect
        )

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: project.selectedExportQuality.presetName
        ) else {
            throw ExportServiceError.exportSessionUnavailable
        }

        await progressHandler?(ExportProgress(fraction: 0.68, stage: "Preparing output file"))
        let exportFormat = supportedExportFormat(
            requested: project.selectedExportFormat,
            supportedTypes: exportSession.supportedFileTypes
        )
        let destinationURL = try exportURL(for: project, format: exportFormat)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        await progressHandler?(ExportProgress(fraction: 0.78, stage: "Rendering movie"))
        try await exportSession.export(to: destinationURL, as: exportFormat.fileType)
        await progressHandler?(.completed)
        return destinationURL
    }

    private func exportURL(for project: StudioProject, format: ExportFormat) throws -> URL {
        let fileManager = FileManager.default
        let moviesDirectory = fileManager.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        let exportDirectory = moviesDirectory.appending(path: "CaptureCue/Exports", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let fileName = [
            project.title.safeFileName,
            project.exportPreset.rawValue.replacingOccurrences(of: ":", with: "x"),
            project.selectedExportQuality.rawValue.safeFileName,
            "rendered"
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "-")

        return exportDirectory.appending(path: "\(fileName).\(format.fileExtension)")
    }

    private func supportedExportFormat(requested: ExportFormat, supportedTypes: [AVFileType]) -> ExportFormat {
        if supportedTypes.contains(requested.fileType) {
            return requested
        }

        if supportedTypes.contains(.mp4) {
            return .mp4
        }

        return .mov
    }

    private func orientedVideoSize(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    private func sourceTimeRange(for clip: StudioClip, assetDuration: CMTime) -> CMTimeRange {
        let assetSeconds = finiteSeconds(assetDuration, fallback: clip.duration)
        let safeStart = min(max(clip.trimStartValue, 0), max(assetSeconds - 0.1, 0))
        let safeDuration = min(max(clip.effectiveDuration, 0.1), max(assetSeconds - safeStart, 0.1))

        return CMTimeRange(
            start: CMTime(seconds: safeStart, preferredTimescale: 600),
            duration: CMTime(seconds: safeDuration, preferredTimescale: 600)
        )
    }

    private func finiteSeconds(_ time: CMTime, fallback: TimeInterval) -> TimeInterval {
        let seconds = time.seconds
        guard seconds.isFinite, seconds > 0 else {
            return max(fallback, 0.1)
        }
        return seconds
    }

    private func contentRect(for videoSize: CGSize, in renderSize: CGSize) -> CGRect {
        let margin = min(renderSize.width, renderSize.height) * 0.09
        let safeRect = CGRect(
            x: margin,
            y: margin * 1.22,
            width: renderSize.width - margin * 2,
            height: renderSize.height - margin * 2.25
        )

        return AVMakeRect(aspectRatio: videoSize, insideRect: safeRect)
    }

    private func transform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        contentRect: CGRect
    ) -> CGAffineTransform {
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let normalizedTransform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -transformedRect.origin.x, y: -transformedRect.origin.y)
        )
        let orientedSize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let scale = min(contentRect.width / orientedSize.width, contentRect.height / orientedSize.height)

        return normalizedTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: contentRect.origin.x, y: contentRect.origin.y))
    }

    private func presenterInstruction(
        presenterURL: URL,
        recordingClip: StudioClip,
        composition: AVMutableComposition,
        duration: CMTime,
        renderSize: CGSize
    ) async throws -> AVMutableVideoCompositionLayerInstruction? {
        let presenterAsset = AVURLAsset(url: presenterURL)
        let presenterTracks = try await presenterAsset.loadTracks(withMediaType: .video)
        guard let presenterTrack = presenterTracks.first,
              let compositionTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            return nil
        }

        let presenterDuration = try await presenterAsset.load(.duration)
        let presenterSeconds = finiteSeconds(presenterDuration, fallback: duration.seconds)
        let presenterStartSeconds = min(max(recordingClip.trimStartValue, 0), max(presenterSeconds - 0.1, 0))
        let sourceSeconds = min(finiteSeconds(duration, fallback: recordingClip.effectiveDuration), max(presenterSeconds - presenterStartSeconds, 0.1))
        let sourceDuration = CMTime(seconds: sourceSeconds, preferredTimescale: 600)
        guard sourceDuration.seconds > 0 else {
            return nil
        }

        try compositionTrack.insertTimeRange(
            CMTimeRange(
                start: CMTime(seconds: presenterStartSeconds, preferredTimescale: 600),
                duration: sourceDuration
            ),
            of: presenterTrack,
            at: .zero
        )

        let naturalSize = try await presenterTrack.load(.naturalSize)
        let preferredTransform = try await presenterTrack.load(.preferredTransform)
        let orientedSize = orientedVideoSize(naturalSize: naturalSize, preferredTransform: preferredTransform)
        let rect = presenterRect(
            renderSize: renderSize,
            videoSize: orientedSize,
            placement: recordingClip.presenterPlacement ?? .bottomRight,
            size: recordingClip.presenterSize ?? 0.24
        )
        let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
        instruction.setTransform(
            transform(naturalSize: naturalSize, preferredTransform: preferredTransform, contentRect: rect),
            at: .zero
        )

        return instruction
    }

    private func addMicrophoneAudio(
        from microphoneURL: URL,
        to composition: AVMutableComposition,
        recordingClip: StudioClip,
        duration: CMTime
    ) async throws {
        let microphoneAsset = AVURLAsset(url: microphoneURL)
        let microphoneTracks = try await microphoneAsset.loadTracks(withMediaType: .audio)
        guard let microphoneTrack = microphoneTracks.first,
              let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            return
        }

        let microphoneDuration = try await microphoneAsset.load(.duration)
        let microphoneSeconds = finiteSeconds(microphoneDuration, fallback: duration.seconds)
        let microphoneStartSeconds = min(max(recordingClip.trimStartValue, 0), max(microphoneSeconds - 0.1, 0))
        let sourceSeconds = min(finiteSeconds(duration, fallback: recordingClip.effectiveDuration), max(microphoneSeconds - microphoneStartSeconds, 0.1))
        let sourceDuration = CMTime(seconds: sourceSeconds, preferredTimescale: 600)
        guard sourceDuration.seconds > 0 else {
            return
        }

        try compositionAudioTrack.insertTimeRange(
            CMTimeRange(
                start: CMTime(seconds: microphoneStartSeconds, preferredTimescale: 600),
                duration: sourceDuration
            ),
            of: microphoneTrack,
            at: .zero
        )
    }

    private func presenterRect(
        renderSize: CGSize,
        videoSize: CGSize,
        placement: PresenterOptions.Placement,
        size: Double
    ) -> CGRect {
        let diameter = min(renderSize.width, renderSize.height) * CGFloat(min(max(size, 0.14), 0.38))
        let margin = min(renderSize.width, renderSize.height) * 0.065
        let rect = AVMakeRect(
            aspectRatio: videoSize,
            insideRect: CGRect(x: 0, y: 0, width: diameter, height: diameter)
        )

        let origin: CGPoint
        switch placement {
        case .bottomRight:
            origin = CGPoint(x: renderSize.width - rect.width - margin, y: renderSize.height - rect.height - margin)
        case .bottomLeft:
            origin = CGPoint(x: margin, y: renderSize.height - rect.height - margin)
        case .topRight:
            origin = CGPoint(x: renderSize.width - rect.width - margin, y: margin)
        }

        return CGRect(origin: origin, size: rect.size)
    }

    private func animationTool(
        project: StudioProject,
        recordingClip: StudioClip,
        renderSize: CGSize,
        contentRect: CGRect
    ) -> AVVideoCompositionCoreAnimationTool {
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = true

        let backgroundLayer = CAGradientLayer()
        backgroundLayer.frame = parentLayer.bounds
        backgroundLayer.colors = project.canvasStyle.gradientColors.map(\.cgColor)
        backgroundLayer.startPoint = CGPoint(x: 0, y: 0)
        backgroundLayer.endPoint = CGPoint(x: 1, y: 1)
        parentLayer.addSublayer(backgroundLayer)

        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)

        for region in recordingClip.redactionRegions {
            parentLayer.addSublayer(redactionLayer(for: region, contentRect: contentRect))
        }

        let chromeLayer = chromeLayer(project: project, renderSize: renderSize, contentRect: contentRect)
        parentLayer.addSublayer(chromeLayer)

        if let presenterURL = recordingClip.presenterURL,
           FileManager.default.fileExists(atPath: presenterURL.path) {
            parentLayer.addSublayer(
                presenterFrameLayer(
                    recordingClip: recordingClip,
                    renderSize: renderSize
                )
            )
        }

        if project.hasCaption {
            parentLayer.addSublayer(
                captionLayer(
                    project: project,
                    renderSize: renderSize,
                    contentRect: contentRect
                )
            )
        }

        for clip in project.generatedPolishClips where clip.sourceClipID == recordingClip.id {
            switch clip.kind {
            case .keyHint:
                if let layer = keyHintLayer(for: clip, recordingClip: recordingClip, renderSize: renderSize) {
                    parentLayer.addSublayer(layer)
                }
            case .cursor:
                if let layer = cursorLayer(for: clip, recordingClip: recordingClip, contentRect: contentRect) {
                    parentLayer.addSublayer(layer)
                }
            default:
                break
            }
        }

        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
    }

    private func applyZoomRamps(
        to layerInstruction: AVMutableVideoCompositionLayerInstruction,
        project: StudioProject,
        recordingClip: StudioClip,
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        contentRect: CGRect,
        baseTransform: CGAffineTransform
    ) {
        let zoomScale = 1.08 + min(max(project.zoomIntensity, 0), 1) * 0.34

        for clip in project.generatedPolishClips where clip.kind == .zoom && clip.sourceClipID == recordingClip.id {
            guard let timing = visibleTiming(for: clip, recordingClip: recordingClip) else {
                continue
            }

            let focusedRect = focusedContentRect(
                contentRect: contentRect,
                focusX: clip.focusX ?? 0.5,
                focusY: clip.focusY ?? 0.5,
                zoomScale: zoomScale
            )
            let focusedTransform = transform(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                contentRect: focusedRect
            )

            let relativeStart = timing.start
            let rampDuration = min(0.22, timing.duration / 3)
            let holdDuration = max(timing.duration - rampDuration * 2, 0)

            layerInstruction.setTransformRamp(
                fromStart: baseTransform,
                toEnd: focusedTransform,
                timeRange: CMTimeRange(
                    start: CMTime(seconds: relativeStart, preferredTimescale: 600),
                    duration: CMTime(seconds: rampDuration, preferredTimescale: 600)
                )
            )
            layerInstruction.setTransform(
                focusedTransform,
                at: CMTime(seconds: relativeStart + rampDuration, preferredTimescale: 600)
            )
            layerInstruction.setTransformRamp(
                fromStart: focusedTransform,
                toEnd: baseTransform,
                timeRange: CMTimeRange(
                    start: CMTime(seconds: relativeStart + rampDuration + holdDuration, preferredTimescale: 600),
                    duration: CMTime(seconds: rampDuration, preferredTimescale: 600)
                )
            )
        }
    }

    private func focusedContentRect(
        contentRect: CGRect,
        focusX: Double,
        focusY: Double,
        zoomScale: Double
    ) -> CGRect {
        let scale = CGFloat(zoomScale)
        let clampedX = CGFloat(min(max(focusX, 0), 1))
        let clampedY = CGFloat(min(max(focusY, 0), 1))
        let focus = CGPoint(
            x: contentRect.minX + contentRect.width * clampedX,
            y: contentRect.minY + contentRect.height * (1 - clampedY)
        )
        let targetCenter = CGPoint(x: contentRect.midX, y: contentRect.midY)
        let scaledSize = CGSize(width: contentRect.width * scale, height: contentRect.height * scale)
        let origin = CGPoint(
            x: targetCenter.x - (focus.x - contentRect.minX) * scale,
            y: targetCenter.y - (focus.y - contentRect.minY) * scale
        )

        return CGRect(origin: origin, size: scaledSize)
    }

    private func chromeLayer(project: StudioProject, renderSize: CGSize, contentRect: CGRect) -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: renderSize)

        let titleLayer = CATextLayer()
        titleLayer.string = project.title
        titleLayer.font = NSFont.systemFont(ofSize: 28, weight: .semibold)
        titleLayer.fontSize = 28
        titleLayer.foregroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        titleLayer.contentsScale = 2
        titleLayer.alignmentMode = .left
        titleLayer.frame = CGRect(x: contentRect.minX, y: max(contentRect.minY - 54, 18), width: contentRect.width, height: 38)
        layer.addSublayer(titleLayer)

        let badgeLayer = CATextLayer()
        badgeLayer.string = "CaptureCue"
        badgeLayer.font = NSFont.monospacedSystemFont(ofSize: 18, weight: .medium)
        badgeLayer.fontSize = 18
        badgeLayer.foregroundColor = NSColor.white.withAlphaComponent(0.72).cgColor
        badgeLayer.contentsScale = 2
        badgeLayer.alignmentMode = .right
        badgeLayer.frame = CGRect(x: contentRect.maxX - 220, y: contentRect.maxY + 18, width: 220, height: 30)
        layer.addSublayer(badgeLayer)

        return layer
    }

    private func captionLayer(project: StudioProject, renderSize: CGSize, contentRect: CGRect) -> CALayer {
        let captionText = project.captionTextValue
        let maxWidth = min(contentRect.width * 0.82, renderSize.width * 0.72)
        let height: CGFloat = min(max(renderSize.height * 0.074, 76), 116)
        let x = (renderSize.width - maxWidth) / 2

        let y: CGFloat
        switch project.selectedCaptionPlacement {
        case .lower:
            y = min(contentRect.maxY - height - renderSize.height * 0.045, renderSize.height - height - 20)
        case .center:
            y = renderSize.height / 2 - height / 2
        case .upper:
            y = max(contentRect.minY + renderSize.height * 0.045, 20)
        }

        let container = CALayer()
        container.frame = CGRect(x: x, y: y, width: maxWidth, height: height)
        container.cornerRadius = 18
        container.backgroundColor = NSColor.black.withAlphaComponent(0.58).cgColor
        container.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        container.borderWidth = 1.5
        container.shadowColor = NSColor.black.cgColor
        container.shadowOpacity = 0.24
        container.shadowRadius = 16
        container.shadowOffset = CGSize(width: 0, height: 8)

        let textLayer = CATextLayer()
        textLayer.string = captionText
        textLayer.font = NSFont.systemFont(ofSize: min(max(renderSize.height * 0.03, 28), 42), weight: .semibold)
        textLayer.fontSize = min(max(renderSize.height * 0.03, 28), 42)
        textLayer.foregroundColor = NSColor.white.withAlphaComponent(0.94).cgColor
        textLayer.contentsScale = 2
        textLayer.alignmentMode = .center
        textLayer.isWrapped = true
        textLayer.truncationMode = .end
        textLayer.frame = CGRect(x: 28, y: 18, width: maxWidth - 56, height: height - 30)
        container.addSublayer(textLayer)

        return container
    }

    private func presenterFrameLayer(recordingClip: StudioClip, renderSize: CGSize) -> CALayer {
        let size = min(renderSize.width, renderSize.height) * CGFloat(min(max(recordingClip.presenterSize ?? 0.24, 0.14), 0.38))
        let margin = min(renderSize.width, renderSize.height) * 0.065
        let origin: CGPoint

        switch recordingClip.presenterPlacement ?? .bottomRight {
        case .bottomRight:
            origin = CGPoint(x: renderSize.width - size - margin, y: renderSize.height - size - margin)
        case .bottomLeft:
            origin = CGPoint(x: margin, y: renderSize.height - size - margin)
        case .topRight:
            origin = CGPoint(x: renderSize.width - size - margin, y: margin)
        }

        let layer = CAShapeLayer()
        layer.frame = CGRect(origin: origin, size: CGSize(width: size, height: size))
        layer.path = CGPath(ellipseIn: CGRect(origin: .zero, size: CGSize(width: size, height: size)), transform: nil)
        layer.fillColor = NSColor.clear.cgColor
        layer.strokeColor = NSColor.white.withAlphaComponent(0.86).cgColor
        layer.lineWidth = 5
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 8)
        return layer
    }

    private func redactionLayer(for region: RedactionRegion, contentRect: CGRect) -> CALayer {
        let safeRegion = region.clamped
        let frame = CGRect(
            x: contentRect.minX + contentRect.width * safeRegion.x,
            y: contentRect.minY + contentRect.height * safeRegion.y,
            width: contentRect.width * safeRegion.width,
            height: contentRect.height * safeRegion.height
        )

        let container = CALayer()
        container.frame = frame
        container.cornerRadius = min(max(min(frame.width, frame.height) * 0.08, 8), 18)
        container.masksToBounds = true
        container.backgroundColor = NSColor.black.withAlphaComponent(0.76).cgColor
        container.borderColor = NSColor.white.withAlphaComponent(0.32).cgColor
        container.borderWidth = 1.5

        let labelLayer = CATextLayer()
        labelLayer.string = safeRegion.label
        labelLayer.font = NSFont.systemFont(ofSize: min(max(frame.height * 0.2, 15), 24), weight: .semibold)
        labelLayer.fontSize = min(max(frame.height * 0.2, 15), 24)
        labelLayer.foregroundColor = NSColor.white.withAlphaComponent(0.82).cgColor
        labelLayer.contentsScale = 2
        labelLayer.alignmentMode = .center
        labelLayer.frame = CGRect(
            x: 10,
            y: max((frame.height - labelLayer.fontSize) / 2 - 4, 4),
            width: max(frame.width - 20, 1),
            height: labelLayer.fontSize + 8
        )
        container.addSublayer(labelLayer)

        return container
    }

    private func visibleTiming(for clip: StudioClip, recordingClip: StudioClip) -> (start: TimeInterval, duration: TimeInterval)? {
        let rawStart = clip.start - recordingClip.start
        let rawEnd = rawStart + clip.duration
        let visibleStart = max(rawStart, recordingClip.trimStartValue)
        let visibleEnd = min(rawEnd, recordingClip.trimStartValue + recordingClip.effectiveDuration)
        let visibleDuration = visibleEnd - visibleStart

        guard visibleDuration > 0.08 else {
            return nil
        }

        return (visibleStart - recordingClip.trimStartValue, visibleDuration)
    }

    private func keyHintLayer(for clip: StudioClip, recordingClip: StudioClip, renderSize: CGSize) -> CALayer? {
        guard let timing = visibleTiming(for: clip, recordingClip: recordingClip) else {
            return nil
        }

        let container = CALayer()
        let width: CGFloat = min(max(CGFloat(clip.title.count * 18 + 50), 150), renderSize.width * 0.68)
        let height: CGFloat = 58
        container.frame = CGRect(
            x: (renderSize.width - width) / 2,
            y: renderSize.height - height - 92,
            width: width,
            height: height
        )
        container.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        container.cornerRadius = 18
        container.opacity = 0

        let textLayer = CATextLayer()
        textLayer.string = clip.title
        textLayer.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        textLayer.fontSize = 24
        textLayer.foregroundColor = NSColor.white.cgColor
        textLayer.contentsScale = 2
        textLayer.alignmentMode = .center
        textLayer.frame = CGRect(x: 14, y: 13, width: width - 28, height: 32)
        container.addSublayer(textLayer)

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [0, 1, 1, 0]
        animation.keyTimes = [0, 0.16, 0.78, 1]
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + timing.start
        animation.duration = max(timing.duration, 0.8)
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        container.add(animation, forKey: "opacity")

        return container
    }

    private func cursorLayer(for clip: StudioClip, recordingClip: StudioClip, contentRect: CGRect) -> CALayer? {
        guard let timing = visibleTiming(for: clip, recordingClip: recordingClip) else {
            return nil
        }

        let focusX = CGFloat(min(max(clip.focusX ?? 0.5, 0), 1))
        let focusY = CGFloat(min(max(clip.focusY ?? 0.5, 0), 1))
        let point = CGPoint(
            x: contentRect.minX + contentRect.width * focusX,
            y: contentRect.minY + contentRect.height * (1 - focusY)
        )

        let ring = CAShapeLayer()
        ring.frame = CGRect(x: point.x - 34, y: point.y - 34, width: 68, height: 68)
        ring.path = CGPath(ellipseIn: CGRect(x: 4, y: 4, width: 60, height: 60), transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = NSColor.systemYellow.withAlphaComponent(0.92).cgColor
        ring.lineWidth = 5
        ring.opacity = 0

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1, 0]
        opacity.keyTimes = [0, 0.12, 0.72, 1]
        opacity.beginTime = AVCoreAnimationBeginTimeAtZero + timing.start
        opacity.duration = max(timing.duration, 0.45)
        opacity.isRemovedOnCompletion = false
        opacity.fillMode = .forwards

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.72, 1, 1.14]
        scale.keyTimes = [0, 0.55, 1]
        scale.beginTime = opacity.beginTime
        scale.duration = opacity.duration
        scale.isRemovedOnCompletion = false
        scale.fillMode = .forwards

        ring.add(opacity, forKey: "opacity")
        ring.add(scale, forKey: "scale")

        return ring
    }
}

enum ExportServiceError: LocalizedError {
    case noRecording
    case missingSource(URL)
    case noVideoTrack
    case compositionFailed
    case exportSessionUnavailable
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .noRecording:
            "Record a clip before exporting."
        case .missingSource(let url):
            "The recording file is missing: \(url.lastPathComponent)"
        case .noVideoTrack:
            "The recording does not contain a video track."
        case .compositionFailed:
            "CaptureCue could not prepare the export composition."
        case .exportSessionUnavailable:
            "macOS could not create a movie export session."
        case .exportFailed:
            "The rendered export did not complete."
        }
    }
}

private extension ExportPreset {
    var renderSize: CGSize {
        switch self {
        case .wide:
            CGSize(width: 1920, height: 1080)
        case .square:
            CGSize(width: 1200, height: 1200)
        case .vertical:
            CGSize(width: 1080, height: 1920)
        case .docs:
            CGSize(width: 1600, height: 1000)
        }
    }
}

private extension ExportFormat {
    var fileType: AVFileType {
        switch self {
        case .mp4:
            .mp4
        case .mov:
            .mov
        }
    }
}

private extension ExportQuality {
    var presetName: String {
        switch self {
        case .balanced:
            AVAssetExportPreset1280x720
        case .crisp:
            AVAssetExportPreset1920x1080
        case .archive:
            AVAssetExportPresetHighestQuality
        }
    }
}

private extension CanvasStyle {
    var backgroundColor: NSColor {
        switch self {
        case .aurora:
            NSColor(calibratedRed: 0.03, green: 0.09, blue: 0.18, alpha: 1)
        case .graphite:
            NSColor(calibratedWhite: 0.04, alpha: 1)
        case .cloud:
            NSColor(calibratedRed: 0.82, green: 0.94, blue: 1, alpha: 1)
        case .focus:
            NSColor(calibratedRed: 0.22, green: 0.09, blue: 0.33, alpha: 1)
        }
    }

    var gradientColors: [NSColor] {
        switch self {
        case .aurora:
            [
                NSColor(calibratedRed: 0.03, green: 0.07, blue: 0.15, alpha: 1),
                NSColor(calibratedRed: 0.02, green: 0.36, blue: 0.53, alpha: 1),
                NSColor(calibratedRed: 0.26, green: 0.18, blue: 0.66, alpha: 1)
            ]
        case .graphite:
            [
                NSColor(calibratedWhite: 0.03, alpha: 1),
                NSColor(calibratedWhite: 0.23, alpha: 1)
            ]
        case .cloud:
            [
                NSColor(calibratedRed: 0.62, green: 0.84, blue: 1, alpha: 1),
                NSColor(calibratedRed: 0.72, green: 0.95, blue: 0.86, alpha: 1),
                NSColor(calibratedWhite: 0.96, alpha: 1)
            ]
        case .focus:
            [
                NSColor(calibratedRed: 0.31, green: 0.13, blue: 0.58, alpha: 1),
                NSColor(calibratedRed: 0.75, green: 0.25, blue: 0.54, alpha: 1),
                NSColor(calibratedRed: 0.9, green: 0.54, blue: 0.24, alpha: 1)
            ]
        }
    }
}
