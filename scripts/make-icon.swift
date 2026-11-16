#!/usr/bin/env swift
// Draws the MarkdownPeek app icon (a Markdown "M↓" mark on a page) and writes
// every size an AppIcon.appiconset needs. Usage: swift scripts/make-icon.swift <appiconset dir> [sample png]
import AppKit

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // Squircle background (macOS icon grid: 824pt body inside 1024 canvas).
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let bg = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 18 * s
    shadow.shadowOffset = NSSize(width: 0, height: -8 * s)
    shadow.set()
    NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.95, alpha: 1),
               ending: NSColor(calibratedRed: 0.10, green: 0.18, blue: 0.45, alpha: 1))!
        .draw(in: bg, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Markdown mark: rounded outline, "M" and a down arrow.
    let mark = NSRect(x: 210 * s, y: 330 * s, width: 604 * s, height: 370 * s)
    let outline = NSBezierPath(roundedRect: mark, xRadius: 60 * s, yRadius: 60 * s)
    outline.lineWidth = 36 * s
    NSColor.white.setStroke()
    outline.stroke()

    NSColor.white.setFill()
    let m = NSBezierPath()
    let mx = 290 * s, my = 420 * s, mw = 230 * s, mh = 190 * s, t = 52 * s
    m.move(to: NSPoint(x: mx, y: my))
    m.line(to: NSPoint(x: mx, y: my + mh))
    m.line(to: NSPoint(x: mx + t, y: my + mh))
    m.line(to: NSPoint(x: mx + mw / 2, y: my + mh - 80 * s))
    m.line(to: NSPoint(x: mx + mw - t, y: my + mh))
    m.line(to: NSPoint(x: mx + mw, y: my + mh))
    m.line(to: NSPoint(x: mx + mw, y: my))
    m.line(to: NSPoint(x: mx + mw - t, y: my))
    m.line(to: NSPoint(x: mx + mw - t, y: my + mh - 95 * s))
    m.line(to: NSPoint(x: mx + mw / 2, y: my + mh - 170 * s))
    m.line(to: NSPoint(x: mx + t, y: my + mh - 95 * s))
    m.line(to: NSPoint(x: mx + t, y: my))
    m.close()
    m.fill()

    let a = NSBezierPath()
    let ax = 640 * s, aw = 52 * s
    a.move(to: NSPoint(x: ax - aw / 2, y: my + mh))
    a.line(to: NSPoint(x: ax + aw / 2, y: my + mh))
    a.line(to: NSPoint(x: ax + aw / 2, y: my + 90 * s))
    a.line(to: NSPoint(x: ax + 70 * s, y: my + 90 * s))
    a.line(to: NSPoint(x: ax, y: my))
    a.line(to: NSPoint(x: ax - 70 * s, y: my + 90 * s))
    a.line(to: NSPoint(x: ax - aw / 2, y: my + 90 * s))
    a.close()
    a.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: make-icon.swift <appiconset dir> [sample png]"); exit(1) }
let dir = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try drawIcon(size: CGFloat(px)).representation(using: .png, properties: [:])!
            .write(to: dir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: dir.appendingPathComponent("Contents.json"))

if args.count >= 3 {
    try drawIcon(size: 256).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: args[2]))
}
print("Wrote icon set to \(dir.path)")
