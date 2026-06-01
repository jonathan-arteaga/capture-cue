import AVFoundation
import Foundation

@MainActor
@Observable
final class PresenterCameraService: NSObject {
    var authorization: CaptureAuthorization = .unknown
    var cameras: [CameraSource] = []
    var selectedCameraID: CameraSource.ID?
    var options = PresenterOptions()
    var lastError: String?

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private var configuredDeviceID: String?
    @ObservationIgnored private let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored private let recorder = PresenterVideoRecorder()
    @ObservationIgnored private var activePresenterRecordingURL: URL?

    var selectedCamera: CameraSource? {
        guard let selectedCameraID else {
            return cameras.first
        }
        return cameras.first(where: { $0.id == selectedCameraID }) ?? cameras.first
    }

    func refreshCameras() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorization = .ready
        case .notDetermined:
            authorization = .unknown
        case .denied, .restricted:
            authorization = .denied
        @unknown default:
            authorization = .denied
        }

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video,
            position: .unspecified
        )

        cameras = discoverySession.devices.map { device in
            CameraSource(id: device.uniqueID, title: device.localizedName)
        }

        if selectedCameraID == nil || !cameras.contains(where: { $0.id == selectedCameraID }) {
            selectedCameraID = cameras.first?.id
        }

        if cameras.isEmpty {
            options.isEnabled = false
            stopPreview()
        }
    }

    func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                self?.authorization = granted ? .ready : .denied
                self?.refreshCameras()
                if granted {
                    self?.lastError = nil
                    self?.startPreviewIfNeeded()
                } else {
                    self?.options.isEnabled = false
                    self?.lastError = "macOS has not granted Camera access to CaptureCue."
                }
            }
        }
    }

    func setPresenterEnabled(_ isEnabled: Bool) {
        options.isEnabled = isEnabled

        guard isEnabled else {
            stopPreview()
            return
        }

        if authorization == .unknown {
            requestCameraAccess()
        } else if authorization == .ready {
            startPreviewIfNeeded()
        } else {
            options.isEnabled = false
            lastError = "Camera permission is required before enabling presenter mode."
        }
    }

    func startPreviewIfNeeded() {
        guard options.isEnabled,
              authorization == .ready,
              let selectedCameraID else {
            return
        }

        if configuredDeviceID != selectedCameraID {
            configureSession(deviceID: selectedCameraID)
        }

        if !session.isRunning {
            session.startRunning()
        }
    }

    func stopPreview() {
        guard !recorder.isRecording else {
            return
        }

        if session.isRunning {
            session.stopRunning()
        }
    }

    func updateSelectedCamera(_ id: CameraSource.ID?) {
        selectedCameraID = id
        configuredDeviceID = nil
        if options.isEnabled {
            startPreviewIfNeeded()
        }
    }

    private func configureSession(deviceID: String) {
        session.beginConfiguration()
        session.sessionPreset = .high

        for input in session.inputs {
            session.removeInput(input)
        }

        if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(recorder, queue: recorder.queue)
            session.addOutput(videoOutput)
        }

        defer {
            session.commitConfiguration()
        }

        guard let device = AVCaptureDevice(uniqueID: deviceID) else {
            lastError = "Selected camera is no longer available."
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                configuredDeviceID = deviceID
                lastError = nil
            } else {
                lastError = "CaptureCue could not use the selected camera."
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func startCompanionRecording() throws -> PresenterRecordingAsset? {
        guard options.isEnabled else {
            return nil
        }

        guard authorization == .ready else {
            lastError = "Camera permission is required before recording presenter video."
            return nil
        }

        guard selectedCameraID != nil else {
            lastError = "Choose a camera before recording presenter video."
            return nil
        }

        startPreviewIfNeeded()

        guard !recorder.isRecording else {
            guard let activePresenterRecordingURL else {
                return nil
            }
            return PresenterRecordingAsset(
                url: activePresenterRecordingURL,
                placement: options.placement,
                size: options.size
            )
        }

        let outputURL = try makePresenterRecordingURL()
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        activePresenterRecordingURL = outputURL
        try recorder.startRecording(to: outputURL)
        return PresenterRecordingAsset(url: outputURL, placement: options.placement, size: options.size)
    }

    func stopCompanionRecording() {
        recorder.stopRecording()
    }

    private func makePresenterRecordingURL() throws -> URL {
        let moviesDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        let directory = moviesDirectory.appending(path: "CaptureCue/Presenter", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Presenter-\(Int(Date.now.timeIntervalSince1970)).mov")
    }
}

private final class PresenterVideoRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.jonathanarteaga.CaptureCue.presenter-recorder")

    private(set) var isRecording = false
    private var outputURL: URL?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var firstSampleTime: CMTime?
    private var finishRequested = false

    func startRecording(to outputURL: URL) throws {
        queue.sync {
            resetWriterState()
            self.outputURL = outputURL
            isRecording = true
        }
    }

    func stopRecording() {
        queue.async {
            guard self.isRecording || self.writer != nil else {
                return
            }

            self.isRecording = false
            self.finishRequested = true
            self.videoInput?.markAsFinished()

            guard let writer = self.writer else {
                self.resetWriterState()
                return
            }

            self.resetWriterState()
            writer.finishWriting {}
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isRecording, !finishRequested else {
            return
        }

        do {
            if writer == nil {
                try startWriter(from: sampleBuffer)
            }

            guard let writer,
                  writer.status == .writing,
                  let videoInput,
                  videoInput.isReadyForMoreMediaData else {
                return
            }

            videoInput.append(sampleBuffer)
        } catch {
            isRecording = false
            resetWriterState()
        }
    }

    private func startWriter(from sampleBuffer: CMSampleBuffer) throws {
        guard let outputURL,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(dimensions.width),
                AVVideoHeightKey: Int(dimensions.height)
            ],
            sourceFormatHint: formatDescription
        )
        videoInput.expectsMediaDataInRealTime = true

        if writer.canAdd(videoInput) {
            writer.add(videoInput)
        }

        let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        writer.startWriting()
        writer.startSession(atSourceTime: startTime)

        self.writer = writer
        self.videoInput = videoInput
        self.firstSampleTime = startTime
    }

    private func resetWriterState() {
        outputURL = nil
        writer = nil
        videoInput = nil
        firstSampleTime = nil
        finishRequested = false
        isRecording = false
    }
}
