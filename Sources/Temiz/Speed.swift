import SwiftUI

enum MaintenanceTask: String, CaseIterable, Identifiable {
    case flushDNS, freeRAM, launchServices, quickLook, periodic, spotlight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flushDNS: "Flush DNS cache"
        case .freeRAM: "Free up RAM"
        case .launchServices: "Rebuild the Open With list"
        case .quickLook: "Reset Quick Look"
        case .periodic: "Run maintenance scripts"
        case .spotlight: "Rebuild the Spotlight index"
        }
    }

    var detail: String {
        switch self {
        case .flushDNS: "Helps when websites fail to load after a network or DNS change."
        case .freeRAM: "Drops the file cache with macOS's purge command. macOS fills it again over time."
        case .launchServices: "Fixes duplicate or missing apps in the Open With menu."
        case .quickLook: "Fixes stale or missing previews in Finder and Quick Look."
        case .periodic: "macOS's old daily, weekly and monthly scripts. Modern macOS runs what matters on its own, so this rarely changes anything."
        case .spotlight: "Fixes search that misses files. Spotlight is slow and busy for a while afterwards."
        }
    }

    var needsAdmin: Bool { [.flushDNS, .freeRAM, .periodic, .spotlight].contains(self) }

    /// Fixed literals only; see Shell.admin.
    var adminCommands: [StaticString] {
        switch self {
        case .flushDNS: ["/usr/bin/dscacheutil -flushcache", "/usr/bin/killall -HUP mDNSResponder"]
        case .freeRAM: ["/usr/sbin/purge"]
        case .periodic: ["/usr/sbin/periodic daily weekly monthly"]
        case .spotlight: ["/usr/bin/mdutil -E /"]
        case .launchServices, .quickLook: []
        }
    }

    func runAsUser() -> Bool {
        switch self {
        case .launchServices:
            Shell.run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                      ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"], timeout: 300).status == 0
        case .quickLook:
            Shell.run("/usr/bin/qlmanage", ["-r", "cache"], timeout: 60).status == 0
        default: false
        }
    }
}

struct StartupItem: Identifiable {
    var id: URL { item.file }
    let item: BackgroundItem
    var enabled: Bool
}

final class SpeedModel: ObservableObject {
    @Published var startup: [StartupItem] = []
    @Published var loaded = false
    @Published var loading = false
    @Published var tasks: Set<MaintenanceTask> = [.flushDNS, .quickLook]
    @Published var running = false
    @Published var message: String?

    private let defaults = UserDefaults.standard

    func lastRun(_ t: MaintenanceTask) -> Date? { defaults.object(forKey: "lastRun." + t.rawValue) as? Date }

    func load() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let items = SecurityModel.backgroundItems().filter { $0.domain != .helper }
            let user = Self.disabledLabels("gui/\(getuid())")
            let system = Self.disabledLabels("system")
            let list = items.map { i in
                StartupItem(item: i, enabled: !(i.domain == .daemon ? system : user).contains(i.label))
            }
            DispatchQueue.main.async {
                self.startup = list.sorted { $0.item.label.lowercased() < $1.item.label.lowercased() }
                self.loaded = true
                self.loading = false
            }
        }
    }

    private static func disabledLabels(_ domain: String) -> Set<String> {
        let out = Shell.run("/bin/launchctl", ["print-disabled", domain], timeout: 10).out
        var set = Set<String>()
        for line in out.split(separator: "\n") where line.contains("=> disabled") || line.contains("=> true") {
            let parts = line.split(separator: "\"")
            if parts.count >= 2 { set.insert(String(parts[1])) }
        }
        return set
    }

    /// Turns one of the user's own agents off or on. Reversible: "off" marks it disabled in
    /// launchd so it stays off after a restart, and "on" loads it again.
    func setEnabled(_ s: StartupItem, _ on: Bool) {
        let label = s.item.label
        guard s.item.domain == .user, Launchd.validLabel(label) else {
            message = "This item can only be changed by its app or with an admin command."
            return
        }
        let domain = "gui/\(getuid())"
        if on {
            Shell.run("/bin/launchctl", ["enable", "\(domain)/\(label)"])
            Shell.run("/bin/launchctl", ["bootstrap", domain, s.item.file.path])
        } else {
            Shell.run("/bin/launchctl", ["disable", "\(domain)/\(label)"])
            Launchd.bootoutUserAgent(plist: s.item.file)
        }
        if let i = startup.firstIndex(where: { $0.id == s.id }) { startup[i].enabled = on }
        message = "\(label.displaySafe) turned \(on ? "on" : "off")."
    }

    func runTasks() {
        let chosen = MaintenanceTask.allCases.filter { tasks.contains($0) }
        guard !chosen.isEmpty else { return }
        running = true
        message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            var done: [MaintenanceTask] = []
            var notes: [String] = []
            let admin = chosen.filter(\.needsAdmin)
            if !admin.isEmpty {
                switch Shell.admin(admin.flatMap(\.adminCommands)) {
                case .ok: done += admin
                case .cancelled: notes.append("Admin tasks were cancelled.")
                case .failed: notes.append("Admin tasks could not run.")
                }
            }
            for t in chosen where !t.needsAdmin {
                if t.runAsUser() { done.append(t) } else { notes.append("\(t.title) failed.") }
            }
            DispatchQueue.main.async {
                for t in done { self.defaults.set(Date(), forKey: "lastRun." + t.rawValue) }
                self.running = false
                self.message = (done.isEmpty ? "" : "Done: \(done.map(\.title).joined(separator: ", ")). ") + notes.joined(separator: " ")
            }
        }
    }
}

struct SpeedView: View {
    @ObservedObject var model: SpeedModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Speed",
                       subtitle: "What starts with your Mac, and maintenance tasks for when something feels off.") {
                Button("Login Items settings") {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(u)
                    }
                }
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let m = model.message {
                        Text(m).font(.callout).foregroundStyle(.secondary)
                    }
                    maintenance
                    startup
                }
                .padding(16)
            }
        }
        .onAppear { if !model.loaded && !model.loading { model.load() } }
    }

    private var maintenance: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Maintenance").font(.headline)
                Spacer()
                Button {
                    model.runTasks()
                } label: {
                    if model.running { ProgressView().controlSize(.small) } else { Text("Run selected") }
                }
                .buttonStyle(.brand)
                .disabled(model.running || model.tasks.isEmpty)
            }
            Text("Tasks marked with a lock ask for your password once, together.")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), alignment: .top)], spacing: 10) {
                ForEach(MaintenanceTask.allCases) { t in
                    Toggle(isOn: Binding(get: { model.tasks.contains(t) },
                                         set: { if $0 { model.tasks.insert(t) } else { model.tasks.remove(t) } })) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(t.title).bold()
                                if t.needsAdmin { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
                            }
                            Text(t.detail).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(model.lastRun(t).map { "Last run \($0.formatted(.relative(presentation: .named)))" } ?? "Not run with Temiz yet")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 12)
                }
            }
        }
    }

    private var startup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Starts with your Mac").font(.headline)
                Spacer()
                Button { model.load() } label: { Image(systemName: "arrow.clockwise") }.disabled(model.loading)
            }
            Text("Background services that start on their own. Your own agents can be turned off and on again here; for app login items, use Login Items settings.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.loading && !model.loaded { ProgressView() }
            ForEach(model.startup) { s in
                HStack(spacing: 10) {
                    TrustBadge(trust: s.item.sig.trust)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.item.label.displaySafe).bold().lineLimit(1)
                        Text(s.item.command.displaySafe).font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Text(s.item.domain.rawValue).font(.caption).foregroundStyle(.secondary)
                    if s.item.domain == .user {
                        Toggle("", isOn: Binding(get: { s.enabled }, set: { model.setEnabled(s, $0) }))
                            .toggleStyle(PillSwitchStyle()).labelsHidden().controlSize(.small)
                    } else {
                        Text(s.enabled ? "On" : "Off").font(.caption).foregroundStyle(.secondary).frame(width: 40)
                    }
                }
                .padding(10)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .contextMenu { Button("Show in Finder") { FS.reveal(s.item.file) } }
            }
        }
    }
}
