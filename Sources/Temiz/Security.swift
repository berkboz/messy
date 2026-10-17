import AppKit
import Security
import SwiftUI

// MARK: - Code signature

enum Trust: Int, Comparable {
    case danger, caution, warning, ok
    static func < (a: Trust, b: Trust) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .danger: "Risky"
        case .caution: "Review"
        case .warning: "Not notarized"
        case .ok: "Trusted"
        }
    }

    var color: Color {
        switch self {
        case .danger: .red
        case .caution: .orange
        case .warning: .yellow
        case .ok: .green
        }
    }
}

struct SigInfo {
    let trust: Trust
    let summary: String
    var signer: String? = nil
    /// A signal strong enough that the Check up may preselect the item for removal: code injection,
    /// a fake Apple name or running from a temporary folder. A non-Apple certificate alone is not.
    var strong = false

    var isApple: Bool { trust == .ok && summary == "Apple" }
}

enum CodeSign {
    private static let fast = SecCSFlags(rawValue: kSecCSDoNotValidateResources)
    /// Also hashes every resource and nested framework, so a patched framework inside a
    /// validly signed app is caught. Slower, so it is used for apps only.
    private static let deep = SecCSFlags(rawValue: kSecCSCheckNestedCode | kSecCSStrictValidate)

    static func check(_ url: URL, thorough: Bool = false) -> SigInfo {
        guard FS.exists(url) else { return SigInfo(trust: .caution, summary: "File not found") }
        // Opening a FIFO or device to read its signature blocks forever; only look at real files and bundles.
        let real = url.resolvingSymlinksInPath()
        let kind = try? real.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
        guard kind?.isRegularFile == true || kind?.isDirectory == true else {
            return SigInfo(trust: .danger, summary: "Not a regular file or app")
        }

        var sc: SecStaticCode?
        guard SecStaticCodeCreateWithPath(real as CFURL, [], &sc) == errSecSuccess, let code = sc else {
            return SigInfo(trust: .caution, summary: "Unsigned")
        }

        var infoCF: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF)
        let info = (infoCF as? [String: Any]) ?? [:]
        guard info[kSecCodeInfoIdentifier as String] != nil else {
            return SigInfo(trust: .caution, summary: "Unsigned")
        }

        let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let adhoc: UInt32 = 0x2
        if certs.isEmpty || flags & adhoc != 0 {
            return SigInfo(trust: .caution, summary: "Ad-hoc signature: no developer identity")
        }

        let signer = certs.first.flatMap { SecCertificateCopySubjectSummary($0) as String? }

        let validity = SecStaticCodeCheckValidity(code, thorough ? deep : fast, nil)
        if validity == errSecCSResourcesNotFound {
            // The bundle lacks the resource list its signature expects: a packaging slip by the
            // developer (some generated helper apps do this), not evidence of tampering.
            return SigInfo(trust: .caution, summary: "Incomplete signature: files the signature lists are missing. Reinstall it if unsure.", signer: signer)
        }
        guard validity == errSecSuccess else {
            return SigInfo(trust: .danger, summary: "Broken signature: the app was changed after it was signed", signer: signer)
        }
        if isApple(code) {
            return SigInfo(trust: .ok, summary: "Apple", signer: signer)
        }
        if satisfies(code, "notarized") {
            return SigInfo(trust: .ok, summary: "Developer ID, notarized by Apple", signer: signer)
        }
        if satisfies(code, "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists") {
            return SigInfo(trust: .warning, summary: "Developer ID, but not notarized", signer: signer)
        }
        if satisfies(code, "anchor apple generic") {
            return SigInfo(trust: .warning, summary: "Apple development certificate (not for distribution)", signer: signer)
        }
        return SigInfo(trust: .danger,
                       summary: "Non-Apple certificate: may be cracked or re-signed",
                       signer: signer)
    }

    static func isApple(_ code: SecStaticCode) -> Bool { satisfies(code, "anchor apple") }

    private static func satisfies(_ code: SecStaticCode, _ requirement: String) -> Bool {
        var r: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &r) == errSecSuccess, let r else { return false }
        return SecStaticCodeCheckValidity(code, fast, r) == errSecSuccess
    }
}

// MARK: - Model

struct SystemCheck: Identifiable {
    let id: String
    let title: String
    let ok: Bool
    let fix: String
}

enum ItemDomain: String {
    case user = "User agent"
    case globalAgent = "Global agent"
    case daemon = "System daemon (root)"
    case helper = "Privileged helper (root)"
}

struct BackgroundItem: Identifiable {
    var id: URL { file }
    let file: URL
    let label: String
    let domain: ItemDomain
    let command: String
    let sig: SigInfo
}

struct AppSig: Identifiable {
    var id: URL { url }
    let url: URL
    let name: String
    let sig: SigInfo
}

struct Listener: Identifiable {
    var id: String { process + address }
    let process: String
    let address: String
    var exposed: Bool {
        !(address.hasPrefix("127.") || address.hasPrefix("[::1]") || address.hasPrefix("localhost"))
    }
}

final class SecurityModel: ObservableObject {
    @Published var checks: [SystemCheck] = []
    @Published var items: [BackgroundItem] = []
    @Published var apps: [AppSig] = []
    @Published var listeners: [Listener] = []
    @Published var threats: [Threat] = []
    @Published var xprotect: String?
    @Published var scanning = false
    @Published var scanned = false
    @Published var showAllApps = false
    @Published var message: String?
    @Published var pendingDisable: BackgroundItem?

    var riskyCount: Int { threats.filter { $0.trust == .danger }.count }

    var reviewCount: Int {
        threats.filter { $0.trust != .danger }.count
            + items.filter { $0.sig.trust == .caution || $0.sig.trust == .warning }.count
            + apps.filter { $0.sig.trust == .caution || $0.sig.trust == .warning }.count
    }

    func scan() {
        scanning = true
        message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Self.fullScan()
            DispatchQueue.main.async {
                self.apply(r)
                self.scanning = false
            }
        }
    }

    struct Results {
        let checks: [SystemCheck]
        let items: [BackgroundItem]
        let apps: [AppSig]
        let listeners: [Listener]
        let threats: [Threat]
        let xprotect: String?
    }

    /// The whole scan without touching the UI; the Check up runs it too.
    static func fullScan() -> Results {
        let i = backgroundItems(), a = appSignatures()
        return Results(checks: systemChecks(), items: i, apps: a, listeners: listeningPorts(),
                       threats: ThreatScanner.scan(items: i, apps: a), xprotect: ThreatScanner.xprotectVersion)
    }

    func apply(_ r: Results) {
        checks = r.checks
        items = r.items
        apps = r.apps
        listeners = r.listeners
        threats = r.threats
        xprotect = r.xprotect
        scanned = true
    }

    /// Unload and trash one of the user's own launch agents.
    func disable(_ item: BackgroundItem) {
        Launchd.bootoutUserAgent(plist: item.file)
        if let f = FS.trash([item.file]).first {
            message = "Could not move: \(f.1)"
        } else {
            Sound.trash.play()
            message = "\(item.label.displaySafe) stopped and moved to the Trash."
            items.removeAll { $0.id == item.id }
            threats.removeAll { $0.item?.id == item.id }
        }
    }

    /// Nil when the path contains hidden characters; the view then asks the user to remove it in Finder.
    static func adminCommands(for item: BackgroundItem) -> String? {
        // Unload by plist path (not the plist's Label, which can lie) and quote everything:
        // the user runs this with sudo.
        let path = item.file.path
        let lines = [Shell.bootout(path), Shell.sudoTrash(path)].compactMap { $0 }
        return Shell.adminScript(lines, values: [path])
    }

    static func systemChecks() -> [SystemCheck] {
        func out(_ path: String, _ args: [String]) -> String { Shell.run(path, args).out.lowercased() }
        let fw = "/usr/libexec/ApplicationFirewall/socketfilterfw"
        let autoUpdate = out("/usr/bin/defaults", ["read", "/Library/Preferences/com.apple.SoftwareUpdate", "AutomaticallyInstallMacOSUpdates"])
        return [
            SystemCheck(id: "sip", title: "System Integrity Protection (SIP)",
                        ok: out("/usr/bin/csrutil", ["status"]).contains("enabled"),
                        fix: "Turn on in Recovery mode with `csrutil enable`."),
            SystemCheck(id: "gk", title: "Gatekeeper",
                        ok: out("/usr/sbin/spctl", ["--status"]).contains("assessments enabled"),
                        fix: "Terminal: `sudo spctl --master-enable`"),
            SystemCheck(id: "fv", title: "FileVault disk encryption",
                        ok: out("/usr/bin/fdesetup", ["status"]).contains("is on"),
                        fix: "System Settings → Privacy & Security → FileVault"),
            SystemCheck(id: "fw", title: "Firewall",
                        ok: out(fw, ["--getglobalstate"]).contains("enabled"),
                        fix: "System Settings → Network → Firewall"),
            SystemCheck(id: "stealth", title: "Stealth mode",
                        ok: out(fw, ["--getstealthmode"]).contains("is on"),
                        fix: "System Settings → Network → Firewall → Options"),
            SystemCheck(id: "updates", title: "Automatic macOS updates",
                        ok: autoUpdate.trimmingCharacters(in: .whitespacesAndNewlines) == "1",
                        fix: "System Settings → General → Software Update → Automatic Updates"),
        ]
    }

    /// Script runtimes that live outside /usr/bin (Homebrew, nvm…), so they are not Apple-signed.
    private static let runtimes: Set<String> = [
        "node", "bun", "deno", "python", "python3", "ruby", "perl", "php", "bash", "zsh", "sh", "fish",
    ]

    /// Environment variables that make a trusted binary load or run someone else's code.
    private static func injects(_ key: String) -> Bool {
        key.hasPrefix("DYLD_") || key == "ELECTRON_RUN_AS_NODE" || key == "NODE_OPTIONS"
    }

    /// What a launchd job actually runs, judged by more than the signature of its first argument:
    /// an Apple-signed tool such as /bin/sh, /usr/bin/nohup or /usr/bin/curl can run anything.
    static func classify(label: String, exe: String, args: [String], env: [String: String]) -> SigInfo {
        if let key = env.keys.sorted().first(where: injects) {
            return SigInfo(trust: .danger, summary: "Injects code into the program via \(key)", strong: key.hasPrefix("DYLD_"))
        }
        if exe.isEmpty { return SigInfo(trust: .caution, summary: "No program specified") }
        guard exe.hasPrefix("/") else { return SigInfo(trust: .caution, summary: "Program path is not absolute") }

        let sig = CodeSign.check(URL(fileURLWithPath: exe))
        if var place = ThreatScanner.suspiciousLocation(exe) {
            place.signer = sig.signer
            return place
        }
        let pretendsApple = label.lowercased().hasPrefix("com.apple.")
        if pretendsApple && !sig.isApple {
            return SigInfo(trust: .danger, summary: "Uses an Apple-style name but is not Apple software", signer: sig.signer, strong: true)
        }
        if sig.isApple && args.count > 1 {
            return SigInfo(trust: .caution, summary: "An Apple tool running a command; check what it runs", signer: sig.signer)
        }
        if runtimes.contains(URL(fileURLWithPath: exe).lastPathComponent) && args.count > 1 {
            return SigInfo(trust: .caution, summary: "Runs a script; check what it runs", signer: sig.signer)
        }
        return sig
    }

    static func backgroundItems() -> [BackgroundItem] {
        let sources: [(URL, ItemDomain)] = [
            (FS.home.appendingPathComponent("Library/LaunchAgents"), .user),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .globalAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .daemon),
        ]
        var out: [BackgroundItem] = []
        for (dir, domain) in sources {
            for f in FS.children(dir) where f.pathExtension == "plist" {
                let d = FS.plist(f) ?? [:]
                // Nothing is skipped by name: real Apple jobs live in /System, and malware likes
                // to call itself com.apple.something.
                let label = d["Label"] as? String ?? f.deletingPathExtension().lastPathComponent
                let args = d["ProgramArguments"] as? [String] ?? []
                let exe = d["Program"] as? String ?? args.first ?? ""
                let env = d["EnvironmentVariables"] as? [String: String] ?? [:]
                let command = (env.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
                               + [exe] + args.dropFirst()).joined(separator: " ")
                let sig = classify(label: label, exe: exe, args: args, env: env)
                out.append(BackgroundItem(file: f, label: label, domain: domain, command: command, sig: sig))
            }
        }
        for f in FS.children(URL(fileURLWithPath: "/Library/PrivilegedHelperTools")) {
            out.append(BackgroundItem(file: f, label: f.lastPathComponent, domain: .helper,
                                      command: f.path, sig: CodeSign.check(f)))
        }
        return out.sorted { ($0.sig.trust, $0.label) < ($1.sig.trust, $1.label) }
    }

    static func appSignatures() -> [AppSig] {
        let list = AppScanner.apps()
        var out: [AppSig] = []
        let lock = NSLock()
        // Trust Temiz by location, not bundle ID: any app can claim com.berk.temiz.
        let me = Bundle.main.bundleURL.standardizedFileURL
        DispatchQueue.concurrentPerform(iterations: list.count) { i in
            let a = list[i]
            let sig = a.url.standardizedFileURL == me
                ? SigInfo(trust: .ok, summary: "This app (your own build)")
                : CodeSign.check(a.url, thorough: true)
            lock.lock(); out.append(AppSig(url: a.url, name: a.name, sig: sig)); lock.unlock()
        }
        return out.sorted { ($0.sig.trust, $0.name) < ($1.sig.trust, $1.name) }
    }

    static func listeningPorts() -> [Listener] {
        let text = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"]).out
        var seen = Set<String>()
        var out: [Listener] = []
        for line in text.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 10 else { continue }
            let l = Listener(process: String(parts[0]), address: String(parts[parts.count - 2]))
            if seen.insert(l.id).inserted { out.append(l) }
        }
        return out.sorted { ($0.exposed ? 0 : 1, $0.process) < ($1.exposed ? 0 : 1, $1.process) }
    }
}

// MARK: - View

struct SecurityView: View {
    @ObservedObject var model: SecurityModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Protect",
                       subtitle: "A threat check, system protections, background services, app signatures and ports open to the network.") {
                Button(model.scanned ? "Scan again" : "Scan") { model.scan() }
                    .disabled(model.scanning)
            }
            Divider()

            if model.scanning {
                ProgressView("Checking signatures…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.scanned {
                Placeholder(icon: "lock.shield", text: "Press “Scan” to start.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let m = model.message {
                            Text(m).font(.callout).foregroundStyle(.secondary)
                        }
                        threatsSection
                        checksSection
                        itemsSection
                        appsSection
                        portsSection
                    }
                    .padding(16)
                }
            }
        }
        .confirmationDialog("Stop “\(model.pendingDisable?.label.displaySafe ?? "")” and move it to the Trash?",
                            isPresented: Binding(get: { model.pendingDisable != nil }, set: { if !$0 { model.pendingDisable = nil } })) {
            Button("Stop and move", role: .destructive) {
                if let i = model.pendingDisable { model.disable(i) }
                model.pendingDisable = nil
            }
        } message: {
            Text("The app that installed this service may add it again the next time it opens.")
        }
    }

    private var threatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Threat check").font(.headline)
            Text("A check of the places malware usually hides, not an antivirus. macOS's own XProtect\(model.xprotect.map { " (version \($0))" } ?? "") scans for known malware in the background.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.threats.isEmpty {
                Label("Nothing suspicious found.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Brand.emerald).padding(.vertical, 4)
            }
            ForEach(model.threats) { t in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TrustBadge(trust: t.trust)
                        Text(t.title.displaySafe).bold().lineLimit(1)
                        Spacer()
                    }
                    Text(t.detail.displaySafe).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if let f = t.item?.file ?? t.app { Button("Show in Finder") { FS.reveal(f) } }
                        if t.removable, let i = t.item { Button("Stop and remove…") { model.pendingDisable = i } }
                    }
                    .buttonStyle(.brandLink).font(.caption)
                    if let i = t.item, !t.removable {
                        CommandBox(title: "To remove", commands: SecurityModel.adminCommands(for: i))
                    }
                    if t.app != nil {
                        Text("Remove it with Apps, which also finds its leftovers.").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(10)
                .background(t.trust.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var checksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("System protections").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 8)], spacing: 8) {
                ForEach(model.checks) { c in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: c.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(c.ok ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.title)
                            if !c.ok { Text(.init(c.fix)).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background services (\(model.items.count))").font(.headline)
            Text("Third-party programs that start on their own when your Mac starts. Malware usually settles here. Login items added in System Settings → General → Login Items are not listed.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(model.items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TrustBadge(trust: item.sig.trust)
                        Text(item.label.displaySafe).bold().lineLimit(1)
                        Spacer()
                        Text(item.domain.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(item.sig.summary + (item.sig.signer.map { " · \($0.displaySafe)" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(item.command.displaySafe).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    HStack {
                        Button("Show in Finder") { FS.reveal(item.file) }
                        if item.domain == .user {
                            Button("Stop and remove…") { model.pendingDisable = item }
                        }
                    }
                    .buttonStyle(.brandLink).font(.caption)
                }
                .padding(10)
                .background(item.sig.trust.color.opacity(item.sig.trust == .ok ? 0.05 : 0.1),
                            in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var appsSection: some View {
        let flagged = model.apps.filter { $0.sig.trust != .ok }
        let shown = model.showAllApps ? model.apps : flagged
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Apps: \(flagged.count) flagged of \(model.apps.count)").font(.headline)
                Spacer()
                Toggle("Show all", isOn: $model.showAllApps).toggleStyle(PillSwitchStyle()).controlSize(.small)
            }
            ForEach(shown) { a in
                HStack(spacing: 10) {
                    FileIcon(url: a.url, size: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.name.displaySafe)
                        Text(a.sig.summary + (a.sig.signer.map { " · \($0.displaySafe)" } ?? ""))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    TrustBadge(trust: a.sig.trust)
                }
                .contextMenu { Button("Show in Finder") { FS.reveal(a.url) } }
            }
            if !flagged.isEmpty {
                Text("You can remove “Risky” apps and their leftovers from Uninstall.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var portsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Listening ports").font(.headline)
            Text("Other devices on the same network can connect to ports marked “Open to network”. Only your own processes are listed; services running as root are not visible without admin rights.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(model.listeners) { l in
                HStack {
                    Text(l.process.displaySafe).frame(width: 160, alignment: .leading)
                    Text(l.address).font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(l.exposed ? "Open to network" : "This Mac only")
                        .font(.caption)
                        .foregroundStyle(l.exposed ? .orange : .secondary)
                }
            }
        }
    }
}

struct TrustBadge: View {
    let trust: Trust

    var body: some View {
        Text(trust.label)
            .font(.caption.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(trust.color.opacity(0.2), in: Capsule())
            .foregroundStyle(trust.color == .yellow ? Color.primary : trust.color)
    }
}
