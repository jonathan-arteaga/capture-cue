import SwiftUI

@MainActor
struct AnnotationCanvasView: View {
    let capture: CaptureItem
    @Bindable var store: CaptureStore
    @State private var draftAnnotation: CaptureAnnotation?
    @State private var draggingAnnotationID: CaptureAnnotation.ID?
    @State private var lastDragPoint: CGPoint?
    @State private var activeResizeHandle: AnnotationResizeHandle?

    var body: some View {
        GeometryReader { proxy in
            let imageRect = fittedImageRect(imageSize: capture.image.size, in: proxy.size)

            ZStack {
                Image(nsImage: capture.image)
                    .resizable()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 20, y: 12)
                    .position(x: imageRect.midX, y: imageRect.midY)

                ForEach(capture.annotations) { annotation in
                    AnnotationShapeView(
                        annotation: annotation,
                        imageRect: imageRect,
                        isSelected: store.selectedAnnotationID == annotation.id
                    )
                }

                if let draftAnnotation {
                    AnnotationShapeView(annotation: draftAnnotation, imageRect: imageRect, isSelected: false)
                        .opacity(0.78)
                }
            }
            .contentShape(Rectangle())
            .gesture(annotationGesture(imageRect: imageRect))
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    private func annotationGesture(imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: store.activeTool == .step || store.activeTool == .text ? 0 : 4)
            .onChanged { value in
                guard imageRect.contains(value.startLocation) else { return }
                if store.activeTool == .move {
                    moveAnnotation(with: value, imageRect: imageRect)
                    return
                }

                let start = value.startLocation.normalized(in: imageRect)
                let end = value.location.normalized(in: imageRect)
                draftAnnotation = CaptureAnnotation(
                    tool: store.activeTool,
                    start: start,
                    end: end,
                    text: store.activeText.isEmpty ? "Note" : store.activeText,
                    stepNumber: nextStepNumber
                )
            }
            .onEnded { value in
                defer {
                    draggingAnnotationID = nil
                    lastDragPoint = nil
                    activeResizeHandle = nil
                }

                guard imageRect.contains(value.startLocation) else {
                    draftAnnotation = nil
                    return
                }

                if store.activeTool == .move {
                    if draggingAnnotationID == nil {
                        store.selectAnnotation(id: hitAnnotationID(at: value.location, imageRect: imageRect))
                    }
                    return
                }

                let start = value.startLocation.normalized(in: imageRect)
                let end = value.location.normalized(in: imageRect)
                store.addAnnotation(tool: store.activeTool, start: start, end: end)
                draftAnnotation = nil
            }
    }

    private func moveAnnotation(with value: DragGesture.Value, imageRect: CGRect) {
        if draggingAnnotationID == nil {
            if let selectedAnnotation = capture.annotations.first(where: { $0.id == store.selectedAnnotationID }),
               let handle = selectedAnnotation.resizeHandleHit(at: value.startLocation, imageRect: imageRect) {
                draggingAnnotationID = selectedAnnotation.id
                activeResizeHandle = handle
            } else {
                draggingAnnotationID = hitAnnotationID(at: value.startLocation, imageRect: imageRect)
            }

            store.selectAnnotation(id: draggingAnnotationID)
            lastDragPoint = value.startLocation.normalized(in: imageRect)
        }

        guard let draggingAnnotationID else { return }
        let currentPoint = value.location.normalized(in: imageRect)

        if let activeResizeHandle {
            store.resizeAnnotation(id: draggingAnnotationID, handle: activeResizeHandle, to: currentPoint)
            return
        }

        guard let lastDragPoint else { return }
        let delta = CGPoint(x: currentPoint.x - lastDragPoint.x, y: currentPoint.y - lastDragPoint.y)
        store.moveAnnotation(id: draggingAnnotationID, by: delta)
        self.lastDragPoint = currentPoint
    }

    private func hitAnnotationID(at point: CGPoint, imageRect: CGRect) -> CaptureAnnotation.ID? {
        capture.annotations.reversed().first { annotation in
            annotation.hitTest(point: point, imageRect: imageRect)
        }?.id
    }

    private var nextStepNumber: Int {
        let maxStep = capture.annotations
            .filter { $0.tool == .step }
            .map(\.stepNumber)
            .max() ?? 0
        return maxStep + 1
    }

    private func fittedImageRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }

        let available = CGSize(
            width: max(container.width - 68, 1),
            height: max(container.height - 68, 1)
        )
        let scale = min(available.width / imageSize.width, available.height / imageSize.height, 1)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

@MainActor
private struct AnnotationShapeView: View {
    let annotation: CaptureAnnotation
    let imageRect: CGRect
    let isSelected: Bool

    var body: some View {
        ZStack {
            switch annotation.tool {
            case .move:
                EmptyView()
            case .arrow:
                ArrowAnnotationView(start: startPoint, end: endPoint)
            case .rectangle:
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.trailAccent, lineWidth: 3)
                    .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                    .position(x: rect.midX, y: rect.midY)
            case .text:
                Text(annotation.text)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.trailAccent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .position(startPoint)
            case .redact:
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.black.opacity(0.82))
                    .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                    .position(x: rect.midX, y: rect.midY)
            case .step:
                Text("\(annotation.stepNumber)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.trailAccent, in: Circle())
                    .position(startPoint)
            }

            if isSelected {
                SelectionOutlineView(rect: selectionRect)
                ResizeHandlesView(annotation: annotation, imageRect: imageRect)
            }
        }
    }

    private var startPoint: CGPoint {
        annotation.start.denormalized(in: imageRect)
    }

    private var endPoint: CGPoint {
        annotation.end.denormalized(in: imageRect)
    }

    private var rect: CGRect {
        CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
    }

    private var selectionRect: CGRect {
        switch annotation.tool {
        case .text:
            return CGRect(x: startPoint.x - 44, y: startPoint.y - 18, width: 88, height: 36)
        case .step:
            return CGRect(x: startPoint.x - 20, y: startPoint.y - 20, width: 40, height: 40)
        default:
            return rect.insetBy(dx: -8, dy: -8)
        }
    }
}

@MainActor
private struct SelectionOutlineView: View {
    let rect: CGRect

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [6, 4]))
            .frame(width: max(rect.width, 1), height: max(rect.height, 1))
            .position(x: rect.midX, y: rect.midY)
            .shadow(color: .black.opacity(0.35), radius: 2)
    }
}

@MainActor
private struct ResizeHandlesView: View {
    let annotation: CaptureAnnotation
    let imageRect: CGRect

    var body: some View {
        ForEach(annotation.resizeHandles(in: imageRect)) { handle in
            Circle()
                .fill(.white)
                .frame(width: 10, height: 10)
                .overlay {
                    Circle()
                        .stroke(.trailAccent, lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.24), radius: 2, y: 1)
                .position(handle.point)
        }
    }
}

private struct ResizeHandlePoint: Identifiable {
    let handle: AnnotationResizeHandle
    let point: CGPoint

    var id: String {
        "\(handle)-\(Int(point.x.rounded()))-\(Int(point.y.rounded()))"
    }
}

@MainActor
private struct ArrowAnnotationView: View {
    let start: CGPoint
    let end: CGPoint

    var body: some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)

            let angle = atan2(end.y - start.y, end.x - start.x)
            let length: CGFloat = 16
            let spread: CGFloat = .pi / 7
            path.move(to: end)
            path.addLine(to: CGPoint(
                x: end.x - length * cos(angle - spread),
                y: end.y - length * sin(angle - spread)
            ))
            path.move(to: end)
            path.addLine(to: CGPoint(
                x: end.x - length * cos(angle + spread),
                y: end.y - length * sin(angle + spread)
            ))
        }
        .stroke(.trailAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    }
}

private extension CGPoint {
    func normalized(in rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max((x - rect.minX) / rect.width, 0), 1),
            y: min(max((y - rect.minY) / rect.height, 0), 1)
        )
    }

    func denormalized(in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + x * rect.width,
            y: rect.minY + y * rect.height
        )
    }
}

private extension CaptureAnnotation {
    func hitTest(point: CGPoint, imageRect: CGRect) -> Bool {
        let startPoint = start.denormalized(in: imageRect)
        let endPoint = end.denormalized(in: imageRect)
        let rect = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )

        switch tool {
        case .move:
            return false
        case .arrow:
            return point.distanceToSegment(start: startPoint, end: endPoint) <= 14
        case .rectangle, .redact:
            return rect.insetBy(dx: -12, dy: -12).contains(point)
        case .text:
            return CGRect(x: startPoint.x - 54, y: startPoint.y - 22, width: 108, height: 44).contains(point)
        case .step:
            return hypot(point.x - startPoint.x, point.y - startPoint.y) <= 24
        }
    }

    func resizeHandleHit(at point: CGPoint, imageRect: CGRect) -> AnnotationResizeHandle? {
        resizeHandles(in: imageRect).first { handle in
            hypot(point.x - handle.point.x, point.y - handle.point.y) <= 12
        }?.handle
    }

    func resizeHandles(in imageRect: CGRect) -> [ResizeHandlePoint] {
        let startPoint = start.denormalized(in: imageRect)
        let endPoint = end.denormalized(in: imageRect)
        let rect = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )

        switch tool {
        case .arrow:
            return [
                ResizeHandlePoint(handle: .start, point: startPoint),
                ResizeHandlePoint(handle: .end, point: endPoint)
            ]
        case .rectangle, .redact:
            return [
                ResizeHandlePoint(handle: .topLeft, point: CGPoint(x: rect.minX, y: rect.minY)),
                ResizeHandlePoint(handle: .topRight, point: CGPoint(x: rect.maxX, y: rect.minY)),
                ResizeHandlePoint(handle: .bottomLeft, point: CGPoint(x: rect.minX, y: rect.maxY)),
                ResizeHandlePoint(handle: .bottomRight, point: CGPoint(x: rect.maxX, y: rect.maxY))
            ]
        case .text, .step, .move:
            return []
        }
    }
}

private extension CGPoint {
    func distanceToSegment(start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx != 0 || dy != 0 else {
            return hypot(x - start.x, y - start.y)
        }

        let t = max(0, min(1, ((x - start.x) * dx + (y - start.y) * dy) / (dx * dx + dy * dy)))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(x - projection.x, y - projection.y)
    }
}

private extension ShapeStyle where Self == Color {
    static var trailAccent: Color {
        Color(red: 0.05, green: 0.46, blue: 0.86)
    }
}
