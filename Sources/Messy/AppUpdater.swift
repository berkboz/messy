import Combine
import Sparkle
import SwiftUI

/// Messy's own updates, through Sparkle. The feed is the appcast.xml attached to the latest GitHub release,
/// and every download is checked against the EdDSA key in Info.plist before it is installed.
/// Automatic checks are off until the user agrees (onboarding, Sparkle's own prompt or Settings).
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()

    @Published private(set) var canCheck = false
    @Published private(set) var lastCheck: Date?
    /// Mirrors of Sparkle's settings, which its own dialogs can change too.
    @Published private(set) var checksAutomatically = false
    @Published private(set) var downloadsAutomatically = false

    private var controller: SPUStandardUpdaterController!
    private var bag = Set<AnyCancellable>()

    var updater: SPUUpdater { controller.updater }

    /// Builds run with `swift run` have no feed in their Info.plist; Sparkle would only show an error there.
    var isAvailable: Bool { Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        guard isAvailable else { return }
        controller.startUpdater()
        updater.publisher(for: \.canCheckForUpdates).receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheck = $0 }.store(in: &bag)
        updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.checksAutomatically = $0 }.store(in: &bag)
        updater.publisher(for: \.automaticallyDownloadsUpdates).receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.downloadsAutomatically = $0 }.store(in: &bag)
        refresh()
    }

    /// `lastUpdateCheckDate` is not observable, so it is read again after each check and when Settings opens.
    func refresh() {
        guard isAvailable else { return }
        lastCheck = updater.lastUpdateCheckDate
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        DispatchQueue.main.async { self.refresh() }
    }

    func check() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// Whether the user has answered yet, in onboarding, Settings or Sparkle's prompt.
    var hasChoice: Bool { UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") != nil }

    var automaticChecks: Bool {
        get { isAvailable && checksAutomatically }
        set {
            guard isAvailable else { return }
            updater.automaticallyChecksForUpdates = newValue
            if !newValue { updater.automaticallyDownloadsUpdates = false }
        }
    }

    var automaticDownloads: Bool {
        get { isAvailable && downloadsAutomatically }
        set {
            guard isAvailable else { return }
            updater.automaticallyDownloadsUpdates = newValue
        }
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updater = AppUpdater.shared

    var body: some View {
        Button("Check for Updates…") { updater.check() }
            .disabled(!updater.canCheck)
    }
}
