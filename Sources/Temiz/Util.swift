import AppKit
import SwiftUI

enum Fmt {
    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        bytes(Int64(bytesPerSecond)) + "/s"
    }
}

/// "1 item", "3 items"; pass `many` for irregular plurals.
func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String {
    "\(n) \(n == 1 ? one : (many ?? one + "s"))"
}

/// Characters that can hide or reorder text on screen: C0/C1 controls, DEL and bidi formatting.
private func isHidden(_ u: Unicode.Scalar) -> Bool {
    switch u.value {
    case 0x00...0x1F, 0x7F...0x9F, 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: true
    default: false
    }
}

extension String {
    /// Untrusted text (file names, plist labels, commands) made safe to show: hidden characters
    /// become visible escapes such as \u{202E}, so a name cannot spoof what it looks like.
    var displaySafe: String {
        unicodeScalars.map { isHidden($0) ? "\\u{\(String($0.value, radix: 16, uppercase: true))}" : String($0) }
            .joined()
    }

    var hasHiddenCharacters: Bool { unicodeScalars.contains(where: isHidden) }

    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum FS {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    private static let sizeKeys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
    ]

    /// Allocated size on disk. Symlinks are not followed.
    static func size(of url: URL) -> Int64 {
        guard let v = try? url.resourceValues(forKeys: sizeKeys) else { return 0 }
        if v.isSymbolicLink == true { return 0 }
        if v.isRegularFile == true { return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0) }
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(sizeKeys), options: [],
            errorHandler: { _, _ in true })
        else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            guard let fv = try? f.resourceValues(forKeys: sizeKeys), fv.isRegularFile == true else { continue }
            total += Int64(fv.totalFileAllocatedSize ?? fv.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    static func children(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    /// Moves items to the Trash. Temiz never deletes anything permanently.
    static func trash(_ urls: [URL]) -> [(URL, String)] {
        var failed: [(URL, String)] = []
        for u in urls {
            do { try FileManager.default.trashItem(at: u, resultingItemURL: nil) }
            catch { failed.append((u, error.localizedDescription)) }
        }
        return failed
    }

    /// Trash via Finder, which can ask for an admin password for protected items.
    static func recycle(_ urls: [URL], completion: @escaping (Set<URL>) -> Void) {
        NSWorkspace.shared.recycle(urls) { trashed, _ in
            DispatchQueue.main.async { completion(Set(trashed.keys)) }
        }
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Reads a small, untrusted file. Symlinks are followed (dotfile managers use them), but only
    /// regular files up to `limit` are read, so a FIFO or /dev/zero cannot hang or exhaust Temiz.
    static func readCapped(_ url: URL, limit: Int = 1_000_000) -> Data? {
        let real = url.resolvingSymlinksInPath()
        guard let v = try? real.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              v.isRegularFile == true, (v.fileSize ?? 0) <= limit,
              let h = try? FileHandle(forReadingFrom: real)
        else { return nil }
        defer { try? h.close() }
        return try? h.read(upToCount: limit)
    }

    static func plist(_ url: URL) -> [String: Any]? {
        guard let data = readCapped(url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    /// Size and item count of the user's Trash; nil without Full Disk Access, since macOS hides it.
    static func trashInfo() -> (size: Int64, count: Int)? {
        let trash = home.appendingPathComponent(".Trash")
        guard let items = try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil, options: []) else {
            return nil
        }
        let visible = items.filter { $0.lastPathComponent != ".DS_Store" }
        return (visible.reduce(0) { $0 + size(of: $1) }, visible.count)
    }

    /// The only permanent deletion in Temiz: Finder empties the Trash, after the user confirms.
    static func emptyTrash() -> Bool {
        Shell.run("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"], timeout: 600).status == 0
    }

    static func openTrash() {
        NSWorkspace.shared.open(home.appendingPathComponent(".Trash"))
    }

    static func shortPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: home.path, with: "~")
    }
}

enum Launchd {
    static func validLabel(_ label: String) -> Bool {
        label.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
    }

    /// Stops one of the user's agents, but only if launchd has that label loaded from this very
    /// plist. A plist can claim any Label, so booting out by path alone could stop another app's job.
    @discardableResult
    static func bootoutUserAgent(plist: URL) -> Bool {
        guard let label = FS.plist(plist)?["Label"] as? String, validLabel(label) else { return false }
        let domain = "gui/\(getuid())"
        let info = Shell.run("/bin/launchctl", ["print", "\(domain)/\(label)"], timeout: 10)
        guard info.status == 0, info.out.contains("path = \(plist.path)\n") else { return false }
        return Shell.run("/bin/launchctl", ["bootout", domain, plist.path], timeout: 10).status == 0
    }
}

enum Shell {
    /// Runs a program directly (never through a shell). `env` entries are added to the inherited
    /// environment; after `timeout` seconds the process is terminated.
    @discardableResult
    static func run(_ path: String, _ args: [String], env: [String: String] = [:],
                    timeout: TimeInterval? = nil) -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if !env.isEmpty {
            p.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    enum AdminResult: Equatable {
        case ok
        case cancelled
        case failed(String)
    }

    /// Runs fixed shell commands as root behind one system password dialog. Only `StaticString`
    /// literals are accepted, so nothing from a file name, plist or the network can end up in a
    /// command that runs as root.
    static func admin(_ commands: [StaticString]) -> AdminResult {
        let script = commands.map { $0.description }.joined(separator: "; ")
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let r = run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
        if r.status == 0 { return .ok }
        return r.out.contains("-128") ? .cancelled : .failed(r.out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Commands the user pastes into Terminal with sudo. Returns nil if any value contains hidden
    /// characters, since those could carry escape sequences into the terminal.
    static func adminScript(_ lines: [String], values: [String]) -> String? {
        values.contains(where: \.hasHiddenCharacters) ? nil : lines.joined(separator: "\n")
    }

    /// Moves a protected item to the user's Trash with sudo, never overwriting what is already there.
    static func sudoTrash(_ path: String) -> String {
        "sudo /bin/mv -n -- \(quote(path)) \"$HOME/.Trash/\""
    }

    /// Unloads a launchd job by its plist path, which works even if the file name and Label differ.
    static func bootout(_ plist: String) -> String? {
        if plist.hasPrefix("/Library/LaunchDaemons/") { return "sudo launchctl bootout system \(quote(plist))" }
        if plist.hasPrefix("/Library/LaunchAgents/") { return "launchctl bootout gui/$(id -u) \(quote(plist))" }
        return nil
    }
}

func copyToClipboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

// MARK: - Shared views

struct PaneHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 20)
            actions
        }
        .padding(16)
    }
}

struct Placeholder: View {
    let icon: String
    let text: String

    /// Empty states show the mascot: happy when there is nothing left to do, waiting otherwise.
    var body: some View {
        VStack(spacing: 12) {
            Mascot(pose: icon.hasPrefix("checkmark") ? .happy : .idle, size: 92, motion: .bob)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FileIcon: View {
    let url: URL
    var size: CGFloat = 18

    /// Icon lookups hit the disk, and lists redraw every few seconds, so keep them.
    private static let cache = NSCache<NSString, NSImage>()

    private static func icon(_ path: String) -> NSImage {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    var body: some View {
        Image(nsImage: Self.icon(url.path))
            .resizable()
            .frame(width: size, height: size)
    }
}

/// Copyable box for commands that need an admin password.
struct CommandBox: View {
    let title: String
    /// Nil when the name contains hidden characters and no safe command can be shown.
    let commands: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: "lock").font(.callout.bold())
                Spacer()
                if let commands { Button("Copy") { copyToClipboard(commands) } }
            }
            if let commands {
                Text(commands).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                Text("Paste into Terminal and run; it will ask for your admin password.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("The name contains hidden characters, so Temiz will not build a command for it. Use “Show in Finder” and remove it there.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
