#!/usr/bin/env swift
// Draws the DMG installer window background at 1x and 2x.
// Usage: swift scripts/dmg/make-background.swift <output-dir>
// Writes background.png and background@2x.png (660x440 points).
//
// Layout must match scripts/dmg/settings.py: app icon centred at (170, 205),
// Applications at (490, 205), 128 pt icons, labels underneath.
//
// Finder draws icon labels black in Light Mode and white in Dark Mode, so the
// background is a mid-tone blue where both stay readable.
import AppKit

let width: CGFloat = 660
// Taller than the content: Finder windows with a tab bar lose ~40 pt at the
// bottom, so everything important sits in the top 400 pt.
let height: CGFloat = 440

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

/// Converts a top-left-origin y coordinate (how the layout is designed) to AppKit's bottom-left.
func y(_ top: CGFloat) -> CGFloat { height - top }

func drawText(_ string: String, font: NSFont, color textColor: NSColor, centerX: CGFloat, top: CGFloat) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowOffset = NSSize(width: 0, height: -1)
    shadow.shadowBlurRadius = 2
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor, .shadow: shadow]
    let text = NSAttributedString(string: string, attributes: attrs)
    let size = text.size()
    text.draw(at: NSPoint(x: centerX - size.width / 2, y: y(top) - size.height))
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)  // points; pixels carry the scale
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)

    // Base: brand-blue vertical gradient.
    NSGradient(colors: [color(0x5E8EF2), color(0x4A7BE6), color(0x3D69D3)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: bounds, angle: -90)

    // Soft light from the top centre.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: width / 2, y: y(10)), radius: 0,
              toCenter: NSPoint(x: width / 2, y: y(10)), radius: 380, options: [])

    // Faint "page" outlines behind each icon slot.
    for cx in [170.0, 490.0] as [CGFloat] {
        let slot = NSRect(x: cx - 92, y: y(318), width: 184, height: 196)
        let path = NSBezierPath(roundedRect: slot, xRadius: 26, yRadius: 26)
        NSColor.white.withAlphaComponent(0.08).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // Title and instruction.
    drawText("MarkdownPeek", font: .systemFont(ofSize: 30, weight: .bold),
             color: .white, centerX: width / 2, top: 30)
    drawText("Drag the app into your Applications folder", font: .systemFont(ofSize: 15, weight: .medium),
             color: NSColor.white.withAlphaComponent(0.88), centerX: width / 2, top: 72)

    // Arrow from the app to Applications: a gentle upward curve with a dashed shaft.
    let start = NSPoint(x: 272, y: y(206))
    let control = NSPoint(x: 330, y: y(164))
    let end = NSPoint(x: 378, y: y(196))
    let dx = end.x - control.x, dy = end.y - control.y
    let len = (dx * dx + dy * dy).squareRoot()
    let dir = NSPoint(x: dx / len, y: dy / len)
    let perp = NSPoint(x: -dir.y, y: dir.x)
    let headLength: CGFloat = 24, headWidth: CGFloat = 15
    let shaftEnd = NSPoint(x: end.x - dir.x * headLength * 0.6, y: end.y - dir.y * headLength * 0.6)

    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor.black.withAlphaComponent(0.2)
    glow.shadowOffset = NSSize(width: 0, height: -2)
    glow.shadowBlurRadius = 4
    glow.set()
    // One layer so the shadow is applied to the finished arrow, not to each piece.
    let cg = NSGraphicsContext.current!.cgContext
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    let shaft = NSBezierPath()
    shaft.move(to: start)
    shaft.curve(to: shaftEnd, controlPoint1: control, controlPoint2: control)
    shaft.lineWidth = 6
    shaft.lineCapStyle = .round
    shaft.setLineDash([12, 11], count: 2, phase: 0)
    NSColor.white.setStroke()
    shaft.stroke()

    let tip = NSPoint(x: end.x + dir.x * headLength * 0.4, y: end.y + dir.y * headLength * 0.4)
    let base = NSPoint(x: tip.x - dir.x * headLength, y: tip.y - dir.y * headLength)
    let head = NSBezierPath()
    head.move(to: tip)
    head.line(to: NSPoint(x: base.x + perp.x * headWidth, y: base.y + perp.y * headWidth))
    head.line(to: NSPoint(x: base.x - perp.x * headWidth, y: base.y - perp.y * headWidth))
    head.close()
    head.lineJoinStyle = .round
    head.lineWidth = 4
    NSColor.white.setFill()
    head.fill()
    NSColor.white.setStroke()
    head.stroke()
    cg.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()

    // Next step, in a pill at the bottom.
    let hint = NSAttributedString(
        string: "Then open MarkdownPeek once to switch on the Quick Look preview",
        attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                     .foregroundColor: NSColor.white])
    let hintSize = hint.size()
    let pill = NSRect(x: (width - hintSize.width) / 2 - 18, y: y(388),
                      width: hintSize.width + 36, height: 32)
    let pillPath = NSBezierPath(roundedRect: pill, xRadius: 16, yRadius: 16)
    color(0x1E3F99, 0.35).setFill()
    pillPath.fill()
    NSColor.white.withAlphaComponent(0.18).setStroke()
    pillPath.lineWidth = 1
    pillPath.stroke()
    hint.draw(at: NSPoint(x: pill.midX - hintSize.width / 2, y: pill.midY - hintSize.height / 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let args = CommandLine.arguments
guard args.count == 2 else {
    print("usage: make-background.swift <output-dir>")
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] as [(CGFloat, String)] {
    try render(scale: scale).representation(using: .png, properties: [:])!
        .write(to: outDir.appendingPathComponent(name))
}
print("Wrote background.png and background@2x.png to \(outDir.path)")
