import Foundation

extension TimeInterval {
    var formattedDuration: String {
        let totalSeconds = max(Int(self), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

extension Int64 {
    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension Date {
    var formattedExportTimestamp: String {
        formatted(
            date: .abbreviated,
            time: .shortened
        )
    }
}
