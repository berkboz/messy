import ServiceManagement
import SwiftUI

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message, or nil on success.
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

enum FullDiskAccess {
    /// The TCC database is only readable by apps the user granted Full Disk Access.
    static var granted: Bool {
        FileManager.default.isReadableFile(atPath: "/Library/Application Support/com.apple.TCC/TCC.db")
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

final class OnboardingState: ObservableObject {
    @Published var step = 0
    @Published var loginItem = LoginItem.isEnabled
    @Published var loginError: String?
    @Published var fdaGranted = FullDiskAccess.granted

    func toggleLogin(_ on: Bool) {
        loginError = LoginItem.set(on)
        loginItem = LoginItem.isEnabled
    }

    func refreshFDA() { fdaGranted = FullDiskAccess.granted }
}

struct OnboardingView: View {
    /// Called with true when the user wants to start with a security scan.
    let finish: (Bool) -> Void
    @StateObject private var state = OnboardingState()
    @AppStorage(Prefs.showMenuBar) private var showMenuBar = true
    @AppStorage(Prefs.showInDock) private var showInDock = true
    /// Asked here once, so Sparkle never shows its own permission prompt. Keeps an earlier answer.
    @State private var autoUpdates = AppUpdater.shared.hasChoice ? AppUpdater.shared.automaticChecks : true

    private let lastStep = 2

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch state.step {
                case 0: welcome
                case 1: features
                default: setup
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)

            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(0...lastStep, id: \.self) { i in
                        Circle().fill(i == state.step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if state.step > 0 {
                    Button("Back") { state.step -= 1 }
                }
                if state.step < lastStep {
                    Button("Continue") { state.step += 1 }
                        .buttonStyle(.brand)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Skip for now") { done(false) }
                    Button("Start with a security scan") { done(true) }
                        .buttonStyle(.brand)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 620, height: 540)
        .background(BrandBackground())
        .messyStyle()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshFDA()
        }
    }

    private func done(_ scan: Bool) {
        AppUpdater.shared.automaticChecks = autoUpdates
        finish(scan)
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Mascot(pose: .happy, size: 120, motion: .bob)
            Wordmark(size: 40)
            Text("Messy finds the mess on your Mac: caches, leftovers, duplicates, things running in the background. Its little broom sweeps it up, and only when you say so. Free and open source.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            VStack(alignment: .leading, spacing: 10) {
                Promise(icon: "trash", title: "Nothing is deleted permanently",
                        text: "Everything goes to the Trash first, so you can put it back.")
                Promise(icon: "wifi.slash", title: "Your data stays on your Mac",
                        text: "No analytics, accounts or servers. Scan results stay on this Mac.")
                Promise(icon: "chevron.left.forwardslash.chevron.right", title: "Open source (MIT)",
                        text: "All the code is on GitHub, so you can read what it does.")
            }
            .padding(.top, 6)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("What it does").font(.title.bold())
            Feature(pane: .checkup, text: "One button checks everything below and shows what it found before anything changes.")
            Feature(pane: .clean, text: "Finds caches, logs, developer leftovers and old installers.")
            Feature(pane: .protect, text: "Flags cracked or tampered apps, suspicious background services and open ports.")
            Feature(pane: .speed, text: "Shows what starts with your Mac and runs maintenance tasks.")
            Feature(pane: .apps, text: "Removes apps with their leftovers and checks for updates when you ask.")
            Feature(pane: .clutter, text: "Finds large, old and duplicate files.")
            Feature(pane: .space, text: "Maps what takes up space on your disk.")
            Feature(pane: .monitor, text: "Watches CPU, memory, battery, disk and network, also from the menu bar.")
        }
        .frame(maxWidth: 480)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A few preferences").font(.title.bold())

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Full Disk Access", systemImage: "externaldrive.badge.checkmark").font(.headline)
                    Spacer()
                    if state.fdaGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open Settings") { FullDiskAccess.openSettings() }
                    }
                }
                Text("Optional. With it, Messy can also scan places like Mail attachments and other apps' protected folders. Without it, those places are skipped; everything else works.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !state.fdaGranted {
                    Text("Add Messy to the list in System Settings, turn the switch on, then come back here.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show Messy in the menu bar", isOn: $showMenuBar)
                    .disabled(!showInDock)
                Toggle("Open Messy at login", isOn: Binding(get: { state.loginItem },
                                                                    set: { state.toggleLogin($0) }))
                if let e = state.loginError {
                    Text(e).font(.caption).foregroundStyle(.red)
                }
                if AppUpdater.shared.isAvailable {
                    Toggle("Keep Messy up to date", isOn: $autoUpdates)
                    Text("Asks GitHub once a day for a new version. You can change this in Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: 480)
    }
}

private struct Promise: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct Feature: View {
    let pane: Pane
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: pane.icon).font(.title3).frame(width: 28).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.rawValue).bold()
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
