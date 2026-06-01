import AppKit
import UniformTypeIdentifiers

@MainActor
struct ImageExportService {
    enum ExportVariant {
        case annotated
        case framed
    }

    func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    func saveWithPanel(_ capture: CaptureItem) async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedFilename(for: capture, variant: .annotated)
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try renderedImage(for: capture).pngData()?.write(to: url, options: .atomic)
        } catch {
            NSSound.beep()
        }
    }

    func saveFramedWithPanel(_ capture: CaptureItem) async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedFilename(for: capture, variant: .framed)
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try framedImage(for: capture).pngData()?.write(to: url, options: .atomic)
        } catch {
            NSSound.beep()
        }
    }

    func renderedImage(for capture: CaptureItem) -> NSImage {
        let image = NSImage(size: capture.image.size)
        image.lockFocus()

        let canvas = CGRect(origin: .zero, size: capture.image.size)
        capture.image.draw(in: canvas)

        for annotation in capture.annotations {
            draw(annotation, in: canvas)
        }

        image.unlockFocus()
        return image
    }

    func temporaryPNGURL(for capture: CaptureItem, variant: ExportVariant) throws -> URL {
        let directory = try dragExportDirectory()
        let image: NSImage
        let suffix: String

        switch variant {
        case .annotated:
            image = renderedImage(for: capture)
            suffix = "annotated"
        case .framed:
            image = framedImage(for: capture)
            suffix = "framed"
        }

        guard let data = image.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }

        let filename = "\(baseFilename(for: capture))-\(suffix)-\(UUID().uuidString.prefix(8)).png"
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    func suggestedFilename(for capture: CaptureItem, variant: ExportVariant) -> String {
        let suffix: String
        switch variant {
        case .annotated:
            suffix = ""
        case .framed:
            suffix = "-framed"
        }

        return "\(baseFilename(for: capture))\(suffix).png"
    }

    func framedImage(for capture: CaptureItem) -> NSImage {
        let content = renderedImage(for: capture)
        let contentSize = content.size
        let padding = min(max(min(contentSize.width, contentSize.height) * 0.08, 72), 150)
        let titleBarHeight = min(max(contentSize.height * 0.035, 30), 46)
        let windowSize = CGSize(width: contentSize.width, height: contentSize.height + titleBarHeight)
        let canvasSize = CGSize(width: windowSize.width + padding * 2, height: windowSize.height + padding * 2)
        let image = NSImage(size: canvasSize)

        image.lockFocus()

        let canvas = CGRect(origin: .zero, size: canvasSize)
        drawFramedBackground(in: canvas)

        let windowRect = CGRect(
            x: padding,
            y: padding,
            width: windowSize.width,
            height: windowSize.height
        )
        let windowPath = NSBezierPath(roundedRect: windowRect, xRadius: 16, yRadius: 16)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 34
        shadow.shadowOffset = CGSize(width: 0, height: -14)
        shadow.set()
        NSColor.white.setFill()
        windowPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.setFill()
        windowPath.fill()

        let titleBarRect = CGRect(
            x: windowRect.minX,
            y: windowRect.maxY - titleBarHeight,
            width: windowRect.width,
            height: titleBarHeight
        )
        drawTitleBar(in: titleBarRect, title: capture.name)

        let contentRect = CGRect(
            x: windowRect.minX,
            y: windowRect.minY,
            width: contentSize.width,
            height: contentSize.height
        )
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: windowRect, xRadius: 16, yRadius: 16).addClip()
        content.draw(in: contentRect)
        NSGraphicsContext.restoreGraphicsState()

        windowPath.lineWidth = 1
        NSColor.black.withAlphaComponent(0.08).setStroke()
        windowPath.stroke()

        image.unlockFocus()
        return image
    }

    private func draw(_ annotation: CaptureAnnotation, in canvas: CGRect) {
        let start = annotation.start.denormalized(in: canvas)
        let end = annotation.end.denormalized(in: canvas)
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        switch annotation.tool {
        case .move:
            break
        case .arrow:
            drawArrow(from: start, to: end)
        case .rectangle:
            drawRectangle(rect)
        case .text:
            drawText(annotation.text, at: start)
        case .redact:
            drawRedaction(rect)
        case .step:
            drawStep(annotation.stepNumber, at: start)
        }
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = 5
        NSColor.trailAccent.setStroke()
        path.stroke()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 18
        let arrowAngle: CGFloat = .pi / 7
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        ))
        head.move(to: end)
        head.line(to: CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        ))
        head.lineWidth = 5
        NSColor.trailAccent.setStroke()
        head.stroke()
    }

    private func drawRectangle(_ rect: CGRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        path.lineWidth = 5
        NSColor.trailAccent.setStroke()
        path.stroke()
    }

    private func drawText(_ text: String, at point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.trailAccent
        ]
        text.draw(at: point, withAttributes: attributes)
    }

    private func drawRedaction(_ rect: CGRect) {
        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
    }

    private func drawStep(_ number: Int, at point: CGPoint) {
        let diameter: CGFloat = 32
        let rect = CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2, width: diameter, height: diameter)
        NSColor.trailAccent.setFill()
        NSBezierPath(ovalIn: rect).fill()

        let text = "\(number)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func drawFramedBackground(in rect: CGRect) {
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.96, green: 0.98, blue: 0.98, alpha: 1),
            NSColor(calibratedRed: 0.89, green: 0.93, blue: 0.97, alpha: 1)
        ])
        gradient?.draw(in: rect, angle: -35)

        NSColor(calibratedWhite: 1, alpha: 0.22).setFill()
        NSBezierPath(rect: rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)).fill()
    }

    private func drawTitleBar(in rect: CGRect, title: String) {
        let titlePath = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
        NSColor(calibratedRed: 0.98, green: 0.985, blue: 0.99, alpha: 1).setFill()
        titlePath.fill()

        let dividerRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1)
        NSColor.black.withAlphaComponent(0.06).setFill()
        dividerRect.fill()

        let dotDiameter: CGFloat = 11
        let dotY = rect.midY - dotDiameter / 2
        let dotColors = [
            NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.34, alpha: 1),
            NSColor(calibratedRed: 1.0, green: 0.77, blue: 0.23, alpha: 1),
            NSColor(calibratedRed: 0.28, green: 0.79, blue: 0.35, alpha: 1)
        ]

        for (index, color) in dotColors.enumerated() {
            let dotRect = CGRect(
                x: rect.minX + 18 + CGFloat(index) * 18,
                y: dotY,
                width: dotDiameter,
                height: dotDiameter
            )
            color.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let textSize = title.size(withAttributes: attributes)
        let textRect = CGRect(
            x: rect.midX - min(textSize.width, rect.width * 0.44) / 2,
            y: rect.midY - textSize.height / 2,
            width: min(textSize.width, rect.width * 0.44),
            height: textSize.height
        )
        (title as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private func dragExportDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CaptureCueDragExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        removeStaleDragExports(in: directory)
        return directory
    }

    private func removeStaleDragExports(in directory: URL) {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )
        else {
            return
        }

        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for file in files {
            let modificationDate = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if modificationDate.map({ $0 < cutoff }) ?? false {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func baseFilename(for capture: CaptureItem) -> String {
        safeFilename(capture.name)
    }

    private func safeFilename(_ name: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitizedScalars = name.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(sanitizedScalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "CaptureCue" : collapsed
    }
}

private extension CGPoint {
    func denormalized(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + (1 - y) * rect.height)
    }
}

private extension NSColor {
    static let trailAccent = NSColor(calibratedRed: 0.05, green: 0.46, blue: 0.86, alpha: 1)
}
