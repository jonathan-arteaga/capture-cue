import AppKit

@MainActor
final class AreaSelectionService {
    private var activeSession: AreaSelectionSession?

    func selectArea() async -> CGRect? {
        await withCheckedContinuation { continuation in
            let session = AreaSelectionSession { [weak self] rect in
                self?.activeSession = nil
                continuation.resume(returning: rect)
            }

            activeSession = session
            session.begin()
        }
    }
}

@MainActor
private final class AreaSelectionSession {
    private let completion: (CGRect?) -> Void
    private var windows: [NSWindow] = []
    private var coordinator: AreaSelectionCoordinator?

    init(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
    }

    func begin() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            completion(nil)
            return
        }

        let coordinator = AreaSelectionCoordinator { [weak self] rect in
            self?.finish(rect)
        }
        self.coordinator = coordinator

        windows = screens.map { screen in
            let overlay = AreaSelectionView(screenFrame: screen.frame, coordinator: coordinator)
            coordinator.register(view: overlay)

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.contentView = overlay
            window.backgroundColor = .clear
            window.isOpaque = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.makeKeyAndOrderFront(nil)
            return window
        }

        NSCursor.crosshair.set()
    }

    private func finish(_ rect: CGRect?) {
        NSCursor.arrow.set()
        windows.forEach { $0.orderOut(nil) }
        windows = []
        coordinator = nil
        completion(rect)
    }
}

@MainActor
private final class AreaSelectionCoordinator {
    private let completion: (CGRect?) -> Void
    private var views: [WeakAreaSelectionView] = []
    private var startPoint: CGPoint?
    private(set) var currentRect: CGRect = .zero

    init(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
    }

    func register(view: AreaSelectionView) {
        views.append(WeakAreaSelectionView(view))
    }

    func begin(at point: CGPoint) {
        startPoint = point
        currentRect = .zero
        redraw()
    }

    func update(to point: CGPoint) {
        guard let startPoint else { return }
        currentRect = CGRect(
            x: min(startPoint.x, point.x),
            y: min(startPoint.y, point.y),
            width: abs(point.x - startPoint.x),
            height: abs(point.y - startPoint.y)
        )
        redraw()
    }

    func complete() {
        guard currentRect.width >= 8, currentRect.height >= 8 else {
            completion(nil)
            return
        }

        completion(currentRect.integral)
    }

    func cancel() {
        completion(nil)
    }

    private func redraw() {
        views = views.filter { $0.view != nil }
        views.forEach { $0.view?.needsDisplay = true }
    }
}

private struct WeakAreaSelectionView {
    weak var view: AreaSelectionView?

    init(_ view: AreaSelectionView) {
        self.view = view
    }
}

private final class AreaSelectionView: NSView {
    private let screenFrame: CGRect
    private let coordinator: AreaSelectionCoordinator

    init(screenFrame: CGRect, coordinator: AreaSelectionCoordinator) {
        self.screenFrame = screenFrame
        self.coordinator = coordinator
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        coordinator.begin(at: globalPoint(from: event))
    }

    override func mouseDragged(with event: NSEvent) {
        coordinator.update(to: globalPoint(from: event))
    }

    override func mouseUp(with event: NSEvent) {
        coordinator.complete()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            coordinator.cancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.42).setFill()
        bounds.fill()

        let localRect = coordinator.currentRect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        let visibleSelection = localRect.intersection(bounds)

        if !visibleSelection.isEmpty {
            NSGraphicsContext.current?.compositingOperation = .clear
            visibleSelection.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            let path = NSBezierPath(rect: visibleSelection)
            path.lineWidth = 2
            NSColor.trailBlue.setStroke()
            path.stroke()

            drawSizeLabel(for: visibleSelection)
        }
    }

    private func drawSizeLabel(for visibleSelection: CGRect) {
        let globalRect = coordinator.currentRect
        let text = "\(Int(globalRect.width)) x \(Int(globalRect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let labelRect = CGRect(
            x: min(max(visibleSelection.minX, bounds.minX + 8), bounds.maxX - size.width - 24),
            y: min(max(visibleSelection.maxY + 8, 8), bounds.maxY - size.height - 12),
            width: size.width + 16,
            height: size.height + 8
        )

        let pill = NSBezierPath(roundedRect: labelRect, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.72).setFill()
        pill.fill()
        text.draw(at: CGPoint(x: labelRect.minX + 8, y: labelRect.minY + 4), withAttributes: attributes)
    }

    private func globalPoint(from event: NSEvent) -> CGPoint {
        let localPoint = convert(event.locationInWindow, from: nil)
        return CGPoint(x: localPoint.x + screenFrame.minX, y: localPoint.y + screenFrame.minY)
    }
}

private extension NSColor {
    static let trailBlue = NSColor(calibratedRed: 0.05, green: 0.46, blue: 0.86, alpha: 1)
}
