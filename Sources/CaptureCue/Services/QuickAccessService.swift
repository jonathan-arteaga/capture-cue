import AppKit
import SwiftUI

@MainActor
final class QuickAccessService {
    private var panel: NSPanel?

    func show(
        captureName: String,
        subtitle: String,
        copy: @escaping () -> Void,
        save: @escaping () -> Void,
        pin: @escaping () -> Void,
        annotate: @escaping () -> Void,
        useInStudio: (() -> Void)? = nil
    ) {
        panel?.close()

        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let size = CGSize(width: useInStudio == nil ? 330 : 376, height: 74)
        let origin = CGPoint(
            x: screenFrame.maxX - size.width - 24,
            y: screenFrame.maxY - size.height - 24
        )

        let panel = NSPanel(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: QuickAccessBubbleView(
                captureName: captureName,
                subtitle: subtitle,
                copy: { copy() },
                save: { save() },
                pin: { pin() },
                annotate: { annotate() },
                useInStudio: useInStudio
            )
        )

        self.panel = panel
        panel.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self, weak panel] in
            guard self?.panel === panel else { return }
            panel?.close()
            self?.panel = nil
        }
    }
}

private struct QuickAccessBubbleView: View {
    let captureName: String
    let subtitle: String
    let copy: () -> Void
    let save: () -> Void
    let pin: () -> Void
    let annotate: () -> Void
    let useInStudio: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            LogoMark(size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(captureName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: copy) {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy")

            Button(action: save) {
                Image(systemName: "square.and.arrow.down")
            }
            .help("Save")

            Button(action: pin) {
                Image(systemName: "pin")
            }
            .help("Pin")

            Button(action: annotate) {
                Image(systemName: "pencil")
            }
            .help("Annotate")

            if let useInStudio {
                Button(action: useInStudio) {
                    Image(systemName: "rectangle.stack.badge.play")
                }
                .help("Use in Studio")
            }
        }
        .padding(12)
        .frame(width: useInStudio == nil ? 330 : 376, height: 74)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(CaptureCueTheme.aqua.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: CaptureCueTheme.ink.opacity(0.18), radius: 22, y: 12)
    }
}
