import Foundation

struct AutoPolishService {
    static let generatorID = "capturecue.auto-polish.v1"

    func suggestions(for recordingClip: StudioClip, intensity: Double) -> [StudioClip] {
        let events = (recordingClip.interactionEvents ?? [])
            .sorted { $0.timestamp < $1.timestamp }

        var suggestions: [StudioClip] = []
        var lastZoomTime: TimeInterval = -10

        for event in events {
            switch event.kind {
            case .click:
                if event.timestamp - lastZoomTime >= 1.2 {
                    suggestions.append(
                        StudioClip(
                            title: "Auto zoom",
                            start: recordingClip.start + max(event.timestamp - 0.35, 0),
                            duration: zoomDuration(for: intensity),
                            kind: .zoom,
                            generatedBy: Self.generatorID,
                            sourceClipID: recordingClip.id,
                            focusX: event.x,
                            focusY: event.y
                        )
                    )
                    lastZoomTime = event.timestamp
                }

                suggestions.append(
                    StudioClip(
                        title: "Cursor emphasis",
                        start: recordingClip.start + max(event.timestamp - 0.08, 0),
                        duration: 0.65,
                        kind: .cursor,
                        generatedBy: Self.generatorID,
                        sourceClipID: recordingClip.id,
                        focusX: event.x,
                        focusY: event.y
                    )
                )

            case .keyPress:
                suggestions.append(
                    StudioClip(
                        title: event.label,
                        start: recordingClip.start + event.timestamp,
                        duration: 1.1,
                        kind: .keyHint,
                        generatedBy: Self.generatorID,
                        sourceClipID: recordingClip.id
                    )
                )
            }
        }

        return coalesced(suggestions, recordingClip: recordingClip)
    }

    private func zoomDuration(for intensity: Double) -> TimeInterval {
        let normalized = min(max(intensity, 0), 1)
        return 1.3 + (normalized * 1.1)
    }

    private func coalesced(_ clips: [StudioClip], recordingClip: StudioClip) -> [StudioClip] {
        var output: [StudioClip] = []

        for clip in clips.sorted(by: { $0.start < $1.start }) {
            let end = min(clip.start + clip.duration, recordingClip.start + recordingClip.duration)
            guard end > clip.start else {
                continue
            }

            var clipped = clip
            clipped.duration = end - clipped.start

            if let previous = output.last,
               previous.kind == clipped.kind,
               clipped.start - (previous.start + previous.duration) < 0.28 {
                var merged = previous
                merged.duration = max(previous.duration, clipped.start + clipped.duration - previous.start)
                output[output.count - 1] = merged
            } else {
                output.append(clipped)
            }
        }

        return output
    }
}
