import AppKit
@testable import CaptureCue
import XCTest

@MainActor
final class CaptureWorkflowTests: XCTestCase {
    func testCaptureLibraryPersistsImagesAndAnnotations() throws {
        let directory = temporaryDirectory(named: "CaptureLibrary")
        let service = CaptureLibraryService(directory: directory)
        let capture = CaptureItem(
            kind: .area,
            createdAt: Date(timeIntervalSince1970: 1_234),
            image: testImage(),
            pixelSize: CGSize(width: 160, height: 90),
            name: "Area Test",
            annotations: [
                CaptureAnnotation(
                    tool: .arrow,
                    start: CGPoint(x: 0.1, y: 0.2),
                    end: CGPoint(x: 0.8, y: 0.7)
                )
            ]
        )

        try service.saveCaptures([capture])
        let loaded = service.loadCaptures()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, capture.id)
        XCTAssertEqual(loaded[0].name, "Area Test")
        XCTAssertEqual(loaded[0].annotations.count, 1)
        XCTAssertEqual(loaded[0].annotations[0].tool, .arrow)
    }

    func testImageExportRendersMarkupAndFramedCanvas() {
        let service = ImageExportService()
        let capture = CaptureItem(
            kind: .window,
            createdAt: Date(timeIntervalSince1970: 1_234),
            image: testImage(size: CGSize(width: 200, height: 120)),
            pixelSize: CGSize(width: 200, height: 120),
            name: "Window Test",
            annotations: [
                CaptureAnnotation(
                    tool: .step,
                    start: CGPoint(x: 0.5, y: 0.5),
                    end: CGPoint(x: 0.5, y: 0.5),
                    stepNumber: 1
                )
            ]
        )

        let rendered = service.renderedImage(for: capture)
        let framed = service.framedImage(for: capture)

        XCTAssertEqual(rendered.size.width, capture.image.size.width, accuracy: 0.1)
        XCTAssertGreaterThan(framed.size.width, rendered.size.width)
        XCTAssertTrue(service.suggestedFilename(for: capture, variant: .framed).hasSuffix("-framed.png"))
    }

    func testCaptureShortcutsStayMinimalForMVP() {
        XCTAssertEqual(GlobalShortcutAction.allCases, [.captureArea, .captureFullScreen, .captureWindow])
        XCTAssertEqual(GlobalShortcutAction.captureArea.defaultShortcut.displayValue, "⌃⌥⇧4")
        XCTAssertEqual(GlobalShortcutAction.captureFullScreen.defaultShortcut.displayValue, "⌃⌥⇧3")
        XCTAssertEqual(GlobalShortcutAction.captureWindow.defaultShortcut.displayValue, "⌃⌥⇧5")
    }

    func testMarkupToolsStayMinimalForMVP() {
        XCTAssertEqual(AnnotationTool.visibleMarkupTools, [.arrow, .rectangle, .text, .redact])
    }

    func testDisplaySlicesStitchSelectionAcrossDisplays() {
        let displayFrames = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 1440, y: 0, width: 1280, height: 900)
        ]
        let selection = CGRect(x: 1300, y: 120, width: 300, height: 220)

        let slices = ScreenshotCaptureService.displaySlices(for: selection, displayFrames: displayFrames)

        XCTAssertEqual(slices.count, 2)
        XCTAssertEqual(slices[0].sourceRect, CGRect(x: 1300, y: 120, width: 140, height: 220))
        XCTAssertEqual(slices[0].destinationRect, CGRect(x: 0, y: 0, width: 140, height: 220))
        XCTAssertEqual(slices[1].sourceRect, CGRect(x: 1440, y: 120, width: 160, height: 220))
        XCTAssertEqual(slices[1].destinationRect, CGRect(x: 140, y: 0, width: 160, height: 220))
    }

    func testDesktopFrameUnionsDisplaysForFullScreenCapture() throws {
        let displayFrames = [
            CGRect(x: -1280, y: 160, width: 1280, height: 720),
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 1440, y: 80, width: 1280, height: 800)
        ]

        let desktopFrame = try XCTUnwrap(ScreenshotCaptureService.desktopFrame(displayFrames: displayFrames))
        let slices = ScreenshotCaptureService.displaySlices(for: desktopFrame, displayFrames: displayFrames)

        XCTAssertEqual(desktopFrame, CGRect(x: -1280, y: 0, width: 4000, height: 900))
        XCTAssertEqual(slices.count, 3)
        XCTAssertEqual(slices[0].destinationRect, CGRect(x: 0, y: 160, width: 1280, height: 720))
        XCTAssertEqual(slices[1].destinationRect, CGRect(x: 1280, y: 0, width: 1440, height: 900))
        XCTAssertEqual(slices[2].destinationRect, CGRect(x: 2720, y: 80, width: 1280, height: 800))
    }

    func testWindowCandidateSearchMatchesTitleAppAndSize() {
        let candidate = CaptureWindowCandidate(
            id: 42,
            title: "Opportunity Workspace",
            appName: "Safari",
            frame: CGRect(x: 20, y: 40, width: 1440, height: 900)
        )

        XCTAssertTrue(candidate.matchesWindowSearch(""))
        XCTAssertTrue(candidate.matchesWindowSearch("opportunity"))
        XCTAssertTrue(candidate.matchesWindowSearch("safari"))
        XCTAssertTrue(candidate.matchesWindowSearch("1440 x 900"))
        XCTAssertFalse(candidate.matchesWindowSearch("slack"))
    }

    func testStudioCanAttachSnapshotReference() {
        let root = temporaryDirectory(named: "StudioSnapshot")
        let persistence = ProjectPersistence(appSupportDirectory: root.appending(path: "Projects", directoryHint: .isDirectory))
        let snapshotDirectory = root.appending(path: "Snapshots", directoryHint: .isDirectory)
        let project = StudioProject(
            title: "Untitled Demo",
            owner: "Salesforce",
            updatedAt: Date(timeIntervalSince1970: 1_234),
            duration: 0,
            canvasStyle: .aurora,
            zoomIntensity: 0.6,
            cursorStyle: .spotlight,
            exportPreset: .wide,
            clips: [],
            notes: ""
        )
        let store = StudioStore(
            persistence: persistence,
            snapshotDirectory: snapshotDirectory,
            seedProjects: [project]
        )
        let capture = CaptureItem(
            kind: .area,
            createdAt: Date(timeIntervalSince1970: 1_235),
            image: testImage(),
            pixelSize: CGSize(width: 160, height: 90),
            name: "Flow Reference"
        )

        store.attachSnapshot(capture, image: capture.image)

        let snapshot = store.selectedProject.latestReferenceSnapshot
        XCTAssertEqual(snapshot?.title, "Flow Reference")
        XCTAssertEqual(store.selectedProject.title, "Flow Reference")
        XCTAssertTrue(snapshot.map { FileManager.default.fileExists(atPath: $0.url.path) } ?? false)
    }

    private func temporaryDirectory(named name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureCueTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func testImage(size: CGSize = CGSize(width: 160, height: 90)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.08, green: 0.16, blue: 0.32, alpha: 1).setFill()
        CGRect(origin: .zero, size: size).fill()
        NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.88, alpha: 1).setFill()
        CGRect(x: size.width * 0.25, y: size.height * 0.28, width: size.width * 0.5, height: size.height * 0.44).fill()
        image.unlockFocus()
        return image
    }
}
