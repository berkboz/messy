import AppKit
import SwiftUI

struct DiskEntry: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    let isDir: Bool
}

final class DiskModel: ObservableObject {
    @Published var stack: [URL] = []
    @Published var entries: [DiskEntry] = []
    @Published var scanning = false
    @Published var message: String?
    @Published var pendingTrash: DiskEntry?
    @Published var showMap = true

    private var cache: [URL: [DiskEntry]] = [:]

    var current: URL? { stack.last }
    var total: Int64 { entries.reduce(0) { $0 + $1.size } }

    func start(_ url: URL) {
        stack = [url]
        load(url)
    }

    func open(_ entry: DiskEntry) {
        guard entry.isDir else { return }
        stack.append(entry.url)
        load(entry.url)
    }

    func go(to index: Int) {
        stack = Array(stack.prefix(index + 1))
        if let c = current { load(c) }
    }

    func refresh() {
        guard let c = current else { return }
        cache[c] = nil
        load(c)
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = current ?? FS.home
        if panel.runModal() == .OK, let u = panel.url { start(u) }
    }

    func trash(_ entry: DiskEntry) {
        let failed = FS.trash([entry.url])
        if let f = failed.first {
            message = "Could not move: \(f.1)"
            return
        }
        message = "\(entry.url.lastPathComponent.displaySafe) (\(Fmt.bytes(entry.size))) moved to the Trash."
        // Sizes of every folder above this one changed.
        for u in stack { cache[u] = nil }
        entries.removeAll { $0.url == entry.url }
    }

    private func load(_ url: URL) {
        message = nil
        if let c = cache[url] {
            entries = c
            return
        }
        scanning = true
        entries = []
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.scan(url)
            DispatchQueue.main.async {
                self.cache[url] = result
                guard self.current == url else { return }
                self.entries = result
                self.scanning = false
            }
        }
    }

    private static func scan(_ url: URL) -> [DiskEntry] {
        let kids = FS.children(url)
        var out: [DiskEntry] = []
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: kids.count) { i in
            let k = kids[i]
            let v = try? k.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
            if v?.isSymbolicLink == true { return }
            let e = DiskEntry(url: k, size: FS.size(of: k),
                              isDir: v?.isDirectory == true && v?.isPackage != true)
            lock.lock(); out.append(e); lock.unlock()
        }
        return out.sorted { $0.size > $1.size }
    }
}

struct DiskView: View {
    @ObservedObject var model: DiskModel
    @EnvironmentObject private var stats: SystemStats

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Space",
                       subtitle: "\(Fmt.bytes(stats.diskFree)) free of \(Fmt.bytes(stats.diskTotal)). What takes up space, largest first; double-click a folder to open it.") {
                HStack {
                    Segmented(selection: $model.showMap, options: [(true, "Map"), (false, "List")])
                    Button("Home folder") { model.start(FS.home) }
                    Button("Choose folder…") { model.choose() }
                    if model.current != nil {
                        Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
                .disabled(model.scanning)
            }
            Divider()

            if !model.stack.isEmpty { breadcrumb; Divider() }

            if model.scanning {
                VStack(spacing: 16) {
                    ScanRing(progress: 0.25, spinning: true, size: 90, lineWidth: 9)
                    Text("Calculating sizes… Large folders can take a minute.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.stack.isEmpty {
                Placeholder(icon: "chart.pie", text: "Press “Home folder” to start.")
            } else if model.showMap {
                SpaceMapView(entries: model.entries, open: { model.open($0) }, trash: { model.pendingTrash = $0 })
                    .padding(12)
            } else {
                list
            }

            if let m = model.message {
                Divider()
                HStack {
                    Text(m).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Trash") { FS.openTrash() }
                }
                .padding(12)
            }
        }
        .confirmationDialog("Move “\(model.pendingTrash?.url.lastPathComponent.displaySafe ?? "")” to the Trash?",
                            isPresented: Binding(get: { model.pendingTrash != nil }, set: { if !$0 { model.pendingTrash = nil } })) {
            Button("Move", role: .destructive) {
                if let e = model.pendingTrash { model.trash(e) }
                model.pendingTrash = nil
            }
        } message: {
            Text(Fmt.bytes(model.pendingTrash?.size ?? 0))
        }
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(model.stack.enumerated()), id: \.offset) { i, u in
                    if i > 0 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                    Button((i == 0 ? FS.shortPath(u) : u.lastPathComponent).displaySafe) { model.go(to: i) }
                        .buttonStyle(.brandLink)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var list: some View {
        let maxSize = Double(model.entries.first?.size ?? 1)
        return List(model.entries) { e in
            HStack(spacing: 10) {
                FileIcon(url: e.url, size: 18)
                Text(e.url.lastPathComponent.displaySafe).lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 160, alignment: .leading)
                ProgressView(value: maxSize > 0 ? Double(e.size) / maxSize : 0)
                    .frame(maxWidth: .infinity)
                Text(Fmt.bytes(e.size)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                Image(systemName: "chevron.right").foregroundStyle(.secondary).opacity(e.isDir ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.open(e) }
            .contextMenu {
                if e.isDir { Button("Open") { model.open(e) } }
                Button("Show in Finder") { FS.reveal(e.url) }
                Divider()
                Button("Move to Trash…") { model.pendingTrash = e }
            }
        }
    }
}
