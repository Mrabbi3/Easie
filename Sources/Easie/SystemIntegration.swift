import AppKit
import CoreServices
import EasieCore

/// Turns the Finder "Edit with Easie" item on and off.
/// macOS keeps this switch in the Services preferences (the same one System Settings →
/// Keyboard → Keyboard Shortcuts → Services edits), keyed by bundle id, title and message.
enum ServiceMenu {
    private static let domain = "pbs" as CFString
    private static let statusKey = "NSServicesStatus" as CFString
    private static let serviceKey = "app.easie.Easie - Edit with Easie - convertWithEasie"

    static var isEnabled: Bool {
        let status = CFPreferencesCopyAppValue(statusKey, domain) as? [String: Any]
        let entry = status?[serviceKey] as? [String: Any]
        return entry?["enabled_context_menu"] as? Bool ?? true
    }

    static func setEnabled(_ enabled: Bool) {
        var status = CFPreferencesCopyAppValue(statusKey, domain) as? [String: Any] ?? [:]
        status[serviceKey] = [
            "enabled_context_menu": enabled,
            "enabled_services_menu": enabled,
            "presentation_modes": ["ContextMenu": enabled, "ServicesMenu": enabled],
        ]
        CFPreferencesSetAppValue(statusKey, status as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
        refresh()
    }

    /// Asks macOS to re-read the Services list so Finder picks up the change.
    static func refresh() {
        NSUpdateDynamicServices()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        process.arguments = ["-update"]
        try? process.run()
    }
}

/// Permission to drive Pages, Keynote and Numbers, which macOS asks for once per app.
enum AutomationPermission {
    enum Status { case granted, denied, notAsked }

    private static func rememberedKey(_ app: AppleApp) -> String { "automationGranted.\(app.rawValue)" }

    /// What we know without showing a prompt.
    static func knownStatus(_ app: AppleApp) -> Status {
        if let status = check(app, prompt: false) { return status }
        return UserDefaults.standard.bool(forKey: rememberedKey(app)) ? .granted : .notAsked
    }

    /// Shows the macOS "Easie wants to control …" prompt if needed. Blocks until answered,
    /// so call it off the main thread. The app has to be running to be asked about, so it is
    /// started hidden and quit again afterwards.
    static func request(_ app: AppleApp) -> Status {
        var launched: NSRunningApplication?
        if NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = true
            let started = DispatchSemaphore(value: 0)
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { running, _ in
                launched = running
                started.signal()
            }
            _ = started.wait(timeout: .now() + 20)
        }

        var status: Status?
        for _ in 0..<20 {  // the app needs a moment before it can answer
            status = check(app, prompt: true)
            if status != nil { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        launched?.terminate()

        let result = status ?? .notAsked
        UserDefaults.standard.set(result == .granted, forKey: rememberedKey(app))
        return result
    }

    /// nil when the app isn't running (macOS can only answer for running apps).
    private static func check(_ app: AppleApp, prompt: Bool) -> Status? {
        var target = AEAddressDesc()
        let bundleID = Array(app.bundleID.utf8)
        let created = bundleID.withUnsafeBytes { bytes in
            AECreateDesc(DescType(typeApplicationBundleID), bytes.baseAddress, bytes.count, &target)
        }
        guard created == noErr else { return nil }
        defer { AEDisposeDesc(&target) }

        switch AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), prompt) {
        case noErr: return .granted
        case -1743: return .denied      // errAEEventNotPermitted
        case -1744: return .notAsked    // errAEEventWouldRequireUserConsent
        default: return nil             // procNotFound: not running
        }
    }
}
