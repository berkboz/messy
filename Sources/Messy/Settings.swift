import SwiftUI

enum Prefs {
    static let onboarded = "onboarded"
    static let showMenuBar = "showMenuBar"
    static let showInDock = "showInDock"
}

/// What the menu bar item shows. With everything off it is just the broom.
enum MenuBarPrefs {
    static let cpu = "menuCPU"
    static let ram = "menuRAM"
    static let network = "menuNetwork"
    static let disk = "menuDisk"
}

enum Dock {
    static var visible: Bool { UserDefaults.standard.object(forKey: Prefs.showInDock) as? Bool ?? true }

    /// Hiding the Dock icon turns Messy into a menu bar app; the menu bar item then must stay.
    static func apply() {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Never leave Messy with no Dock icon and no menu bar item.
        if !Dock.visible { UserDefaults.standard.set(true, forKey: Prefs.showMenuBar) }
        Dock.apply()
    }
}

/// Opens Settings and brings it forward, which a menu bar app does not do on its own.
struct SettingsButton<Label: View>: View {
    @ViewBuilder let label: () -> Label

    var body: some View {
        SettingsLink(label: label)
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
    }
}

struct SettingsView: View {
    @StateObject private var state = OnboardingState()
    @ObservedObject private var updater = AppUpdater.shared
    @AppStorage(Prefs.showMenuBar) private var showMenuBar = true
    @AppStorage(Prefs.showInDock) private var showInDock = true
    @AppStorage(MenuBarPrefs.cpu) private var menuCPU = true
    @AppStorage(MenuBarPrefs.ram) private var menuRAM = true
    @AppStorage(MenuBarPrefs.network) private var menuNetwork = false
    @AppStorage(MenuBarPrefs.disk) private var menuDisk = false
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
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return b.map { "\(v) (\($0))" } ?? v
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
                    Toggle("Show Messy in the Dock", isOn: Binding(get: { showInDock }, set: { on in
                        showInDock = on
                        Dock.apply()
                        // Switching to a menu bar app deactivates Messy; keep this window in front.
                        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
                    }))
                    .toggleStyle(PillSwitchStyle())
                    .disabled(!showMenuBar)
                    if !showMenuBar {
                        Text("Turn on the menu bar item first, so Messy stays reachable.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Open Messy at login", isOn: Binding(get: { state.loginItem }, set: { state.toggleLogin($0) }))
                        .toggleStyle(PillSwitchStyle())
                    if let e = state.loginError { Text(e).font(.caption).foregroundStyle(.red) }
                    Toggle("Sound effects", isOn: $soundEffects).toggleStyle(PillSwitchStyle())
                }
                group("Menu bar") {
                    Toggle("Show in the menu bar", isOn: $showMenuBar)
                        .toggleStyle(PillSwitchStyle())
                        .disabled(!showInDock)
                    if !showInDock {
                        Text("Messy is hidden from the Dock, so the menu bar item stays.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("CPU usage", isOn: $menuCPU)
                        Toggle("Memory usage", isOn: $menuRAM)
                        Toggle("Network speed", isOn: $menuNetwork)
                        Toggle("Free disk space", isOn: $menuDisk)
                        HStack(spacing: 8) {
                            Text("Preview").font(.caption).foregroundStyle(.secondary)
                            MenuBarPreview()
                        }
                        Text("Turn everything off to show only the broom.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .disabled(!showMenuBar)
                    .opacity(showMenuBar ? 1 : 0.5)
                }
                group("Updates", note: updater.isAvailable
                      ? "Messy asks GitHub once a day whether a new version is out, so GitHub sees your IP address. Every update is signed and checked before it is installed."
                      : "Updates work in the released app, not in development builds.") {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updater.automaticChecks }, set: { updater.automaticChecks = $0 }))
                        .toggleStyle(PillSwitchStyle())
                    Toggle("Download and install them in the background", isOn: Binding(
                        get: { updater.automaticDownloads }, set: { updater.automaticDownloads = $0 }))
                        .toggleStyle(PillSwitchStyle())
                        .disabled(!updater.automaticChecks)
                    HStack {
                        CheckForUpdatesButton()
                        Spacer()
                        if let d = updater.lastCheck {
                            Text("Last checked \(d.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(!updater.isAvailable)
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
                    HStack(spacing: 14) {
                        Link("Source code", destination: URL(string: "https://github.com/berkboz/messy")!)
                        Link("Release notes", destination: URL(string: "https://github.com/berkboz/messy/releases")!)
                        Spacer()
                        Button("Show welcome screen again") { onboarded = false }
                    }
                    .foregroundStyle(Brand.teal)
                }
            }
            .padding(22)
        }
        .frame(width: 500, height: 680)
        .background(BrandBackground())
        .messyStyle()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshFDA()
            updater.refresh()
        }
        .onAppear { updater.refresh() }
    }

    private func group<Content: View>(_ title: String, note: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 10) { content() }.card()
            if let note { Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// The menu bar item as it will look, on a strip the colour of the menu bar.
private struct MenuBarPreview: View {
    @EnvironmentObject private var stats: SystemStats

    var body: some View {
        MenuBarLabel(stats: stats)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(.bar, in: RoundedRectangle(cornerRadius: 6))
    }
}
