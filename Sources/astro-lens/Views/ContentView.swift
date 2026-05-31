import SwiftUI

struct ContentView: View {
    var store: StudioStore
    var captureService: ScreenCaptureService
    var captureStore: CaptureStore
    var presenterService: PresenterCameraService

    @State private var selectedMode: WorkspaceMode = .studio

    var body: some View {
        ZStack {
            Rectangle()
                .fill(AstroTheme.appBackground)
                .ignoresSafeArea()

            HStack(spacing: 18) {
                CaptureRail(
                    store: store,
                    captureStore: captureStore,
                    selectedMode: $selectedMode
                )
                .frame(width: 252)

                VStack(spacing: 16) {
                    TopCommandBar(
                        store: store,
                        captureService: captureService,
                        captureStore: captureStore,
                        presenterService: presenterService,
                        selectedMode: $selectedMode
                    )

                    Group {
                        switch selectedMode {
                        case .capture:
                            SnapshotEditorView(
                                studioStore: store,
                                captureStore: captureStore,
                                selectedMode: $selectedMode
                            )
                        case .studio:
                            StudioWorkspaceView(
                                store: store,
                                captureService: captureService,
                                presenterService: presenterService
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(18)
        }
        .onAppear {
            captureStore.onOpenMarkup = {
                selectedMode = .capture
            }
            captureStore.onUseInStudio = {
                attachSelectedCaptureToStudio()
                selectedMode = .studio
            }
        }
    }

    private func attachSelectedCaptureToStudio() {
        guard let capture = captureStore.selectedCapture,
              let image = captureStore.renderedSelectedCapture() else {
            return
        }

        store.attachSnapshot(capture, image: image)
    }
}

private enum WorkspaceMode: String, CaseIterable, Identifiable {
    case studio = "Studio"
    case capture = "Capture"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .studio:
            "play.rectangle"
        case .capture:
            "camera.viewfinder"
        }
    }
}

private struct TopCommandBar: View {
    var store: StudioStore
    var captureService: ScreenCaptureService
    var captureStore: CaptureStore
    var presenterService: PresenterCameraService
    @Binding var selectedMode: WorkspaceMode

    private var canStartRecording: Bool {
        captureService.canStartRecording(presenterService: presenterService)
    }

    var body: some View {
        HStack(spacing: 14) {
            LogoMark(size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedMode == .studio ? store.selectedProject.title : captureStore.selectedCapture?.name ?? "Quick capture")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AstroTheme.ink)
                    .lineLimit(1)
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AstroTheme.ink.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer()

            WorkspaceSwitch(selectedMode: $selectedMode)

            HStack(spacing: 8) {
                Button {
                    Task { await captureStore.captureArea() }
                } label: {
                    Image(systemName: "camera.viewfinder")
                }
                .buttonStyle(AstroIconButtonStyle())
                .help("Capture area")

                Button {
                    Task { await captureStore.captureWindow() }
                } label: {
                    Image(systemName: "macwindow.on.rectangle")
                }
                .buttonStyle(AstroIconButtonStyle())
                .help("Capture window")
            }

            Button {
                Task {
                    await captureService.toggleRecording()
                }
            } label: {
                Label(
                    captureService.sessionState.isActive ? "Stop" : "Record",
                    systemImage: captureService.sessionState.isActive ? "stop.fill" : "record.circle"
                )
            }
            .buttonStyle(AstroPrimaryButtonStyle(color: captureService.sessionState.isActive ? AstroTheme.coral : AstroTheme.aqua))
            .disabled(recordButtonDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPanel()
    }

    private var statusText: String {
        switch selectedMode {
        case .studio:
            captureService.sessionState.statusDetail()
        case .capture:
            switch captureStore.status {
            case .ready:
                captureStore.globalShortcutSummary
            case .selectingArea:
                "Select an area"
            case .working(let message), .failed(let message):
                message
            }
        }
    }

    private var recordButtonDisabled: Bool {
        captureService.sessionState == .preparing
            || captureService.sessionState == .stopping
            || (!captureService.sessionState.isActive && !canStartRecording)
    }
}

private struct WorkspaceSwitch: View {
    @Binding var selectedMode: WorkspaceMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(WorkspaceMode.allCases) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    Label(mode.rawValue, systemImage: mode.symbolName)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedMode == mode ? .white : AstroTheme.ink.opacity(0.58))
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selectedMode == mode ? AnyShapeStyle(AstroTheme.ink) : AnyShapeStyle(Color.clear))
                }
            }
        }
        .padding(4)
        .background(.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AstroTheme.line, lineWidth: 1)
        }
    }
}

private struct CaptureRail: View {
    var store: StudioStore
    var captureStore: CaptureStore
    @Binding var selectedMode: WorkspaceMode

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                LogoMark(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("astro-lens")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AstroTheme.ink)
                    Text("Capture studio")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AstroTheme.ink.opacity(0.46))
                }
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    CaptureActionButton(title: "Area", symbolName: "camera.viewfinder") {
                        Task { await captureStore.captureArea() }
                    }
                    CaptureActionButton(title: "Screen", symbolName: "macwindow") {
                        Task { await captureStore.captureFullScreen() }
                    }
                }

                Button {
                    Task { await captureStore.captureWindow() }
                } label: {
                    Label("Capture Window", systemImage: "macwindow.on.rectangle")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AstroSecondaryButtonStyle())
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AstroTheme.ink.opacity(0.52))
                    Spacer()
                    Text("\(captureStore.recentCaptures.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AstroTheme.ink.opacity(0.38))
                }

                if captureStore.recentCaptures.isEmpty {
                    EmptyRecentCapturesView(captureStore: captureStore)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(captureStore.recentCaptures) { capture in
                                CaptureRailRow(
                                    capture: capture,
                                    isSelected: captureStore.selectedCaptureID == capture.id && selectedMode == .capture
                                ) {
                                    captureStore.selectCapture(id: capture.id)
                                    selectedMode = .capture
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }

            Spacer()

            Button {
                selectedMode = .studio
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundStyle(AstroTheme.aqua)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Studio")
                            .font(.system(size: 12, weight: .bold))
                        Text(store.selectedProject.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AstroTheme.ink.opacity(0.50))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AstroTheme.ink.opacity(0.28))
                }
                .padding(12)
                .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selectedMode == .studio ? AstroTheme.aqua.opacity(0.35) : AstroTheme.line, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .glassPanel()
    }
}

private struct CaptureActionButton: View {
    let title: String
    let symbolName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbolName)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AstroTheme.ink.opacity(0.78))
        .background(.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AstroTheme.line, lineWidth: 1)
        }
    }
}

private struct EmptyRecentCapturesView: View {
    var captureStore: CaptureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AstroTheme.aqua)
            Text("Screenshots stay quiet until you need them.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AstroTheme.ink.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await captureStore.captureArea() }
            } label: {
                Label("Capture Area", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AstroPrimaryButtonStyle(color: AstroTheme.ink))
        }
        .padding(12)
        .background(.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AstroTheme.line, lineWidth: 1)
        }
    }
}

private struct CaptureRailRow: View {
    let capture: CaptureItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: capture.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(capture.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(capture.kind.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AstroTheme.ink.opacity(0.42))
                }

                Spacer(minLength: 0)
            }
            .padding(8)
            .background(isSelected ? AstroTheme.aqua.opacity(0.14) : .white.opacity(0.42), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? AstroTheme.aqua.opacity(0.46) : AstroTheme.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SnapshotEditorView: View {
    var studioStore: StudioStore
    @Bindable var captureStore: CaptureStore
    @Binding var selectedMode: WorkspaceMode

    var body: some View {
        ZStack {
            Rectangle()
                .fill(AstroTheme.stageBackground)

            if let capture = captureStore.selectedCapture {
                AnnotationCanvasView(capture: capture, store: captureStore)
                    .padding(28)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }
                    .padding(.horizontal, 86)
                    .padding(.vertical, 52)

                MarkupToolDock(captureStore: captureStore)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 22)

                EditorActionDock(
                    studioStore: studioStore,
                    captureStore: captureStore,
                    selectedMode: $selectedMode
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 22)
            } else {
                EmptyCaptureState(captureStore: captureStore)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: AstroTheme.ink.opacity(0.12), radius: 24, y: 14)
    }
}

private struct MarkupToolDock: View {
    @Bindable var captureStore: CaptureStore

    var body: some View {
        VStack(spacing: 8) {
            ForEach(AnnotationTool.visibleMarkupTools) { tool in
                Button {
                    captureStore.activeTool = tool
                } label: {
                    Image(systemName: tool.symbolName)
                }
                .buttonStyle(AstroIconButtonStyle(isSelected: captureStore.activeTool == tool))
                .help(tool.rawValue)
            }

            Divider()
                .frame(width: 24)

            Button {
                captureStore.undoLastAnnotation()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(AstroIconButtonStyle())
            .help("Undo")
            .disabled(captureStore.selectedCapture?.annotations.isEmpty ?? true)

            Button {
                captureStore.deleteSelectedAnnotation()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(AstroIconButtonStyle())
            .help("Delete")
            .disabled(captureStore.selectedAnnotationID == nil)
        }
        .padding(10)
        .glassPanel()
    }
}

private struct EditorActionDock: View {
    var studioStore: StudioStore
    @Bindable var captureStore: CaptureStore
    @Binding var selectedMode: WorkspaceMode

    var body: some View {
        HStack(spacing: 10) {
            if captureStore.activeTool == .text {
                TextField("Text", text: $captureStore.activeText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(width: 180, height: 34)
                    .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Button {
                captureStore.copySelectedCapture()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(AstroSecondaryButtonStyle())

            Button {
                Task { await captureStore.saveSelectedCapture() }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(AstroSecondaryButtonStyle())

            Button {
                attachSelectedCaptureToStudio()
            } label: {
                Label("Use in Studio", systemImage: "rectangle.stack.badge.play")
            }
            .buttonStyle(AstroPrimaryButtonStyle(color: AstroTheme.aqua))
        }
        .padding(10)
        .glassPanel()
        .disabled(captureStore.selectedCapture == nil)
    }

    private func attachSelectedCaptureToStudio() {
        guard let capture = captureStore.selectedCapture,
              let image = captureStore.renderedSelectedCapture() else {
            return
        }

        studioStore.attachSnapshot(capture, image: image)
        selectedMode = .studio
    }
}

private struct EmptyCaptureState: View {
    var captureStore: CaptureStore

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(AstroTheme.aqua.opacity(0.18))
                    .frame(width: 74, height: 74)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AstroTheme.aqua)
            }

            VStack(spacing: 6) {
                Text("Capture first. Edit only when it matters.")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("astro-lens keeps screenshots quiet, then opens a focused markup surface when you ask.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await captureStore.captureArea() }
                } label: {
                    Label("Capture Area", systemImage: "camera.viewfinder")
                }
                .buttonStyle(AstroPrimaryButtonStyle(color: AstroTheme.aqua))

                Button {
                    Task { await captureStore.captureWindow() }
                } label: {
                    Label("Capture Window", systemImage: "macwindow.on.rectangle")
                }
                .buttonStyle(AstroSecondaryButtonStyle())
            }
        }
    }
}

private struct StudioWorkspaceView: View {
    var store: StudioStore
    var captureService: ScreenCaptureService
    var presenterService: PresenterCameraService

    var body: some View {
        VStack(spacing: 14) {
            StudioCanvasView(store: store, captureService: captureService, presenterService: presenterService)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            StudioBottomDock(store: store)
        }
    }
}

private struct StudioBottomDock: View {
    var store: StudioStore

    var body: some View {
        HStack(spacing: 14) {
            if let latestRecordingClip = store.selectedProject.latestRecordingClip {
                HStack(spacing: 10) {
                    Image(systemName: "video.fill")
                        .foregroundStyle(AstroTheme.aqua)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Latest recording")
                            .font(.system(size: 12, weight: .bold))
                        Text(latestRecordingClip.effectiveDuration.formattedDuration)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(AstroTheme.ink.opacity(0.48))
                    }
                }
            } else {
                Label("Record a clip to start the studio timeline.", systemImage: "sparkles.tv")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AstroTheme.ink.opacity(0.58))
            }

            Spacer()

            ExportPanel(store: store)
                .frame(width: 260)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPanel()
    }
}

private struct ExportPanel: View {
    var store: StudioStore

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .trailing, spacing: 2) {
                if let progress = store.exportProgress {
                    Text(progress.stage)
                } else if let error = store.exportError {
                    Text(error)
                        .foregroundStyle(AstroTheme.coral)
                } else {
                    Text(store.exportReadiness.blockingMessage ?? "Ready to export")
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AstroTheme.ink.opacity(0.48))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)

            Button {
                Task { await store.exportSelectedProject() }
            } label: {
                Label(store.isExporting ? "Rendering" : "Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(AstroPrimaryButtonStyle(color: AstroTheme.ink))
            .disabled(!store.exportReadiness.canExport || store.isExporting)
        }
    }
}
