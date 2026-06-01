import CoreGraphics
import Foundation

enum CaptureAuthorization: Equatable {
    case unknown
    case ready
    case denied

    var title: String {
        switch self {
        case .unknown:
            "Not checked"
        case .ready:
            "Ready"
        case .denied:
            "Permission needed"
        }
    }
}

enum RecordingState: Equatable {
    case idle
    case preparing
    case recording(startedAt: Date)
    case stopping
    case failed(String)

    var isActive: Bool {
        if case .recording = self {
            return true
        }
        return false
    }

    var startedAt: Date? {
        if case .recording(let startedAt) = self {
            return startedAt
        }
        return nil
    }

    func elapsedDuration(at date: Date = .now) -> TimeInterval {
        guard let startedAt else {
            return 0
        }
        return max(date.timeIntervalSince(startedAt), 0)
    }

    var title: String {
        switch self {
        case .idle:
            "Ready to record"
        case .preparing:
            "Preparing capture"
        case .recording:
            "Recording"
        case .stopping:
            "Stopping"
        case .failed:
            "Needs attention"
        }
    }

    func statusTitle(at date: Date = .now) -> String {
        switch self {
        case .idle:
            "Ready"
        case .preparing:
            "Preparing"
        case .recording:
            elapsedDuration(at: date).formattedDuration
        case .stopping:
            "Saving"
        case .failed:
            "Needs attention"
        }
    }

    func statusDetail(at date: Date = .now) -> String {
        switch self {
        case .idle:
            "Ready to record"
        case .preparing:
            "Setting up capture"
        case .recording:
            "Recording in progress"
        case .stopping:
            "Finalizing clip"
        case .failed(let message):
            message
        }
    }
}

struct CaptureRecoverySuggestion: Equatable {
    enum Kind: Equatable {
        case screenPermission
        case microphonePermission
        case sourceSelection
        case failedCapture
    }

    var kind: Kind
    var title: String
    var detail: String
    var primaryActionTitle: String
    var secondaryActionTitle: String?

    static func suggestion(
        authorization: CaptureAuthorization,
        selectedSource: CaptureSource?,
        microphoneRequired: Bool,
        microphoneAuthorization: CaptureAuthorization,
        sessionState: RecordingState,
        lastError: String?
    ) -> CaptureRecoverySuggestion? {
        if authorization != .ready {
            return CaptureRecoverySuggestion(
                kind: .screenPermission,
                title: "Screen Recording is not ready",
                detail: "Grant Screen Recording access, then refresh sources.",
                primaryActionTitle: "Open Privacy Settings",
                secondaryActionTitle: "Refresh"
            )
        }

        if microphoneRequired && microphoneAuthorization != .ready {
            return CaptureRecoverySuggestion(
                kind: .microphonePermission,
                title: "Microphone is not ready",
                detail: "Grant microphone access or turn narration off before recording.",
                primaryActionTitle: "Open Privacy Settings",
                secondaryActionTitle: "Refresh"
            )
        }

        if selectedSource == nil {
            return CaptureRecoverySuggestion(
                kind: .sourceSelection,
                title: "Choose a capture source",
                detail: "Pick a screen or window before starting a recording.",
                primaryActionTitle: "Refresh Sources",
                secondaryActionTitle: nil
            )
        }

        if case .failed = sessionState {
            return CaptureRecoverySuggestion(
                kind: .failedCapture,
                title: "Capture needs attention",
                detail: lastError ?? "The last recording attempt stopped unexpectedly.",
                primaryActionTitle: "Recover",
                secondaryActionTitle: "Refresh Sources"
            )
        }

        return nil
    }
}

struct CaptureSource: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case display
        case window

        var symbolName: String {
            switch self {
            case .display:
                "display"
            case .window:
                "macwindow"
            }
        }
    }

    let id: String
    let kind: Kind
    var title: String
    var subtitle: String
    var pixelWidth: Int
    var pixelHeight: Int
    var captureFrame: CGRect
}

struct CaptureMetrics: Equatable {
    var framesReceived = 0
    var droppedFrames = 0
    var lastFrameAt: Date?

    var frameReadout: String {
        guard framesReceived > 0 else {
            return "No frames yet"
        }
        return "\(framesReceived) frames"
    }
}

struct MicrophoneSource: Identifiable, Hashable {
    let id: String
    var title: String
}

struct AudioCaptureOptions: Equatable {
    var includeSystemAudio = false
    var includeMicrophone = false
}

struct CameraSource: Identifiable, Hashable {
    let id: String
    var title: String
}

struct PresenterOptions: Equatable {
    enum Placement: String, CaseIterable, Codable, Identifiable, Hashable {
        case bottomRight = "Bottom Right"
        case bottomLeft = "Bottom Left"
        case topRight = "Top Right"

        var id: String { rawValue }
    }

    var isEnabled = false
    var placement: Placement = .bottomRight
    var size: Double = 0.24
}
