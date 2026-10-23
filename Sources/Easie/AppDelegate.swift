import AppKit
import EasieCore
import OSLog
import SwiftUI

/// Debug-level diagnostics (not stored by macOS; visible with `log stream --level debug`). Never logs file contents.
let log = Logger(subsystem: "app.easie.Easie", category: "app")

/// Easie has two faces:
/// - right-click a file → "Edit with Easie": only the radial popup appears, at the pointer;
/// - open Easie itself: the setup window (right-click switch, permissions, a place to try it).
/// After the first use it stays in the background (no Dock icon, nothing on screen), so the next
/// right-click pops up instantly instead of waiting for the app to start.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let setup = SetupModel()
    private var setupWindow: NSWindow?
    private var popup: RadialController?
    private var receivedFiles = false
    private var incoming: [URL] = []
    private lazy var services = ServiceProvider { [weak self] urls in self?.showPopup(for: urls) }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        // When launched by the right-click menu, the files arrive a moment after launch: wait for them
        // before deciding to show the setup window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if !self.receivedFiles { self.showSetup() }
        }
    }

    /// "Open With → Easie", or files dropped on the app icon. macOS can hand over one selection
    /// in several batches (measured 20–30 ms apart), so batches arriving together become one popup.
    func application(_ application: NSApplication, open urls: [URL]) {
        receivedFiles = true
        let first = incoming.isEmpty
        incoming += urls
        guard first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            let urls = self.incoming
            self.incoming = []
            self.showPopup(for: urls)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSetup()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc func openDocument(_ sender: Any?) {
        chooseFiles()
    }

    func showPopup(for urls: [URL], at point: NSPoint = NSEvent.mouseLocation) {
        log.debug("showPopup: \(urls.count) file(s), current popup busy: \(self.popup?.session.isBusy ?? false)")
        guard !urls.isEmpty else { return }
        receivedFiles = true
        if let current = popup, current.session.isBusy { return }
        popup?.onClose = nil
        popup?.dismiss()

        let controller = RadialController(urls: urls, at: point)
        controller.onClose = { [weak self, weak controller] in
            guard let self, self.popup === controller else { return }
            self.popup = nil
        }
        popup = controller
        controller.show()
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose files to convert"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.showPopup(for: panel.urls)
        }
    }

    private func showSetup() {
        NSApp.setActivationPolicy(.regular)
        if setupWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 470, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Easie"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SetupView(
                model: setup,
                tryFiles: { [weak self] urls in self?.showPopup(for: urls) },
                chooseFiles: { [weak self] in self?.chooseFiles() }
            ))
            window.setContentSize(window.contentView!.fittingSize)
            window.center()
            // Closing the window just tucks Easie back into the background.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
            }
            setupWindow = window
        }
        AppleApp.refreshInstalledApps()
        setup.refreshPermissions()
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Receives the Finder right-click "Edit with Easie" service (declared in Info.plist).
final class ServiceProvider: NSObject {
    private let onFiles: ([URL]) -> Void

    init(onFiles: @escaping ([URL]) -> Void) {
        self.onFiles = onFiles
    }

    @objc func convertWithEasie(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        onFiles(urls)
    }
}

enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let appMenu = submenu(in: main, title: "Easie")
        appMenu.addItem(withTitle: "About Easie", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let servicesItem = appMenu.addItem(withTitle: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = NSMenu()
        NSApp.servicesMenu = servicesItem.submenu
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Easie", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Easie", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenu = submenu(in: main, title: "File")
        fileMenu.addItem(withTitle: "Open…", action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editMenu = submenu(in: main, title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = submenu(in: main, title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = windowMenu

        return main
    }

    private static func submenu(in menu: NSMenu, title: String) -> NSMenu {
        let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        item.submenu = submenu
        return submenu
    }
}
