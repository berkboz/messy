import AppKit
import SwiftUI

struct AppInfo: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let bundleID: String?
    var size: Int64 = -1
}

struct Leftover: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    /// Matched only because its name equals the app's name, which another app can share
    /// ("Google", "Microsoft"), so it is never ticked for the user.
    var byName = false
    /// Lives under /Library and may need an admin password to remove.
    var system: Bool { url.path.hasPrefix("/Library/") }
    var isLaunchItem: Bool { url.path.contains("/LaunchAgents/") || url.path.contains("/LaunchDaemons/") }
}

enum AppScanner {
    /// Third-party apps in /Applications and ~/Applications, one folder level deep.
    static func apps() -> [AppInfo] {
        var urls: [URL] = []
        for root in [URL(fileURLWithPath: "/Applications"), FS.home.appendingPathComponent("Applications")] {
            for u in FS.children(root) {
                if u.pathExtension == "app" { urls.append(u) }
                else if FS.isDirectory(u) { urls += FS.children(u).filter { $0.pathExtension == "app" } }
            }
        }
        return urls.compactMap { u in
            let bid = FS.plist(u.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String
            // Case-insensitive: "Com.Apple.Safari" must not slip past and match Safari's files.
            if bid?.lowercased().hasPrefix("com.apple.") == true { return nil }
            return AppInfo(url: u, name: u.deletingPathExtension().lastPathComponent, bundleID: bid)
        }
    }

    static func leftovers(for app: AppInfo) -> [Leftover] {
        let lib = FS.home.appendingPathComponent("Library")
        let userDirs = ["Application Support", "Caches", "Preferences", "Containers", "Group Containers",
                        "Saved Application State", "Logs", "HTTPStorages", "WebKit", "Cookies",
                        "LaunchAgents", "Application Scripts"].map { lib.appendingPathComponent($0) }
        let systemDirs = ["/Library/Application Support", "/Library/Caches", "/Library/Preferences",
                          "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools",
                          "/Library/Logs"].map { URL(fileURLWithPath: $0) }

        // A bundle ID is chosen by the app's author, so only trust reverse-DNS IDs and match them
        // as whole dot-separated components. Otherwise an app with an ID like "application" could
        // drag unrelated folders into the uninstall list.
        let bid = app.bundleID?.lowercased()
        let usableBID = bid.flatMap { $0.split(separator: ".").count >= 3 ? $0 : nil }
        let name = app.name.lowercased()
        let compact = name.replacingOccurrences(of: " ", with: "")

        func matchesID(_ f: String) -> Bool {
            guard let b = usableBID else { return false }
            return f == b || f.hasPrefix(b + ".") || f.hasSuffix("." + b) || f.contains("." + b + ".")
        }
        func matchesName(_ f: String) -> Bool {
            let base = (f as NSString).deletingPathExtension
            return name.count >= 4 && (base == name || base == compact)
        }

        var found: [Leftover] = []
        for dir in userDirs + systemDirs {
            for u in FS.children(dir) {
                let f = u.lastPathComponent.lowercased()
                if matchesID(f) {
                    found.append(Leftover(url: u, size: FS.size(of: u)))
                } else if matchesName(f) {
                    found.append(Leftover(url: u, size: FS.size(of: u), byName: true))
                }
            }
        }
        return found
    }
}

final class UninstallModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var loading = false
    @Published var search = ""
    @Published var selection: URL?
    @Published var leftovers: [Leftover] = []
    @Published var chosen: Set<URL> = []
    @Published var findingLeftovers = false
    @Published var message: String?
    /// Items Finder could not move; they need the commands shown in the CommandBox.
    @Published var needsAdmin: [URL] = []
    /// Another installed app declares the same bundle ID, so its files cannot be told apart.
    @Published var sharedID = false
    @Published var confirm = false

    var filtered: [AppInfo] {
        search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var selectedApp: AppInfo? { apps.first { $0.url == selection } }

    func load() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var list = AppScanner.apps()
            let urls = list.map(\.url)
            var sizes = [Int64](repeating: 0, count: urls.count)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: urls.count) { i in
                let s = FS.size(of: urls[i])
                lock.lock(); sizes[i] = s; lock.unlock()
            }
            for i in list.indices { list[i].size = sizes[i] }
            list.sort { $0.size > $1.size }
            DispatchQueue.main.async {
                self.apps = list
                self.loading = false
            }
        }
    }

    /// Leftovers of an app that is already gone, e.g. after the user dragged it to the Trash.
    func showLeftovers(of app: AppInfo) {
        if !apps.contains(where: { $0.url == app.url }) { apps.insert(app, at: 0) }
        search = ""
        select(app.url)
    }

    func select(_ url: URL?) {
        selection = url
        leftovers = []
        chosen = []
        message = nil
        needsAdmin = []
        guard let app = selectedApp else { return }
        sharedID = false
        findingLeftovers = true
        DispatchQueue.global(qos: .userInitiated).async {
            let l = AppScanner.leftovers(for: app)
            let shared = Self.otherCopyExists(of: app)
            DispatchQueue.main.async {
                guard self.selection == app.url else { return }
                self.sharedID = shared
                self.leftovers = l
                // Only bundle-ID matches are ticked, and none at all if the ID is not unique.
                let sure = self.sharedID ? [] : l.filter { !$0.byName }.map(\.url)
                self.chosen = Set(sure).union(FS.exists(app.url) ? [app.url] : [])
                self.findingLeftovers = false
            }
        }
    }

    /// Another installed app with the same bundle ID, anywhere on the Mac. Checked fresh, since the
    /// app list may not be loaded (e.g. when opened from an "app was removed" notification).
    static func otherCopyExists(of app: AppInfo) -> Bool {
        guard let bid = app.bundleID?.lowercased() else { return false }
        let me = app.url.standardizedFileURL
        if AppScanner.apps().contains(where: { $0.url.standardizedFileURL != me && $0.bundleID?.lowercased() == bid }) { return true }
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: app.bundleID ?? "")
            .contains { $0.standardizedFileURL != me }
    }

    func binding(_ url: URL) -> Binding<Bool> {
        Binding(get: { self.chosen.contains(url) },
                set: { on in if on { self.chosen.insert(url) } else { self.chosen.remove(url) } })
    }

    var chosenSize: Int64 {
        let left = leftovers.filter { chosen.contains($0.url) }.reduce(0) { $0 + $1.size }
        let app = selectedApp.map { chosen.contains($0.url) ? max($0.size, 0) : 0 } ?? 0
        return left + app
    }

    func uninstall() {
        guard let app = selectedApp else { return }

        // Only quit the copy that is being removed, not another app with the same bundle ID.
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleURL?.standardizedFileURL == app.url.standardizedFileURL }
            .forEach { $0.terminate() }

        // Unload the user's own launch agents before trashing their plists.

        for l in leftovers where chosen.contains(l.url) && !l.system && l.isLaunchItem {
            Launchd.bootoutUserAgent(plist: l.url)
        }

        let targets = Array(chosen.filter(FS.exists))
        // Give terminated apps a moment to exit before moving them.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            FS.recycle(targets) { trashed in
                if !trashed.isEmpty { Sound.trash.play() }
                if trashed.contains(app.url) {
                    self.apps.removeAll { $0.url == app.url }
                }
                // The user may have picked another app in the meantime; don't show this result under it.
                guard self.selection == app.url else { return }
                let failed = targets.filter { !trashed.contains($0) }
                self.needsAdmin = failed
                self.message = failed.isEmpty
                    ? "\(app.name.displaySafe): \(plural(trashed.count, "item")) moved to the Trash."
                    : "\(plural(trashed.count, "item")) moved. \(plural(failed.count, "item")) need admin rights."
                self.leftovers.removeAll { trashed.contains($0.url) }
                self.chosen.subtract(trashed)
            }
        }
    }

    /// Nil if any path contains hidden characters.
    static func adminScript(for urls: [URL]) -> String? {
        let paths = urls.map(\.path)
        let lines = paths.compactMap(Shell.bootout) + paths.map(Shell.sudoTrash)
        return Shell.adminScript(lines, values: paths)
    }
}

struct UninstallView: View {
    @ObservedObject var model: UninstallModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Apps",
                       subtitle: "Removes an app together with its settings, caches and background services. Everything goes to the Trash.") {
                Button(model.apps.isEmpty ? "List apps" : "Refresh") { model.load() }
                    .disabled(model.loading)
            }
            Divider()

            if model.loading {
                ProgressView("Finding apps and their sizes…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.apps.isEmpty {
                Placeholder(icon: "trash", text: "Press “List apps” to start.")
            } else {
                HSplitView {
                    appList.frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
                    detail.frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .confirmationDialog("Move the selected items to the Trash?", isPresented: $model.confirm) {
            Button("Uninstall", role: .destructive) { model.uninstall() }
        } message: {
            Text("The app is quit first if it is open. Total \(Fmt.bytes(model.chosenSize)).")
        }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $model.search).textFieldStyle(.roundedBorder).padding(8)
            List(model.filtered, selection: Binding(get: { model.selection }, set: { model.select($0) })) { app in
                HStack {
                    FileIcon(url: app.url, size: 22)
                    Text(app.name.displaySafe).lineLimit(1)
                    Spacer()
                    Text(app.size >= 0 ? Fmt.bytes(app.size) : "…").monospacedDigit().foregroundStyle(.secondary)
                }
                .tag(app.url)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let app = model.selectedApp {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    FileIcon(url: app.url, size: 48)
                    VStack(alignment: .leading) {
                        Text(app.name.displaySafe).font(.title3.bold())
                        Text(app.bundleID?.displaySafe ?? "No bundle ID").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if model.sharedID {
                    Label("Another installed app uses the same bundle ID, so its files cannot be told apart from this one's. Nothing is ticked for you; check each item.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }

                if model.findingLeftovers {
                    ProgressView("Looking for leftovers…")
                } else {
                    List {
                        if FS.exists(app.url) {
                            Toggle(isOn: model.binding(app.url)) {
                                row(app.url, size: app.size, note: "App")
                            }
                        } else {
                            Text("The app itself is already gone; these are the files it left behind.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(model.leftovers) { l in
                            Toggle(isOn: model.binding(l.url)) {
                                row(l.url, size: l.size, note: [
                                    l.byName ? "Matched by name only; check it belongs to this app" : nil,
                                    l.system ? "System · may need admin" : nil,
                                ].compactMap { $0 }.joined(separator: " · ").nilIfEmpty)
                            }
                        }
                    }
                    .frame(minHeight: 160)
                }

                if !model.needsAdmin.isEmpty {
                    CommandBox(title: "These need admin rights",
                               commands: UninstallModel.adminScript(for: model.needsAdmin))
                }

                HStack {
                    if let m = model.message { Text(m).font(.callout).foregroundStyle(.secondary) }
                    Spacer()
                    Text(Fmt.bytes(model.chosenSize)).monospacedDigit()
                    Button("Uninstall") { model.confirm = true }
                        .buttonStyle(.brand)
                        .disabled(model.chosen.isEmpty || model.findingLeftovers)
                }
            }
            .padding(16)
        } else {
            Placeholder(icon: "app.dashed", text: "Choose an app on the left.")
        }
    }

    private func row(_ url: URL, size: Int64, note: String?) -> some View {
        HStack {
            FileIcon(url: url, size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(FS.shortPath(url).displaySafe).lineLimit(1).truncationMode(.middle)
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(size >= 0 ? Fmt.bytes(size) : "…").monospacedDigit().foregroundStyle(.secondary)
        }
        .contextMenu { Button("Show in Finder") { FS.reveal(url) } }
    }
}
