import SwiftUI

enum Version {
    /// Numeric, component-wise comparison: "1.10" is newer than "1.9", and a pre-release such as
    /// "2.0b1" or "2.0-rc1" is older than "2.0".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let (an, ap) = split(a), (bn, bp) = split(b)
        let c = compare(parts(an), parts(bn))
        if c != 0 { return c > 0 }
        if ap != bp { return bp }           // same numbers: the release beats the pre-release
        return compare(parts(a), parts(b)) > 0
    }

    private static func compare(_ x: [Int], _ y: [Int]) -> Int {
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r ? 1 : -1 }
        }
        return 0
    }

    /// The leading dotted number, and whether what follows marks a pre-release.
    private static func split(_ s: String) -> (String, Bool) {
        let head = String(s.prefix { $0.isNumber || $0 == "." })
        let rest = s.dropFirst(head.count).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " -_."))
        let pre = ["a", "b", "alpha", "beta", "rc", "pre", "dev", "preview"].contains { rest.hasPrefix($0) }
        return (head, pre)
    }

    private static func parts(_ s: String) -> [Int] {
        s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0.prefix(9)) }
    }
}

/// Reads a Sparkle appcast and returns the newest version it offers.
final class Appcast: NSObject, XMLParserDelegate {
    private(set) var versions: [(short: String?, build: String?)] = []
    private var text = ""
    private var current: (short: String?, build: String?)?

    static func latest(_ data: Data) -> (short: String?, build: String?)? {
        let a = Appcast()
        let p = XMLParser(data: data)
        p.shouldResolveExternalEntities = false
        p.delegate = a
        guard p.parse() else { return nil }
        return a.versions.max { lhs, rhs in
            Version.isNewer(rhs.short ?? rhs.build ?? "0", than: lhs.short ?? lhs.build ?? "0")
        }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        if name == "item" { current = (nil, nil) }
        if name == "enclosure", var c = current {
            if c.short == nil { c.short = attributes["sparkle:shortVersionString"] }
            if c.build == nil { c.build = attributes["sparkle:version"] }
            current = c
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "sparkle:shortVersionString": if !value.isEmpty { current?.short = value }
        case "sparkle:version": if !value.isEmpty { current?.build = value }
        case "item":
            if let c = current, c.short != nil || c.build != nil { versions.append(c) }
            current = nil
        default: break
        }
    }
}

/// Downloads small documents only: any response that announces or reaches `limit` bytes is
/// cancelled, and redirects must stay on https and off local addresses.
final class CappedFetcher: NSObject, URLSessionDataDelegate {
    private let limit: Int
    private let lock = NSLock()
    private var buffers: [Int: Data] = [:]
    private var handlers: [Int: (Data?) -> Void] = [:]
    private var session: URLSession!

    init(limit: Int, configuration: URLSessionConfiguration) {
        self.limit = limit
        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// Public https hosts only: no IP literals, localhost or .local names, so an app's feed URL
    /// cannot make Messy probe the local network.
    static func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".localhost") || host.contains(":") { return false }
        return host.range(of: "^[0-9.]+$", options: .regularExpression) == nil
    }

    func fetch(_ url: URL, done: @escaping (Data?) -> Void) {
        let task = session.dataTask(with: url)
        lock.lock(); handlers[task.taskIdentifier] = done; buffers[task.taskIdentifier] = Data(); lock.unlock()
        task.resume()
    }

    func finish() { session.invalidateAndCancel() }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let ok = (response as? HTTPURLResponse)?.statusCode == 200 && response.expectedContentLength <= Int64(limit)
        completionHandler(ok ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        buffers[dataTask.taskIdentifier, default: Data()].append(data)
        let over = (buffers[dataTask.taskIdentifier]?.count ?? 0) > limit
        lock.unlock()
        if over { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(Self.allowed) == true ? request : nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let data = buffers.removeValue(forKey: task.taskIdentifier)
        let handler = handlers.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        let over = (data?.count ?? 0) > limit
        handler?(error == nil && !over ? data : nil)
    }
}

/// True for an app downloaded from the internet that has never been opened; its feed is not
/// contacted, since that would tell its developer about an app the user has not used.
func neverOpened(_ app: URL) -> Bool {
    var buf = [CChar](repeating: 0, count: 256)
    let n = getxattr(app.path, "com.apple.quarantine", &buf, buf.count, 0, 0)
    guard n > 0 else { return false }
    let value = String(decoding: buf.prefix(n).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    guard let flags = Int(value.split(separator: ";").first ?? "", radix: 16) else { return false }
    return flags & 0x40 == 0   // 0x40: the user has opened and approved it
}

struct AppUpdate: Identifiable {
    enum Source { case sparkle(URL), homebrew(String) }
    let id: String
    let name: String
    let installed: String
    let latest: String
    let source: Source
}

final class UpdatesModel: ObservableObject {
    @Published var checking = false
    @Published var checked = false
    @Published var updates: [AppUpdate] = []
    @Published var checkedApps = 0
    @Published var appStoreApps = 0
    @Published var hasBrew = false
    /// Which Apps tab is showing; lives here so the Check up can open Updates.
    @Published var showTab = false

    static let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]

    struct Result {
        let updates: [AppUpdate]
        let checkedApps: Int
        let appStoreApps: Int
        let hasBrew: Bool
    }

    /// Contacts each app's own update server (and reads Homebrew's local data). Only runs on click.
    func check() {
        checking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Self.fetch()
            DispatchQueue.main.async {
                self.apply(r)
                self.checking = false
            }
        }
    }

    func apply(_ r: Result) {
        updates = r.updates
        checkedApps = r.checkedApps
        appStoreApps = r.appStoreApps
        hasBrew = r.hasBrew
        checked = true
    }

    static func fetch() -> Result {
        var found: [AppUpdate] = []
        let lock = NSLock()
        var feeds: [(AppInfo, URL, String, String)] = []
        var mas = 0
        for app in AppScanner.apps() {
            let info = FS.plist(app.url.appendingPathComponent("Contents/Info.plist")) ?? [:]
            if FS.exists(app.url.appendingPathComponent("Contents/_MASReceipt")) { mas += 1; continue }
            guard let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:)),
                  CappedFetcher.allowed(feed), !neverOpened(app.url) else { continue }
            feeds.append((app, feed, info["CFBundleShortVersionString"] as? String ?? "", info["CFBundleVersion"] as? String ?? ""))
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        config.httpCookieStorage = nil
        config.urlCache = nil
        let fetcher = CappedFetcher(limit: 2_000_000, configuration: config)
        let group = DispatchGroup()
        let limit = DispatchSemaphore(value: 4)
        for (app, feed, short, build) in feeds {
            group.enter()
            limit.wait()
            fetcher.fetch(feed) { data in
                defer { limit.signal(); group.leave() }
                guard let data, let latest = Appcast.latest(data) else { return }
                let newer: Bool
                if let s = latest.short, !short.isEmpty { newer = Version.isNewer(s, than: short) }
                else if let b = latest.build { newer = Version.isNewer(b, than: build) }
                else { newer = false }
                if newer {
                    let u = AppUpdate(id: app.url.path, name: app.name, installed: short.isEmpty ? build : short,
                                      latest: latest.short ?? latest.build ?? "", source: .sparkle(app.url))
                    lock.lock(); found.append(u); lock.unlock()
                }
            }
        }
        group.wait()
        fetcher.finish()

        let brew = Self.brewPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
        if let brew { found += Self.brewOutdated(brew) }

        return Result(updates: found.sorted { $0.name.lowercased() < $1.name.lowercased() },
                      checkedApps: feeds.count, appStoreApps: mas, hasBrew: brew != nil)
    }

    /// Uses Homebrew's local data without updating it, so it makes no network request of its own.
    private static func brewOutdated(_ brew: String) -> [AppUpdate] {
        let r = Shell.run(brew, ["outdated", "--cask", "--json=v2"],
                          env: ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1"], timeout: 60)
        guard let data = r.out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = json["casks"] as? [[String: Any]] else { return [] }
        return casks.compactMap { c in
            guard let token = c["name"] as? String, isValidToken(token) else { return nil }
            let installed = (c["installed_versions"] as? [String])?.first ?? ""
            return AppUpdate(id: "brew:" + token, name: token, installed: installed,
                             latest: c["current_version"] as? String ?? "", source: .homebrew(token))
        }
    }

    static func isValidToken(_ t: String) -> Bool {
        t.range(of: "^[a-z0-9][a-z0-9@._+-]*$", options: .regularExpression) != nil
    }
}

struct UpdatesView: View {
    @ObservedObject var model: UpdatesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("Checking asks each app's own update server for its latest version. Those servers see your IP address and that you have the app, the same as when the app checks by itself. Nothing is downloaded or installed.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 20)
                Button {
                    model.check()
                } label: {
                    if model.checking { ProgressView().controlSize(.small) } else { Text(model.checked ? "Check again" : "Check for updates") }
                }
                .buttonStyle(.brand)
                .disabled(model.checking)
            }
            .padding(16)
            Divider()

            if !model.checked {
                Placeholder(icon: "arrow.down.app", text: model.checking ? "Checking…" : "Updates are only checked when you ask.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Checked \(plural(model.checkedApps, "app")) that update themselves\(model.hasBrew ? " and your Homebrew apps" : "").")
                            .font(.caption).foregroundStyle(.secondary)
                        if model.updates.isEmpty {
                            Label("Everything checked is up to date.", systemImage: "checkmark.seal.fill").foregroundStyle(Brand.emerald)
                        }
                        ForEach(model.updates) { u in row(u) }
                        if model.appStoreApps > 0 {
                            HStack {
                                Text("\(plural(model.appStoreApps, "app")) from the App Store update there.").font(.callout)
                                Spacer()
                                Button("Open App Store updates") {
                                    if let url = URL(string: "macappstore://showUpdatesPage") { NSWorkspace.shared.open(url) }
                                }
                            }
                            .card(padding: 12)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func row(_ u: AppUpdate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if case .sparkle(let app) = u.source { FileIcon(url: app, size: 28) } else { GradientIcon(symbol: "shippingbox", size: 20) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(u.name.displaySafe).bold()
                    Text("\(u.installed.displaySafe) → \(u.latest.displaySafe)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if case .sparkle(let app) = u.source {
                    Button("Open app") { NSWorkspace.shared.open(app) }
                        .help("The app installs its own update, usually from its menu: Check for Updates")
                }
            }
            if case .homebrew(let token) = u.source, UpdatesModel.isValidToken(token) {
                CommandBox(title: "Update with Homebrew", commands: "brew upgrade --cask \(token)")
            }
        }
        .card(padding: 12)
    }
}

/// Apps pane: uninstaller and updates.
struct AppsView: View {
    @ObservedObject var uninstall: UninstallModel
    @ObservedObject var updates: UpdatesModel

    var body: some View {
        VStack(spacing: 0) {
            Segmented(selection: $updates.showTab, options: [(false, "Uninstall"), (true, "Updates")])
                .padding(.top, 12)
            if updates.showTab { UpdatesView(model: updates) } else { UninstallView(model: uninstall) }
        }
    }
}
