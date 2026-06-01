import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
@Observable
final class ScreenCaptureService: NSObject {
    var authorization: CaptureAuthorization = .unknown
    var sources: [CaptureSource] = []
    var selectedSourceID: CaptureSource.ID?
    var microphoneAuthorization: CaptureAuthorization = .unknown
    var microphones: [MicrophoneSource] = []
    var selectedMicrophoneID: MicrophoneSource.ID?
    var audioOptions = AudioCaptureOptions()
    var sessionState: RecordingState = .idle
    var metrics = CaptureMetrics()
    var lastRecordingURL: URL?
    var recordingFileSize: Int64 = 0
    var lastError: String?

    @ObservationIgnored var onRecordingFinished: ((RecordedCapture) -> Void)?
    @ObservationIgnored var onPresenterRecordingWillStart: (() throws -> PresenterRecordingAsset?)?
    @ObservationIgnored var onPresenterRecordingWillStop: (() -> Void)?
    @ObservationIgnored private var displaysByID: [String: SCDisplay] = [:]
    @ObservationIgnored private var windowsByID: [String: SCWindow] = [:]
    @ObservationIgnored private var appWindows: [SCWindow] = []
    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var recordingStartedAt: Date?
    @ObservationIgnored private var recordingSourceTitle: String?
    @ObservationIgnored private var presenterRecordingAsset: PresenterRecordingAsset?
    @ObservationIgnored private var microphoneRecordingURL: URL?
    @ObservationIgnored private var recordingFinalized = false
    @ObservationIgnored private let interactionTelemetry = InteractionTelemetryService()
    @ObservationIgnored private let recordingWriter = ScreenRecordingWriter()
    @ObservationIgnored private let sampleQueue = DispatchQueue(label: "com.jonathanarteaga.CaptureCue.capture")

    var selectedSource: CaptureSource? {
        guard let selectedSourceID else {
            return sources.first
        }
        return sources.first(where: { $0.id == selectedSourceID }) ?? sources.first
    }

    var selectedMicrophone: MicrophoneSource? {
        guard let selectedMicrophoneID else {
            return microphones.first
        }
        return microphones.first(where: { $0.id == selectedMicrophoneID }) ?? microphones.first
    }

    var audioSummary: String {
        switch (audioOptions.includeSystemAudio, audioOptions.includeMicrophone) {
        case (true, true):
            "System + mic"
        case (true, false):
            "System"
        case (false, true):
            selectedMicrophone?.title ?? "Mic"
        case (false, false):
            "Muted"
        }
    }

    var recoverySuggestion: CaptureRecoverySuggestion? {
        CaptureRecoverySuggestion.suggestion(
            authorization: authorization,
            selectedSource: selectedSource,
            microphoneRequired: audioOptions.includeMicrophone,
            microphoneAuthorization: microphoneAuthorization,
            sessionState: sessionState,
            lastError: lastError
        )
    }

    func canStartRecording(presenterService: PresenterCameraService) -> Bool {
        authorization == .ready
            && selectedSource != nil
            && (!audioOptions.includeMicrophone || microphoneAuthorization == .ready)
            && (!presenterService.options.isEnabled || presenterService.authorization == .ready)
    }

    func refreshSources() async {
        refreshMicrophones()

        guard CGPreflightScreenCaptureAccess() else {
            authorization = .denied
            sources = []
            selectedSourceID = nil
            lastError = "Grant Screen Recording once from the Capture section or macOS Privacy settings."
            return
        }

        authorization = .ready

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )

            displaysByID = Dictionary(
                uniqueKeysWithValues: content.displays.map { display in
                    let id = "display-\(display.displayID)"
                    return (id, display)
                }
            )

            windowsByID = Dictionary(
                uniqueKeysWithValues: content.windows.prefix(48).map { window in
                    let id = "window-\(window.windowID)"
                    return (id, window)
                }
            )
            appWindows = content.windows.filter {
                $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
            }

            let displaySources = content.displays.map { display in
                CaptureSource(
                    id: "display-\(display.displayID)",
                    kind: .display,
                    title: display.displayID == CGMainDisplayID() ? "Main Display" : "Display \(display.displayID)",
                    subtitle: "\(display.width)x\(display.height)",
                    pixelWidth: display.width,
                    pixelHeight: display.height,
                    captureFrame: CGDisplayBounds(display.displayID)
                )
            }

            let windowSources = content.windows
                .filter { !($0.title ?? "").isEmpty }
                .prefix(48)
                .map { window in
                    CaptureSource(
                        id: "window-\(window.windowID)",
                        kind: .window,
                        title: window.title ?? "Untitled Window",
                        subtitle: window.owningApplication?.applicationName ?? "Window",
                        pixelWidth: Int(window.frame.width),
                        pixelHeight: Int(window.frame.height),
                        captureFrame: window.frame
                    )
                }

            sources = displaySources + windowSources

            if selectedSourceID == nil || !sources.contains(where: { $0.id == selectedSourceID }) {
                selectedSourceID = sources.first?.id
            }

            lastError = nil
        } catch {
            lastError = error.localizedDescription
            authorization = .denied
        }
    }

    func refreshMicrophones() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneAuthorization = .ready
        case .notDetermined:
            microphoneAuthorization = .unknown
        case .denied, .restricted:
            microphoneAuthorization = .denied
        @unknown default:
            microphoneAuthorization = .denied
        }

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )

        microphones = discoverySession.devices.map { device in
            MicrophoneSource(id: device.uniqueID, title: device.localizedName)
        }

        if selectedMicrophoneID == nil || !microphones.contains(where: { $0.id == selectedMicrophoneID }) {
            selectedMicrophoneID = microphones.first?.id
        }

        if microphones.isEmpty {
            audioOptions.includeMicrophone = false
        }
    }

    func requestScreenAccess() {
        if CGRequestScreenCaptureAccess() {
            authorization = .ready
            lastError = nil
        } else {
            authorization = .denied
            lastError = "macOS has not granted Screen Recording to this app identity yet."
        }
    }

    func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                self?.microphoneAuthorization = granted ? .ready : .denied
                self?.refreshMicrophones()
                if !granted {
                    self?.audioOptions.includeMicrophone = false
                    self?.lastError = "macOS has not granted Microphone access to CaptureCue."
                }
            }
        }
    }

    func recoverCaptureSetup() async {
        if case .failed = sessionState {
            sessionState = .idle
        }
        lastError = nil
        await refreshSources()
    }

    func toggleRecording() async {
        if sessionState.isActive {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    func startRecording() async {
        guard !sessionState.isActive else {
            return
        }

        guard authorization == .ready else {
            lastError = "Screen Recording permission is required before recording."
            return
        }

        guard let selectedSource else {
            lastError = "Choose a screen or window before recording."
            return
        }

        if audioOptions.includeMicrophone && microphoneAuthorization != .ready {
            lastError = "Microphone permission is required before recording narration."
            return
        }

        sessionState = .preparing
        metrics = CaptureMetrics()

        do {
            let configuration = SCStreamConfiguration()
            configuration.width = max(selectedSource.pixelWidth, 1280)
            configuration.height = max(selectedSource.pixelHeight, 720)
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            configuration.showsCursor = false
            configuration.queueDepth = 6
            configuration.capturesAudio = audioOptions.includeSystemAudio
            configuration.captureMicrophone = audioOptions.includeMicrophone
            configuration.microphoneCaptureDeviceID = audioOptions.includeMicrophone ? selectedMicrophoneID : nil

            let filter: SCContentFilter
            switch selectedSource.kind {
            case .display:
                guard let display = displaysByID[selectedSource.id] else {
                    throw CaptureServiceError.sourceUnavailable
                }
                filter = SCContentFilter(display: display, excludingWindows: appWindows)
            case .window:
                guard let window = windowsByID[selectedSource.id] else {
                    throw CaptureServiceError.sourceUnavailable
                }
                filter = SCContentFilter(desktopIndependentWindow: window)
            }

            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            if audioOptions.includeSystemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            }
            if audioOptions.includeMicrophone {
                try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue)
            }

            let outputURL = try makeRecordingURL(fileExtension: "mov")
            try recordingWriter.startRecording(
                to: outputURL,
                width: configuration.width,
                height: configuration.height,
                includeSystemAudio: audioOptions.includeSystemAudio,
                includeMicrophone: audioOptions.includeMicrophone
            )
            try await stream.startCapture()

            self.stream = stream
            presenterRecordingAsset = try onPresenterRecordingWillStart?()
            lastRecordingURL = outputURL
            recordingFileSize = 0
            recordingFinalized = false
            let startedAt = Date.now
            recordingStartedAt = startedAt
            recordingSourceTitle = selectedSource.title
            interactionTelemetry.start(captureFrame: selectedSource.captureFrame)
            sessionState = .recording(startedAt: startedAt)
            lastError = nil
        } catch {
            if let stream {
                try? await stream.stopCapture()
            }
            await recordingWriter.cancelRecording()
            self.stream = nil
            onPresenterRecordingWillStop?()
            microphoneRecordingURL = nil
            presenterRecordingAsset = nil
            interactionTelemetry.cancel()
            sessionState = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard let stream else {
            sessionState = .idle
            return
        }

        sessionState = .stopping

        do {
            try await stream.stopCapture()
            let result = await recordingWriter.stopRecording()
            finalizeRecordingIfNeeded(fileSize: Int(result.fileSize), duration: result.duration)
            onPresenterRecordingWillStop?()
            self.stream = nil
            sessionState = .idle
        } catch {
            let result = await recordingWriter.stopRecording()
            finalizeRecordingIfNeeded(fileSize: Int(result.fileSize), duration: result.duration)
            self.stream = nil
            onPresenterRecordingWillStop?()
            if recordingFinalized {
                sessionState = .idle
                lastError = nil
            } else {
                interactionTelemetry.cancel()
                sessionState = .failed(error.localizedDescription)
                lastError = error.localizedDescription
            }
        }
    }

    private func makeRecordingURL(fileExtension: String) throws -> URL {
        let moviesDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        let directory = moviesDirectory.appending(path: "CaptureCue", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let timestamp = String(Int(Date.now.timeIntervalSince1970))
        return directory.appending(path: "CaptureCue-\(timestamp).\(fileExtension)")
    }

    private func finalizeRecording(fileSize: Int64, duration: TimeInterval) {
        guard !recordingFinalized else {
            return
        }

        guard let lastRecordingURL else {
            return
        }

        recordingFinalized = true

        let actualFileSize = fileSize > 0 ? fileSize : lastRecordingURL.fileSize
        let interactionEvents = interactionTelemetry.finish()
        let recording = RecordedCapture(
            url: lastRecordingURL,
            createdAt: recordingStartedAt ?? .now,
            duration: max(duration, 0.1),
            sourceTitle: recordingSourceTitle ?? lastRecordingURL.deletingPathExtension().lastPathComponent,
            fileSize: actualFileSize,
            interactionEvents: interactionEvents,
            presenterURL: presenterRecordingAsset?.url.existingFileURL,
            microphoneURL: nil,
            presenterPlacement: presenterRecordingAsset?.placement,
            presenterSize: presenterRecordingAsset?.size
        )

        onRecordingFinished?(recording)
        recordingStartedAt = nil
        recordingSourceTitle = nil
        presenterRecordingAsset = nil
        microphoneRecordingURL = nil
    }

    private func finalizeRecordingIfNeeded(fileSize: Int, duration: TimeInterval) {
        guard !recordingFinalized else {
            return
        }

        guard duration > 0.1 else {
            return
        }

        finalizeRecording(fileSize: Int64(fileSize), duration: duration)
    }
}

extension ScreenCaptureService: SCStreamOutput, SCStreamDelegate {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid else {
            return
        }

        Task { @MainActor in
            metrics.framesReceived += 1
            metrics.lastFrameAt = .now
        }
        recordingWriter.append(sampleBuffer, type: type)
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            self.stream = nil
            onPresenterRecordingWillStop?()
            interactionTelemetry.cancel()
            sessionState = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }
}

enum CaptureServiceError: LocalizedError {
    case sourceUnavailable
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            "The selected capture source is no longer available."
        case .microphoneUnavailable:
            "The selected microphone is no longer available."
        }
    }
}

private final class ScreenRecordingWriter: @unchecked Sendable {
    struct Result: Sendable {
        var fileSize: Int64
        var duration: TimeInterval
    }

    private let queue = DispatchQueue(label: "com.jonathanarteaga.CaptureCue.screen-writer")
    private var outputURL: URL?
    private var width = 1280
    private var height = 720
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var includeSystemAudio = false
    private var includeMicrophone = false
    private var firstSampleTime: CMTime?
    private var lastSampleTime: CMTime?
    private var isRecording = false

    func startRecording(
        to outputURL: URL,
        width: Int,
        height: Int,
        includeSystemAudio: Bool,
        includeMicrophone: Bool
    ) throws {
        try queue.sync {
            reset()
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            self.outputURL = outputURL
            self.width = width
            self.height = height
            self.includeSystemAudio = includeSystemAudio
            self.includeMicrophone = includeMicrophone
            isRecording = true
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        let sendableSampleBuffer = SendableSampleBuffer(sampleBuffer)
        queue.async {
            let sampleBuffer = sendableSampleBuffer.value
            guard self.isRecording, sampleBuffer.isValid else {
                return
            }

            do {
                switch type {
                case .screen:
                    try self.appendVideo(sampleBuffer)
                case .audio:
                    self.appendAudio(sampleBuffer, input: self.systemAudioInput)
                case .microphone:
                    self.appendAudio(sampleBuffer, input: self.microphoneInput)
                @unknown default:
                    return
                }
            } catch {
                self.isRecording = false
            }
        }
    }

    func stopRecording() async -> Result {
        await withCheckedContinuation { continuation in
            queue.async {
                self.isRecording = false
                self.videoInput?.markAsFinished()
                self.systemAudioInput?.markAsFinished()
                self.microphoneInput?.markAsFinished()

                guard let writer = self.writer else {
                    let result = self.result(fileSize: 0)
                    self.reset()
                    continuation.resume(returning: result)
                    return
                }

                writer.finishWriting {
                    self.queue.async {
                        let result = self.result(fileSize: self.outputURL?.fileSize ?? 0)
                        self.reset()
                        continuation.resume(returning: result)
                    }
                }
            }
        }
    }

    func cancelRecording() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.isRecording = false
                self.writer?.cancelWriting()
                self.reset()
                continuation.resume()
            }
        }
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer) throws {
        if writer == nil {
            try startWriter(from: sampleBuffer)
        }

        guard let writer,
              writer.status == .writing,
              let videoInput,
              videoInput.isReadyForMoreMediaData,
              let pixelBufferAdaptor,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            lastSampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        }
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer, input: AVAssetWriterInput?) {
        guard let writer,
              writer.status == .writing else {
            return
        }

        guard let input,
              input.isReadyForMoreMediaData else {
            return
        }

        input.append(sampleBuffer)
    }

    private func startWriter(from sampleBuffer: CMSampleBuffer) throws {
        guard let outputURL,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ],
            sourceFormatHint: formatDescription
        )
        videoInput.expectsMediaDataInRealTime = true
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }
        if includeSystemAudio {
            let input = makeAudioInput(channelCount: 2)
            if writer.canAdd(input) {
                writer.add(input)
                systemAudioInput = input
            }
        }
        if includeMicrophone {
            let input = makeAudioInput(channelCount: 1)
            if writer.canAdd(input) {
                writer.add(input)
                microphoneInput = input
            }
        }

        let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        writer.startWriting()
        writer.startSession(atSourceTime: startTime)

        self.writer = writer
        self.videoInput = videoInput
        self.pixelBufferAdaptor = pixelBufferAdaptor
        self.firstSampleTime = startTime
        self.lastSampleTime = startTime
    }

    private func makeAudioInput(channelCount: Int) -> AVAssetWriterInput {
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: channelCount,
                AVEncoderBitRateKey: 128_000
            ]
        )
        input.expectsMediaDataInRealTime = true
        return input
    }

    private func result(fileSize: Int64) -> Result {
        let duration: TimeInterval
        if let firstSampleTime,
           let lastSampleTime {
            duration = max(CMTimeSubtract(lastSampleTime, firstSampleTime).seconds, 0)
        } else {
            duration = 0
        }
        return Result(fileSize: fileSize, duration: duration)
    }

    private func reset() {
        outputURL = nil
        writer = nil
        videoInput = nil
        pixelBufferAdaptor = nil
        systemAudioInput = nil
        microphoneInput = nil
        includeSystemAudio = false
        includeMicrophone = false
        firstSampleTime = nil
        lastSampleTime = nil
        isRecording = false
    }
}

private struct SendableSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer

    init(_ value: CMSampleBuffer) {
        self.value = value
    }
}

private extension URL {
    var fileSize: Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.size] as? Int64 ?? 0
    }

    var existingFileURL: URL? {
        FileManager.default.fileExists(atPath: path) ? self : nil
    }
}
