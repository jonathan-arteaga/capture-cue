import AppKit
import SwiftUI

struct InspectorView: View {
    var store: StudioStore
    var captureService: ScreenCaptureService
    var presenterService: PresenterCameraService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                inspectorSections
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var inspectorSections: some View {
        switch store.selectedTab {
        case .studio:
            InspectorSection(title: "Capture", symbolName: "record.circle") {
                SourceSummary(store: store, captureService: captureService)
            }

            InspectorSection(title: "Edit", symbolName: "slider.horizontal.3") {
                TrimControls(store: store)
            }

            InspectorSection(title: "Privacy", symbolName: "eye.slash") {
                RedactionControls(store: store)
            }

            InspectorSection(title: "Audio", symbolName: "waveform") {
                AudioControls(captureService: captureService)
            }

            InspectorSection(title: "Presenter", symbolName: "person.crop.circle") {
                PresenterControls(presenterService: presenterService)
            }

            InspectorSection(title: "Project", symbolName: "doc.text") {
                ProjectControls(store: store)
            }

        case .polish:
            InspectorSection(title: "Polish", symbolName: "sparkles") {
                PolishControls(store: store)
            }

            InspectorSection(title: "Privacy", symbolName: "eye.slash") {
                RedactionControls(store: store)
            }

            InspectorSection(title: "Project", symbolName: "doc.text") {
                ProjectControls(store: store)
            }

        case .export:
            InspectorSection(title: "Export", symbolName: "square.and.arrow.up") {
                ExportControls(store: store)
            }

            InspectorSection(title: "Security", symbolName: "lock.shield") {
                SecuritySummary(store: store)
            }
        }
    }
}

private struct PresenterControls: View {
    var presenterService: PresenterCameraService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Presenter camera", isOn: Binding(
                get: { presenterService.options.isEnabled },
                set: { presenterService.setPresenterEnabled($0) }
            ))
            .disabled(presenterService.cameras.isEmpty)

            HStack {
                Text("Permission")
                Spacer()
                Text(presenterService.authorization.title)
                    .foregroundStyle(presenterService.authorization == .ready ? .green : .secondary)
            }
            .font(.caption)

            if presenterService.authorization != .ready {
                Button {
                    presenterService.requestCameraAccess()
                } label: {
                    Label("Allow Camera", systemImage: "camera")
                }
                .buttonStyle(.bordered)
            }

            Picker("Camera", selection: Binding(
                get: { presenterService.selectedCameraID },
                set: { presenterService.updateSelectedCamera($0) }
            )) {
                ForEach(presenterService.cameras) { camera in
                    Text(camera.title).tag(Optional(camera.id))
                }
            }
            .disabled(presenterService.cameras.isEmpty)

            Picker("Position", selection: Binding(
                get: { presenterService.options.placement },
                set: { presenterService.options.placement = $0 }
            )) {
                ForEach(PresenterOptions.Placement.allCases) { placement in
                    Text(placement.rawValue).tag(placement)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Size")
                    Spacer()
                    Text("\(Int(presenterService.options.size * 100))%")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { presenterService.options.size },
                        set: { presenterService.options.size = $0 }
                    ),
                    in: 0.18...0.34
                )
            }

            if presenterService.cameras.isEmpty {
                Text("No camera detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastError = presenterService.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AudioControls: View {
    var captureService: ScreenCaptureService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("System audio", isOn: Binding(
                get: { captureService.audioOptions.includeSystemAudio },
                set: { captureService.audioOptions.includeSystemAudio = $0 }
            ))
            .disabled(captureService.sessionState.isActive)

            Toggle("Microphone", isOn: Binding(
                get: { captureService.audioOptions.includeMicrophone },
                set: { enabled in
                    captureService.audioOptions.includeMicrophone = enabled
                    if enabled && captureService.microphoneAuthorization == .unknown {
                        captureService.requestMicrophoneAccess()
                    }
                }
            ))
            .disabled(captureService.sessionState.isActive || captureService.microphones.isEmpty)

            HStack {
                Text("Permission")
                Spacer()
                Text(captureService.microphoneAuthorization.title)
                    .foregroundStyle(captureService.microphoneAuthorization == .ready ? .green : .secondary)
            }
            .font(.caption)

            if captureService.microphoneAuthorization != .ready {
                Button {
                    captureService.requestMicrophoneAccess()
                } label: {
                    Label("Allow Microphone", systemImage: "mic")
                }
                .buttonStyle(.bordered)
            }

            Picker("Input", selection: Binding(
                get: { captureService.selectedMicrophoneID },
                set: { captureService.selectedMicrophoneID = $0 }
            )) {
                ForEach(captureService.microphones) { microphone in
                    Text(microphone.title).tag(Optional(microphone.id))
                }
            }
            .disabled(captureService.sessionState.isActive || captureService.microphones.isEmpty)

            if captureService.microphones.isEmpty {
                Text("No microphone input detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TrimControls: View {
    var store: StudioStore

    private var latestClip: StudioClip? {
        store.selectedProject.latestRecordingClip
    }

    private var maxTrimStart: TimeInterval {
        guard let latestClip else {
            return 0
        }
        return max(latestClip.duration - latestClip.trimEndValue - 0.1, 0)
    }

    private var maxTrimEnd: TimeInterval {
        guard let latestClip else {
            return 0
        }
        return max(latestClip.duration - latestClip.trimStartValue - 0.1, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let latestClip {
                HStack {
                    Text("Duration")
                    Spacer()
                    Text(latestClip.effectiveDuration.formattedDuration)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Trim start")
                        Spacer()
                        Text(latestClip.trimStartValue.formattedDuration)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { latestClip.trimStartValue },
                            set: { value in
                                store.updateLatestRecordingTrim(start: value, end: latestClip.trimEndValue)
                            }
                        ),
                        in: 0...max(maxTrimStart, 0.1)
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Trim end")
                        Spacer()
                        Text(latestClip.trimEndValue.formattedDuration)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { latestClip.trimEndValue },
                            set: { value in
                                store.updateLatestRecordingTrim(start: latestClip.trimStartValue, end: value)
                            }
                        ),
                        in: 0...max(maxTrimEnd, 0.1)
                    )
                }

                Button {
                    store.updateLatestRecordingTrim(start: 0, end: 0)
                } label: {
                    Label("Reset Trim", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .disabled(!latestClip.hasTrim)
            } else {
                Text("No recording selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RedactionControls: View {
    var store: StudioStore
    @State private var selectedRedactionID: RedactionRegion.ID?

    private var latestClip: StudioClip? {
        store.selectedProject.latestRecordingClip
    }

    private var redactions: [RedactionRegion] {
        latestClip?.redactionRegions ?? []
    }

    private var selectedRedaction: RedactionRegion? {
        if let selectedRedactionID,
           let selected = redactions.first(where: { $0.id == selectedRedactionID }) {
            return selected
        }
        return redactions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if latestClip != nil {
                HStack {
                    Button {
                        store.addRedactionToLatestRecording()
                        selectedRedactionID = store.selectedProject.latestRecordingClip?.redactionRegions.last?.id
                    } label: {
                        Label("Add Mask", systemImage: "plus")
                    }

                    Button {
                        if let selectedRedaction {
                            store.removeLatestRecordingRedaction(id: selectedRedaction.id)
                            selectedRedactionID = store.selectedProject.latestRecordingClip?.redactionRegions.first?.id
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedRedaction == nil)
                    .help("Remove selected mask")
                }

                if redactions.isEmpty {
                    Text("Mask customer names, IDs, or private org data before sharing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Picker("Mask", selection: Binding(
                        get: { selectedRedaction?.id },
                        set: { selectedRedactionID = $0 }
                    )) {
                        ForEach(redactions) { region in
                            Text(region.label).tag(Optional(region.id))
                        }
                    }

                    if let selectedRedaction {
                        RedactionEditor(store: store, region: selectedRedaction)
                    }
                }
            } else {
                Text("No recording selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: redactions) {
            guard !redactions.isEmpty else {
                selectedRedactionID = nil
                return
            }

            if selectedRedactionID == nil || !redactions.contains(where: { $0.id == selectedRedactionID }) {
                selectedRedactionID = redactions.first?.id
            }
        }
    }
}

private struct RedactionEditor: View {
    var store: StudioStore
    let region: RedactionRegion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Label", text: Binding(
                get: { region.label },
                set: { value in
                    store.updateLatestRecordingRedaction(id: region.id) { $0.label = value }
                }
            ))

            RedactionSlider(title: "X", value: region.x) { value in
                store.updateLatestRecordingRedaction(id: region.id) { $0.x = value }
            }

            RedactionSlider(title: "Y", value: region.y) { value in
                store.updateLatestRecordingRedaction(id: region.id) { $0.y = value }
            }

            RedactionSlider(title: "Width", value: region.width) { value in
                store.updateLatestRecordingRedaction(id: region.id) { $0.width = value }
            }

            RedactionSlider(title: "Height", value: region.height) { value in
                store.updateLatestRecordingRedaction(id: region.id) { $0.height = value }
            }
        }
    }
}

private struct RedactionSlider: View {
    let title: String
    let value: Double
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: { newValue in
                        onChange(newValue)
                    }
                ),
                in: 0...1
            )
        }
    }
}

private struct ProjectControls: View {
    var store: StudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: Binding(
                get: { store.selectedProject.title },
                set: { value in store.updateSelectedProject { $0.title = value } }
            ))

            TextField("Owner", text: Binding(
                get: { store.selectedProject.owner },
                set: { value in store.updateSelectedProject { $0.owner = value } }
            ))

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: Binding(
                    get: { store.selectedProject.notes },
                    set: { value in store.updateSelectedProject { $0.notes = value } }
                ))
                .frame(minHeight: 72)
                .scrollContentBackground(.hidden)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct SourceSummary: View {
    var store: StudioStore
    var captureService: ScreenCaptureService

    private var latestClip: StudioClip? {
        store.selectedProject.latestRecordingClip
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Permission")
                Spacer()
                Text(captureService.authorization.title)
                    .foregroundStyle(captureService.authorization == .ready ? Color.secondary : Color.yellow)
            }

            HStack {
                Text("Source")
                Spacer()
                Text(captureService.selectedSource?.title ?? "None")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Frames")
                Spacer()
                Text(captureService.metrics.frameReadout)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let suggestion = captureService.recoverySuggestion {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    Label(suggestion.title, systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)

                    Text(suggestion.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button(suggestion.primaryActionTitle) {
                            performRecoveryPrimaryAction(for: suggestion)
                        }
                        .buttonStyle(.bordered)

                        if let secondaryActionTitle = suggestion.secondaryActionTitle {
                            Button(secondaryActionTitle) {
                                Task {
                                    await captureService.recoverCaptureSetup()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if let recordingURL = captureService.lastRecordingURL {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Latest recording")
                        .foregroundStyle(.secondary)

                    Text(recordingURL.lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([recordingURL])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }

            if let latestClip {
                Divider()

                HStack {
                    Text("Project clips")
                    Spacer()
                    Text("\(store.selectedProject.clips.count)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Latest asset")
                    Spacer()
                    Text(latestClip.fileSize?.formattedByteCount ?? "Pending")
                        .foregroundStyle(.secondary)
                }

                if latestClip.hasTrim {
                    HStack {
                        Text("Trim")
                        Spacer()
                        Text(latestClip.effectiveDuration.formattedDuration)
                            .foregroundStyle(.secondary)
                    }
                }

                if latestClip.hasRedactions {
                    HStack {
                        Text("Privacy masks")
                        Spacer()
                        Text("\(latestClip.redactionRegions.count)")
                            .foregroundStyle(.secondary)
                    }
                }

                if latestClip.presenterURL != nil {
                    HStack {
                        Text("Presenter")
                        Spacer()
                        Text(latestClip.presenterPlacement?.rawValue ?? "Attached")
                            .foregroundStyle(.secondary)
                    }
                }

                let clicks = latestClip.interactionEvents?.filter { $0.kind == .click }.count ?? 0
                let keys = latestClip.interactionEvents?.filter { $0.kind == .keyPress }.count ?? 0

                HStack {
                    Text("Interactions")
                    Spacer()
                    Text("\(clicks) clicks, \(keys) keys")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Polish clips")
                    Spacer()
                    Text("\(store.selectedProject.generatedPolishClips.count)")
                        .foregroundStyle(.secondary)
                }
            }

            if let lastError = captureService.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
    }

    private func performRecoveryPrimaryAction(for suggestion: CaptureRecoverySuggestion) {
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

private struct PolishControls: View {
    var store: StudioStore

    private var latestClip: StudioClip? {
        store.selectedProject.latestRecordingClip
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Canvas", selection: Binding(
                get: { store.selectedProject.canvasStyle },
                set: { style in store.updateSelectedProject { $0.canvasStyle = style } }
            )) {
                ForEach(CanvasStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }

            Picker("Cursor", selection: Binding(
                get: { store.selectedProject.cursorStyle },
                set: { style in store.updateSelectedProject { $0.cursorStyle = style } }
            )) {
                ForEach(CursorStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Caption", systemImage: "captions.bubble")
                    .font(.caption.weight(.semibold))

                TextField("Short demo takeaway", text: Binding(
                    get: { store.selectedProject.captionText ?? "" },
                    set: { value in
                        store.updateSelectedProject {
                            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            $0.captionText = cleaned.isEmpty ? nil : String(cleaned.prefix(120))
                        }
                    }
                ))

                Picker("Placement", selection: Binding(
                    get: { store.selectedProject.selectedCaptionPlacement },
                    set: { placement in store.updateSelectedProject { $0.captionPlacement = placement } }
                )) {
                    ForEach(CaptionPlacement.allCases) { placement in
                        Text(placement.rawValue).tag(placement)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!store.selectedProject.hasCaption)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Auto zoom")
                    Spacer()
                    Text("\(Int(store.selectedProject.zoomIntensity * 100))%")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { store.selectedProject.zoomIntensity },
                        set: { value in store.updateSelectedProject { $0.zoomIntensity = value } }
                    ),
                    in: 0...1
                )
            }

            if let latestClip {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label("Auto polish anchors", systemImage: "scope")
                        .font(.caption.weight(.semibold))

                    let events = latestClip.interactionEvents ?? []
                    Text(events.isEmpty ? "No interaction anchors captured yet." : "\(events.count) local anchors ready for zooms, cursor emphasis, and key hints.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button {
                        store.regenerateAutoPolishForLatestRecording()
                    } label: {
                        Label("Generate", systemImage: "wand.and.stars")
                    }
                    .disabled((latestClip.interactionEvents ?? []).isEmpty)

                    Button {
                        store.removeGeneratedPolish()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(store.selectedProject.generatedPolishClips.isEmpty)
                    .help("Remove generated polish clips")
                }

                ForEach(store.selectedProject.generatedPolishClips.prefix(5)) { clip in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 8, height: 8)

                        Text(clip.title)
                            .lineLimit(1)

                        Spacer()

                        Text(clip.start.formattedDuration)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }

                let focusedCount = store.selectedProject.generatedPolishClips.filter { $0.focusX != nil && $0.focusY != nil }.count
                if focusedCount > 0 {
                    Text("\(focusedCount) focus-aware effects will render with click-position timing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct ExportControls: View {
    var store: StudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Preset", selection: Binding(
                get: { store.selectedProject.exportPreset },
                set: { preset in store.updateSelectedProject { $0.exportPreset = preset } }
            )) {
                ForEach(ExportPreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            Text(store.selectedProject.exportPreset.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Format", selection: Binding(
                get: { store.selectedProject.selectedExportFormat },
                set: { format in store.updateSelectedProject { $0.exportFormat = format } }
            )) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)

            Text(store.selectedProject.selectedExportFormat.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Quality", selection: Binding(
                get: { store.selectedProject.selectedExportQuality },
                set: { quality in store.updateSelectedProject { $0.exportQuality = quality } }
            )) {
                ForEach(ExportQuality.allCases) { quality in
                    Text(quality.rawValue).tag(quality)
                }
            }
            .pickerStyle(.segmented)

            Text(store.selectedProject.selectedExportQuality.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            ExportReadinessView(summary: store.exportReadiness)

            if let exportProgress = store.exportProgress {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(exportProgress.stage)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(exportProgress.percentText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: exportProgress.clampedFraction)
                        .progressViewStyle(.linear)
                }
                .padding(10)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }

            Button {
                Task {
                    await store.exportSelectedProject()
                }
            } label: {
                Label(
                    store.isExporting ? "Rendering" : "Render \(store.selectedProject.selectedExportFormat.rawValue)",
                    systemImage: "film"
                )
            }
            .disabled(!store.exportReadiness.canExport || store.isExporting)

            if let exportURL = store.exportURL {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Export ready", systemImage: "checkmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)

                    Text(exportURL.lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let exportFileSize = store.exportFileSize {
                        HStack {
                            Text("Size")
                            Spacer()
                            Text(exportFileSize.formattedByteCount)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }

                    if let exportCompletedAt = store.exportCompletedAt {
                        HStack {
                            Text("Completed")
                            Spacer()
                            Text(exportCompletedAt.formattedExportTimestamp)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }

                    HStack {
                        Button {
                            store.revealLatestExport()
                        } label: {
                            Label("Reveal", systemImage: "folder")
                        }

                        Button {
                            store.copyLatestExportPath()
                        } label: {
                            Label("Copy Path", systemImage: "doc.on.doc")
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }

            if let exportError = store.exportError {
                Label(exportError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ExportReadinessView: View {
    let summary: ExportReadinessSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(summary.canExport ? "Ready to export" : "Export blocked", systemImage: summary.canExport ? "checkmark.seal" : "xmark.octagon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(summary.canExport ? Color.secondary : Color.red)

            ForEach(summary.items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: item.state.symbolName)
                        .foregroundStyle(item.state.color)
                        .frame(width: 14)

                    Text(item.title)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(item.detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
            }
        }
    }
}

private extension ExportReadinessItem.State {
    var symbolName: String {
        switch self {
        case .ready:
            "checkmark.circle.fill"
        case .info:
            "circle"
        case .blocked:
            "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready:
            .secondary
        case .info:
            .secondary
        case .blocked:
            .red
        }
    }
}

private struct SecuritySummary: View {
    var store: StudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Local files only", systemImage: "internaldrive")
            Label("Explicit device permissions", systemImage: "checkmark.shield")
            Label("Typed characters are not stored", systemImage: "keyboard.badge.eye")
            if let persistenceError = store.persistenceError {
                Label(persistenceError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.yellow)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    let symbolName: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            content
        }
        .padding(.vertical, 2)
    }
}
