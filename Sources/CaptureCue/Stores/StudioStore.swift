import AppKit
import Foundation

@MainActor
@Observable
final class StudioStore {
    var projects: [StudioProject]
    var selectedProjectID: StudioProject.ID?
    var isInspectorVisible = true
    var isSidebarVisible = true
    var selectedTab: StudioTab = .studio
    var defaultOwner = "Salesforce"
    var persistenceError: String?
    var isExporting = false
    var exportURL: URL?
    var exportFileSize: Int64?
    var exportCompletedAt: Date?
    var exportError: String?
    var exportProgress: ExportProgress?
    var isImporting = false
    var importError: String?

    @ObservationIgnored private let persistence: ProjectPersistence
    @ObservationIgnored private let exportService = ExportService()
    @ObservationIgnored private let importService: any VideoImporting
    @ObservationIgnored private let snapshotDirectory: URL?

    init(
        persistence: ProjectPersistence = ProjectPersistence(),
        importService: any VideoImporting = VideoImportService(),
        snapshotDirectory: URL? = nil,
        seedProjects: [StudioProject]? = nil
    ) {
        self.persistence = persistence
        self.importService = importService
        self.snapshotDirectory = snapshotDirectory
        if let seedProjects {
            self.projects = seedProjects.isEmpty ? [StudioProject.empty(owner: "Salesforce")] : seedProjects
        } else {
            do {
                let loadedProjects = try persistence.loadProjects()
                self.projects = loadedProjects.isEmpty ? [StudioProject.empty(owner: "Salesforce")] : loadedProjects
            } catch {
                self.projects = [StudioProject.empty(owner: "Salesforce")]
                self.persistenceError = error.localizedDescription
            }
        }
        selectedProjectID = self.projects.first?.id
    }

    var selectedProject: StudioProject {
        get {
            guard let selectedProjectID,
                  let project = projects.first(where: { $0.id == selectedProjectID }) else {
                return projects.first ?? StudioProject.empty(owner: defaultOwner)
            }
            return project
        }
        set {
            guard let index = projects.firstIndex(where: { $0.id == newValue.id }) else {
                return
            }
            projects[index] = newValue
        }
    }

    var exportReadiness: ExportReadinessSummary {
        selectedProject.exportReadiness(sourceFileExists: latestRecordingSourceExists)
    }

    private var latestRecordingSourceExists: Bool? {
        guard let assetURL = selectedProject.latestRecordingClip?.assetURL else {
            return nil
        }
        return FileManager.default.fileExists(atPath: assetURL.path)
    }

    func select(_ project: StudioProject) {
        selectedProjectID = project.id
    }

    func createProject() {
        let project = StudioProject(
            title: "Untitled Demo",
            owner: defaultOwner,
            updatedAt: .now,
            duration: 0,
            canvasStyle: .aurora,
            zoomIntensity: 0.6,
            cursorStyle: .spotlight,
            exportPreset: .wide,
            clips: [],
            notes: ""
        )
        projects.insert(project, at: 0)
        selectedProjectID = project.id
        save()
    }

    func duplicateSelectedProject() {
        guard let selectedProjectID,
              let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else {
            return
        }

        let duplicate = projects[index].duplicated()
        projects.insert(duplicate, at: index)
        self.selectedProjectID = duplicate.id
        save()
    }

    func deleteSelectedProject() {
        guard let selectedProjectID,
              let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else {
            return
        }

        projects.remove(at: index)

        if projects.isEmpty {
            let replacement = StudioProject.empty(owner: defaultOwner)
            projects.append(replacement)
            self.selectedProjectID = replacement.id
        } else {
            let nextIndex = min(index, projects.count - 1)
            self.selectedProjectID = projects[nextIndex].id
        }

        exportURL = nil
        exportFileSize = nil
        exportCompletedAt = nil
        exportError = nil
        exportProgress = nil
        save()
    }

    func importRecording(from url: URL) async {
        guard !isImporting else {
            return
        }

        isImporting = true
        importError = nil

        do {
            let importedRecording = try await importService.importVideo(from: url)
            attachRecording(importedRecording)
            selectedTab = .polish
            isInspectorVisible = true
        } catch {
            importError = error.localizedDescription
        }

        isImporting = false
    }

    func updateSelectedProject(_ mutate: (inout StudioProject) -> Void) {
        guard let selectedProjectID,
              let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else {
            return
        }
        mutate(&projects[index])
        projects[index].updatedAt = .now
        save()
    }

    func attachRecording(_ recording: RecordedCapture) {
        guard let selectedProjectID,
              let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else {
            return
        }

        let start = projects[index].duration
        let clip = StudioClip(
            title: recording.url.deletingPathExtension().lastPathComponent,
            start: start,
            duration: recording.duration,
            kind: .recording,
            assetURL: recording.url,
            presenterURL: recording.presenterURL,
            microphoneURL: recording.microphoneURL,
            presenterPlacement: recording.presenterPlacement,
            presenterSize: recording.presenterSize,
            sourceTitle: recording.sourceTitle,
            fileSize: recording.fileSize,
            interactionEvents: recording.interactionEvents
        )

        projects[index].clips.append(clip)
        projects[index].clips.append(
            contentsOf: AutoPolishService().suggestions(
                for: clip,
                intensity: projects[index].zoomIntensity
            )
        )
        projects[index].clips.sort { left, right in
            if left.start == right.start {
                return left.kind.rawValue < right.kind.rawValue
            }
            return left.start < right.start
        }
        projects[index].duration += recording.duration
        projects[index].updatedAt = recording.createdAt

        if projects[index].title == "Untitled Demo" {
            projects[index].title = recording.sourceTitle
        }

        save()
    }

    func attachSnapshot(_ capture: CaptureItem, image: NSImage) {
        guard let selectedProjectID,
              let index = projects.firstIndex(where: { $0.id == selectedProjectID }) else {
            return
        }

        do {
            let url = try saveSnapshotImage(image, captureID: capture.id)
            let snapshot = StudioSnapshot(
                title: capture.name,
                url: url,
                createdAt: Date(),
                pixelWidth: Double(capture.pixelSize.width),
                pixelHeight: Double(capture.pixelSize.height)
            )
            var snapshots = projects[index].referenceSnapshotItems
            snapshots.removeAll { $0.url == url }
            snapshots.insert(snapshot, at: 0)
            projects[index].referenceSnapshots = Array(snapshots.prefix(8))
            projects[index].updatedAt = .now

            if projects[index].title == "Untitled Demo" {
                projects[index].title = capture.name
            }

            save()
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    func regenerateAutoPolishForLatestRecording() {
        guard let selectedProjectID,
              let index = projects.firstIndex(where: { $0.id == selectedProjectID }),
              let latestRecording = projects[index].latestRecordingClip else {
            return
        }

        let generatorID = AutoPolishService.generatorID
        let suggestions = AutoPolishService().suggestions(
            for: latestRecording,
            intensity: projects[index].zoomIntensity
        )

        projects[index].clips.removeAll { clip in
            clip.generatedBy == generatorID && clip.sourceClipID == latestRecording.id
        }
        projects[index].clips.append(contentsOf: suggestions)
        projects[index].clips.sort { left, right in
            if left.start == right.start {
                return left.kind.rawValue < right.kind.rawValue
            }
            return left.start < right.start
        }
        projects[index].updatedAt = .now
        save()
    }

    func removeGeneratedPolish() {
        updateSelectedProject { project in
            project.clips.removeAll { $0.generatedBy == AutoPolishService.generatorID }
        }
    }

    func updateLatestRecordingTrim(start: TimeInterval, end: TimeInterval) {
        guard let selectedProjectID,
              let projectIndex = projects.firstIndex(where: { $0.id == selectedProjectID }),
              let clipIndex = projects[projectIndex].clips.lastIndex(where: { $0.kind == .recording && $0.assetURL != nil }) else {
            return
        }

        let trim = projects[projectIndex].clips[clipIndex].clampedTrim(start: start, end: end)
        projects[projectIndex].clips[clipIndex].trimStart = trim.start
        projects[projectIndex].clips[clipIndex].trimEnd = trim.end
        projects[projectIndex].updatedAt = .now
        save()
    }

    func addRedactionToLatestRecording() {
        guard let selectedProjectID,
              let projectIndex = projects.firstIndex(where: { $0.id == selectedProjectID }),
              let clipIndex = projects[projectIndex].clips.lastIndex(where: { $0.kind == .recording && $0.assetURL != nil }) else {
            return
        }

        var regions = projects[projectIndex].clips[clipIndex].redactionRegions
        var region = RedactionRegion.defaultRegion
        region.label = regions.isEmpty ? "Sensitive area" : "Sensitive area \(regions.count + 1)"
        regions.append(region)
        projects[projectIndex].clips[clipIndex].redactions = regions
        projects[projectIndex].updatedAt = .now
        save()
    }

    func updateLatestRecordingRedaction(id: RedactionRegion.ID, _ mutate: (inout RedactionRegion) -> Void) {
        guard let selectedProjectID,
              let projectIndex = projects.firstIndex(where: { $0.id == selectedProjectID }),
              let clipIndex = projects[projectIndex].clips.lastIndex(where: { $0.kind == .recording && $0.assetURL != nil }) else {
            return
        }

        var regions = projects[projectIndex].clips[clipIndex].redactionRegions
        guard let regionIndex = regions.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutate(&regions[regionIndex])
        regions[regionIndex] = regions[regionIndex].clamped
        projects[projectIndex].clips[clipIndex].redactions = regions
        projects[projectIndex].updatedAt = .now
        save()
    }

    func removeLatestRecordingRedaction(id: RedactionRegion.ID) {
        guard let selectedProjectID,
              let projectIndex = projects.firstIndex(where: { $0.id == selectedProjectID }),
              let clipIndex = projects[projectIndex].clips.lastIndex(where: { $0.kind == .recording && $0.assetURL != nil }) else {
            return
        }

        var regions = projects[projectIndex].clips[clipIndex].redactionRegions
        regions.removeAll { $0.id == id }
        projects[projectIndex].clips[clipIndex].redactions = regions.isEmpty ? nil : regions
        projects[projectIndex].updatedAt = .now
        save()
    }

    func exportSelectedProject() async {
        guard !isExporting else {
            return
        }

        let readiness = exportReadiness
        guard readiness.canExport else {
            exportError = readiness.blockingMessage ?? ExportServiceError.noRecording.localizedDescription
            exportProgress = nil
            return
        }

        isExporting = true
        exportError = nil
        exportURL = nil
        exportFileSize = nil
        exportCompletedAt = nil
        exportProgress = .preparing

        do {
            let renderedURL = try await exportService.exportLatestRecording(from: selectedProject) { [weak self] progress in
                await MainActor.run {
                    self?.exportProgress = progress
                }
            }
            exportURL = renderedURL
            exportFileSize = fileSize(for: renderedURL)
            exportCompletedAt = .now
            exportProgress = .completed
        } catch {
            exportError = error.localizedDescription
            exportProgress = nil
        }

        isExporting = false
    }

    func revealLatestExport() {
        guard let exportURL else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([exportURL])
    }

    func copyLatestExportPath() {
        guard let exportURL else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(exportURL.path, forType: .string)
    }

    private func fileSize(for url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }

        return size.int64Value
    }

    private func saveSnapshotImage(_ image: NSImage, captureID: CaptureItem.ID) throws -> URL {
        let directory: URL
        if let snapshotDirectory {
            directory = snapshotDirectory
        } else {
            let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            directory = baseDirectory
                .appending(path: "CaptureCue", directoryHint: .isDirectory)
                .appending(path: "StudioSnapshots", directoryHint: .isDirectory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let data = image.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }

        let url = directory.appending(path: "\(captureID.uuidString).png")
        try data.write(to: url, options: [.atomic])
        return url
    }

    func save() {
        do {
            try persistence.saveProjects(projects)
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }
}

enum StudioTab: String, CaseIterable, Identifiable {
    case studio = "Studio"
    case polish = "Polish"
    case export = "Export"

    var id: String { rawValue }
}

private extension StudioProject {
    static func empty(owner: String) -> StudioProject {
        StudioProject(
            title: "Untitled Demo",
            owner: owner,
            updatedAt: .now,
            duration: 0,
            canvasStyle: .aurora,
            zoomIntensity: 0.6,
            cursorStyle: .spotlight,
            exportPreset: .wide,
            clips: [],
            notes: ""
        )
    }
}
