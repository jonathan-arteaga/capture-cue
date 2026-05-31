import XCTest
@testable import astro_lens

final class AutoPolishServiceTests: XCTestCase {
    func testClickEventsCreateFocusAwareZoomAndCursorClips() {
        let recording = StudioClip(
            title: "Recording",
            start: 4,
            duration: 20,
            kind: .recording,
            interactionEvents: [
                .click(timestamp: 2, x: 0.25, y: 0.7, modifiers: [])
            ]
        )

        let suggestions = AutoPolishService().suggestions(for: recording, intensity: 0.6)
        let zoom = suggestions.first { $0.kind == .zoom }
        let cursor = suggestions.first { $0.kind == .cursor }

        XCTAssertEqual(zoom?.sourceClipID, recording.id)
        XCTAssertEqual(zoom?.focusX, 0.25)
        XCTAssertEqual(zoom?.focusY, 0.7)
        XCTAssertEqual(cursor?.focusX, 0.25)
        XCTAssertEqual(cursor?.focusY, 0.7)
    }

    func testPrivacySafeKeyEventsCreateKeyHintsWithoutFocusCoordinates() {
        let recording = StudioClip(
            title: "Recording",
            start: 0,
            duration: 10,
            kind: .recording,
            interactionEvents: [
                .keyPress(timestamp: 3, label: "Return", modifiers: ["Command"])
            ]
        )

        let suggestions = AutoPolishService().suggestions(for: recording, intensity: 0.5)
        let keyHint = suggestions.first { $0.kind == .keyHint }

        XCTAssertEqual(keyHint?.title, "Return")
        XCTAssertNil(keyHint?.focusX)
        XCTAssertNil(keyHint?.focusY)
    }

    func testRecordingStateElapsedDurationUsesStableStartDate() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let state = RecordingState.recording(startedAt: startedAt)

        XCTAssertEqual(state.elapsedDuration(at: Date(timeIntervalSince1970: 143)), 43, accuracy: 0.001)
        XCTAssertEqual(state.statusTitle(at: Date(timeIntervalSince1970: 143)), "0:43")
    }

    func testRecordingStateElapsedDurationNeverGoesNegative() {
        let startedAt = Date(timeIntervalSince1970: 100)
        let state = RecordingState.recording(startedAt: startedAt)

        XCTAssertEqual(state.elapsedDuration(at: Date(timeIntervalSince1970: 95)), 0, accuracy: 0.001)
        XCTAssertEqual(RecordingState.stopping.statusDetail(), "Finalizing clip")
    }

    func testRecoverySuggestionPrioritizesScreenPermission() {
        let suggestion = CaptureRecoverySuggestion.suggestion(
            authorization: .denied,
            selectedSource: nil,
            microphoneRequired: true,
            microphoneAuthorization: .denied,
            sessionState: .idle,
            lastError: nil
        )

        XCTAssertEqual(suggestion?.kind, .screenPermission)
        XCTAssertEqual(suggestion?.primaryActionTitle, "Open Privacy Settings")
    }

    func testRecoverySuggestionDetectsMissingMicrophoneWhenNarrationEnabled() {
        let source = CaptureSource(
            id: "display-1",
            kind: .display,
            title: "Main Display",
            subtitle: "1920x1080",
            pixelWidth: 1920,
            pixelHeight: 1080,
            captureFrame: .zero
        )

        let suggestion = CaptureRecoverySuggestion.suggestion(
            authorization: .ready,
            selectedSource: source,
            microphoneRequired: true,
            microphoneAuthorization: .denied,
            sessionState: .idle,
            lastError: nil
        )

        XCTAssertEqual(suggestion?.kind, .microphonePermission)
        XCTAssertEqual(suggestion?.secondaryActionTitle, "Refresh")
    }

    func testRecoverySuggestionUsesFailedCaptureErrorWhenSetupIsReady() {
        let source = CaptureSource(
            id: "window-42",
            kind: .window,
            title: "Demo Window",
            subtitle: "Salesforce",
            pixelWidth: 1280,
            pixelHeight: 720,
            captureFrame: .zero
        )

        let suggestion = CaptureRecoverySuggestion.suggestion(
            authorization: .ready,
            selectedSource: source,
            microphoneRequired: false,
            microphoneAuthorization: .unknown,
            sessionState: .failed("The selected capture source is no longer available."),
            lastError: "The selected capture source is no longer available."
        )

        XCTAssertEqual(suggestion?.kind, .failedCapture)
        XCTAssertEqual(suggestion?.detail, "The selected capture source is no longer available.")
        XCTAssertEqual(suggestion?.primaryActionTitle, "Recover")
    }

    func testExportProgressClampsAndFormatsPercentText() {
        let low = ExportProgress(fraction: -0.25, stage: "Preparing")
        let mid = ExportProgress(fraction: 0.426, stage: "Rendering")
        let high = ExportProgress(fraction: 1.4, stage: "Done")

        XCTAssertEqual(low.clampedFraction, 0, accuracy: 0.001)
        XCTAssertEqual(low.percentText, "0%")
        XCTAssertEqual(mid.percentText, "43%")
        XCTAssertEqual(high.clampedFraction, 1, accuracy: 0.001)
        XCTAssertEqual(high.percentText, "100%")
    }

    func testExportReadinessBlocksWhenThereIsNoRecording() {
        let project = StudioProject(
            title: "Empty",
            owner: "Salesforce",
            updatedAt: .now,
            duration: 0,
            canvasStyle: .aurora,
            zoomIntensity: 0.6,
            cursorStyle: .spotlight,
            exportPreset: .wide,
            clips: [],
            notes: ""
        )

        let readiness = project.exportReadiness()

        XCTAssertFalse(readiness.canExport)
        XCTAssertEqual(readiness.blockingMessage, "Record a clip before rendering.")
    }

    func testExportReadinessBlocksWhenSourceFileIsMissing() {
        let project = StudioProject(
            title: "Missing Source",
            owner: "Salesforce",
            updatedAt: .now,
            duration: 10,
            canvasStyle: .aurora,
            zoomIntensity: 0.6,
            cursorStyle: .spotlight,
            exportPreset: .wide,
            clips: [
                StudioClip(
                    title: "Recording",
                    start: 0,
                    duration: 10,
                    kind: .recording,
                    assetURL: URL(fileURLWithPath: "/tmp/missing-astrolens-recording.mov")
                )
            ],
            notes: ""
        )

        let readiness = project.exportReadiness(sourceFileExists: false)

        XCTAssertFalse(readiness.canExport)
        XCTAssertEqual(readiness.items.first?.title, "Source file")
        XCTAssertEqual(readiness.blockingMessage, "The latest recording file is missing from disk.")
    }

    func testExportReadinessSummarizesPrivacyCaptionsAndPolish() {
        let recordingID = UUID()
        let recording = StudioClip(
            id: recordingID,
            title: "Recording",
            start: 0,
            duration: 12,
            kind: .recording,
            assetURL: URL(fileURLWithPath: "/tmp/recording.mov"),
            sourceTitle: "Main Display",
            trimStart: 2,
            trimEnd: 1,
            redactions: [.defaultRegion]
        )
        let project = StudioProject(
            title: "Ready",
            owner: "Salesforce",
            updatedAt: .now,
            duration: 12,
            canvasStyle: .aurora,
            zoomIntensity: 0.6,
            cursorStyle: .spotlight,
            exportPreset: .wide,
            captionText: "  Forecast updated  ",
            captionPlacement: .lower,
            clips: [
                recording,
                StudioClip(
                    title: "Zoom",
                    start: 2,
                    duration: 2,
                    kind: .zoom,
                    generatedBy: AutoPolishService.generatorID,
                    sourceClipID: recordingID
                )
            ],
            notes: ""
        )

        let readiness = project.exportReadiness(sourceFileExists: true)

        XCTAssertTrue(readiness.canExport)
        XCTAssertEqual(readiness.items.first { $0.title == "Duration" }?.detail, "0:09")
        XCTAssertEqual(readiness.items.first { $0.title == "Privacy masks" }?.detail, "1 will render")
        XCTAssertEqual(readiness.items.first { $0.title == "Captions" }?.detail, "Lower")
        XCTAssertEqual(readiness.items.first { $0.title == "Auto polish" }?.detail, "1 effects")
    }

    @MainActor
    func testImportRecordingAttachesImportedVideoAndSwitchesToPolish() async {
        let store = StudioStore(
            persistence: temporaryPersistence(),
            importService: StubVideoImporter(
                result: .success(
                    RecordedCapture(
                        url: URL(fileURLWithPath: "/tmp/imported.mov"),
                        createdAt: Date(timeIntervalSince1970: 10),
                        duration: 7,
                        sourceTitle: "Imported Demo",
                        fileSize: 2048,
                        interactionEvents: []
                    )
                )
            ),
            seedProjects: [
                StudioProject(
                    title: "Untitled Demo",
                    owner: "Salesforce",
                    updatedAt: .now,
                    duration: 0,
                    canvasStyle: .aurora,
                    zoomIntensity: 0.6,
                    cursorStyle: .spotlight,
                    exportPreset: .wide,
                    clips: [],
                    notes: ""
                )
            ]
        )

        await store.importRecording(from: URL(fileURLWithPath: "/tmp/source.mov"))

        XCTAssertFalse(store.isImporting)
        XCTAssertNil(store.importError)
        XCTAssertEqual(store.selectedTab, .polish)
        XCTAssertEqual(store.selectedProject.title, "Imported Demo")
        XCTAssertEqual(store.selectedProject.latestRecordingClip?.sourceTitle, "Imported Demo")
        XCTAssertEqual(store.selectedProject.latestRecordingClip?.fileSize, 2048)
    }

    @MainActor
    func testImportRecordingSurfacesImportFailure() async {
        let store = StudioStore(
            persistence: temporaryPersistence(),
            importService: StubVideoImporter(result: .failure(VideoImportServiceError.noVideoTrack)),
            seedProjects: []
        )

        await store.importRecording(from: URL(fileURLWithPath: "/tmp/not-a-movie.txt"))

        XCTAssertFalse(store.isImporting)
        XCTAssertEqual(store.importError, "Choose a movie file with a video track.")
        XCTAssertTrue(store.selectedProject.clips.isEmpty)
    }

    @MainActor
    func testSuccessfulImportClearsPreviousImportError() async {
        let store = StudioStore(
            persistence: temporaryPersistence(),
            importService: StubVideoImporter(
                result: .success(
                    RecordedCapture(
                        url: URL(fileURLWithPath: "/tmp/retry.mov"),
                        createdAt: .now,
                        duration: 3,
                        sourceTitle: "Retry",
                        fileSize: 100,
                        interactionEvents: []
                    )
                )
            ),
            seedProjects: []
        )
        store.importError = "Previous error"

        await store.importRecording(from: URL(fileURLWithPath: "/tmp/retry-source.mov"))

        XCTAssertNil(store.importError)
        XCTAssertEqual(store.selectedProject.latestRecordingClip?.sourceTitle, "Retry")
    }

    @MainActor
    func testDuplicatingSelectedProjectRemapsProjectClipAndSourceIDs() {
        let recordingID = UUID()
        let project = StudioProject(
            title: "Pipeline Demo",
            owner: "Salesforce",
            updatedAt: .now,
            duration: 8,
            canvasStyle: .aurora,
            zoomIntensity: 0.6,
            cursorStyle: .spotlight,
            exportPreset: .wide,
            clips: [
                StudioClip(
                    id: recordingID,
                    title: "Recording",
                    start: 0,
                    duration: 8,
                    kind: .recording,
                    assetURL: URL(fileURLWithPath: "/tmp/recording.mov")
                ),
                StudioClip(
                    title: "Zoom",
                    start: 1,
                    duration: 2,
                    kind: .zoom,
                    generatedBy: AutoPolishService.generatorID,
                    sourceClipID: recordingID
                )
            ],
            notes: ""
        )
        let store = StudioStore(persistence: temporaryPersistence(), seedProjects: [project])

        store.duplicateSelectedProject()

        XCTAssertEqual(store.projects.count, 2)
        XCTAssertEqual(store.selectedProject.title, "Pipeline Demo Copy")
        XCTAssertNotEqual(store.projects[0].id, project.id)
        XCTAssertNotEqual(store.projects[0].clips[0].id, recordingID)
        XCTAssertEqual(store.projects[0].clips[1].sourceClipID, store.projects[0].clips[0].id)
    }

    @MainActor
    func testDeletingSelectedProjectKeepsAValidSelectionAndReplacementWhenEmpty() {
        let project = StudioProject(
            title: "Only Project",
            owner: "Salesforce",
            updatedAt: .now,
            duration: 0,
            canvasStyle: .aurora,
            zoomIntensity: 0.6,
            cursorStyle: .spotlight,
            exportPreset: .wide,
            clips: [],
            notes: ""
        )
        let store = StudioStore(persistence: temporaryPersistence(), seedProjects: [project])

        store.deleteSelectedProject()

        XCTAssertEqual(store.projects.count, 1)
        XCTAssertNotEqual(store.projects[0].id, project.id)
        XCTAssertEqual(store.selectedProjectID, store.projects[0].id)
        XCTAssertEqual(store.selectedProject.title, "Untitled Demo")
    }

    func testRecordingTrimCalculatesEffectiveDurationAndClampsToSafeRange() {
        let recording = StudioClip(
            title: "Recording",
            start: 0,
            duration: 10,
            kind: .recording,
            trimStart: 2,
            trimEnd: 3
        )

        XCTAssertEqual(recording.effectiveDuration, 5, accuracy: 0.001)
        XCTAssertTrue(recording.hasTrim)

        let clamped = recording.clampedTrim(start: 9.8, end: 3)
        XCTAssertEqual(clamped.start, 9.8, accuracy: 0.001)
        XCTAssertEqual(clamped.end, 0.1, accuracy: 0.001)
    }

    func testOlderClipsDecodeWithoutTrimFields() throws {
        let json = """
        {
          "id": "D1BFB355-C02B-486F-93FD-B7E500F2647C",
          "title": "Legacy Recording",
          "start": 0,
          "duration": 12,
          "kind": "recording"
        }
        """.data(using: .utf8)!

        let clip = try JSONDecoder().decode(StudioClip.self, from: json)

        XCTAssertEqual(clip.trimStartValue, 0, accuracy: 0.001)
        XCTAssertEqual(clip.trimEndValue, 0, accuracy: 0.001)
        XCTAssertEqual(clip.effectiveDuration, 12, accuracy: 0.001)
    }

    func testOlderProjectsDecodeWithDefaultExportOptions() throws {
        let json = """
        {
          "id": "5B7BF20D-C250-4E1D-A151-73D5F268A917",
          "title": "Legacy Project",
          "owner": "Salesforce",
          "updatedAt": 0,
          "duration": 0,
          "canvasStyle": "Aurora",
          "zoomIntensity": 0.6,
          "cursorStyle": "Spotlight",
          "exportPreset": "16:9",
          "clips": [],
          "notes": ""
        }
        """.data(using: .utf8)!

        let project = try JSONDecoder().decode(StudioProject.self, from: json)

        XCTAssertEqual(project.selectedExportFormat, .mp4)
        XCTAssertEqual(project.selectedExportQuality, .balanced)
        XCTAssertFalse(project.hasCaption)
        XCTAssertEqual(project.selectedCaptionPlacement, .lower)
    }

    func testProjectCaptionTrimsWhitespaceAndDetectsEnabledState() {
        let project = StudioProject(
            title: "Caption Demo",
            owner: "Salesforce",
            updatedAt: .now,
            duration: 0,
            canvasStyle: .aurora,
            zoomIntensity: 0.6,
            cursorStyle: .spotlight,
            exportPreset: .wide,
            captionText: "  Keep the forecast update short.  ",
            captionPlacement: .upper,
            clips: [],
            notes: ""
        )

        XCTAssertEqual(project.captionTextValue, "Keep the forecast update short.")
        XCTAssertTrue(project.hasCaption)
        XCTAssertEqual(project.selectedCaptionPlacement, .upper)
    }

    func testRedactionRegionClampsToVisibleFrameAndKeepsFallbackLabel() {
        let region = RedactionRegion(
            label: "   ",
            x: 0.98,
            y: -0.2,
            width: 0.95,
            height: 0.02
        ).clamped

        XCTAssertEqual(region.label, "Sensitive area")
        XCTAssertEqual(region.width, 0.88, accuracy: 0.001)
        XCTAssertEqual(region.height, 0.06, accuracy: 0.001)
        XCTAssertEqual(region.x, 0.12, accuracy: 0.001)
        XCTAssertEqual(region.y, 0, accuracy: 0.001)
    }

    private func temporaryPersistence() -> ProjectPersistence {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "astro_lensTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return ProjectPersistence(appSupportDirectory: directory)
    }
}

private struct StubVideoImporter: VideoImporting, @unchecked Sendable {
    var result: Result<RecordedCapture, Error>

    func importVideo(from sourceURL: URL) async throws -> RecordedCapture {
        try result.get()
    }
}
