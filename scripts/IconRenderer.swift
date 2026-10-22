// Draws Easie's 1024×1024 app icon. Usage: swift scripts/IconRenderer.swift out.png
import AppKit

let size = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let violet = NSColor(srgbRed: 0.42, green: 0.33, blue: 0.98, alpha: 1)
let teal = NSColor(srgbRed: 0.10, green: 0.76, blue: 0.85, alpha: 1)

// Squircle background on the standard macOS icon grid.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
violet.setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: violet, ending: teal)!.draw(in: tilePath, angle: -55)

func sheet(_ rect: NSRect, alpha: CGFloat, rotation: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: rect.midX, yBy: rect.midY)
    transform.rotate(byDegrees: rotation)
    transform.translateX(by: -rect.midX, yBy: -rect.midY)
    transform.concat()
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(0.18)
    s.shadowBlurRadius = 20
    s.shadowOffset = NSSize(width: 0, height: -8)
    s.set()
    NSColor.white.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 44, yRadius: 44).fill()
    NSGraphicsContext.restoreGraphicsState()
}

// A document behind, a document in front: "this file becomes that file".
sheet(NSRect(x: 250, y: 300, width: 360, height: 450), alpha: 0.45, rotation: 9)
let front = NSRect(x: 380, y: 230, width: 380, height: 470)
sheet(front, alpha: 1, rotation: -4)

NSGraphicsContext.saveGraphicsState()
let tilt = NSAffineTransform()
tilt.translateX(by: front.midX, yBy: front.midY)
tilt.rotate(byDegrees: -4)
tilt.translateX(by: -front.midX, yBy: -front.midY)
tilt.concat()
violet.withAlphaComponent(0.28).setFill()
for (i, width) in [260.0, 300.0, 230.0, 280.0].enumerated() {
    NSBezierPath(roundedRect: NSRect(x: front.minX + 50, y: front.maxY - 90 - CGFloat(i) * 52, width: width, height: 22),
                 xRadius: 11, yRadius: 11).fill()
}
NSGraphicsContext.restoreGraphicsState()

// The "convert" badge.
let badge = NSRect(x: 555, y: 175, width: 250, height: 250)
NSGraphicsContext.saveGraphicsState()
let badgeShadow = NSShadow()
badgeShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
badgeShadow.shadowBlurRadius = 18
badgeShadow.shadowOffset = NSSize(width: 0, height: -6)
badgeShadow.set()
NSColor.white.setFill()
NSBezierPath(ovalIn: badge).fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: violet, ending: teal)!.draw(in: NSBezierPath(ovalIn: badge.insetBy(dx: 14, dy: 14)), angle: -55)

let config = NSImage.SymbolConfiguration(pointSize: 120, weight: .bold).applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    symbol.draw(in: NSRect(x: badge.midX - s.width / 2, y: badge.midY - s.height / 2, width: s.width, height: s.height))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
