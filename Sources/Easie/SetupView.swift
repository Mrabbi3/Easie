import AppKit
import EasieCore
import SwiftUI

@MainActor
final class SetupModel: ObservableObject {
    @Published var rightClickEnabled = ServiceMenu.isEnabled {
        didSet { if rightClickEnabled != oldValue { ServiceMenu.setEnabled(rightClickEnabled) } }
    }
    @Published private(set) var permissions: [AppleApp: AutomationPermission.Status] = [:]
    @Published private(set) var isRequesting = false
    @Published var isDropTargeted = false

    let installedApps = AppleApp.allCases.filter(\.isInstalled)

    var allAllowed: Bool { installedApps.allSatisfy { permissions[$0] == .granted } }
    var anyDenied: Bool { installedApps.contains { permissions[$0] == .denied } }

    func refreshPermissions() {
        Task.detached {
            let statuses = Dictionary(uniqueKeysWithValues: AppleApp.allCases.filter(\.isInstalled).map { ($0, AutomationPermission.knownStatus($0)) })
            await MainActor.run { self.permissions = statuses }
        }
    }

    func requestPermissions() {
        guard !isRequesting else { return }
        isRequesting = true
        let apps = installedApps.filter { permissions[$0] != .granted }
        Task.detached {
            for app in apps {
                let status = AutomationPermission.request(app)
                await MainActor.run { self.permissions[app] = status }
            }
            await MainActor.run { self.isRequesting = false }
        }
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }
}

/// The window you see when you open Easie itself: one switch, one permission, a place to try it.
struct SetupView: View {
    @ObservedObject var model: SetupModel
    let tryFiles: ([URL]) -> Void
    let chooseFiles: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Easie").font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Convert any file, right from Finder.").foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 4)

            card {
                HStack(alignment: .center, spacing: 12) {
                    icon("cursorarrow.click.2", tint: .accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Right-click menu").font(.headline)
                        Text(model.rightClickEnabled
                             ? "Right-click any file → **Edit with Easie**"
                             : "Off. Easie won't appear when you right-click.")
                        .fixedSize(horizontal: false, vertical: true)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Right-click menu", isOn: $model.rightClickEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.large)
                }
            }

            if !model.installedApps.isEmpty {
                card {
                    HStack(alignment: .center, spacing: 12) {
                        icon("checkmark.shield", tint: .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.installedApps.map(\.rawValue).formatted(.list(type: .and))).font(.headline)
                            Text(model.anyDenied
                                 ? "Blocked. Allow Easie in System Settings → Automation."
                                 : "Lets Easie convert Apple's own file formats.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.allAllowed {
                            Label("Allowed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.callout.weight(.medium))
                        } else if model.isRequesting {
                            ProgressView().controlSize(.small)
                        } else if model.anyDenied {
                            Button("Open Settings") { model.openAutomationSettings() }
                        } else {
                            Button("Allow…") { model.requestPermissions() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach([Format.pdf, .docx, .xlsx, .pptx, .png], id: \.self) { format in
                        FormatGlyph(format: format).frame(width: 30, height: 37)
                    }
                }
                Text("Drop a file here to try it").font(.headline)
                Button("Choose a File…", action: chooseFiles).buttonStyle(.link)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(model.isDropTargeted ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    .foregroundStyle(model.isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
            )
            .dropDestination(for: URL.self) { urls, _ in
                tryFiles(urls)
                return true
            } isTargeted: { model.isDropTargeted = $0 }

            HStack {
                Label("Free forever · Works offline · Files never leave your Mac", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit Easie") { NSApp.terminate(nil) }
                    .controlSize(.small)
                    .help("Easie waits quietly in the background so right-clicks open instantly. Quitting is fine: it starts again when you need it.")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 36)
        .padding(.bottom, 18)
        .frame(width: 470)
        .onAppear { model.refreshPermissions() }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.045)))
    }

    private func icon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.14)))
    }
}
