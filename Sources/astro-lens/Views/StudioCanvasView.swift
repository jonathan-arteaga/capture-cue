import AppKit
import AVKit
import SwiftUI

struct StudioCanvasView: View {
    var store: StudioStore
    var captureService: ScreenCaptureService
    var presenterService: PresenterCameraService

    private var project: StudioProject {
        store.selectedProject
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .white.opacity(0.70),
                    AstroTheme.aqua.opacity(0.10),
                    AstroTheme.amber.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 14) {
                Spacer(minLength: 8)

                PreviewStage(project: project, captureService: captureService, presenterService: presenterService)
                    .padding(.horizontal, 36)

                if let suggestion = captureService.recoverySuggestion {
                    ModernPermissionBanner(suggestion: suggestion, captureService: captureService)
                        .padding(.horizontal, 48)
                }

                RecordingDock(captureService: captureService, presenterService: presenterService)
                    .padding(.horizontal, 48)

                Spacer(minLength: 18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: AstroTheme.ink.opacity(0.10), radius: 24, y: 14)
    }
}

private struct PreviewStage: View {
    let project: StudioProject
    var captureService: ScreenCaptureService
    var presenterService: PresenterCameraService

    var body: some View {
        ZStack {
            CanvasBackdrop(style: project.canvasStyle)

            VStack(spacing: 0) {
                PreviewChrome(project: project, captureService: captureService)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AstroTheme.ink)

                    PreviewContent(project: project, captureService: captureService, presenterService: presenterService)
                        .padding(18)
                }
                .padding([.horizontal, .bottom], 12)
            }
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(16)
        }
        .aspectRatio(project.exportPreset == .vertical ? 9.0 / 16.0 : 16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: project.exportPreset == .vertical ? 560 : 1160)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: AstroTheme.ink.opacity(0.22), radius: 30, y: 18)
    }
}

private struct ModernPermissionBanner: View {
    let suggestion: CaptureRecoverySuggestion
    var captureService: ScreenCaptureService

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AstroTheme.amber)
                .frame(width: 36, height: 36)
                .background(AstroTheme.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AstroTheme.ink)
                Text(suggestion.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AstroTheme.ink.opacity(0.52))
                    .lineLimit(2)
            }

            Spacer()

            if let secondaryActionTitle = suggestion.secondaryActionTitle {
                Button(secondaryActionTitle) {
                    Task {
                        await captureService.recoverCaptureSetup()
                    }
                }
                .buttonStyle(AstroSecondaryButtonStyle())
            }

            Button(suggestion.primaryActionTitle) {
                performPrimaryAction()
            }
            .buttonStyle(AstroPrimaryButtonStyle(color: AstroTheme.amber))
        }
        .padding(10)
        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AstroTheme.amber.opacity(0.26), lineWidth: 1)
        }
    }

    private var symbolName: String {
        switch suggestion.kind {
        case .screenPermission:
            "rectangle.on.rectangle.slash"
        case .microphonePermission:
            "mic.slash"
        case .sourceSelection:
            "display.trianglebadge.exclamationmark"
        case .failedCapture:
            "exclamationmark.triangle"
        }
    }

    private func performPrimaryAction() {
        switch suggestion.kind {
        case .screenPermission:
            SystemSettingsLinks.openScreenRecordingPrivacy()
        case .microphonePermission:
            SystemSettingsLinks.openMicrophonePrivacy()
        case .sourceSelection, .failedCapture:
            Task {
                await captureService.recoverCaptureSetup()
            }
        }
    }
}

private struct PreviewChrome: View {
    let project: StudioProject
    var captureService: ScreenCaptureService

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(AstroTheme.coral).frame(width: 9, height: 9)
            Circle().fill(AstroTheme.amber).frame(width: 9, height: 9)
            Circle().fill(AstroTheme.mint).frame(width: 9, height: 9)

            Text(project.title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
                .padding(.leading, 8)

            Spacer()

            RecordingStatusBadge(
                state: captureService.sessionState,
                metrics: captureService.metrics,
                showsDetail: false
            )
        }
    }
}

private struct PreviewContent: View {
    let project: StudioProject
    var captureService: ScreenCaptureService
    var presenterService: PresenterCameraService

    private var latestRecordingClip: StudioClip? {
        project.latestRecordingClip
    }

    private var hasMedia: Bool {
        latestRecordingClip?.assetURL != nil || project.latestReferenceSnapshot != nil
    }

    var body: some View {
        ZStack {
            if let latestRecordingClip,
               latestRecordingClip.assetURL != nil {
                RecordingPlayerView(clip: latestRecordingClip)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RedactionPreviewOverlay(regions: latestRecordingClip.redactionRegions)
                    }
                    .overlay {
                        LinearGradient(
                            colors: [.black.opacity(0.45), .clear, .black.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            } else if let snapshot = project.latestReferenceSnapshot {
                StudioSnapshotImage(url: snapshot.url)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        LinearGradient(
                            colors: [.black.opacity(0.24), .clear, .black.opacity(0.38)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            } else {
                ModernPreviewPlaceholder()
            }

            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(previewTitle)
                            .font(.system(size: hasMedia ? 18 : 22, weight: .bold))
                        Text(previewDetail)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .opacity(hasMedia ? 1 : 0)

                if project.hasCaption {
                    CaptionPreviewOverlay(project: project)
                }

                if latestRecordingClip?.hasTrim == true {
                    StatusChip(title: "Trimmed", symbolName: "scissors")
                }

                if let latestRecordingClip,
                   latestRecordingClip.hasRedactions {
                    StatusChip(title: "\(latestRecordingClip.redactionRegions.count) privacy mask\(latestRecordingClip.redactionRegions.count == 1 ? "" : "s")", symbolName: "eye.slash")
                }

                if let snapshot = project.latestReferenceSnapshot {
                    StatusChip(title: snapshot.title, symbolName: "photo")
                }

                Spacer()

                HStack(spacing: 10) {
                    Image(systemName: captureService.selectedSource?.kind.symbolName ?? "display")
                        .foregroundStyle(.white.opacity(0.56))
                    Text(captureService.selectedSource?.title ?? "No source selected")
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)

                    Spacer()

                    Text(captureService.metrics.frameReadout)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.44))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .foregroundStyle(.white)

            if presenterService.options.isEnabled {
                PresenterOverlayView(presenterService: presenterService)
            }
        }
    }

    private var previewTitle: String {
        if latestRecordingClip != nil {
            return "Latest recording"
        }
        if project.latestReferenceSnapshot != nil {
            return "Reference snapshot"
        }
        return "Ready to record"
    }

    private var previewDetail: String {
        if !project.notes.isEmpty {
            return project.notes
        }
        if project.latestReferenceSnapshot != nil {
            return "Use this snapshot as context, then record the flow."
        }
        return "Choose a source and start recording."
    }
}

private struct ModernPreviewPlaceholder: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.20), lineWidth: 1)
                    .frame(width: 270, height: 160)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AstroTheme.brandWash)
                    .frame(width: 230, height: 126)
                LogoMark(size: 42)
            }

            VStack(spacing: 5) {
                Text("Ready to record")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text("Pick a source, press Record, then polish the result in one place.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StatusChip: View {
    let title: String
    let symbolName: String

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .lineLimit(1)
    }
}

private struct StudioSnapshotImage: View {
    let url: URL

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(22)
        } else {
            Image(systemName: "photo")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
        }
    }
}

private struct PresenterOverlayView: View {
    var presenterService: PresenterCameraService

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height) * presenterService.options.size
            let margin = max(proxy.size.width, proxy.size.height) * 0.035

            Group {
                if presenterService.authorization == .ready {
                    CameraPreviewView(session: presenterService.session)
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.84), lineWidth: 3)
                        }
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                        .onAppear {
                            presenterService.startPreviewIfNeeded()
                        }
                } else {
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.5))
                        Image(systemName: "camera")
                            .font(.system(size: diameter * 0.28, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .frame(width: diameter, height: diameter)
            .position(position(in: proxy.size, diameter: diameter, margin: margin))
        }
    }

    private func position(in size: CGSize, diameter: CGFloat, margin: CGFloat) -> CGPoint {
        switch presenterService.options.placement {
        case .bottomRight:
            CGPoint(x: size.width - diameter / 2 - margin, y: size.height - diameter / 2 - margin)
        case .bottomLeft:
            CGPoint(x: diameter / 2 + margin, y: size.height - diameter / 2 - margin)
        case .topRight:
            CGPoint(x: size.width - diameter / 2 - margin, y: diameter / 2 + margin)
        }
    }
}

private struct CaptionPreviewOverlay: View {
    let project: StudioProject

    var body: some View {
        GeometryReader { proxy in
            Text(project.captionTextValue)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .frame(maxWidth: min(proxy.size.width * 0.76, 620))
                .background(.black.opacity(0.54), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
                .position(position(in: proxy.size))
        }
        .allowsHitTesting(false)
    }

    private func position(in size: CGSize) -> CGPoint {
        switch project.selectedCaptionPlacement {
        case .lower:
            CGPoint(x: size.width / 2, y: size.height * 0.76)
        case .center:
            CGPoint(x: size.width / 2, y: size.height * 0.52)
        case .upper:
            CGPoint(x: size.width / 2, y: size.height * 0.26)
        }
    }
}

private struct RedactionPreviewOverlay: View {
    let regions: [RedactionRegion]

    var body: some View {
        GeometryReader { proxy in
            ForEach(regions) { region in
                let rect = CGRect(
                    x: proxy.size.width * region.x,
                    y: proxy.size.height * region.y,
                    width: proxy.size.width * region.width,
                    height: proxy.size.height * region.height
                )

                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.black.opacity(0.72))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.38), lineWidth: 1)
                    Text(region.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8)
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct RecordingPlayerView: NSViewRepresentable {
    let clip: StudioClip

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = context.coordinator.player
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        if playerView.player !== context.coordinator.player {
            playerView.player = context.coordinator.player
        }
        playerView.controlsStyle = .none
        context.coordinator.configurePlayer(for: clip)
    }

    static func dismantleNSView(_ playerView: AVPlayerView, coordinator: Coordinator) {
        coordinator.stop()
        playerView.player = nil
    }

    final class Coordinator {
        let player = AVPlayer()
        private var configuredClip: StudioClip?
        private var timeObserver: Any?

        func configurePlayer(for clip: StudioClip) {
            guard configuredClip != clip,
                  let url = clip.assetURL else {
                return
            }

            configuredClip = clip
            removeLoopObserver()
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.actionAtItemEnd = .none
            player.seek(to: startTime(for: clip), toleranceBefore: .zero, toleranceAfter: .zero)
            installLoopObserver(for: clip)
        }

        func stop() {
            player.pause()
            removeLoopObserver()
            player.replaceCurrentItem(with: nil)
            configuredClip = nil
        }

        private func startTime(for clip: StudioClip) -> CMTime {
            CMTime(seconds: clip.trimStartValue, preferredTimescale: 600)
        }

        private func installLoopObserver(for clip: StudioClip) {
            let interval = CMTime(seconds: 0.08, preferredTimescale: 600)
            let loopStartTime = startTime(for: clip)
            let loopEndSeconds = clip.trimStartValue + clip.effectiveDuration
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [player] time in
                if time.seconds >= loopEndSeconds {
                    player.seek(to: loopStartTime, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
        }

        private func removeLoopObserver() {
            if let timeObserver {
                player.removeTimeObserver(timeObserver)
                self.timeObserver = nil
            }
        }
    }
}

private struct RecordingDock: View {
    var captureService: ScreenCaptureService
    var presenterService: PresenterCameraService

    private var canStartRecording: Bool {
        captureService.canStartRecording(presenterService: presenterService)
    }

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(captureService.sources) { source in
                    Button {
                        captureService.selectedSourceID = source.id
                    } label: {
                        Label(source.title, systemImage: source.kind.symbolName)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: captureService.selectedSource?.kind.symbolName ?? "display")
                    Text(captureService.selectedSource?.title ?? "Choose source")
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AstroTheme.ink.opacity(0.36))
                }
                .frame(maxWidth: 260, alignment: .leading)
            }
            .buttonStyle(AstroSecondaryButtonStyle())

            Button {
                Task {
                    await captureService.refreshSources()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(AstroIconButtonStyle())
            .help("Refresh capture sources")

            Spacer()

            if captureService.authorization != .ready {
                Button("Allow") {
                    captureService.requestScreenAccess()
                    Task {
                        await captureService.refreshSources()
                    }
                }
                .buttonStyle(AstroSecondaryButtonStyle())
            }

            Button {
                Task {
                    await captureService.toggleRecording()
                }
            } label: {
                Label(
                    captureService.sessionState.isActive ? "Stop Recording" : "Start Recording",
                    systemImage: captureService.sessionState.isActive ? "stop.fill" : "record.circle"
                )
            }
            .buttonStyle(AstroPrimaryButtonStyle(color: captureService.sessionState.isActive ? AstroTheme.coral : AstroTheme.aqua))
            .disabled(captureService.sessionState == .preparing || captureService.sessionState == .stopping || (!captureService.sessionState.isActive && !canStartRecording))
        }
        .padding(10)
        .glassPanel()
    }
}

private struct CanvasBackdrop: View {
    let style: CanvasStyle

    var body: some View {
        switch style {
        case .aurora:
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.06, blue: 0.12),
                    AstroTheme.aqua.opacity(0.32),
                    Color(red: 0.52, green: 0.70, blue: 0.95).opacity(0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .graphite:
            LinearGradient(colors: [AstroTheme.ink, Color(red: 0.22, green: 0.24, blue: 0.26)], startPoint: .top, endPoint: .bottom)
        case .cloud:
            LinearGradient(colors: [.white.opacity(0.72), AstroTheme.aqua.opacity(0.18), AstroTheme.mint.opacity(0.20)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .focus:
            LinearGradient(colors: [AstroTheme.midnight, AstroTheme.amber.opacity(0.18), AstroTheme.aqua.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
