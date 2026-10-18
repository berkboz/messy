import AppKit
import CoreServices
import UserNotifications

enum AlertPrefs {
    static let enabled = "alerts.enabled"
    static let lowDiskGB = "alerts.lowDiskGB"
    static let trashGB = "alerts.trashGB"
    static let memory = "alerts.memory"
    static let weekly = "alerts.weekly"
    static let appRemoved = "alerts.appRemoved"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            enabled: false, lowDiskGB: 15, trashGB: 5, memory: true, weekly: false, appRemoved: true,
        ])
    }
}

/// Notifications for low disk, a full Trash, sustained memory pressure, a weekly reminder and
/// apps deleted from /Applications. Opt-in, and only while Messy is running: there is no daemon.
final class AlertCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertCenter()

    /// Opens the main window on a given pane; set by the window when it first appears.
    var show: ((Pane) -> Void)?
    private weak var stats: SystemStats?
    private weak var store: Store?
    private var timer: Timer?
    private var stream: FSEventStreamRef?
    private var knownApps: [String: AppInfo] = [:]
    private var pressureSince: Date?
    private let defaults = UserDefaults.standard

    private var enabled: Bool { defaults.bool(forKey: AlertPrefs.enabled) }

    func start(stats: SystemStats, store: Store) {
        guard self.stats == nil else { return }
        self.stats = stats
        self.store = store
        UNUserNotificationCenter.current().delegate = self
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.evaluate() }
        refreshKnownApps()
        watchApplications()
        updateWeekly()
    }

    /// Asks macOS for permission the first time alerts are turned on.
    func requestPermission(_ done: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }

    // MARK: Conditions

    private func evaluate() {
        guard enabled, let s = stats else { return }
        let lowDisk = Int64(defaults.integer(forKey: AlertPrefs.lowDiskGB)) * 1_000_000_000
        if s.diskTotal > 0, s.diskFree < lowDisk {
            post("lowDisk", title: "Your startup disk is getting full",
                 body: "\(Fmt.bytes(s.diskFree)) free. Open Messy to see what takes up space.", pane: .space)
        }
        if defaults.bool(forKey: AlertPrefs.memory) {
            // Only after five minutes of high pressure, so short spikes do not alert.
            if s.pressure >= 2 {
                pressureSince = pressureSince ?? Date()
                if Date().timeIntervalSince(pressureSince!) > 300 {
                    post("memory", title: "Memory has been tight for a while",
                         body: "Quitting an app you are not using helps most. Open Messy to see which apps use the most.",
                         pane: .monitor)
                }
            } else {
                pressureSince = nil
            }
        }
        let trashLimit = Int64(defaults.integer(forKey: AlertPrefs.trashGB)) * 1_000_000_000
        DispatchQueue.global(qos: .utility).async {
            if let t = FS.trashInfo(), t.size > trashLimit {
                self.post("trash", title: "The Trash holds \(Fmt.bytes(t.size))",
                          body: "Emptying it gives the space back.", pane: .clean)
            }
        }
    }

    /// At most one alert of each kind per day.
    private func post(_ kind: String, title: String, body: String, pane: Pane, extra: [String: String] = [:]) {
        let key = "alerts.last." + kind
        if let last = defaults.object(forKey: key) as? Date, Date().timeIntervalSince(last) < 86400 { return }
        defaults.set(Date(), forKey: key)
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.userInfo = extra.merging(["pane": pane.rawValue]) { a, _ in a }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: kind + UUID().uuidString, content: c, trigger: nil))
    }

    func updateWeekly() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["weekly"])
        guard enabled, defaults.bool(forKey: AlertPrefs.weekly) else { return }
        let c = UNMutableNotificationContent()
        c.title = "Time for a Check up"
        c.body = "A quick scan for junk, threats and duplicates."
        c.userInfo = ["pane": Pane.checkup.rawValue]
        var when = DateComponents()
        when.weekday = 1   // Sunday
        when.hour = 11
        center.add(UNNotificationRequest(identifier: "weekly", content: c,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
    }

    // MARK: Apps moved to the Trash

    private func refreshKnownApps() {
        DispatchQueue.global(qos: .utility).async {
            let apps = Dictionary(AppScanner.apps().map { ($0.url.path, $0) }) { a, _ in a }
            DispatchQueue.main.async { self.knownApps = apps }
        }
    }

    /// FSEvents on the Applications folders; needs no Full Disk Access, unlike watching ~/.Trash.
    private func watchApplications() {
        let paths = ["/Applications", FS.home.appendingPathComponent("Applications").path] as CFArray
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let me = Unmanaged<AlertCenter>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { me.applicationsChanged() }
        }
        guard let s = FSEventStreamCreate(nil, callback, &ctx, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                          2.0, FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)) else { return }
        FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
        FSEventStreamStart(s)
        stream = s
    }

    private func applicationsChanged() {
        let before = knownApps
        DispatchQueue.global(qos: .utility).async {
            let now = Dictionary(AppScanner.apps().map { ($0.url.path, $0) }) { a, _ in a }
            let removed = before.filter { now[$0.key] == nil }.map(\.value)
            let withLeftovers = removed.filter { !AppScanner.leftovers(for: $0).isEmpty }
            DispatchQueue.main.async {
                self.knownApps = now
                guard self.enabled, self.defaults.bool(forKey: AlertPrefs.appRemoved) else { return }
                for app in withLeftovers {
                    self.post("removed:" + (app.bundleID ?? app.name),
                              title: "\(app.name.displaySafe) was removed",
                              body: "It left settings and caches behind. Open Messy to remove them too.",
                              pane: .apps,
                              extra: ["path": app.url.path, "name": app.name, "bundleID": app.bundleID ?? ""])
                }
            }
        }
    }

    // MARK: Notification clicks

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        DispatchQueue.main.async {
            if let path = info["path"] as? String, let name = info["name"] as? String {
                let bid = (info["bundleID"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                self.store?.uninstall.showLeftovers(of: AppInfo(url: URL(fileURLWithPath: path), name: name, bundleID: bid, size: 0))
            }
            let pane = (info["pane"] as? String).flatMap(Pane.init(rawValue:)) ?? .checkup
            self.show?(pane)
        }
        done()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner])
    }
}
