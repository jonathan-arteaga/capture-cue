import AppKit
import Observation

@MainActor
@Observable
final class CaptureStore {
    var captures: [CaptureItem]
    var selectedCaptureID: CaptureItem.ID?
    var status: CaptureStatus = .ready
    var activeTool: AnnotationTool = .arrow
    var activeText = "Note"
    var selectedAnnotationID: CaptureAnnotation.ID?
    var pinnedCaptures: [PinnedCapture] = []
    var hasScreenRecordingPermission: Bool
    var areGlobalShortcutsEnabled: Bool
    var globalShortcuts: [GlobalShortcut]
    var globalShortcutRegistrations: [GlobalShortcutRegistration] = []
    var shortcutEditingMessage: String?

    @ObservationIgnored private let captureService = ScreenshotCaptureService()
    @ObservationIgnored private let selectionService = AreaSelectionService()
    @ObservationIgnored private let hoverWindowSelectionService = HoverWindowSelectionService()
    @ObservationIgnored private let exportService = ImageExportService()
    @ObservationIgnored private let quickAccessService = QuickAccessService()
    @ObservationIgnored private let pinWindowService = PinWindowService()
    @ObservationIgnored private let sensitiveTextDetectionService = SensitiveTextDetectionService()
    @ObservationIgnored private let captureLibraryService: CaptureLibraryService
    @ObservationIgnored private let permissionService = ScreenRecordingPermissionService()
    @ObservationIgnored private let globalHotKeyService = GlobalHotKeyService()
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored var onOpenMarkup: (() -> Void)?
    @ObservationIgnored var onUseInStudio: (() -> Void)?

    init(
        userDefaults: UserDefaults = .standard,
        captureLibraryDirectory: URL = CaptureLibraryService.defaultLibraryDirectory
    ) {
        self.userDefaults = userDefaults
        self.captureLibraryService = CaptureLibraryService(directory: captureLibraryDirectory)
        self.hasScreenRecordingPermission = permissionService.hasPermission()
        self.areGlobalShortcutsEnabled = userDefaults.object(forKey: PreferencesKeys.globalShortcutsEnabled) as? Bool ?? true
        self.globalShortcuts = Self.loadGlobalShortcuts(from: userDefaults)
        self.captures = captureLibraryService.loadCaptures()
        self.selectedCaptureID = captures.first?.id
    }

    var selectedCapture: CaptureItem? {
        guard let selectedCaptureID else { return captures.first }
        return captures.first { $0.id == selectedCaptureID }
    }

    var selectedAnnotation: CaptureAnnotation? {
        guard let selectedCapture, let selectedAnnotationID else { return nil }
        return selectedCapture.annotations.first { $0.id == selectedAnnotationID }
    }

    var recentCaptures: [CaptureItem] {
        Array(captures.prefix(24))
    }

    var defaultGlobalShortcuts: [GlobalShortcut] {
        GlobalShortcutAction.allCases.map(\.defaultShortcut)
    }

    var globalShortcutSummary: String {
        guard areGlobalShortcutsEnabled else { return "Shortcuts off" }
        guard !globalShortcutRegistrations.isEmpty else { return "Shortcuts starting" }
        let failedCount = globalShortcutRegistrations.filter { !$0.isRegistered }.count
        return failedCount == 0 ? "Shortcuts ready" : "\(failedCount) unavailable"
    }

    func startGlobalShortcuts() {
        configureGlobalShortcuts()
    }

    func setGlobalShortcutsEnabled(_ enabled: Bool) {
        areGlobalShortcutsEnabled = enabled
        userDefaults.set(enabled, forKey: PreferencesKeys.globalShortcutsEnabled)
        configureGlobalShortcuts()
    }

    func updateGlobalShortcut(_ shortcut: GlobalShortcut) {
        guard shortcut.isUsableGlobalShortcut else {
            shortcutEditingMessage = "Use Command, Control, or Option with a key."
            return
        }

        guard !hasShortcutConflict(shortcut) else {
            shortcutEditingMessage = "\(shortcut.displayValue) is already assigned."
            return
        }

        replaceGlobalShortcut(shortcut)
        shortcutEditingMessage = "\(shortcut.action.title) set to \(shortcut.displayValue)."
    }

    func resetGlobalShortcut(action: GlobalShortcutAction) {
        replaceGlobalShortcut(action.defaultShortcut)
        shortcutEditingMessage = "\(action.title) reset."
    }

    func resetAllGlobalShortcuts() {
        globalShortcuts = defaultGlobalShortcuts
        persistGlobalShortcuts()
        configureGlobalShortcuts()
        shortcutEditingMessage = "Shortcuts reset."
    }

    func captureArea() async {
        guard ensureScreenRecordingPermission() else { return }
        status = .selectingArea

        do {
            guard let rect = await selectionService.selectArea() else {
                status = .ready
                return
            }

            status = .working("Capturing selection")
            let image = try await captureService.captureMainDisplay(rect: rect)
            insertCapture(image: image, kind: .area)
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func captureFullScreen() async {
        guard ensureScreenRecordingPermission() else { return }
        status = .working("Capturing screen")

        do {
            let image = try await captureService.captureAllDisplays()
            insertCapture(image: image, kind: .fullScreen)
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func captureWindow() async {
        guard ensureScreenRecordingPermission() else { return }
        status = .working("Choose a window")

        do {
            let candidates = try await captureService.availableWindows()
            guard !candidates.isEmpty else {
                status = .failed("No capturable windows found.")
                return
            }

            guard let candidate = await hoverWindowSelectionService.selectWindow(from: candidates) else {
                status = .ready
                return
            }

            status = .working("Capturing \(candidate.appName)")
            let image = try await captureService.captureWindow(id: candidate.id)
            insertCapture(image: image, kind: .window)
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func selectCapture(id: CaptureItem.ID) {
        selectedCaptureID = id
        selectedAnnotationID = nil
    }

    func copySelectedCapture() {
        guard let capture = selectedCapture else { return }
        exportService.copyToClipboard(exportService.renderedImage(for: capture))
        showTransientStatus("Copied image")
    }

    func copySelectedCaptureFramed() {
        guard let capture = selectedCapture else { return }
        exportService.copyToClipboard(exportService.framedImage(for: capture))
        showTransientStatus("Copied framed image")
    }

    func saveSelectedCapture() async {
        guard let capture = selectedCapture else { return }
        await exportService.saveWithPanel(capture)
    }

    func saveSelectedCaptureFramed() async {
        guard let capture = selectedCapture else { return }
        await exportService.saveFramedWithPanel(capture)
    }

    func renderedSelectedCapture() -> NSImage? {
        guard let capture = selectedCapture else { return nil }
        return exportService.renderedImage(for: capture)
    }

    func pinSelectedCapture() {
        guard let capture = selectedCapture else { return }
        let renderedImage = exportService.renderedImage(for: capture)
        let pinnedCapture = PinnedCapture(
            captureID: capture.id,
            title: capture.name,
            createdAt: Date(),
            pixelSize: renderedImage.pixelSize
        )

        pinnedCaptures.insert(pinnedCapture, at: 0)
        pinWindowService.pin(id: pinnedCapture.id, image: renderedImage, title: pinnedCapture.title) { [weak self] id in
            Task { @MainActor in
                self?.pinnedCaptures.removeAll { $0.id == id }
            }
        }
    }

    func autoRedactSensitiveText() async {
        guard let index = selectedCaptureIndex else { return }
        status = .working("Scanning locally")

        do {
            let matches = try await sensitiveTextDetectionService.detect(in: captures[index].image)
            guard !matches.isEmpty else {
                showTransientStatus("No sensitive text found")
                return
            }

            let annotations = matches.map(\.redactionAnnotation)
            captures[index].annotations.append(contentsOf: annotations)
            selectedAnnotationID = annotations.last?.id
            activeTool = .move
            persistCaptureLibrary()
            showTransientStatus("Added \(annotations.count) redaction\(annotations.count == 1 ? "" : "s")")
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func clearAnnotations() {
        guard let index = selectedCaptureIndex else { return }
        captures[index].annotations.removeAll()
        selectedAnnotationID = nil
        persistCaptureLibrary()
    }

    func addAnnotation(tool: AnnotationTool, start: CGPoint, end: CGPoint) {
        guard let index = selectedCaptureIndex, tool != .move else { return }

        let annotation = CaptureAnnotation(
            tool: tool,
            start: start.clampedToUnitSquare,
            end: end.clampedToUnitSquare,
            text: activeText.isEmpty ? "Note" : activeText,
            stepNumber: nextStepNumber(for: captures[index])
        )
        captures[index].annotations.append(annotation)
        selectedAnnotationID = annotation.id
        persistCaptureLibrary()
    }

    func selectAnnotation(id: CaptureAnnotation.ID?) {
        selectedAnnotationID = id
        if id != nil {
            activeTool = .move
        }
    }

    func moveAnnotation(id: CaptureAnnotation.ID, by delta: CGPoint) {
        guard
            let captureIndex = selectedCaptureIndex,
            let annotationIndex = captures[captureIndex].annotations.firstIndex(where: { $0.id == id })
        else {
            return
        }

        var annotation = captures[captureIndex].annotations[annotationIndex]
        annotation.start = annotation.start.offsetBy(delta).clampedToUnitSquare
        annotation.end = annotation.end.offsetBy(delta).clampedToUnitSquare
        captures[captureIndex].annotations[annotationIndex] = annotation
        persistCaptureLibrary()
    }

    func resizeAnnotation(id: CaptureAnnotation.ID, handle: AnnotationResizeHandle, to point: CGPoint) {
        guard
            let captureIndex = selectedCaptureIndex,
            let annotationIndex = captures[captureIndex].annotations.firstIndex(where: { $0.id == id })
        else {
            return
        }

        var annotation = captures[captureIndex].annotations[annotationIndex]
        let point = point.clampedToUnitSquare

        switch annotation.tool {
        case .arrow:
            if handle == .start {
                annotation.start = point
            } else {
                annotation.end = point
            }
        case .rectangle, .redact:
            let minX = min(annotation.start.x, annotation.end.x)
            let maxX = max(annotation.start.x, annotation.end.x)
            let minY = min(annotation.start.y, annotation.end.y)
            let maxY = max(annotation.start.y, annotation.end.y)

            switch handle {
            case .topLeft:
                annotation.start = CGPoint(x: min(point.x, maxX - 0.01), y: min(point.y, maxY - 0.01))
                annotation.end = CGPoint(x: maxX, y: maxY)
            case .topRight:
                annotation.start = CGPoint(x: minX, y: min(point.y, maxY - 0.01))
                annotation.end = CGPoint(x: max(point.x, minX + 0.01), y: maxY)
            case .bottomLeft:
                annotation.start = CGPoint(x: min(point.x, maxX - 0.01), y: minY)
                annotation.end = CGPoint(x: maxX, y: max(point.y, minY + 0.01))
            case .bottomRight, .end:
                annotation.start = CGPoint(x: minX, y: minY)
                annotation.end = CGPoint(x: max(point.x, minX + 0.01), y: max(point.y, minY + 0.01))
            case .start:
                annotation.start = point
            }
        case .text, .step, .move:
            annotation.start = point
            annotation.end = point
        }

        captures[captureIndex].annotations[annotationIndex] = annotation
        persistCaptureLibrary()
    }

    func updateSelectedAnnotationText(_ text: String) {
        guard
            let captureIndex = selectedCaptureIndex,
            let selectedAnnotationID,
            let annotationIndex = captures[captureIndex].annotations.firstIndex(where: { $0.id == selectedAnnotationID }),
            captures[captureIndex].annotations[annotationIndex].tool == .text
        else {
            return
        }

        captures[captureIndex].annotations[annotationIndex].text = text
        persistCaptureLibrary()
    }

    func deleteSelectedAnnotation() {
        guard
            let index = selectedCaptureIndex,
            let selectedAnnotationID,
            let annotationIndex = captures[index].annotations.firstIndex(where: { $0.id == selectedAnnotationID })
        else {
            return
        }

        captures[index].annotations.remove(at: annotationIndex)
        self.selectedAnnotationID = nil
        persistCaptureLibrary()
    }

    func undoLastAnnotation() {
        guard let index = selectedCaptureIndex, !captures[index].annotations.isEmpty else { return }
        let removed = captures[index].annotations.removeLast()
        if selectedAnnotationID == removed.id {
            selectedAnnotationID = nil
        }
        persistCaptureLibrary()
    }

    func deleteSelectedCapture() {
        guard let selectedCapture else { return }
        captures.removeAll { $0.id == selectedCapture.id }
        selectedCaptureID = captures.first?.id
        selectedAnnotationID = nil
        persistCaptureLibrary()
    }

    func refreshScreenRecordingPermission() {
        hasScreenRecordingPermission = permissionService.hasPermission()
        if hasScreenRecordingPermission, case .failed(let message) = status, message == screenRecordingPermissionMessage {
            status = .ready
        }
    }

    func requestScreenRecordingPermission() {
        hasScreenRecordingPermission = permissionService.requestPermission()
        if hasScreenRecordingPermission {
            status = .ready
        } else {
            status = .failed(screenRecordingPermissionMessage)
        }
    }

    func openScreenRecordingSettings() {
        permissionService.openSystemSettings()
        status = .failed(screenRecordingPermissionMessage)
    }

    private func insertCapture(image: NSImage, kind: CaptureKind) {
        let createdAt = Date()
        let item = CaptureItem(
            kind: kind,
            createdAt: createdAt,
            image: image,
            pixelSize: image.pixelSize,
            name: "\(kind.rawValue) \(createdAt.formatted(date: .omitted, time: .shortened))"
        )

        captures.insert(item, at: 0)
        selectedCaptureID = item.id
        selectedAnnotationID = nil
        persistCaptureLibrary()
        exportService.copyToClipboard(image)
        quickAccessService.show(
            captureName: item.name,
            subtitle: "Copied to clipboard",
            copy: { [weak self] in self?.copySelectedCapture() },
            save: { [weak self] in Task { await self?.saveSelectedCapture() } },
            pin: { [weak self] in self?.pinSelectedCapture() },
            annotate: { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.onOpenMarkup?()
            },
            useInStudio: { [weak self] in
                NSApp.activate(ignoringOtherApps: true)
                self?.onUseInStudio?()
            }
        )
    }

    private func configureGlobalShortcuts() {
        guard areGlobalShortcutsEnabled else {
            globalHotKeyService.unregisterAll()
            globalShortcutRegistrations = []
            return
        }

        globalShortcutRegistrations = globalHotKeyService.register(shortcuts: globalShortcuts) { [weak self] action in
            Task { @MainActor in
                await self?.performGlobalShortcut(action)
            }
        }
    }

    private func performGlobalShortcut(_ action: GlobalShortcutAction) async {
        switch action {
        case .captureArea:
            await captureArea()
        case .captureFullScreen:
            await captureFullScreen()
        case .captureWindow:
            await captureWindow()
        }
    }

    private func replaceGlobalShortcut(_ shortcut: GlobalShortcut) {
        if let index = globalShortcuts.firstIndex(where: { $0.action == shortcut.action }) {
            globalShortcuts[index] = shortcut
        } else {
            globalShortcuts.append(shortcut)
            globalShortcuts.sort { $0.action.rawValue < $1.action.rawValue }
        }

        persistGlobalShortcuts()
        configureGlobalShortcuts()
    }

    private func hasShortcutConflict(_ shortcut: GlobalShortcut) -> Bool {
        globalShortcuts.contains {
            $0.action != shortcut.action &&
                $0.keyCode == shortcut.keyCode &&
                $0.modifiers == shortcut.modifiers
        }
    }

    private func persistGlobalShortcuts() {
        guard let data = try? JSONEncoder().encode(globalShortcuts) else { return }
        userDefaults.set(data, forKey: PreferencesKeys.globalShortcuts)
    }

    private static func loadGlobalShortcuts(from userDefaults: UserDefaults) -> [GlobalShortcut] {
        guard
            let data = userDefaults.data(forKey: PreferencesKeys.globalShortcuts),
            let decoded = try? JSONDecoder().decode([GlobalShortcut].self, from: data)
        else {
            return GlobalShortcutAction.allCases.map(\.defaultShortcut)
        }

        return GlobalShortcutAction.allCases.map { action in
            decoded.first { $0.action == action && $0.isUsableGlobalShortcut } ?? action.defaultShortcut
        }
    }

    private func persistCaptureLibrary() {
        do {
            try captureLibraryService.saveCaptures(captures)
        } catch {
            status = .failed("Could not save capture history.")
        }
    }

    private func showTransientStatus(_ message: String) {
        status = .working(message)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard case .working(message) = self?.status else { return }
            self?.status = .ready
        }
    }

    private var selectedCaptureIndex: Int? {
        guard let selectedCaptureID else {
            return captures.isEmpty ? nil : 0
        }
        return captures.firstIndex { $0.id == selectedCaptureID }
    }

    private func nextStepNumber(for capture: CaptureItem) -> Int {
        let maxStep = capture.annotations
            .filter { $0.tool == .step }
            .map(\.stepNumber)
            .max() ?? 0
        return maxStep + 1
    }

    private func ensureScreenRecordingPermission() -> Bool {
        hasScreenRecordingPermission = permissionService.hasPermission()
        guard hasScreenRecordingPermission else {
            status = .failed(screenRecordingPermissionMessage)
            return false
        }
        return true
    }
}

private let screenRecordingPermissionMessage = "Screen Recording permission required."

private enum PreferencesKeys {
    static let globalShortcutsEnabled = "globalShortcutsEnabled"
    static let globalShortcuts = "globalShortcuts"
}

private extension CGPoint {
    var clampedToUnitSquare: CGPoint {
        CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    func offsetBy(_ delta: CGPoint) -> CGPoint {
        CGPoint(x: x + delta.x, y: y + delta.y)
    }
}
