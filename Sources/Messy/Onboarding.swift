import ServiceManagement
import SwiftUI

enum Prefs {
    static let onboarded = "onboarded"
    static let showMenuBar = "showMenuBar"
}

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
                    Button("Skip for now") { finish(false) }
                    Button("Start with a security scan") { finish(true) }
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

    private var welcome: some View {
        VStack(spacing: 18) {
            Mascot(pose: .happy, size: 120, motion: .bob)
            Text("Welcome to Messy").font(.largeTitle.bold())
            Text("A free, open-source maintenance tool for your Mac: cleaning, uninstalling apps, disk analysis, a system monitor and a security check in one window.")
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
                Toggle("Show CPU and RAM in the menu bar", isOn: $showMenuBar)
                Toggle("Open Messy at login", isOn: Binding(get: { state.loginItem },
                                                                    set: { state.toggleLogin($0) }))
                if let e = state.loginError {
                    Text(e).font(.caption).foregroundStyle(.red)
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

struct SettingsView: View {
    @StateObject private var state = OnboardingState()
    @AppStorage(Prefs.showMenuBar) private var showMenuBar = true
    @AppStorage(Prefs.onboarded) private var onboarded = false
    @AppStorage(Prefs2.checkupUpdates) private var checkupUpdates = false
    @AppStorage(Sound.enabledKey) private var soundEffects = true
    @AppStorage(AlertPrefs.enabled) private var alerts = false
    @AppStorage(AlertPrefs.lowDiskGB) private var lowDiskGB = 15
    @AppStorage(AlertPrefs.trashGB) private var trashGB = 5
    @AppStorage(AlertPrefs.memory) private var memoryAlert = true
    @AppStorage(AlertPrefs.weekly) private var weekly = false
    @AppStorage(AlertPrefs.appRemoved) private var appRemoved = true

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Mascot(pose: .idle, size: 54, motion: .bob)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Settings").font(.title2.bold())
                        Text("Messy \(version)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                group("General") {
                    Toggle("Show CPU and RAM in the menu bar", isOn: $showMenuBar).toggleStyle(PillSwitchStyle())
                    Toggle("Sound effects", isOn: $soundEffects).toggleStyle(PillSwitchStyle())
                    Toggle("Open Messy at login", isOn: Binding(get: { state.loginItem }, set: { state.toggleLogin($0) }))
                        .toggleStyle(PillSwitchStyle())
                    if let e = state.loginError { Text(e).font(.caption).foregroundStyle(.red) }
                }
                group("Check up", note: "Checking asks each app's update server for its latest version, so those servers see your IP address. Off by default; Apps → Updates always checks on demand.") {
                    Toggle("Include an update check", isOn: $checkupUpdates).toggleStyle(PillSwitchStyle())
                }
                group("Alerts", note: "Alerts only arrive while Messy is running; there is no background service. Turn on Open Messy at login to keep them working. The Trash alert needs Full Disk Access.") {
                    Toggle("Show alerts", isOn: Binding(get: { alerts }, set: { on in
                        if on {
                            AlertCenter.shared.requestPermission { ok in alerts = ok; AlertCenter.shared.updateWeekly() }
                        } else {
                            alerts = false
                            AlertCenter.shared.updateWeekly()
                        }
                    })).toggleStyle(PillSwitchStyle())
                    VStack(alignment: .leading, spacing: 10) {
                        PillStepper(label: "Startup disk below (GB free)", value: $lowDiskGB, range: 5...200, step: 5)
                        PillStepper(label: "Trash above (GB)", value: $trashGB, range: 1...100)
                        Toggle("Memory tight for five minutes", isOn: $memoryAlert)
                        Toggle("An app was removed and left files behind", isOn: $appRemoved)
                        Toggle("Weekly Check up reminder (Sundays)", isOn: Binding(get: { weekly }, set: {
                            weekly = $0
                            AlertCenter.shared.updateWeekly()
                        }))
                    }
                    .disabled(!alerts)
                    .opacity(alerts ? 1 : 0.5)
                }
                group("Permissions") {
                    HStack {
                        Text("Full Disk Access")
                        Spacer()
                        if state.fdaGranted {
                            Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(Brand.emerald)
                        } else {
                            Button("Open Settings") { FullDiskAccess.openSettings() }
                        }
                    }
                }
                group("About") {
                    HStack {
                        Link("Source code on GitHub", destination: URL(string: "https://github.com/berkboz/messy")!)
                            .foregroundStyle(Brand.teal)
                        Spacer()
                        Button("Show welcome screen again") { onboarded = false }
                    }
                }
            }
            .padding(22)
        }
        .frame(width: 500, height: 640)
        .background(BrandBackground())
        .messyStyle()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshFDA()
        }
    }
    private func group<Content: View>(_ title: String, note: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 10) { content() }.card()
            if let note { Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
