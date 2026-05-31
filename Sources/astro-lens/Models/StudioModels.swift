import Foundation
import SwiftUI

struct StudioProject: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var owner: String
    var updatedAt: Date
    var duration: TimeInterval
    var canvasStyle: CanvasStyle
    var zoomIntensity: Double
    var cursorStyle: CursorStyle
    var exportPreset: ExportPreset
    var exportFormat: ExportFormat?
    var exportQuality: ExportQuality?
    var captionText: String?
    var captionPlacement: CaptionPlacement?
    var clips: [StudioClip]
    var notes: String
    var referenceSnapshots: [StudioSnapshot]? = nil

    static let samples: [StudioProject] = [
        StudioProject(
            title: "Sales Cloud Pipeline Walkthrough",
            owner: "Demo Engineering",
            updatedAt: .now,
            duration: 142,
            canvasStyle: .aurora,
            zoomIntensity: 0.68,
            cursorStyle: .spotlight,
            exportPreset: .wide,
            clips: StudioClip.samples,
            notes: "Show account context, pipeline change, and final forecast update."
        ),
        StudioProject(
            title: "Agentforce Setup Flow",
            owner: "Platform UX",
            updatedAt: .now.addingTimeInterval(-8600),
            duration: 96,
            canvasStyle: .graphite,
            zoomIntensity: 0.52,
            cursorStyle: .halo,
            exportPreset: .square,
            clips: [
                StudioClip(title: "Connect data source", start: 0, duration: 30, kind: .recording),
                StudioClip(title: "Configure guardrails", start: 30, duration: 44, kind: .zoom),
                StudioClip(title: "Preview answer", start: 74, duration: 22, kind: .recording)
            ],
            notes: "Keep this one calm and short for async review."
        )
    ]
}

struct StudioClip: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case recording
        case zoom
        case cursor
        case keyHint
        case trim

        var color: Color {
            switch self {
            case .recording:
                Color.cyan
            case .zoom:
                Color.indigo
            case .cursor:
                Color.yellow
            case .keyHint:
                Color.green
            case .trim:
                Color.pink
            }
        }

        var displayName: String {
            switch self {
            case .recording:
                "Recording"
            case .zoom:
                "Zoom"
            case .cursor:
                "Cursor"
            case .keyHint:
                "Key Hint"
            case .trim:
                "Trim"
            }
        }
    }

    var id = UUID()
    var title: String
    var start: TimeInterval
    var duration: TimeInterval
    var kind: Kind
    var assetURL: URL?
    var presenterURL: URL?
    var microphoneURL: URL?
    var presenterPlacement: PresenterOptions.Placement?
    var presenterSize: Double?
    var sourceTitle: String?
    var fileSize: Int64?
    var interactionEvents: [InteractionEvent]?
    var generatedBy: String?
    var sourceClipID: UUID?
    var focusX: Double?
    var focusY: Double?
    var trimStart: TimeInterval?
    var trimEnd: TimeInterval?
    var redactions: [RedactionRegion]?

    init(
        id: UUID = UUID(),
        title: String,
        start: TimeInterval,
        duration: TimeInterval,
        kind: Kind,
        assetURL: URL? = nil,
        presenterURL: URL? = nil,
        microphoneURL: URL? = nil,
        presenterPlacement: PresenterOptions.Placement? = nil,
        presenterSize: Double? = nil,
        sourceTitle: String? = nil,
        fileSize: Int64? = nil,
        interactionEvents: [InteractionEvent]? = nil,
        generatedBy: String? = nil,
        sourceClipID: UUID? = nil,
        focusX: Double? = nil,
        focusY: Double? = nil,
        trimStart: TimeInterval? = nil,
        trimEnd: TimeInterval? = nil,
        redactions: [RedactionRegion]? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.duration = duration
        self.kind = kind
        self.assetURL = assetURL
        self.presenterURL = presenterURL
        self.microphoneURL = microphoneURL
        self.presenterPlacement = presenterPlacement
        self.presenterSize = presenterSize
        self.sourceTitle = sourceTitle
        self.fileSize = fileSize
        self.interactionEvents = interactionEvents
        self.generatedBy = generatedBy
        self.sourceClipID = sourceClipID
        self.focusX = focusX
        self.focusY = focusY
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.redactions = redactions
    }

    static let samples = [
        StudioClip(title: "Dashboard setup", start: 0, duration: 42, kind: .recording),
        StudioClip(title: "Auto zoom: field edit", start: 42, duration: 16, kind: .zoom),
        StudioClip(title: "Cursor emphasis", start: 58, duration: 12, kind: .cursor),
        StudioClip(title: "Export-ready close", start: 70, duration: 34, kind: .recording)
    ]
}

enum CanvasStyle: String, CaseIterable, Codable, Identifiable, Hashable {
    case aurora = "Aurora"
    case graphite = "Graphite"
    case cloud = "Cloud"
    case focus = "Focus"

    var id: String { rawValue }
}

enum CursorStyle: String, CaseIterable, Codable, Identifiable, Hashable {
    case halo = "Halo"
    case spotlight = "Spotlight"
    case trail = "Trail"
    case minimal = "Minimal"

    var id: String { rawValue }
}

enum ExportPreset: String, CaseIterable, Codable, Identifiable, Hashable {
    case wide = "16:9"
    case square = "1:1"
    case vertical = "9:16"
    case docs = "Docs"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .wide:
            "YouTube, Slack, Quip"
        case .square:
            "Feed previews"
        case .vertical:
            "Mobile review"
        case .docs:
            "Crisp embeds"
        }
    }
}

enum ExportFormat: String, CaseIterable, Codable, Identifiable, Hashable {
    case mp4 = "MP4"
    case mov = "MOV"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .mp4:
            "mp4"
        case .mov:
            "mov"
        }
    }

    var description: String {
        switch self {
        case .mp4:
            "Small, easy to share"
        case .mov:
            "Best for editing"
        }
    }
}

enum ExportQuality: String, CaseIterable, Codable, Identifiable, Hashable {
    case balanced = "Balanced"
    case crisp = "Crisp"
    case archive = "Archive"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .balanced:
            "Fast sharing"
        case .crisp:
            "Sharper demos"
        case .archive:
            "Highest quality"
        }
    }
}

enum CaptionPlacement: String, CaseIterable, Codable, Identifiable, Hashable {
    case lower = "Lower"
    case center = "Center"
    case upper = "Upper"

    var id: String { rawValue }
}

struct RecordedCapture: Codable, Hashable {
    var url: URL
    var createdAt: Date
    var duration: TimeInterval
    var sourceTitle: String
    var fileSize: Int64
    var interactionEvents: [InteractionEvent]
    var presenterURL: URL?
    var microphoneURL: URL?
    var presenterPlacement: PresenterOptions.Placement?
    var presenterSize: Double?
}

struct PresenterRecordingAsset: Codable, Hashable {
    var url: URL
    var placement: PresenterOptions.Placement
    var size: Double
}

struct ExportProgress: Equatable {
    var fraction: Double
    var stage: String

    var clampedFraction: Double {
        min(max(fraction, 0), 1)
    }

    var percentText: String {
        "\(Int((clampedFraction * 100).rounded()))%"
    }

    static let preparing = ExportProgress(fraction: 0.02, stage: "Preparing render")
    static let finishing = ExportProgress(fraction: 0.98, stage: "Finalizing movie")
    static let completed = ExportProgress(fraction: 1, stage: "Export ready")
}

struct ExportReadinessSummary: Equatable {
    var items: [ExportReadinessItem]

    var canExport: Bool {
        !items.contains { $0.state == .blocked }
    }

    var blockingMessage: String? {
        items.first { $0.state == .blocked }?.detail
    }
}

struct ExportReadinessItem: Identifiable, Equatable {
    enum State: Equatable {
        case ready
        case info
        case blocked
    }

    var id: String { title }
    var title: String
    var detail: String
    var state: State
}

struct RedactionRegion: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let defaultRegion = RedactionRegion(
        label: "Sensitive area",
        x: 0.34,
        y: 0.34,
        width: 0.32,
        height: 0.16
    )
}

struct StudioSnapshot: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var url: URL
    var createdAt: Date
    var pixelWidth: Double
    var pixelHeight: Double
}

extension StudioProject {
    var latestRecordingClip: StudioClip? {
        clips.last(where: { $0.kind == .recording && $0.assetURL != nil })
    }

    var generatedPolishClips: [StudioClip] {
        clips.filter { $0.generatedBy == AutoPolishService.generatorID }
    }

    var referenceSnapshotItems: [StudioSnapshot] {
        referenceSnapshots ?? []
    }

    var latestReferenceSnapshot: StudioSnapshot? {
        referenceSnapshotItems.first
    }

    var selectedExportFormat: ExportFormat {
        exportFormat ?? .mp4
    }

    var selectedExportQuality: ExportQuality {
        exportQuality ?? .balanced
    }

    var captionTextValue: String {
        captionText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var selectedCaptionPlacement: CaptionPlacement {
        captionPlacement ?? .lower
    }

    var hasCaption: Bool {
        !captionTextValue.isEmpty
    }

    func exportReadiness(sourceFileExists: Bool? = nil) -> ExportReadinessSummary {
        guard let recording = latestRecordingClip else {
            return ExportReadinessSummary(items: [
                ExportReadinessItem(
                    title: "Recording",
                    detail: "Record a clip before rendering.",
                    state: .blocked
                )
            ])
        }

        var items: [ExportReadinessItem] = []

        if sourceFileExists == false {
            items.append(
                ExportReadinessItem(
                    title: "Source file",
                    detail: "The latest recording file is missing from disk.",
                    state: .blocked
                )
            )
        } else {
            items.append(
                ExportReadinessItem(
                    title: "Source file",
                    detail: recording.sourceTitle ?? recording.title,
                    state: .ready
                )
            )
        }

        items.append(
            ExportReadinessItem(
                title: "Duration",
                detail: recording.effectiveDuration.formattedDuration,
                state: .ready
            )
        )

        items.append(
            ExportReadinessItem(
                title: "Privacy masks",
                detail: recording.hasRedactions ? "\(recording.redactionRegions.count) will render" : "None configured",
                state: recording.hasRedactions ? .ready : .info
            )
        )

        items.append(
            ExportReadinessItem(
                title: "Captions",
                detail: hasCaption ? selectedCaptionPlacement.rawValue : "None configured",
                state: hasCaption ? .ready : .info
            )
        )

        let polishCount = generatedPolishClips.filter { $0.sourceClipID == recording.id }.count
        items.append(
            ExportReadinessItem(
                title: "Auto polish",
                detail: polishCount > 0 ? "\(polishCount) effects" : "No generated effects",
                state: polishCount > 0 ? .ready : .info
            )
        )

        if recording.presenterURL != nil {
            items.append(
                ExportReadinessItem(
                    title: "Presenter",
                    detail: recording.presenterPlacement?.rawValue ?? "Attached",
                    state: .ready
                )
            )
        }

        return ExportReadinessSummary(items: items)
    }

    func duplicated(at date: Date = .now) -> StudioProject {
        var duplicate = self
        duplicate.id = UUID()
        duplicate.title = "\(title) Copy"
        duplicate.updatedAt = date

        var idMap: [UUID: UUID] = [:]
        duplicate.clips = clips.map { clip in
            var copiedClip = clip
            let copiedID = UUID()
            idMap[clip.id] = copiedID
            copiedClip.id = copiedID
            return copiedClip
        }
        duplicate.clips = duplicate.clips.map { clip in
            var copiedClip = clip
            if let sourceClipID = clip.sourceClipID,
               let copiedSourceID = idMap[sourceClipID] {
                copiedClip.sourceClipID = copiedSourceID
            }
            return copiedClip
        }

        return duplicate
    }
}

extension StudioClip {
    var redactionRegions: [RedactionRegion] {
        redactions ?? []
    }

    var hasRedactions: Bool {
        !redactionRegions.isEmpty
    }

    var trimStartValue: TimeInterval {
        max(trimStart ?? 0, 0)
    }

    var trimEndValue: TimeInterval {
        max(trimEnd ?? 0, 0)
    }

    var effectiveDuration: TimeInterval {
        max(duration - trimStartValue - trimEndValue, 0.1)
    }

    var hasTrim: Bool {
        trimStartValue > 0 || trimEndValue > 0
    }

    func clampedTrim(start: TimeInterval, end: TimeInterval) -> (start: TimeInterval, end: TimeInterval) {
        let safeStart = min(max(start, 0), max(duration - 0.1, 0))
        let safeEnd = min(max(end, 0), max(duration - safeStart - 0.1, 0))
        return (safeStart, safeEnd)
    }
}

extension RedactionRegion {
    var clamped: RedactionRegion {
        let safeWidth = min(max(width, 0.08), 0.88)
        let safeHeight = min(max(height, 0.06), 0.72)
        let safeX = min(max(x, 0), max(1 - safeWidth, 0))
        let safeY = min(max(y, 0), max(1 - safeHeight, 0))
        let safeLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)

        return RedactionRegion(
            id: id,
            label: safeLabel.isEmpty ? "Sensitive area" : safeLabel,
            x: safeX,
            y: safeY,
            width: safeWidth,
            height: safeHeight
        )
    }
}

struct InteractionEvent: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case click
        case keyPress

        var label: String {
            switch self {
            case .click:
                "Click"
            case .keyPress:
                "Key"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var timestamp: TimeInterval
    var label: String
    var x: Double?
    var y: Double?
    var modifiers: [String]

    static func click(timestamp: TimeInterval, x: Double, y: Double, modifiers: [String]) -> InteractionEvent {
        InteractionEvent(kind: .click, timestamp: timestamp, label: "Click", x: x, y: y, modifiers: modifiers)
    }

    static func keyPress(timestamp: TimeInterval, label: String, modifiers: [String]) -> InteractionEvent {
        InteractionEvent(kind: .keyPress, timestamp: timestamp, label: label, x: nil, y: nil, modifiers: modifiers)
    }
}
