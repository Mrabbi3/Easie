import AppKit
import EasieCore

/// Command line mode, handy for scripting and testing:
///   Easie convert report.docx notes.md --to pdf [--out ~/Desktop]
///   Easie formats
enum CLI {
    static let commands: Set<String> = ["convert", "formats", "help", "--help", "-h"]

    static func run(_ arguments: [String]) -> Int32 {
        _ = NSApplication.shared  // the text system expects an app object
        switch arguments[0] {
        case "convert": return convert(Array(arguments.dropFirst()))
        case "formats": printFormats(); return 0
        default: printUsage(); return 0
        }
    }

    private static func convert(_ arguments: [String]) -> Int32 {
        var files: [URL] = []
        var target: Format?
        var outputDirectory: URL?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if ["--to", "-t", "--out", "-o"].contains(argument), index + 1 < arguments.count {
                index += 1
                if argument == "--to" || argument == "-t" {
                    target = Format(fileURL: URL(fileURLWithPath: "file." + arguments[index].lowercased()))
                } else {
                    outputDirectory = URL(fileURLWithPath: (arguments[index] as NSString).expandingTildeInPath)
                }
            } else {
                files.append(URL(fileURLWithPath: argument))
            }
            index += 1
        }
        guard let target, !files.isEmpty else {
            printUsage()
            return 64
        }

        var failures: Int32 = 0
        for file in files {
            do {
                for output in try ConversionEngine.convert(file, to: target, outputDirectory: outputDirectory) {
                    print("✓ \(file.lastPathComponent) → \(output.path)")
                }
            } catch {
                failures += 1
                FileHandle.standardError.write(Data("✗ \(file.lastPathComponent): \(error.localizedDescription)\n".utf8))
            }
        }
        AppleAppBridge.quitLaunchedApps()
        return failures == 0 ? 0 : 1
    }

    private static func printFormats() {
        for format in Format.allCases {
            let targets = format.targets.map(\.rawValue).joined(separator: ", ")
            print(format.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0) + "→ " + targets)
        }
    }

    private static func printUsage() {
        print("""
        Easie — convert any file, free and offline.

        Usage:
          Easie convert <file>… --to <format> [--out <folder>]
          Easie formats      list what converts to what
        """)
    }
}
