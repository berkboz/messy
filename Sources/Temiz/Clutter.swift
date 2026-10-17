import CoreServices
import CryptoKit
import Foundation

/// Lets a long scan stop early. Checked between files.
final class CancelToken {
    private let lock = NSLock()
    private var flag = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func cancel() { lock.lock(); flag = true; lock.unlock() }
}

struct FileEntry: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    var lastUsed: Date?
}

struct DuplicateGroup: Identifiable {
    let id: String   // content hash
    let size: Int64  // size of one copy
    /// The copy Temiz suggests keeping; it is never selected for removal.
    let keep: URL
    let files: [URL]
    var wasted: Int64 { size * Int64(files.count - 1) }
}

enum Clutter {
    private static let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileSizeKey,
        .contentAccessDateKey, .contentModificationDateKey, .addedToDirectoryDateKey,
        .creationDateKey, .fileResourceIdentifierKey,
    ]

    /// Regular files under `roots`, skipping hidden files, package contents (apps, photo libraries)
    /// and ~/Library and ~/.Trash, which belong to apps and the Trash rather than to the user.
    static func files(in roots: [URL], minSize: Int64, cancel: CancelToken,
                      visit: (URL, URLResourceValues) -> Void) {
        let skip = [FS.home.appendingPathComponent("Library").path, FS.home.appendingPathComponent(".Trash").path]
        for root in roots {
            guard let e = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true })
            else { continue }
            for case let url as URL in e {
                if cancel.cancelled { return }
                if skip.contains(url.path) { e.skipDescendants(); continue }
                guard let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true,
                      v.isSymbolicLink != true, Int64(v.fileSize ?? 0) >= minSize
                else { continue }
                visit(url, v)
            }
        }
    }

    /// When the file was last opened. Spotlight's "last used" date is the most accurate; APFS updates
    /// access dates lazily, so the file dates are only a fallback.
    static func lastUsed(_ url: URL, _ v: URLResourceValues) -> Date? {
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
           let d = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
            return d
        }
        return [v.contentAccessDate, v.contentModificationDate, v.addedToDirectoryDate].compactMap { $0 }.max()
    }

    static func largeAndOld(roots: [URL], minSize: Int64, notUsedSince: Date, cancel: CancelToken) -> [FileEntry] {
        var out: [FileEntry] = []
        files(in: roots, minSize: minSize, cancel: cancel) { url, v in
            let used = lastUsed(url, v)
            if let used, used > notUsedSince { return }
            out.append(FileEntry(url: url, size: Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0), lastUsed: used))
        }
        return out.sorted { $0.size > $1.size }
    }

    /// Size, then the first and last 64 KB, then a full SHA-256. Hard links to the same file are
    /// counted once, since removing one frees nothing.
    static func duplicates(roots: [URL], minSize: Int64 = 1_000_000, cancel: CancelToken) -> [DuplicateGroup] {
        var bySize: [Int64: [(URL, URLResourceValues)]] = [:]
        var seenInodes = Set<String>()
        files(in: roots, minSize: minSize, cancel: cancel) { url, v in
            if let id = v.fileResourceIdentifier { if !seenInodes.insert("\(id)").inserted { return } }
            bySize[Int64(v.fileSize ?? 0), default: []].append((url, v))
        }

        var groups: [DuplicateGroup] = []
        for (size, candidates) in bySize where candidates.count > 1 {
            if cancel.cancelled { break }
            let byEdge = Dictionary(grouping: candidates) { edgeHash($0.0, size: size) ?? UUID().uuidString }
            for (_, same) in byEdge where same.count > 1 {
                let byFull = Dictionary(grouping: same) { fullHash($0.0) ?? UUID().uuidString }
                for (hash, copies) in byFull where copies.count > 1 {
                    let keep = suggestedKeep(copies)
                    groups.append(DuplicateGroup(id: hash, size: size, keep: keep, files: copies.map(\.0)))
                }
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    /// The selected copies that may go to the Trash right now. A group is skipped entirely unless at
    /// least one copy that stays is still on disk with the same size, so the last copy can never be
    /// removed, even if files were moved or changed since the scan or the selection is stale.
    static func removable(_ groups: [DuplicateGroup], selected: Set<URL>) -> [URL] {
        groups.flatMap { g -> [URL] in
            let chosen = g.files.filter { selected.contains($0) }
            let staying = g.files.filter { !selected.contains($0) && stillThere($0, size: g.size) }
            return staying.isEmpty ? [] : chosen
        }
    }

    private static func stillThere(_ url: URL, size: Int64) -> Bool {
        // A fresh URL: URL objects cache resource values from the scan, which would hide a deletion.
        let fresh = URL(fileURLWithPath: url.path)
        guard let v = try? fresh.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]) else { return false }
        return v.isRegularFile == true && v.isSymbolicLink != true && Int64(v.fileSize ?? -1) == size
    }

    /// Keep a copy outside Downloads if there is one, then the oldest.
    static func suggestedKeep(_ copies: [(URL, URLResourceValues)]) -> URL {
        let downloads = FS.home.appendingPathComponent("Downloads").path + "/"
        return copies.sorted { a, b in
            let aDl = a.0.path.hasPrefix(downloads), bDl = b.0.path.hasPrefix(downloads)
            if aDl != bDl { return !aDl }
            return (a.1.creationDate ?? .distantFuture) < (b.1.creationDate ?? .distantFuture)
        }[0].0
    }

    private static func edgeHash(_ url: URL, size: Int64) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let chunk = 64 * 1024
        var hasher = SHA256()
        if let head = try? h.read(upToCount: chunk) { hasher.update(data: head) }
        if size > Int64(chunk * 2) {
            try? h.seek(toOffset: UInt64(size) - UInt64(chunk))
            if let tail = try? h.read(upToCount: chunk) { hasher.update(data: tail) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func fullHash(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let data = try? h.read(upToCount: 1 << 20), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
