import AVFoundation
import SwiftUI

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewContainerView {
        let view = CameraPreviewContainerView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: CameraPreviewContainerView, context: Context) {
        nsView.previewLayer.session = session
    }
}

final class CameraPreviewContainerView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer = previewLayer
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
