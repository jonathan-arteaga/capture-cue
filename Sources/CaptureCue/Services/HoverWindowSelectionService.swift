import AppKit

@MainActor
final class HoverWindowSelectionService {
    private var activeSession: HoverWindowSelectionSession?

    func selectWindow(from candidates: [CaptureWindowCandidate]) async -> CaptureWindowCandidate? {
        guard !candidates.isEmpty else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let session = HoverWindowSelectionSession(candidates: candidates) { [weak self] candidate in
                self?.activeSession = nil
                continuation.resume(returning: candidate)
            }

            activeSession = session
            session.begin()
        }
    }
}

@MainActor
private final class HoverWindowSelectionSession {
    private let candidates: [CaptureWindowCandidate]
    private let completion: (CaptureWindowCandidate?) -> Void
    private var windows: [NSWindow] = []
    private var coordinator: HoverWindowSelectionCoordinator?
    private var isFinished = false

    init(candidates: [CaptureWindowCandidate], completion: @escaping (CaptureWindowCandidate?) -> Void) {
        self.candidates = candidates
        self.completion = completion
    }

    func begin() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            completion(nil)
            return
        }

        let coordinator = HoverWindowSelectionCoordinator(
            candidates: candidates,
            screenFrames: screens.map(\.frame),
            completion: { [weak self] candidate in
                self?.finish(candidate)
            }
        )
        self.coordinator = coordinator

        windows = screens.map { screen in
            let overlay = HoverWindowSelectionView(screenFrame: screen.frame, coordinator: coordinator)
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
            window.makeFirstResponder(overlay)
            return window
        }

        NSCursor.pointingHand.set()
    }

    private func finish(_ candidate: CaptureWindowCandidate?) {
        guard !isFinished else { return }
        isFinished = true

        NSCursor.arrow.set()
        windows.forEach { $0.orderOut(nil) }
        windows = []
        coordinator = nil
        completion(candidate)
    }
}

@MainActor
private final class HoverWindowSelectionCoordinator {
    private let candidates: [CaptureWindowCandidate]
    private let desktopFrame: CGRect
    private let completion: (CaptureWindowCandidate?) -> Void
    private var views: [WeakHoverWindowSelectionView] = []
    private(set) var highlightedCandidate: CaptureWindowCandidate?

    init(
        candidates: [CaptureWindowCandidate],
        screenFrames: [CGRect],
        completion: @escaping (CaptureWindowCandidate?) -> Void
    ) {
        self.candidates = candidates.sorted { lhs, rhs in
            (lhs.frame.width * lhs.frame.height) < (rhs.frame.width * rhs.frame.height)
        }
        self.desktopFrame = screenFrames.reduce(CGRect.null) { $0.union($1) }
        self.completion = completion
    }

    func register(view: HoverWindowSelectionView) {
        views.append(WeakHoverWindowSelectionView(view))
    }

    func updateHover(at appKitPoint: CGPoint) {
        let capturePoint = CGPoint(x: appKitPoint.x, y: desktopFrame.maxY - appKitPoint.y)
        let nextCandidate = candidates.first { candidate in
            candidate.frame.insetBy(dx: -4, dy: -4).contains(capturePoint)
        }

        guard nextCandidate?.id != highlightedCandidate?.id else { return }
        highlightedCandidate = nextCandidate
        redraw()
    }

    func complete() {
        completion(highlightedCandidate)
    }

    func cancel() {
        completion(nil)
    }

    func appKitRect(for captureRect: CGRect) -> CGRect {
        CGRect(
            x: captureRect.minX,
            y: desktopFrame.maxY - captureRect.maxY,
            width: captureRect.width,
            height: captureRect.height
        )
    }

    private func redraw() {
        views = views.filter { $0.view != nil }
        views.forEach { $0.view?.needsDisplay = true }
    }
}

private struct WeakHoverWindowSelectionView {
    weak var view: HoverWindowSelectionView?

    init(_ view: HoverWindowSelectionView) {
        self.view = view
    }
}

private final class HoverWindowSelectionView: NSView {
    private let screenFrame: CGRect
    private let coordinator: HoverWindowSelectionCoordinator

    init(screenFrame: CGRect, coordinator: HoverWindowSelectionCoordinator) {
        self.screenFrame = screenFrame
        self.coordinator = coordinator
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseMoved(with event: NSEvent) {
        coordinator.updateHover(at: globalPoint(from: event))
    }

    override func mouseDragged(with event: NSEvent) {
        coordinator.updateHover(at: globalPoint(from: event))
    }

    override func mouseDown(with event: NSEvent) {
        coordinator.updateHover(at: globalPoint(from: event))
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
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()

        guard let candidate = coordinator.highlightedCandidate else {
            return
        }

        let windowRect = coordinator
            .appKitRect(for: candidate.frame)
            .offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
            .intersection(bounds)

        guard !windowRect.isEmpty else {
            return
        }

        let highlightPath = NSBezierPath(roundedRect: windowRect, xRadius: 10, yRadius: 10)
        NSGraphicsContext.current?.compositingOperation = .clear
        highlightPath.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        highlightPath.lineWidth = 3
        NSColor.trailBlue.setStroke()
        highlightPath.stroke()

        let innerPath = NSBezierPath(roundedRect: windowRect.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8)
        innerPath.lineWidth = 1
        NSColor.white.withAlphaComponent(0.85).setStroke()
        innerPath.stroke()

        drawLabel(for: candidate, near: windowRect)
    }

    private func drawLabel(for candidate: CaptureWindowCandidate, near windowRect: CGRect) {
        let title = candidate.displayTitle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = title.size(withAttributes: attributes)
        let labelWidth = min(size.width + 20, max(bounds.width - 24, 80))
        let labelRect = CGRect(
            x: min(max(windowRect.minX, bounds.minX + 12), bounds.maxX - labelWidth - 12),
            y: max(min(windowRect.minY - size.height - 18, bounds.maxY - size.height - 18), bounds.minY + 12),
            width: labelWidth,
            height: size.height + 10
        )

        let pill = NSBezierPath(roundedRect: labelRect, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.76).setFill()
        pill.fill()

        let clippedTitle = title as NSString
        clippedTitle.draw(
            in: labelRect.insetBy(dx: 10, dy: 5),
            withAttributes: attributes
        )
    }

    private func globalPoint(from event: NSEvent) -> CGPoint {
        let localPoint = convert(event.locationInWindow, from: nil)
        return CGPoint(x: localPoint.x + screenFrame.minX, y: localPoint.y + screenFrame.minY)
    }
}

private extension NSColor {
    static let trailBlue = NSColor(calibratedRed: 0.05, green: 0.46, blue: 0.86, alpha: 1)
}
