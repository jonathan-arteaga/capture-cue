import AppKit
import UniformTypeIdentifiers

enum VideoImportPicker {
    @MainActor
    static func chooseVideo() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Recording"
        panel.prompt = "Import"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]

        return panel.runModal() == .OK ? panel.url : nil
    }
}
