import SwiftUI

enum Prefs2 {
    /// The update check contacts other servers, so it joins the Check up only when turned on.
    static let checkupUpdates = "checkupUpdates"
}

final class CheckupModel: ObservableObject {
    enum Phase { case idle, scanning, results, running, done }

    enum Module: String, CaseIterable, Identifiable {
        case junk, threats, maintenance, duplicates, updates
        var id: String { rawValue }

        var title: String {
            switch self {
            case .junk: "Junk"
            case .threats: "Threats"
            case .maintenance: "Maintenance"
            case .duplicates: "Duplicates"
            case .updates: "App updates"
            }
        }

        var icon: String {
            switch self {
            case .junk: "sparkles"
            case .threats: "lock.shield"
            case .maintenance: "bolt"
            case .duplicates: "doc.on.doc"
            case .updates: "arrow.down.app"
            }
        }
    }

    @Published var phase: Phase = .idle
    @Published var finished: Set<Module> = []
    @Published var selected: Set<Module> = []
    @Published var confirm = false
    @Published var summary: [String] = []
    @Published var problems: [String] = []
    @Published var lastScan: Date?

    // Results
    @Published var junk: Int64 = 0
    @Published var threats: [Threat] = []
    @Published var tasks: [MaintenanceTask] = []
    @Published var duplicatesSize: Int64 = 0
    @Published var duplicateGroups = 0
    /// The Check up's own Downloads scan; Run acts on exactly this, not on the Clutter pane's state.
    private var dupGroups: [DuplicateGroup] = []
    @Published var updateCount: Int?

    private unowned let store: Store
    private var token = CancelToken()

    init(store: Store) { self.store = store }

    var modules: [Module] { Module.allCases }
    var progress: Double { Double(finished.count) / Double(modules.count) }
    var includeUpdates: Bool { UserDefaults.standard.bool(forKey: Prefs2.checkupUpdates) }

    /// Threats the Check up may remove: the user's own launch agents with a strong signal (code
    /// injection, a fake Apple name, running from a temporary folder). Weaker findings, such as a
    /// non-Apple certificate, are left for the user to review in Protect.
    var removableThreats: [Threat] { threats.filter { $0.removable && $0.trust == .danger && $0.strong } }

    func start() {
        let t = CancelToken()
        token = t
        withAnimation(.easeInOut(duration: 0.3)) { phase = .scanning }
        Sound.scan.play()
        finished = []
        summary = []
        problems = []
        let speed = store.speed

        func done(_ m: Module, _ apply: @escaping () -> Void) {
            DispatchQueue.main.async {
                guard !t.cancelled else { return }
                apply()
                self.finished.insert(m)
                if self.finished.count == self.modules.count { self.finishScan() }
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let g = CleanModel.collect()
            done(.junk) {
                self.store.clean.apply(g)
                self.junk = self.store.clean.selectedSize
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let r = SecurityModel.fullScan()
            done(.threats) {
                self.store.security.apply(r)
                self.threats = r.threats
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let week = Date().addingTimeInterval(-7 * 86400)
            let due = [MaintenanceTask.flushDNS, .quickLook, .launchServices].filter { (speed.lastRun($0) ?? .distantPast) < week }
            done(.maintenance) { self.tasks = due }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let groups = Clutter.duplicates(roots: [FS.home.appendingPathComponent("Downloads")], cancel: t)
            done(.duplicates) {
                self.dupGroups = groups
                self.store.clutter.scope = .downloads
                self.store.clutter.tab = .duplicates
                self.store.clutter.setDuplicates(groups)
                self.duplicateGroups = groups.count
                self.duplicatesSize = groups.reduce(0) { $0 + $1.wasted }
            }
        }
        let withUpdates = includeUpdates
        DispatchQueue.global(qos: .userInitiated).async {
            let r = withUpdates ? UpdatesModel.fetch() : nil
            done(.updates) {
                if let r { self.store.updates.apply(r) }
                self.updateCount = r?.updates.count
            }
        }
    }

    func cancel() {
        token.cancel()
        withAnimation(.easeInOut(duration: 0.3)) { phase = .idle }
    }

    private func finishScan() {
        lastScan = Date()
        selected = []
        if junk > 0 { selected.insert(.junk) }
        if !removableThreats.isEmpty { selected.insert(.threats) }
        if !tasks.isEmpty { selected.insert(.maintenance) }
        if duplicatesSize > 0 { selected.insert(.duplicates) }
        withAnimation(.easeInOut(duration: 0.35)) { phase = .results }
        (threats.contains { $0.trust == .danger } ? Sound.warn : Sound.found).play()
    }

    var canRun: Bool { !selected.subtracting([.updates]).isEmpty }

    /// What Run will do, for the confirmation dialog.
    var plan: [String] {
        var p: [String] = []
        if selected.contains(.junk) { p.append("Move \(Fmt.bytes(junk)) of junk to the Trash") }
        if selected.contains(.duplicates) { p.append("Move \(Fmt.bytes(duplicatesSize)) of duplicate copies in Downloads to the Trash") }
        if selected.contains(.threats) {
            p.append("Stop and move these background agents to the Trash:")
            p += removableThreats.compactMap(\.item).map { "   \($0.label.displaySafe) (\(FS.shortPath($0.file).displaySafe))" }
        }
        if selected.contains(.maintenance) { p.append(tasks.map(\.title).joined(separator: ", ")) }
        return p
    }

    func run() {
        phase = .running
        let doJunk = selected.contains(.junk), doDupes = selected.contains(.duplicates)
        let doThreats = selected.contains(.threats), doTasks = selected.contains(.maintenance)
        let junkURLs = Array(store.clean.selected)
        // The Check up's own groups, every copy but the suggested one; Clutter.removable re-checks
        // on disk that a copy stays.
        let groups = dupGroups
        let dupSelection = Set(groups.flatMap { g in g.files.filter { $0 != g.keep } })
        let agents = removableThreats.compactMap(\.item)
        let tasks = self.tasks
        let speed = store.speed

        DispatchQueue.global(qos: .userInitiated).async {
            var summary: [String] = []
            var problems: [String] = []
            if doJunk {
                let failed = FS.trash(junkURLs)
                summary.append("Junk: \(plural(junkURLs.count - failed.count, "item")) moved to the Trash")
                if !failed.isEmpty { problems.append("\(plural(failed.count, "junk item")) could not be moved (in use or protected).") }
            }
            var movedDupes: [URL] = []
            if doDupes {
                let dupURLs = Clutter.removable(groups, selected: dupSelection)
                let failed = FS.trash(dupURLs)
                movedDupes = dupURLs.filter { u in !failed.contains { $0.0 == u } }
                summary.append("Duplicates: \(plural(dupURLs.count - failed.count, "copy", "copies")) moved to the Trash")
                if !failed.isEmpty { problems.append("\(plural(failed.count, "copy", "copies")) could not be moved.") }
            }
            if doThreats {
                for a in agents { Launchd.bootoutUserAgent(plist: a.file) }
                let failed = FS.trash(agents.map(\.file))
                summary.append("Threats: \(plural(agents.count - failed.count, "agent")) stopped and moved to the Trash")
                if !failed.isEmpty { problems.append("\(plural(failed.count, "agent")) could not be moved.") }
            }
            var ranTasks: [MaintenanceTask] = []
            if doTasks {
                let admin = tasks.filter(\.needsAdmin)
                if !admin.isEmpty {
                    switch Shell.admin(admin.flatMap(\.adminCommands)) {
                    case .ok: ranTasks += admin
                    case .cancelled: problems.append("Maintenance tasks that need your password were cancelled.")
                    case .failed: problems.append("Maintenance tasks that need your password could not run.")
                    }
                }
                for t in tasks where !t.needsAdmin {
                    if t.runAsUser() { ranTasks.append(t) } else { problems.append("\(t.title) failed.") }
                }
                if !ranTasks.isEmpty { summary.append("Maintenance: " + ranTasks.map(\.title).joined(separator: ", ")) }
            }
            DispatchQueue.main.async {
                for t in ranTasks { UserDefaults.standard.set(Date(), forKey: "lastRun." + t.rawValue) }
                speed.objectWillChange.send()
                self.summary = summary
                self.problems = problems
                withAnimation(.easeInOut(duration: 0.35)) { self.phase = .done }
                Sound.done.play()
                // Rescan or prune the panes that changed so they do not show moved files.
                self.store.clutter.removeMoved(Set(movedDupes))
                self.dupGroups = []
                if doJunk { self.store.clean.scan() }
                if doThreats { self.store.security.scan() }
            }
        }
    }
}

struct CheckupView: View {
    @ObservedObject var model: CheckupModel
    let nav: NavState
    let store: Store

    var body: some View {
        Group {
            switch model.phase {
            case .idle: idle
            case .scanning: scanning
            case .results: results
            case .running: working
            case .done: done
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("Run the Check up?", isPresented: $model.confirm) {
            Button("Run") { model.run() }
        } message: {
            Text(model.plan.map { $0.hasPrefix("   ") ? $0 : "• " + $0 }.joined(separator: "\n") + "\n\nFiles go to the Trash; nothing is deleted.")
        }
    }

    private var idle: some View {
        VStack(spacing: 22) {
            ZStack {
                ScanRing(progress: 0, size: 230, lineWidth: 14)
                Mascot(pose: .idle, size: 132, motion: .bob)
            }
            VStack(spacing: 6) {
                Text("Let's find the mess.").font(.largeTitle.bold())
                Text("Looks for junk, threats, maintenance that is due and duplicates in Downloads, all at once. Nothing changes until you review the results and press Run.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 460)
            }
            Button("Scan") { model.start() }
                .buttonStyle(.brandLarge)
                .keyboardShortcut(.defaultAction)
            Text(model.includeUpdates ? "Includes an update check, which contacts each app's update server."
                                      : "Update checks are off; turn them on in Settings to include them.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var scanning: some View {
        VStack(spacing: 26) {
            ZStack {
                ScanRing(progress: model.progress, spinning: true, size: 230, lineWidth: 14)
                Mascot(pose: .sweep, size: 128, motion: .sweep)
            }
            Text("Hunting for mess… \(Int(model.progress * 100))%")
                .font(.title2.bold()).monospacedDigit().contentTransition(.numericText())
            HStack(spacing: 10) {
                ForEach(model.modules) { m in
                    let done = model.finished.contains(m)
                    HStack(spacing: 6) {
                        Image(systemName: done ? "checkmark.circle.fill" : m.icon)
                            .foregroundStyle(done ? AnyShapeStyle(Brand.emerald) : AnyShapeStyle(Brand.gradient))
                            .symbolEffect(.pulse, isActive: !done)
                        Text(m.title).font(.callout.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(done ? Brand.emerald.opacity(0.15) : Brand.teal.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(Brand.teal.opacity(0.2), lineWidth: 1))
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: done)
                }
            }
            Button("Stop") { model.cancel() }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Here's the mess",
                       subtitle: "Ticked cards run together. Open Review to see or change exactly what is included.") {
                HStack {
                    Button("Scan again") { model.start() }
                    Button("Run") { model.confirm = true }
                        .buttonStyle(.brand)
                        .disabled(!model.canRun)
                }
            }
            ScrollView {
                HStack(spacing: 16) {
                    Mascot(pose: model.threats.contains { $0.trust == .danger } ? .worried : .happy, size: 76, motion: .bob)
                    if model.junk > 0 || model.duplicatesSize > 0 {
                        HStack(spacing: -10) {
                            DustBunny(mood: .scared, size: 38)
                            DustBunny(mood: .idle, size: 30).offset(y: 8)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline).font(.title2.bold())
                        Text("Nothing has changed yet. Untick anything you want to keep as it is.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .card(padding: 18)
                .padding([.horizontal, .top], 16)
                .appearIn(delay: 0)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    Tile(icon: "sparkles", title: "Junk", value: Fmt.bytes(model.junk),
                         accent: model.junk > 0 ? Brand.coral : .primary,
                         caption: "Caches, logs and developer leftovers.",
                         selected: tick(.junk, enabled: model.junk > 0),
                         review: { nav.pane = .clean })
                        .hoverLift().appearIn(delay: 0.05)
                    Tile(icon: "lock.shield", title: "Threats",
                         value: model.threats.isEmpty ? "None" : plural(model.threats.count, "item"),
                         caption: model.threats.isEmpty ? "Nothing suspicious found." :
                            "\(model.removableThreats.count) can be removed here; review the rest in Protect.",
                         selected: tick(.threats, enabled: !model.removableThreats.isEmpty),
                         review: { nav.pane = .protect })
                        .hoverLift().appearIn(delay: 0.10)
                    Tile(icon: "bolt", title: "Maintenance",
                         value: model.tasks.isEmpty ? "Up to date" : plural(model.tasks.count, "task"),
                         caption: model.tasks.isEmpty ? "Nothing is due." : model.tasks.map(\.title).joined(separator: ", "),
                         selected: tick(.maintenance, enabled: !model.tasks.isEmpty),
                         review: { nav.pane = .speed })
                        .hoverLift().appearIn(delay: 0.15)
                    Tile(icon: "doc.on.doc", title: "Duplicates", value: Fmt.bytes(model.duplicatesSize),
                         accent: model.duplicatesSize > 0 ? Brand.coral : .primary,
                         caption: model.duplicateGroups == 0 ? "No duplicates in Downloads." :
                            "\(plural(model.duplicateGroups, "file")) in Downloads with extra copies. One copy is always kept.",
                         selected: tick(.duplicates, enabled: model.duplicatesSize > 0),
                         review: { nav.pane = .clutter; store.clutter.tab = .duplicates })
                        .hoverLift().appearIn(delay: 0.20)
                    Tile(icon: "arrow.down.app", title: "App updates",
                         value: model.updateCount.map { $0 == 0 ? "Up to date" : plural($0, "update") } ?? "Off",
                         caption: model.updateCount == nil ? "Turn on in Settings to include update checks." :
                            "Apps install their own updates; Messy only checks.",
                         review: { nav.pane = .apps; store.updates.showTab = true })
                        .hoverLift().appearIn(delay: 0.25)
                }
                .padding(16)
            }
        }
    }

    private var headline: String {
        var parts: [String] = []
        if model.junk > 0 { parts.append("\(Fmt.bytes(model.junk)) to clean") }
        if model.duplicatesSize > 0 { parts.append("\(Fmt.bytes(model.duplicatesSize)) of duplicates") }
        let risky = model.threats.filter { $0.trust == .danger }.count
        if risky > 0 { parts.append(plural(risky, "thing", "things") + " to look at") }
        return parts.isEmpty ? "Spotless. Nothing to sweep." : "Found " + parts.joined(separator: ", ") + "."
    }

    private func tick(_ m: CheckupModel.Module, enabled: Bool) -> Binding<Bool>? {
        guard enabled else { return nil }
        return Binding(get: { model.selected.contains(m) },
                       set: { if $0 { model.selected.insert(m) } else { model.selected.remove(m) } })
    }

    private var working: some View {
        VStack(spacing: 20) {
            ZStack {
                ScanRing(progress: 1, spinning: true, size: 200, lineWidth: 14)
                Mascot(pose: .sweep, size: 120, motion: .sweep)
            }
            Text("Sweeping it up…").font(.title2.bold())
        }
    }

    private var done: some View {
        VStack(spacing: 20) {
            ZStack {
                ScanRing(progress: 1, size: 200, lineWidth: 14)
                Mascot(pose: .happy, size: 112, motion: .bounce)
                DustBunny(mood: .gone, size: 54).offset(x: 92, y: 58)
            }
            .overlay(Confetti().frame(width: 600, height: 500))
            Text("Spotless.").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.summary, id: \.self) { Label($0, systemImage: "checkmark.circle").foregroundStyle(.primary) }
                ForEach(model.problems, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                if model.summary.isEmpty && model.problems.isEmpty { Text("Nothing needed doing.").foregroundStyle(.secondary) }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .card()
            Text("The space comes back when you empty the Trash.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Open Trash") { FS.openTrash() }
                Button("Scan again") { model.start() }.buttonStyle(.brand)
            }
        }
    }
}
