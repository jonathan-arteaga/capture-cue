import SwiftUI

struct RecordingStatusBadge: View {
    let state: RecordingState
    let metrics: CaptureMetrics?
    var showsDetail = true

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 8) {
                statusDot

                VStack(alignment: .leading, spacing: 1) {
                    Text(state.statusTitle(at: context.date))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()

                    if showsDetail {
                        Text(detail(at: context.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, showsDetail ? 7 : 6)
            .background(statusColor.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(statusColor.opacity(0.24), lineWidth: 1)
            }
            .foregroundStyle(statusColor)
            .accessibilityLabel("\(state.statusTitle(at: context.date)), \(detail(at: context.date))")
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 7, height: 7)
            .shadow(color: statusColor.opacity(state.isActive ? 0.8 : 0), radius: 5)
    }

    private var statusColor: Color {
        switch state {
        case .idle:
            .secondary
        case .preparing, .stopping:
            .yellow
        case .recording:
            .red
        case .failed:
            .orange
        }
    }

    private func detail(at date: Date) -> String {
        guard state.isActive,
              let metrics,
              metrics.framesReceived > 0 else {
            return state.statusDetail(at: date)
        }

        return "\(metrics.frameReadout) captured"
    }
}
