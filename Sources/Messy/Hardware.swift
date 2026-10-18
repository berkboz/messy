import AppKit
import Darwin
import IOKit
import IOKit.ps
import Network

// MARK: - Battery

struct BatteryInfo: Equatable {
    var percent: Int
    var charging: Bool
    var onPower: Bool
    /// Minutes to empty (on battery) or to full (charging); nil while macOS is still estimating.
    var minutesLeft: Int?
    /// Apple's own verdict: "Good", "Fair", "Poor", "Check Battery"…
    var condition: String?
    /// Current full-charge capacity as a share of the original design capacity.
    var health: Int?
    var cycles: Int?
    /// Battery cell temperature. CPU and other temperatures need private APIs.
    var temperature: Double?
}

enum Battery {
    /// Nil on Macs without a battery.
    static func read() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in list {
            guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let minutes = (charging ? d[kIOPSTimeToFullChargeKey] : d[kIOPSTimeToEmptyKey]) as? Int
            var info = BatteryInfo(
                percent: max > 0 ? current * 100 / max : current,
                charging: charging,
                onPower: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                minutesLeft: (minutes ?? -1) > 0 ? minutes : nil,
                condition: d[kIOPSBatteryHealthKey] as? String)

            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if service != 0 {
                defer { IOObjectRelease(service) }
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let top = props?.takeRetainedValue() as? [String: Any] {
                    // Newer macOS versions keep the capacities in a nested BatteryData dictionary.
                    let nested = top["BatteryData"] as? [String: Any] ?? [:]
                    let p = nested.merging(top) { _, topLevel in topLevel }
                    info.cycles = p["CycleCount"] as? Int
                    let design = p["DesignCapacity"] as? Int ?? 0
                    let full = p["AppleRawMaxCapacity"] as? Int ?? p["NominalChargeCapacity"] as? Int ?? 0
                    if design > 0, full > 0 { info.health = min(100, full * 100 / design) }
                    if let t = p["Temperature"] as? Int { info.temperature = Double(t) / 100 }
                }
            }
            return info
        }
        return nil
    }
}

// MARK: - Per-app CPU and memory

struct AppUsage: Identifiable {
    /// The .app bundle path, or the executable path for processes outside an app.
    let id: String
    var bytes: UInt64 = 0
    /// Percent of one core, like Activity Monitor.
    var cpu: Double = 0
    var processes = 0
    var canQuit = false

    var url: URL { URL(fileURLWithPath: id) }
    var name: String { id.hasSuffix(".app") ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent }
}

/// Samples every readable process. CPU use is the change in CPU time since the previous sample,
/// so the first sample reports 0. Only the current user's processes are readable without root.
/// Not thread-safe: call from one serial queue.
final class ProcessSampler {
    private var previous: [pid_t: UInt64] = [:]
    private var previousAt: UInt64 = 0
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var t = mach_timebase_info_data_t()
        mach_timebase_info(&t)
        return (UInt64(t.numer), UInt64(max(t.denom, 1)))
    }()

    func sample() -> [AppUsage] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let n = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        // Never offer to quit macOS's own apps (loginwindow, Finder, Dock…): quitting loginwindow logs the user out.
        let quittable = Set(NSWorkspace.shared.runningApplications
            .filter { !($0.bundleIdentifier ?? "").lowercased().hasPrefix("com.apple.") }
            .compactMap { $0.bundleURL?.path }
            .filter { !$0.hasPrefix("/System/") })

        let now = mach_absolute_time()
        let elapsed = Double((now &- previousAt) * timebase.numer / timebase.denom)
        var current: [pid_t: UInt64] = [:]
        var groups: [String: AppUsage] = [:]
        var buf = [CChar](repeating: 0, count: 4096)

        for pid in pids.prefix(Int(min(max(n, 0), Int32(pids.count)))) where pid > 0 {
            var info = rusage_info_v4()
            let r = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard r == 0, proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { continue }
            let path = String(cString: buf)
            let key = path.range(of: ".app/").map { String(path[..<$0.lowerBound]) + ".app" } ?? path

            // ri_user_time/ri_system_time are mach time units.
            let cpuTime = (info.ri_user_time + info.ri_system_time) * timebase.numer / timebase.denom
            current[pid] = cpuTime
            var g = groups[key] ?? AppUsage(id: key, canQuit: quittable.contains(key))
            g.bytes += info.ri_phys_footprint
            g.processes += 1
            if previousAt != 0, elapsed > 0, let before = previous[pid], cpuTime >= before {
                g.cpu += Double(cpuTime - before) / elapsed * 100
            }
            groups[key] = g
        }
        previous = current
        previousAt = now
        return Array(groups.values)
    }
}

// MARK: - System

enum SystemInfo {
    static var uptime: TimeInterval? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        return Date().timeIntervalSince1970 - Double(boot.tv_sec)
    }

    static var loadAverage: Double? {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) >= 1 ? loads[0] : nil
    }

    static var thermal: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Very hot"
        @unknown default: "Unknown"
        }
    }

    static func duration(_ t: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = t >= 86400 ? [.day, .hour] : [.hour, .minute]
        f.unitsStyle = .abbreviated
        return f.string(from: t) ?? ""
    }
}

// MARK: - Network

/// Connection status from the system; observing it sends no traffic.
final class NetworkStatus: ObservableObject {
    @Published var connected = true
    @Published var kind = ""

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let kind = path.usesInterfaceType(.wifi) ? "Wi-Fi"
                : path.usesInterfaceType(.wiredEthernet) ? "Ethernet"
                : path.usesInterfaceType(.cellular) ? "Cellular" : "Other"
            DispatchQueue.main.async {
                self?.connected = path.status == .satisfied
                self?.kind = path.status == .satisfied ? kind : "Offline"
            }
        }
        monitor.start(queue: DispatchQueue(label: "messy.network"))
    }

    deinit { monitor.cancel() }
}

struct SpeedResult: Equatable {
    var down: Double   // bits per second
    var up: Double
    var responsiveness: Int?
}

enum SpeedTest {
    /// Apple's own networkQuality tool, against Apple's servers. Runs only when the user clicks.
    static func run() -> SpeedResult? {
        let r = Shell.run("/usr/bin/networkQuality", ["-c"], timeout: 60)
        guard r.status == 0, let data = r.out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let down = json["dl_throughput"] as? Double, let up = json["ul_throughput"] as? Double
        else { return nil }
        let rpm = (json["responsiveness"] as? Double) ?? (json["dl_responsiveness"] as? Double)
        return SpeedResult(down: down, up: up, responsiveness: rpm.map { Int($0) })
    }

    static func mbps(_ bits: Double) -> String { String(format: "%.0f Mbps", bits / 1_000_000) }
}

// MARK: - External disks

struct ExternalVolume: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let name: String
    let total: Int64
    let free: Int64
}

enum Volumes {
    static func external() -> [ExternalVolume] {
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsEjectableKey, .volumeLocalizedNameKey,
                                      .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { u in
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.volumeIsBrowsable == true,
                  v.volumeIsInternal == false || v.volumeIsEjectable == true
            else { return nil }
            return ExternalVolume(url: u, name: v.volumeLocalizedName ?? u.lastPathComponent,
                                  total: Int64(v.volumeTotalCapacity ?? 0), free: Int64(v.volumeAvailableCapacity ?? 0))
        }
    }

    static func eject(_ v: ExternalVolume) -> String? {
        do { try NSWorkspace.shared.unmountAndEjectDevice(at: v.url); return nil }
        catch { return error.localizedDescription }
    }
}
