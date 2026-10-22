import AppKit
import EasieCore

/// One right-click: the files picked in Finder, what they can become, and how the conversion is going.
@MainActor
final class ConversionSession: ObservableObject {
    enum Phase: Equatable {
        case choosing
        case converting(Format)
        case done([URL])
        case failed(String)
    }

    let files: [URL]
    let targets: [Format]
    @Published private(set) var phase: Phase = .choosing
    @Published private(set) var chosen: Format?
    @Published var isOpen = false
    @Published var hovered: Format?
    /// The pointer is on the middle disc (where "Show in Finder" is).
    @Published var isHoveringCenter = false

    /// Called when every file converted successfully.
    var onSuccess: (() -> Void)?

    init(urls: [URL]) {
        let all = urls.flatMap(ConversionSession.expand)
        files = all.filter { Format(fileURL: $0) != nil }
        let formats = files.compactMap(Format.init(fileURL:))
        // Files already in the chosen format are left alone, so they don't rule a format out.
        targets = formats.isEmpty ? [] : Format.allCases.filter { target in
            formats.allSatisfy { $0 == target || $0.targets.contains(target) } && formats.contains { $0 != target }
        }
    }

    var isBusy: Bool {
        if case .converting = phase { return true }
        return false
    }

    var title: String {
        switch files.count {
        case 0: "Nothing to convert"
        case 1: files[0].lastPathComponent
        default: "\(files.count) files"
        }
    }

    func convert(to target: Format) {
        guard phase == .choosing else { return }
        chosen = target
        phase = .converting(target)
        let jobs = files.filter { Format(fileURL: $0) != target }
        let several = jobs.count > 1

        Task {
            var outputs: [URL] = []
            var problems: [String] = []
            for url in jobs {
                let result = await Task.detached(priority: .userInitiated) {
                    Result { try ConversionEngine.convert(url, to: target) }
                }.value
                switch result {
                case .success(let written): outputs += written
                case .failure(let error):
                    problems.append(several ? "\(url.lastPathComponent): \(error.localizedDescription)" : error.localizedDescription)
                }
            }
            await Task.detached { AppleAppBridge.quitLaunchedApps() }.value
            if problems.isEmpty {
                phase = .done(outputs)
                onSuccess?()
            } else {
                phase = .failed(problems.joined(separator: "\n"))
            }
        }
    }

    /// Folders contribute the files directly inside them; packages (like older Keynote decks) count as files.
    private static func expand(_ url: URL) -> [URL] {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return [] }
        guard isFolder.boolValue, !isPackage(url) else { return [url] }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isRegularFileKey, .isPackageKey], options: .skipsHiddenFiles)) ?? []
        return children
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true || isPackage($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func isPackage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
    }
}
