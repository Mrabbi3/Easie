import AppKit

/// Apple's free iWork apps. Their file formats are private, so Easie asks the apps
/// themselves to open and export files, which also gives pixel-perfect PDFs of decks.
public enum AppleApp: String, CaseIterable, Sendable {
    case pages = "Pages"
    case keynote = "Keynote"
    case numbers = "Numbers"

    public var bundleID: String { "com.apple.iWork.\(rawValue)" }

    /// Looked up once and remembered: asking Launch Services is slow, and this is checked a lot.
    public var isInstalled: Bool {
        AppleApp.installCache.withLock { cache in
            if let known = cache[self] { return known }
            let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
            cache[self] = installed
            return installed
        }
    }

    /// Forget what was installed (e.g. when the person may have just installed Keynote).
    public static func refreshInstalledApps() {
        installCache.withLock { $0.removeAll() }
    }

    private static let installCache = Locked<[AppleApp: Bool]>([:])

    /// The AppleScript name of each format the app can export.
    func exportTerm(for format: Format) -> String? {
        switch (self, format) {
        case (_, .pdf): "PDF"
        case (.pages, .docx): "Microsoft Word"
        case (.pages, .txt): "unformatted text"
        case (.pages, .rtf): "formatted text"
        case (.keynote, .pptx): "Microsoft PowerPoint"
        case (.numbers, .xlsx): "Microsoft Excel"
        default: nil
        }
    }

    /// The app's own format, which is written with "save" instead of "export".
    var nativeFormat: Format {
        switch self {
        case .pages: .pages
        case .keynote: .key
        case .numbers: .numbers
        }
    }
}

/// How a conversion that needs an iWork app runs: optionally convert natively first,
/// then have the app open the file and write `produces` (the target, or a stepping stone).
struct AppPlan {
    var prepare: Format?
    let app: AppleApp
    let produces: Format

    static func plan(from source: Format, to target: Format) -> AppPlan? {
        switch (source, target) {
        // Pages documents: export what Pages can, go through Word or PDF for the rest.
        case (.pages, .pdf), (.pages, .docx), (.pages, .txt), (.pages, .rtf):
            return AppPlan(app: .pages, produces: target)
        case (.pages, _) where target.group == .images:
            return AppPlan(app: .pages, produces: .pdf)
        case (.pages, _):
            return AppPlan(app: .pages, produces: .docx)
        case (.docx, .pages), (.doc, .pages), (.rtf, .pages), (.txt, .pages):
            return AppPlan(app: .pages, produces: .pages)
        case (_, .pages):
            return AppPlan(prepare: .docx, app: .pages, produces: .pages)

        // Keynote decks: export PDF or PowerPoint, and read text from the PowerPoint.
        case (.key, .pdf), (.key, .pptx):
            return AppPlan(app: .keynote, produces: target)
        case (.key, _) where target.group == .images:
            return AppPlan(app: .keynote, produces: .pdf)
        case (.key, _):
            return AppPlan(app: .keynote, produces: .pptx)
        case (.pptx, .key):
            return AppPlan(app: .keynote, produces: .key)
        // PowerPoint → PDF/images looks exactly right through Keynote; without it Easie falls back to the text.
        case (.pptx, .pdf) where AppleApp.keynote.isInstalled:
            return AppPlan(app: .keynote, produces: .pdf)
        case (.pptx, _) where target.group == .images && AppleApp.keynote.isInstalled:
            return AppPlan(app: .keynote, produces: .pdf)

        // Numbers spreadsheets: export PDF or Excel, and read cells from the Excel file.
        case (.numbers, .pdf), (.numbers, .xlsx):
            return AppPlan(app: .numbers, produces: target)
        case (.numbers, _):
            return AppPlan(app: .numbers, produces: .xlsx)
        case (.xlsx, .numbers), (.csv, .numbers), (.tsv, .numbers):
            return AppPlan(app: .numbers, produces: .numbers)
        case (_, .numbers):
            return AppPlan(prepare: .xlsx, app: .numbers, produces: .numbers)

        default:
            return nil
        }
    }
}

public enum AppleAppBridge {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var launchedApps: Set<AppleApp> = []

    /// Has `app` open `input` and write it to `output` as `format`, without touching the original.
    static func convert(_ input: URL, with app: AppleApp, to output: URL, as format: Format) throws {
        guard app.isInstalled else { throw ConversionError.needsApp(app.rawValue) }
        let action: String
        if format == app.nativeFormat {
            action = "save theDoc in outFile"
        } else if let term = app.exportTerm(for: format) {
            action = "export theDoc to outFile as \(term)"
        } else {
            throw ConversionError.unsupportedTarget(Format(fileURL: input) ?? format, format)
        }

        waitWhileQuitting(app)
        if NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty {
            lock.withLock { _ = launchedApps.insert(app) }
        }

        // Documents the person already has open are left open (and are never re-saved elsewhere).
        let script = """
        on run argv
            set inFile to POSIX file (item 1 of argv)
            set outFile to POSIX file (item 2 of argv)
            with timeout of 900 seconds
                tell application id "\(app.bundleID)"
                    set wasOpen to false
                    repeat with openDoc in documents
                        try
                            if (file of openDoc as text) is (inFile as text) then set wasOpen to true
                        end try
                    end repeat
                    if wasOpen and \(format == app.nativeFormat) then error "Close this file in \(app.rawValue) first, then try again."
                    set theDoc to open inFile
                    try
                        \(action)
                    on error errorMessage number errorNumber
                        if not wasOpen then close theDoc saving no
                        error errorMessage number errorNumber
                    end try
                    if not wasOpen then close theDoc saving no
                end tell
            end timeout
        end run
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-", input.path, output.path]
        let stdin = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        stdin.fileHandleForWriting.write(Data(script.utf8))
        try stdin.fileHandleForWriting.close()
        let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: output.path) else {
            if message.contains("-1743") || message.contains("Not authorized") {
                throw ConversionError.automationDenied(app.rawValue)
            }
            let reason = message.components(separatedBy: "error: ").last?
                .replacingOccurrences(of: #"\s*\(-?\d+\)\s*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConversionError.appFailed(app.rawValue, reason?.isEmpty == false ? reason! : "unknown error")
        }
    }

    /// Quits any iWork app Easie had to start, once a batch of conversions is done, and waits
    /// until it has really exited: an app that is still shutting down silently drops new requests.
    public static func quitLaunchedApps() {
        let apps = lock.withLock {
            defer { launchedApps.removeAll() }
            return launchedApps
        }
        for app in apps {
            quitting.withLock { _ = $0.insert(app) }
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
            running.forEach { $0.terminate() }
            waitUntilExited(running.map(\.processIdentifier))
            quitting.withLock { _ = $0.remove(app) }
        }
    }

    private static let quitting = Locked<Set<AppleApp>>([])

    /// Polls the processes themselves (not AppKit's view of them, which needs a free main thread).
    private static func waitUntilExited(_ pids: [pid_t], timeout: TimeInterval = 15) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, pids.contains(where: { kill($0, 0) == 0 }) {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// A conversion that arrives while the app is still quitting from the previous one waits for it.
    private static func waitWhileQuitting(_ app: AppleApp) {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, quitting.withLock({ $0.contains(app) }) {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
}

/// A value guarded by a lock, safe to touch from conversion threads.
final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
