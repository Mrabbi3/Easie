// Renders Easie's real SwiftUI views to PNGs for the launch video, offscreen:
// no window is ever shown and nothing touches the screen, mouse or keyboard.
// Built by capture/run.sh together with copies of the app's UI files.
import AppKit
import EasieCore
import SwiftUI
import QuickLookThumbnailing
import UniformTypeIdentifiers

@MainActor
enum Shots {
    static let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    static let demo = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

    /// Draws a view (AppKit-backed controls included) in a window that is never ordered front.
    static func render<V: View>(_ view: V, _ name: String, size: CGSize, scale: CGFloat = 3) {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .light))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))   // let SwiftUI settle (animations are off)
        let px = NSSize(width: size.width * scale, height: size.height * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px.width), pixelsHigh: Int(px.height), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name + ".png"))
        window.close()
        print("✓", name)
    }

    static func icon(_ image: NSImage, _ name: String, px: Int = 512) {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name + ".png"))
        print("✓", name)
    }

    static func thumbnail(_ file: URL, _ name: String, px: CGFloat = 512) {
        var image: CGImage?
        let request = QLThumbnailGenerator.Request(fileAt: file, size: CGSize(width: px / 2, height: px / 2), scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in image = rep?.cgImage }
        let deadline = Date().addingTimeInterval(20)
        while image == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        guard let image else { print("✗ no thumbnail for", file.lastPathComponent); return }
        try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name + ".png"))
        print("✓", name)
    }

    static func run() {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        if let appIcon = NSImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])) { NSApp.applicationIconImage = appIcon }

        // Every format's glyph, exactly as the popup draws it.
        for format in Format.allCases {
            render(FormatGlyph(format: format).frame(width: 46, height: 56).padding(8), "glyph-\(format.rawValue)", size: CGSize(width: 62, height: 72), scale: 6)
        }

        // The popup's centre disc through one real conversion of the demo file.
        let file = demo.appendingPathComponent("Q3 Report.docx")
        let session = ConversionSession(urls: [file])
        session.isOpen = true
        print("targets:", session.targets.map(\.rawValue).joined(separator: " "))
        try! session.targets.map(\.rawValue).joined(separator: " ").write(to: out.appendingPathComponent("targets.txt"), atomically: true, encoding: .utf8)
        let menu = { RadialMenu(session: session, close: {}, reveal: { _ in }) }
        let side = RadialMenu.size(for: session.targets.count)
        let disc = CGSize(width: 150, height: 150)
        func center(_ name: String) { render(menu().center.frame(width: 150, height: 150), name, size: disc, scale: 4) }
        render(menu(), "menu-open", size: CGSize(width: side, height: side), scale: 3)
        center("center-file")
        session.hovered = .pdf
        center("center-hover-pdf")
        render(menu(), "menu-hover-pdf", size: CGSize(width: side, height: side), scale: 3)
        session.convert(to: .pdf)
        center("center-converting")
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, case .converting = session.phase { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        session.hovered = nil
        center("center-done")
        render(menu(), "menu-done", size: CGSize(width: side, height: side), scale: 3)

        // The setup window you see when you open Easie.
        let model = SetupModel()
        model.rightClickEnabled = true
        render(SetupView(model: model, tryFiles: { _ in }, chooseFiles: {}).background(Color(nsColor: .windowBackgroundColor)), "setup", size: CGSize(width: 470, height: 470), scale: 3)

        // Finder's own icons on this Mac.
        for (name, type) in [("docx", "org.openxmlformats.wordprocessingml.document"), ("xlsx", "org.openxmlformats.spreadsheetml.sheet"),
                             ("pptx", "org.openxmlformats.presentationml.presentation"), ("pdf", "com.adobe.pdf"), ("png", "public.png"),
                             ("heic", "public.heic"), ("csv", "public.comma-separated-values-text"), ("key", "com.apple.keynote.key"),
                             ("md", "net.daringfireball.markdown"), ("jpg", "public.jpeg")] {
            icon(NSWorkspace.shared.icon(for: UTType(name == "key" ? "com.apple.iwork.keynote.key" : type) ?? .data), "icon-\(name)")
        }
        icon(NSWorkspace.shared.icon(for: .folder), "icon-folder")
        // Dock: apps that ship with macOS (and Apple's free iWork apps, when installed)
        for (name, path) in [("finder", "/System/Library/CoreServices/Finder.app"), ("safari", "/System/Cryptexes/App/System/Applications/Safari.app"),
                             ("mail", "/System/Applications/Mail.app"), ("notes", "/System/Applications/Notes.app"),
                             ("photos", "/System/Applications/Photos.app"), ("pages", "/Applications/Pages.app"),
                             ("keynote", "/Applications/Keynote.app"), ("numbers", "/Applications/Numbers.app"),
                             ("settings", "/System/Applications/System Settings.app"), ("trash", "")] where FileManager.default.fileExists(atPath: path) || name == "trash" {
            let image = name == "trash" ? NSImage(named: NSImage.trashEmptyName) ?? NSImage() : NSWorkspace.shared.icon(forFile: path)
            icon(image, "dock-\(name)", px: 256)
        }
        icon(NSWorkspace.shared.icon(forFile: file.path), "icon-demo-docx")
        icon(NSWorkspace.shared.icon(forFile: demo.appendingPathComponent("Q3 Report.pdf").path), "icon-demo-pdf")
        // Finder shows PDFs as a preview of their first page
        thumbnail(demo.appendingPathComponent("Q3 Report.pdf"), "thumb-q3-pdf")
        thumbnail(demo.appendingPathComponent("Invoice 0412.pdf"), "thumb-invoice-pdf")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)   // no Dock icon, never takes focus
NSApp.appearance = NSAppearance(named: .aqua)
MainActor.assumeIsolated { Shots.run() }
