#!/usr/bin/env swift

import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesURL = rootURL.appending(path: "Resources", directoryHint: .isDirectory)
let iconsetURL = resourcesURL.appending(path: "astro-lens.iconset", directoryHint: .isDirectory)
let icnsURL = resourcesURL.appending(path: "astro-lens.icns")

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let iconSpecs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for spec in iconSpecs {
    let image = drawIcon(size: CGFloat(spec.pixels))
    let destination = iconsetURL.appending(path: spec.name)
    try writePNG(image, to: destination)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "astro-lensIcon", code: Int(process.terminationStatus))
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: CGSize(width: size, height: size))

    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.22
    let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    backgroundPath.fill()

    let markRect = rect.insetBy(dx: size * 0.18, dy: size * 0.18)
    let center = CGPoint(x: markRect.midX, y: markRect.midY)

    let cPath = NSBezierPath()
    cPath.appendArc(
        withCenter: center,
        radius: size * 0.27,
        startAngle: 42,
        endAngle: 318,
        clockwise: false
    )
    cPath.lineWidth = max(size * 0.13, 3)
    cPath.lineCapStyle = .round
    NSColor(calibratedRed: 0.04, green: 0.09, blue: 0.28, alpha: 1).setStroke()
    cPath.stroke()

    let mintPath = NSBezierPath()
    mintPath.move(to: CGPoint(x: size * 0.32, y: size * 0.41))
    mintPath.curve(
        to: CGPoint(x: size * 0.55, y: size * 0.52),
        controlPoint1: CGPoint(x: size * 0.42, y: size * 0.40),
        controlPoint2: CGPoint(x: size * 0.42, y: size * 0.52)
    )
    mintPath.curve(
        to: CGPoint(x: size * 0.70, y: size * 0.50),
        controlPoint1: CGPoint(x: size * 0.62, y: size * 0.52),
        controlPoint2: CGPoint(x: size * 0.64, y: size * 0.50)
    )
    mintPath.lineWidth = max(size * 0.11, 3)
    mintPath.lineCapStyle = .round
    NSColor(calibratedRed: 0.43, green: 0.87, blue: 0.84, alpha: 1).setStroke()
    mintPath.stroke()

    let bluePath = NSBezierPath()
    bluePath.move(to: CGPoint(x: size * 0.41, y: size * 0.40))
    bluePath.curve(
        to: CGPoint(x: size * 0.72, y: size * 0.50),
        controlPoint1: CGPoint(x: size * 0.52, y: size * 0.36),
        controlPoint2: CGPoint(x: size * 0.57, y: size * 0.54)
    )
    bluePath.lineWidth = max(size * 0.11, 3)
    bluePath.lineCapStyle = .round
    NSColor(calibratedRed: 0.02, green: 0.64, blue: 0.84, alpha: 1).setStroke()
    bluePath.stroke()

    return image
}

func star(center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat, points: Int) -> NSBezierPath {
    let path = NSBezierPath()
    let angleStep = CGFloat.pi / CGFloat(points)

    for index in 0..<(points * 2) {
        let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
        let angle = -CGFloat.pi / 2 + CGFloat(index) * angleStep
        let point = CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )

        if index == 0 {
            path.move(to: point)
        } else {
            path.line(to: point)
        }
    }

    path.close()
    return path
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "astro-lensIcon", code: 1)
    }

    try data.write(to: url, options: [.atomic])
}
