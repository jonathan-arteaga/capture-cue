import AppKit
import Foundation

@MainActor
final class InteractionTelemetryService {
    private var startedAt: Date?
    private var events: [InteractionEvent] = []
    private var monitors: [Any] = []
    private var captureFrame: CGRect?

    var isRecording: Bool {
        startedAt != nil
    }

    func start(captureFrame: CGRect?) {
        stopMonitoringOnly()
        startedAt = .now
        events = []
        self.captureFrame = captureFrame

        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let keyMask: NSEvent.EventTypeMask = [.keyDown]

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            Task { @MainActor in
                self?.recordClick(event)
            }
        }) {
            monitors.append(monitor)
        }

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: keyMask, handler: { [weak self] event in
            Task { @MainActor in
                self?.recordKey(event)
            }
        }) {
            monitors.append(monitor)
        }

        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseMask.union(keyMask), handler: { [weak self] event in
            Task { @MainActor in
                switch event.type {
                case .keyDown:
                    self?.recordKey(event)
                default:
                    self?.recordClick(event)
                }
            }
            return event
        }) {
            monitors.append(localMonitor)
        }
    }

    func finish() -> [InteractionEvent] {
        let capturedEvents = events
        startedAt = nil
        events = []
        captureFrame = nil
        stopMonitoringOnly()
        return capturedEvents
    }

    func cancel() {
        startedAt = nil
        events = []
        captureFrame = nil
        stopMonitoringOnly()
    }

    private func stopMonitoringOnly() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
    }

    private func recordClick(_ event: NSEvent) {
        guard let startedAt else {
            return
        }

        let location = normalizedLocation(for: NSEvent.mouseLocation)
        events.append(
            .click(
                timestamp: event.timestamp(relativeTo: startedAt),
                x: location.x,
                y: location.y,
                modifiers: event.modifierFlags.privacySafeLabels
            )
        )
    }

    private func normalizedLocation(for screenLocation: CGPoint) -> CGPoint {
        guard let captureFrame,
              captureFrame.width > 0,
              captureFrame.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        let x = (screenLocation.x - captureFrame.minX) / captureFrame.width
        let y = (screenLocation.y - captureFrame.minY) / captureFrame.height

        return CGPoint(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1)
        )
    }

    private func recordKey(_ event: NSEvent) {
        guard let startedAt else {
            return
        }

        events.append(
            .keyPress(
                timestamp: event.timestamp(relativeTo: startedAt),
                label: event.privacySafeKeyLabel,
                modifiers: event.modifierFlags.privacySafeLabels
            )
        )
    }
}

private extension NSEvent {
    func timestamp(relativeTo date: Date) -> TimeInterval {
        max(Date.now.timeIntervalSince(date), 0)
    }

    var privacySafeKeyLabel: String {
        switch keyCode {
        case 36:
            "Return"
        case 48:
            "Tab"
        case 49:
            "Space"
        case 51:
            "Delete"
        case 53:
            "Escape"
        case 123:
            "Left Arrow"
        case 124:
            "Right Arrow"
        case 125:
            "Down Arrow"
        case 126:
            "Up Arrow"
        default:
            "Key press"
        }
    }
}

private extension NSEvent.ModifierFlags {
    var privacySafeLabels: [String] {
        var labels: [String] = []
        if contains(.command) {
            labels.append("Command")
        }
        if contains(.shift) {
            labels.append("Shift")
        }
        if contains(.option) {
            labels.append("Option")
        }
        if contains(.control) {
            labels.append("Control")
        }
        return labels
    }
}
