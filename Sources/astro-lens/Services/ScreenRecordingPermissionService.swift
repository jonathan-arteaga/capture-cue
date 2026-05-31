import AppKit
import CoreGraphics

@MainActor
struct ScreenRecordingPermissionService {
    func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
