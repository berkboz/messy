import Foundation

/// Something the threat check wants the user to look at. This is a heuristic check of where
/// malware usually hides, not a signature-based antivirus; macOS XProtect does that part.
struct Threat: Identifiable {
    let id: String
    let title: String
    let detail: String
    let trust: Trust
    var item: BackgroundItem? = nil
    var app: URL? = nil
    /// See SigInfo.strong.
    var strong = false
    /// Only the user's own launch agents can be removed without an admin password.
    var removable: Bool { item?.domain == .user }
}

enum ThreatScanner {
    static func scan(items: [BackgroundItem], apps: [AppSig]) -> [Threat] {
        var out: [Threat] = []

        for i in items where i.sig.trust == .danger {
            out.append(Threat(id: "item:" + i.file.path, title: i.label, detail: i.sig.summary, trust: .danger,
                              item: i, strong: i.sig.strong))
        }
        for a in apps where a.sig.trust == .danger {
            out.append(Threat(id: "app:" + a.url.path, title: a.name, detail: a.sig.summary, trust: .danger, app: a.url))
        }

        // A login hook runs a script as root at every login; nothing modern needs one.
        for (domain, args) in [("user", ["read", "com.apple.loginwindow", "LoginHook"]),
                               ("system", ["read", "/Library/Preferences/com.apple.loginwindow", "LoginHook"])] {
            let r = Shell.run("/usr/bin/defaults", args, timeout: 5)
            let value = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
            if r.status == 0, !value.isEmpty {
                out.append(Threat(id: "loginhook:" + domain, title: "Login hook (\(domain))",
                                  detail: "Runs at every login: \(value)", trust: .danger))
            }
        }

        let cron = Shell.run("/usr/bin/crontab", ["-l"], timeout: 5)
        let jobs = cron.status == 0 ? cron.out.split(separator: "\n").map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") } : []
        if !jobs.isEmpty {
            out.append(Threat(id: "cron", title: "Scheduled commands (cron)",
                              detail: plural(jobs.count, "job") + ": " + jobs[0], trust: .caution))
        }

        // DYLD_INSERT_LIBRARIES in a shell profile injects code into every program started from Terminal.
        for name in [".zshrc", ".zprofile", ".zshenv", ".bash_profile", ".bashrc", ".profile"] {
            let url = FS.home.appendingPathComponent(name)
            guard let data = FS.readCapped(url), let text = String(data: data, encoding: .utf8) else { continue }
            if let line = text.split(separator: "\n").first(where: {
                $0.contains("DYLD_INSERT_LIBRARIES") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#")
            }) {
                out.append(Threat(id: "profile:" + name, title: "~/\(name) injects a library",
                                  detail: String(line.prefix(200)), trust: .danger))
            }
        }
        return out
    }

    static var xprotectVersion: String? {
        let plist = URL(fileURLWithPath: "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist")
        return (NSDictionary(contentsOf: plist) as? [String: Any])?["CFBundleShortVersionString"] as? String
    }

    /// Folders where legitimate background programs do not live. Symlinks are resolved and case
    /// ignored (APFS is usually case-insensitive), so "/TMP/x" or a link into /tmp is caught too.
    static func suspiciousLocation(_ path: String) -> SigInfo? {
        let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        let p = real.lowercased()
        let temp = ["/tmp/", "/private/tmp/", "/var/tmp/", "/private/var/tmp/", "/var/folders/", "/private/var/folders/"]
        if temp.contains(where: p.hasPrefix) {
            return SigInfo(trust: .danger, summary: "Runs from a temporary folder", strong: true)
        }
        if p.hasPrefix("/users/shared/") {
            return SigInfo(trust: .danger, summary: "Runs from the shared folder every user can write to")
        }
        if real.split(separator: "/").dropLast().contains(where: { $0.hasPrefix(".") }) {
            return SigInfo(trust: .caution, summary: "Runs from a hidden folder")
        }
        return nil
    }
}
