import SwiftUI

final class ClutterModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case large = "Large & old"
        case duplicates = "Duplicates"
        var id: String { rawValue }
    }

    enum Scope: String, CaseIterable, Identifiable {
        case userFolders = "Downloads, Desktop & Documents"
        case downloads = "Downloads"
        case home = "Home folder"
        var id: String { rawValue }

        var roots: [URL] {
            let h = FS.home
            switch self {
            case .userFolders: return ["Downloads", "Desktop", "Documents"].map { h.appendingPathComponent($0) }
            case .downloads: return [h.appendingPathComponent("Downloads")]
            case .home: return [h]
            }
        }
    }

    @Published var tab: Tab = .large
    @Published var scope: Scope = .userFolders
    @Published var minSizeMB = 100
    @Published var months = 6
    @Published var large: [FileEntry] = []
    @Published var groups: [DuplicateGroup] = []
    @Published var scannedLarge = false
    @Published var scannedDuplicates = false
    @Published var selected: Set<URL> = []
    @Published var scanning = false
    @Published var message: String?
    @Published var confirm = false

    private var token: CancelToken?

    var selectedSize: Int64 {
        let largeSize = large.filter { selected.contains($0.url) }.reduce(0) { $0 + $1.size }
        let dupSize = groups.reduce(Int64(0)) { sum, g in sum + Int64(g.files.filter { selected.contains($0) }.count) * g.size }
        return tab == .large ? largeSize : dupSize
    }

    func scan() {
        let t = CancelToken()
        token = t
        scanning = true
        message = nil
        let tab = self.tab, roots = scope.roots
        let minSize = Int64(minSizeMB) * 1_000_000
        let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? Date()
        DispatchQueue.global(qos: .userInitiated).async {
            switch tab {
            case .large:
                let r = Clutter.largeAndOld(roots: roots, minSize: minSize, notUsedSince: cutoff, cancel: t)
                DispatchQueue.main.async {
                    self.large = r
                    self.scannedLarge = true
                    self.selected.subtract(self.selected.filter { u in !r.contains { $0.url == u } })
                    self.finish(t)
                }
            case .duplicates:
                let r = Clutter.duplicates(roots: roots, cancel: t)
                DispatchQueue.main.async { self.setDuplicates(r); self.finish(t) }
            }
        }
    }

    /// Used by the Check up, which scans Downloads in the background.
    func setDuplicates(_ r: [DuplicateGroup]) {
        groups = r
        scannedDuplicates = true
        selected = Set(r.flatMap { g in g.files.filter { $0 != g.keep } })
    }

    private func finish(_ t: CancelToken) {
        scanning = false
        if t.cancelled { message = "Stopped. Showing what was found so far." }
    }

    func stop() { token?.cancel() }

    func binding(_ url: URL, in group: DuplicateGroup? = nil) -> Binding<Bool> {
        Binding(get: { self.selected.contains(url) }, set: { on in
            if on, let g = group, g.files.allSatisfy({ $0 == url || self.selected.contains($0) }) {
                self.message = "At least one copy is always kept."
                return
            }
            if on { self.selected.insert(url) } else { self.selected.remove(url) }
        })
    }

    /// Drops files that are no longer where the scan found them, so a stale list cannot be acted on.
    func removeMoved(_ moved: Set<URL>) {
        large.removeAll { moved.contains($0.url) }
        groups = groups.compactMap { g in
            let left = g.files.filter { !moved.contains($0) }
            guard left.count > 1 else { return nil }
            let keep = left.contains(g.keep) ? g.keep : left[0]
            return DuplicateGroup(id: g.id, size: g.size, keep: keep, files: left)
        }
        selected.subtract(moved)
    }

    func trashSelected() {
        var urls: [URL]
        switch tab {
        case .large:
            urls = large.map(\.url).filter { selected.contains($0) }
        case .duplicates:
            // Re-checked against the disk right before moving anything: one copy of each group stays.
            urls = Clutter.removable(groups, selected: selected)
        }
        let size = selectedSize
        DispatchQueue.global(qos: .userInitiated).async {
            let failed = FS.trash(urls)
            DispatchQueue.main.async {
                let moved = Set(urls).subtracting(failed.map(\.0))
                self.removeMoved(moved)
                self.message = "\(plural(moved.count, "file")) (\(Fmt.bytes(size))) moved to the Trash."
                    + (failed.isEmpty ? "" : " \(plural(failed.count, "file")) could not be moved.")
            }
        }
    }
}

struct ClutterView: View {
    @ObservedObject var model: ClutterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Clutter",
                       subtitle: "Large files you have not opened in a while, and identical copies of the same file. Nothing is selected without you seeing it first.") {
                if model.scanning {
                    Button("Stop") { model.stop() }
                } else {
                    Button("Scan") { model.scan() }.buttonStyle(.brand)
                }
            }
            controls
            Divider()
            content
            footer
        }
        .confirmationDialog("Move \(Fmt.bytes(model.selectedSize)) of files to the Trash?", isPresented: $model.confirm) {
            Button("Move to Trash", role: .destructive) { model.trashSelected() }
        } message: {
            Text("You can put them back from the Trash until you empty it.")
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Segmented(selection: $model.tab, options: ClutterModel.Tab.allCases.map { ($0, $0.rawValue) })
            ChipMenu(selection: $model.scope, options: ClutterModel.Scope.allCases.map { ($0, $0.rawValue) })
            if model.tab == .large {
                PillStepper(label: "Over (MB)", value: $model.minSizeMB, range: 10...5000, step: 50)
                PillStepper(label: "Unused (months)", value: $model.months, range: 1...36)
            }
            Spacer()
        }
        .disabled(model.scanning)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var content: some View {
        if model.scanning {
            VStack(spacing: 16) {
                ScanRing(progress: 0.25, spinning: true, size: 90, lineWidth: 9)
                Text(model.tab == .large ? "Looking for large, unused files…" : "Comparing files…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.tab == .large {
            if !model.scannedLarge {
                Placeholder(icon: "doc.badge.clock", text: "Press Scan to find large files you have not used.")
            } else if model.large.isEmpty {
                Placeholder(icon: "checkmark.circle", text: "No large, unused files here.")
            } else {
                List(model.large) { f in
                    Toggle(isOn: model.binding(f.url)) { fileRow(f.url, size: f.size, date: f.lastUsed) }
                }
            }
        } else {
            if !model.scannedDuplicates {
                Placeholder(icon: "doc.on.doc", text: "Press Scan to find identical files.")
            } else if model.groups.isEmpty {
                Placeholder(icon: "checkmark.circle", text: "No duplicates here.")
            } else {
                List {
                    ForEach(model.groups) { g in
                        Section {
                            ForEach(g.files, id: \.self) { u in
                                Toggle(isOn: model.binding(u, in: g)) {
                                    fileRow(u, size: g.size, date: nil, keep: u == g.keep)
                                }
                            }
                        } header: {
                            Text("\(plural(g.files.count, "copy", "copies")) of \(Fmt.bytes(g.size)) · \(Fmt.bytes(g.wasted)) to free")
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if let m = model.message {
                    Text(m).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                } else if model.tab == .duplicates, model.scannedDuplicates {
                    Text("Copies made by APFS cloning share space, so removing them may free less than shown.")
                        .font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                }
                Spacer()
                Text("Selected: \(Fmt.bytes(model.selectedSize))").monospacedDigit()
                Button("Move to Trash") { model.confirm = true }
                    .buttonStyle(.brand)
                    .disabled(model.selectedSize == 0 || model.scanning)
            }
            .padding(12)
        }
    }

    private func fileRow(_ url: URL, size: Int64, date: Date?, keep: Bool = false) -> some View {
        HStack {
            FileIcon(url: url, size: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent.displaySafe).lineLimit(1).truncationMode(.middle)
                Text(FS.shortPath(url.deletingLastPathComponent()).displaySafe)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            if keep {
                Text("Keep").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Brand.emerald.opacity(0.2), in: Capsule())
            }
            Spacer()
            if let date {
                Text("Last used \(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !keep, date == nil, model.tab == .large {
                Text("Never opened").font(.caption).foregroundStyle(.secondary)
            }
            Text(Fmt.bytes(size)).monospacedDigit().foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
        }
        .contextMenu { Button("Show in Finder") { FS.reveal(url) } }
    }
}
