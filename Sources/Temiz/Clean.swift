import SwiftUI

struct CleanItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
}

struct CleanGroup: Identifiable {
    let id: String
    let title: String
    let icon: String
    let note: String
    let items: [CleanItem]
    var total: Int64 { items.reduce(0) { $0 + $1.size } }
}

final class CleanModel: ObservableObject {
    @Published var groups: [CleanGroup] = []
    @Published var selected: Set<URL> = []
    @Published var scanning = false
    @Published var message: String?
    @Published var confirm = false
    @Published var trash: (size: Int64, count: Int)?
    @Published var trashKnown = false
    @Published var confirmEmpty = false
    @Published var emptying = false

    func refreshTrash() {
        DispatchQueue.global(qos: .utility).async {
            let t = FS.trashInfo()
            DispatchQueue.main.async { self.trash = t; self.trashKnown = true }
        }
    }

    /// Permanent: asks Finder to empty the Trash. Only ever called after the user confirms.
    func emptyTrash() {
        emptying = true
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = FS.emptyTrash()
            DispatchQueue.main.async {
                self.emptying = false
                self.message = ok ? "The Trash is empty." : "Finder could not empty the Trash. Allow Temiz to control Finder in System Settings → Privacy & Security → Automation."
                self.refreshTrash()
            }
        }
    }

    var trashDescription: String {
        guard let t = trash else { return "everything in the Trash" }
        return "\(plural(t.count, "item")) (\(Fmt.bytes(t.size)))"
    }

    var selectedSize: Int64 {
        groups.flatMap(\.items).filter { selected.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    func scan() {
        scanning = true
        message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let g = Self.collect()
            DispatchQueue.main.async {
                self.apply(g)
                self.scanning = false
            }
        }
    }

    /// Also used by the Check up.
    func apply(_ g: [CleanGroup]) {
        groups = g
        // Installers in Downloads are opt-in; everything else is preselected.
        selected = Set(g.filter { $0.id != "installers" }.flatMap { $0.items.map(\.url) })
    }

    func binding(_ url: URL) -> Binding<Bool> {
        Binding(get: { self.selected.contains(url) },
                set: { on in if on { self.selected.insert(url) } else { self.selected.remove(url) } })
    }

    func allSelected(_ g: CleanGroup) -> Bool {
        g.items.allSatisfy { selected.contains($0.url) }
    }

    func toggleAll(_ g: CleanGroup) {
        let urls = g.items.map(\.url)
        if allSelected(g) { selected.subtract(urls) } else { selected.formUnion(urls) }
    }

    func trashSelected() {
        let urls = Array(selected)
        let size = selectedSize
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let failed = FS.trash(urls)
            DispatchQueue.main.async {
                self.scanning = false
                var m = "\(plural(urls.count - failed.count, "item")) (\(Fmt.bytes(size))) moved to the Trash. Empty the Trash to free the space."
                if !failed.isEmpty { m += " \(plural(failed.count, "item")) could not be moved (in use or protected)." }
                self.scan()
                self.message = m
            }
        }
    }

    static func collect() -> [CleanGroup] {
        let h = FS.home

        func items(_ urls: [URL]) -> [CleanItem] {
            urls.map { CleanItem(url: $0, size: FS.size(of: $0)) }
                .filter { $0.size > 0 }
                .sorted { $0.size > $1.size }
        }
        func kids(_ path: String, skip: (String) -> Bool = { _ in false }) -> [CleanItem] {
            items(FS.children(h.appendingPathComponent(path)).filter { !skip($0.lastPathComponent) })
        }
        func paths(_ ps: [String]) -> [CleanItem] {
            items(ps.map { h.appendingPathComponent($0) }.filter(FS.exists))
        }

        let installerExts: Set<String> = ["dmg", "pkg", "iso", "xip", "mpkg"]
        let installers = items(FS.children(h.appendingPathComponent("Downloads"))
            .filter { installerExts.contains($0.pathExtension.lowercased()) })

        let groups = [
            CleanGroup(id: "caches", title: "App caches", icon: "archivebox",
                       note: "~/Library/Caches. Apps rebuild these when needed. Apple's own caches are left alone.",
                       items: kids("Library/Caches", skip: { $0.hasPrefix("com.apple.") || $0.hasPrefix(".") || $0 == "CloudKit" })),
            CleanGroup(id: "logs", title: "Log files", icon: "doc.text",
                       note: "~/Library/Logs. App and crash logs.",
                       items: kids("Library/Logs", skip: { $0.hasPrefix(".") })),
            CleanGroup(id: "dev", title: "Developer leftovers", icon: "hammer",
                       note: "Xcode DerivedData, simulator caches, npm/bun/cargo/gradle/pnpm caches. Downloaded again on the next build.",
                       items: paths([
                           "Library/Developer/Xcode/DerivedData",
                           "Library/Developer/Xcode/iOS DeviceSupport",
                           "Library/Developer/CoreSimulator/Caches",
                           ".npm/_cacache",
                           ".bun/install/cache",
                           ".cargo/registry/cache",
                           ".gradle/caches",
                           "Library/pnpm/store",
                       ])),
            CleanGroup(id: "mail", title: "Mail attachments", icon: "envelope",
                       note: "Copies Mail keeps of attachments you have opened.",
                       items: paths(["Library/Containers/com.apple.mail/Data/Library/Mail Downloads"])),
            CleanGroup(id: "installers", title: "Installers (Downloads)", icon: "shippingbox",
                       note: ".dmg/.pkg/.iso files in ~/Downloads. Not selected by default.",
                       items: installers),
        ]
        return groups.filter { !$0.items.isEmpty }
    }
}

struct CleanView: View {
    @ObservedObject var model: CleanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Clean",
                       subtitle: "Caches, logs, developer leftovers and old installers. Selected items go to the Trash; nothing is deleted permanently.") {
                Button(model.groups.isEmpty ? "Scan" : "Scan again") { model.scan() }
                    .disabled(model.scanning)
            }
            trashBar
            Divider()

            if model.scanning {
                ProgressView("Scanning…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.groups.isEmpty {
                Placeholder(icon: "sparkles", text: model.message ?? "Press “Scan” to start.")
            } else {
                List {
                    ForEach(model.groups) { g in
                        Section {
                            ForEach(g.items) { item in
                                Toggle(isOn: model.binding(item.url)) {
                                    HStack {
                                        FileIcon(url: item.url, size: 16)
                                        Text(item.url.lastPathComponent.displaySafe).lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        Text(Fmt.bytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
                                    }
                                }
                                .contextMenu { Button("Show in Finder") { FS.reveal(item.url) } }
                            }
                        } header: {
                            HStack {
                                Label(g.title, systemImage: g.icon).font(.headline)
                                Spacer()
                                Text(Fmt.bytes(g.total)).monospacedDigit()
                                Button(model.allSelected(g) ? "None" : "All") { model.toggleAll(g) }
                                    .buttonStyle(.brandLink)
                            }
                        } footer: {
                            Text(g.note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()
                HStack(spacing: 12) {
                    if let m = model.message {
                        Text(m).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        Button("Open Trash") { FS.openTrash() }
                    }
                    Spacer()
                    Text("Selected: \(Fmt.bytes(model.selectedSize))").monospacedDigit()
                    Button("Move to Trash") { model.confirm = true }
                        .buttonStyle(.brand)
                        .disabled(model.selected.isEmpty)
                }
                .padding(12)
            }
        }
        .onAppear { model.refreshTrash() }
        .confirmationDialog("Permanently delete \(model.trashDescription)?", isPresented: $model.confirmEmpty) {
            Button("Empty Trash", role: .destructive) { model.emptyTrash() }
        } message: {
            Text("This cannot be undone. Finder empties the Trash; Temiz itself never deletes anything.")
        }
        .confirmationDialog("Move \(plural(model.selected.count, "item")) (\(Fmt.bytes(model.selectedSize))) to the Trash?",
                            isPresented: $model.confirm) {
            Button("Move") { model.trashSelected() }
        } message: {
            Text("If an open app's cache is moved, that app may need a restart.")
        }
    }

    private var trashBar: some View {
        HStack(spacing: 10) {
            GradientIcon(symbol: "trash", size: 15)
            if let t = model.trash {
                Text("Trash: \(plural(t.count, "item")), \(Fmt.bytes(t.size))").monospacedDigit()
            } else if model.trashKnown {
                Text("Trash").foregroundStyle(.primary)
                Text("Size needs Full Disk Access").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Trash") { FS.openTrash() }
            Button {
                model.confirmEmpty = true
            } label: {
                if model.emptying { ProgressView().controlSize(.small) } else { Text("Empty Trash…") }
            }
            .disabled(model.emptying || model.trash?.count == 0)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
