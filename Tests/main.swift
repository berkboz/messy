import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  ok    \(what)" : "  FAIL  \(what)")
    if !ok { failures += 1 }
}

let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("messy-tests-\(UUID().uuidString)")
try! fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }

func write(_ name: String, _ data: Data) -> URL {
    let u = root.appendingPathComponent(name)
    try! data.write(to: u)
    return u
}

print("Duplicates")
let twoMB = Data((0..<2_000_000).map { UInt8($0 % 251) })
var other = twoMB; other[1_000_000] ^= 0xFF          // same size, differs only in the middle
let a = write("a.bin", twoMB)
let copy = write("copy.bin", twoMB)
_ = write("different.bin", other)
try! fm.linkItem(at: a, to: root.appendingPathComponent("hardlink.bin"))
try! fm.createSymbolicLink(at: root.appendingPathComponent("symlink.bin"), withDestinationURL: a)
_ = write("small.bin", Data(repeating: 1, count: 1000))

let groups = Clutter.duplicates(roots: [root], cancel: CancelToken())
check(groups.count == 1, "one duplicate group")
let names = Set(groups.first?.files.map(\.lastPathComponent) ?? [])
check(names.count == 2 && names.isSubset(of: ["a.bin", "copy.bin", "hardlink.bin"]), "group has exactly two real copies: \(names.sorted())")
check(!names.contains("different.bin"), "same size, different content is not a duplicate")
check(!names.contains("symlink.bin"), "symlinks are ignored")
check(!(names.contains("a.bin") && names.contains("hardlink.bin")), "a hard link is not counted as a copy")

print("Never selecting every copy")
let model = ClutterModel()
model.tab = .duplicates
model.setDuplicates(groups)
if let g = groups.first {
    check(!model.selected.contains(g.keep), "the suggested copy starts unselected")
    model.binding(g.keep, in: g).wrappedValue = true
    check(!g.files.allSatisfy { model.selected.contains($0) }, "selecting the last copy is refused")
}

print("Cancelling")
let t = CancelToken(); t.cancel()
check(Clutter.duplicates(roots: [root], cancel: t).isEmpty, "a cancelled scan stops")

print("Untrusted text and admin commands")
check("a\u{202E}b\n".displaySafe == "a\\u{202E}b\\u{A}", "hidden characters become visible")
check(Shell.adminScript(["x"], values: ["/Library/a\u{1B}[2J"]) == nil, "no sudo command for names with escape codes")
check(Shell.sudoTrash("/Library/it's") == "sudo /bin/mv -n -- '/Library/it'\\''s' \"$HOME/.Trash/\"", "paths are single-quoted")

print("Background service classification")
let fifo = root.appendingPathComponent("fifo")
mkfifo(fifo.path, 0o600)
let start = Date()
check(CodeSign.check(fifo).trust == .danger && Date().timeIntervalSince(start) < 2, "a FIFO does not hang the scan")
check(SecurityModel.classify(label: "com.apple.fake", exe: "/tmp/nope", args: [], env: [:]).trust == .danger, "fake Apple label is risky")
check(SecurityModel.classify(label: "x.y.z", exe: "/usr/bin/nohup", args: ["/usr/bin/nohup", "/tmp/p"], env: [:]).trust == .caution, "Apple tool running a payload needs review")
check(SecurityModel.classify(label: "x.y.z", exe: "/usr/bin/true", args: ["/usr/bin/true"], env: ["DYLD_INSERT_LIBRARIES": "/x"]).trust == .danger, "DYLD injection is risky")

print("Threat locations")
check(ThreatScanner.suspiciousLocation("/tmp/x")?.strong == true, "/tmp is flagged as a strong signal")
check(ThreatScanner.suspiciousLocation("/TMP/x")?.strong == true && ThreatScanner.suspiciousLocation("//tmp/x")?.strong == true, "case and double slashes do not evade it")
check(ThreatScanner.suspiciousLocation(NSTemporaryDirectory() + "x")?.strong == true, "$TMPDIR is flagged")
check(ThreatScanner.suspiciousLocation("/Users/shared/x")?.trust == .danger && ThreatScanner.suspiciousLocation("/Users/Shared/x")?.strong == false, "/Users/Shared is risky but not auto-removed")
check(ThreatScanner.suspiciousLocation("/Users/b/.cache/x")?.trust == .caution, "hidden folders are flagged for review")
check(ThreatScanner.suspiciousLocation("/Applications/X.app/Contents/MacOS/X") == nil, "apps are not flagged")
check(SecurityModel.classify(label: "a.b.c", exe: "/tmp/agent", args: [], env: [:]).trust == .danger, "an agent in /tmp is risky")

print("Updates")
check(Version.isNewer("1.10", than: "1.9"), "1.10 is newer than 1.9")
check(!Version.isNewer("2.0", than: "2.0.0"), "2.0 equals 2.0.0")
check(Version.isNewer("3.2.1 (412)", than: "3.2.1 (400)"), "build numbers in parentheses compare")
let feed = """
<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
<item><title>Old</title><enclosure url="https://x/a.zip" sparkle:version="90" sparkle:shortVersionString="1.9"/></item>
<item><title>New</title><sparkle:shortVersionString>1.10</sparkle:shortVersionString><sparkle:version>100</sparkle:version></item>
</channel></rss>
"""
let latest = Appcast.latest(feed.data(using: .utf8)!)
check(latest?.short == "1.10" && latest?.build == "100", "appcast picks the newest item, not the first")
check(Appcast.latest(Data("<rss><<<".utf8)) == nil, "broken XML is rejected")
check(UpdatesModel.isValidToken("visual-studio-code") && !UpdatesModel.isValidToken("x; rm -rf ~"), "Homebrew tokens are validated")
check(!UpdatesModel.isValidToken("--force"), "a token cannot be an option")
check(!Version.isNewer("2.0b1", than: "2.0") && Version.isNewer("2.0", than: "2.0b1"), "a beta is older than the release")
check(Version.isNewer("2.0b2", than: "2.0b1") && Version.isNewer("2.1b1", than: "2.0"), "betas compare among themselves")
check(!CappedFetcher.allowed(URL(string: "https://192.168.1.1/feed.xml")!) && !CappedFetcher.allowed(URL(string: "https://nas.local/f")!)
      && !CappedFetcher.allowed(URL(string: "http://example.com/f")!) && CappedFetcher.allowed(URL(string: "https://example.com/f")!),
      "feeds must be public https hosts")

print("Reading untrusted files")
let fifo2 = root.appendingPathComponent("fifo2"); mkfifo(fifo2.path, 0o600)
let t0 = Date()
check(FS.readCapped(fifo2) == nil && Date().timeIntervalSince(t0) < 2, "a FIFO is not read")
let big = write("big.bin", Data(count: 2_000_000))
check(FS.readCapped(big) == nil, "files over the limit are not read")
check(FS.readCapped(root.appendingPathComponent("small.bin"))?.count == 1000, "small regular files are read")

print("Duplicates stay safe on disk")
if let g = groups.first {
    let other = g.files.first { $0 != g.keep }!
    check(Clutter.removable(groups, selected: [other]) == [other], "a copy can go while the kept one is on disk")
    check(Clutter.removable(groups, selected: Set(g.files)).isEmpty, "selecting every copy removes nothing")
    try? fm.removeItem(at: g.keep)
    check(Clutter.removable(groups, selected: [other]).isEmpty, "if the kept copy disappeared, the last copy stays")
}

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
