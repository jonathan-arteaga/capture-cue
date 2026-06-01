import AppKit

extension NSImage {
    var pixelSize: CGSize {
        if let representation = representations.first {
            return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
        }
        return size
    }

    func pngData() -> Data? {
        guard
            let tiffData = tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    var cgImageForVision: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}
