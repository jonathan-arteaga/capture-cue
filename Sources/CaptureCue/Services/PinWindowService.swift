import AppKit
import SwiftUI

@MainActor
final class PinWindowService {
    private var windows: [UUID: NSWindow] = [:]

    func pin(id: UUID, image: NSImage, title: String, onClose: @escaping (UUID) -> Void) {
        let maxSize = CGSize(width: 520, height: 360)
        let imageSize = fittedSize(for: image.size, maxSize: maxSize)
        let frameSize = CGSize(width: imageSize.width + 20, height: imageSize.height + 48)
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let offset = CGFloat(windows.count * 18)
        let origin = CGPoint(
            x: screenFrame.maxX - frameSize.width - 32 - offset,
            y: screenFrame.maxY - frameSize.height - 96 - offset
        )

        let window = NSWindow(
            contentRect: CGRect(origin: origin, size: frameSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = NSHostingView(
            rootView: PinnedImageView(image: image, title: title) { [weak self, weak window] in
                guard let window else { return }
                window.close()
                self?.windows[id] = nil
                onClose(id)
            }
        )

        windows[id] = window
        window.orderFrontRegardless()
    }

    func focus(id: UUID) {
        windows[id]?.orderFrontRegardless()
    }

    func close(id: UUID) {
        guard let window = windows.removeValue(forKey: id) else { return }
        window.close()
    }

    func closeAll() {
        let activeWindows = windows.values
        windows.removeAll()
        activeWindows.forEach { $0.close() }
    }

    private func fittedSize(for size: CGSize, maxSize: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return maxSize }
        let scale = min(maxSize.width / size.width, maxSize.height / size.height, 1)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

private struct PinnedImageView: View {
    let image: NSImage
    let title: String
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 10)
            .frame(height: 34)

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding([.horizontal, .bottom], 10)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.separator, lineWidth: 0.5)
        }
        .contentShape(Rectangle())
    }
}
