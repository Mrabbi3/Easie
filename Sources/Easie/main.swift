import AppKit

// `Easie convert …` and `Easie formats` run without opening a window.
let arguments = Array(CommandLine.arguments.dropFirst())
if let command = arguments.first, CLI.commands.contains(command) {
    exit(CLI.run(arguments))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
