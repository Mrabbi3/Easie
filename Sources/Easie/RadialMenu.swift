import AppKit
import EasieCore
import SwiftUI

/// The popup that appears where you right-clicked: the file in the middle,
/// every format it can become around it. One click converts.
@MainActor
final class RadialController: NSObject, NSWindowDelegate {
    let session: ConversionSession
    private let panel: RadialPanel
    private var isClosing = false
    private var outsideClickMonitor: Any?
    var onClose: (() -> Void)?

    init(urls: [URL], at point: NSPoint) {
        session = ConversionSession(urls: urls)
        let side = RadialMenu.size(for: session.targets.count)

        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        var frame = NSRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
        if let visible = screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - side)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - side)
        }

        // Non-activating, like Spotlight: it takes clicks and keys without pulling focus from Finder.
        panel = RadialPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.dismiss() }

        let menu = RadialMenu(
            session: session,
            close: { [weak self] in self?.dismiss() },
            reveal: { urls in NSWorkspace.shared.activateFileViewerSelecting(urls) }
        )
        let host = NSHostingView(rootView: menu)
        host.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentView = host

        // Once everything is saved, fade away by itself, unless the pointer is on "Show in Finder".
        // (The popup opens under the pointer, so only a pointer that has *moved* there since counts.)
        session.onSuccess = { [weak self] in
            self?.dismissWhenIdle(after: 1.6, pointerAtSuccess: NSEvent.mouseLocation)
        }
    }

    private func dismissWhenIdle(after delay: TimeInterval, pointerAtSuccess: NSPoint) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isClosing else { return }
            let reachingForFinder = self.session.isHoveringCenter && NSEvent.mouseLocation != pointerAtSuccess
            if reachingForFinder {
                self.dismissWhenIdle(after: 0.5, pointerAtSuccess: pointerAtSuccess)
            } else {
                self.dismiss()
            }
        }
    }

    func show() {
        panel.orderFrontRegardless()
        panel.makeKey()
        // Clicking anywhere else closes the popup, like a menu.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        // Pop out on the next frame, so SwiftUI animates from the closed state.
        DispatchQueue.main.async { self.session.isOpen = true }
    }

    func dismiss() {
        log.debug("dismiss: closing=\(self.isClosing) busy=\(self.session.isBusy)")
        guard !isClosing, !session.isBusy else { return }
        isClosing = true
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        outsideClickMonitor = nil
        session.isOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            self.panel.orderOut(nil)
            self.onClose?()
        }
    }
}

final class RadialPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

struct RadialMenu: View {
    @ObservedObject var session: ConversionSession
    let close: () -> Void
    let reveal: ([URL]) -> Void

    static let centerSize: CGFloat = 118
    static let bubbleSize = CGSize(width: 46, height: 56)

    static func radius(for count: Int) -> CGFloat {
        max(122, CGFloat(count) * 74 / (2 * .pi))
    }

    static func size(for count: Int) -> CGFloat {
        (radius(for: count) + 64) * 2
    }

    private var radius: CGFloat { RadialMenu.radius(for: session.targets.count) }

    var body: some View {
        let open = session.isOpen
        ZStack {
            // Click the empty space around the ring to dismiss.
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture(perform: close)

            // A soft glassy disc behind everything.
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .frame(width: (radius + 46) * 2, height: (radius + 46) * 2)
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                .scaleEffect(open ? 1 : 0.4)
                .opacity(open ? 1 : 0)
                .animation(.spring(response: 0.34, dampingFraction: 0.8), value: open)

            ForEach(Array(session.targets.enumerated()), id: \.element) { index, format in
                spoke(for: format, index: index)
            }
            ForEach(Array(session.targets.enumerated()), id: \.element) { index, format in
                bubble(for: format, index: index)
            }

            center
                .scaleEffect(open ? 1 : 0.5)
                .opacity(open ? 1 : 0)
                .animation(.spring(response: 0.32, dampingFraction: 0.7), value: open)
        }
        .frame(width: RadialMenu.size(for: session.targets.count), height: RadialMenu.size(for: session.targets.count))
    }

    private func angle(_ index: Int) -> Double {
        -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(max(session.targets.count, 1))
    }

    private func position(_ index: Int) -> CGSize {
        CGSize(width: cos(angle(index)) * radius, height: sin(angle(index)) * radius)
    }

    /// The dashed "this becomes that" line from the file to a format.
    private func spoke(for format: Format, index: Int) -> some View {
        let open = session.isOpen
        let highlighted = session.hovered == format || session.chosen == format
        let side = RadialMenu.size(for: session.targets.count)
        let mid = CGPoint(x: side / 2, y: side / 2)
        let a = angle(index)
        let start = CGPoint(x: mid.x + cos(a) * (RadialMenu.centerSize / 2 + 4), y: mid.y + sin(a) * (RadialMenu.centerSize / 2 + 4))
        let end = CGPoint(x: mid.x + cos(a) * (radius - 34), y: mid.y + sin(a) * (radius - 34))
        return Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .trim(from: 0, to: open ? 1 : 0)
        .stroke(highlighted ? format.tint : Color.secondary.opacity(0.45),
                style: StrokeStyle(lineWidth: highlighted ? 2.5 : 1.5, lineCap: .round, dash: highlighted ? [] : [4, 5]))
        .animation(.easeOut(duration: 0.3).delay(0.08 + Double(index) * 0.02), value: open)
        .animation(.easeOut(duration: 0.15), value: highlighted)
        .allowsHitTesting(false)
    }

    private func bubble(for format: Format, index: Int) -> some View {
        let open = session.isOpen
        let hovered = session.hovered == format
        let chosen = session.chosen == format
        let faded = session.phase != .choosing && !chosen
        let offset = open ? position(index) : .zero
        return Button {
            session.convert(to: format)
        } label: {
            FormatGlyph(format: format)
                .frame(width: RadialMenu.bubbleSize.width, height: RadialMenu.bubbleSize.height)
                .padding(10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(session.phase != .choosing)
        .help("Convert to \(format.label)")
        .accessibilityLabel("Convert to \(format.label), \(format.hint)")
        .onHover { inside in
            if inside { session.hovered = format } else if session.hovered == format { session.hovered = nil }
        }
        .scaleEffect(!open ? 0.2 : chosen ? 1.2 : hovered ? 1.18 : faded ? 0.85 : 1)
        .opacity(!open ? 0 : faded ? 0.25 : 1)
        .offset(offset)
        .animation(.spring(response: 0.42, dampingFraction: 0.62).delay(open ? Double(index) * 0.025 : 0), value: open)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovered)
        .animation(.easeInOut(duration: 0.25), value: session.phase)
    }

    private var center: some View {
        VStack(spacing: 5) {
            switch session.phase {
            case .choosing:
                if let hovered = session.hovered {
                    FormatGlyph(format: hovered).frame(width: 34, height: 42)
                    Text("Convert to \(hovered.label)").font(.system(size: 11, weight: .semibold))
                    Text(hovered.hint).font(.system(size: 10)).foregroundStyle(.secondary)
                } else if session.targets.isEmpty {
                    Image(systemName: "questionmark.folder").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text("Easie can't convert\nthis file type yet").font(.system(size: 10.5)).multilineTextAlignment(.center)
                } else {
                    fileIcon
                    Text(session.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.center)
                }
            case .converting(let format):
                ProgressView().controlSize(.regular)
                Text("Making \(format.label)…").font(.system(size: 11, weight: .medium))
            case .done(let outputs):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.green)
                Text(outputs.count == 1 ? "Saved" : "Saved \(outputs.count) files").font(.system(size: 11, weight: .semibold))
                Button("Show in Finder") { reveal(outputs); close() }
                    .buttonStyle(.link)
                    .font(.system(size: 10.5))
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 9.5))
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
                    .help(message)
            }
        }
        .padding(12)
        .accessibilityElement(children: .combine)
        .frame(width: RadialMenu.centerSize, height: RadialMenu.centerSize)
        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        .onHover { session.isHoveringCenter = $0 }
        .animation(.easeInOut(duration: 0.18), value: session.hovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: session.phase)
    }

    private var fileIcon: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: session.files.first.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage())
                .resizable()
                .frame(width: 46, height: 46)
                .accessibilityHidden(true)
            if session.files.count > 1 {
                Text("\(session.files.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.red))
                    .offset(x: 6, y: -2)
            }
        }
    }
}
