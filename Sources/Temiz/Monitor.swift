import Darwin
import SwiftUI

final class SystemStats: ObservableObject {
    @Published var cpu: Double = 0
    @Published var memUsed: UInt64 = 0
    @Published var diskFree: Int64 = 0
    @Published var diskTotal: Int64 = 0
    @Published var netIn: Double = 0
    @Published var netOut: Double = 0

    /// kern.memorystatus_vm_pressure_level: 1 normal, 2 warning, 4 critical.
    @Published var pressure: Int32 = 1
    @Published var swapUsed: UInt64 = 0
    @Published var apps: [AppUsage] = []
    @Published var battery: BatteryInfo?
    @Published var volumes: [ExternalVolume] = []
    @Published var purging = false
    @Published var purgeMessage: String?

    @Published var speed: SpeedResult?
    @Published var speedTesting = false
    @Published var speedError: String?

    let network = NetworkStatus()
    let memTotal = ProcessInfo.processInfo.physicalMemory

    /// Average CPU over the last five minutes, for the health score.
    private(set) var cpuAverage: Double = 0
    private var cpuHistory: [Double] = []
    private var prevTicks: (busy: UInt64, total: UInt64)?
    private var prevNet: (rx: UInt64, tx: UInt64, at: Date)?
    private var timer: Timer?
    private var tickCount = 0
    private var viewers = 0
    private let sampler = ProcessSampler()
    private let samplerQueue = DispatchQueue(label: "temiz.sampler")

    var cpuPercent: Int { Int((cpu * 100).rounded()) }
    var memPercent: Int { memTotal == 0 ? 0 : Int((Double(memUsed) / Double(memTotal) * 100).rounded()) }
    var topMemory: [AppUsage] { Array(apps.sorted { $0.bytes > $1.bytes }.prefix(10)) }
    var topCPU: [AppUsage] { Array(apps.filter { $0.cpu >= 0.5 }.sorted { $0.cpu > $1.cpu }.prefix(6)) }

    init() {
        tick()
        battery = Battery.read()
        volumes = Volumes.external()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.volumes = Volumes.external()
            }
        }
    }

    /// Per-process sampling walks every process, so it only runs while a panel showing it is open.
    func beginDetail() {
        viewers += 1
        if viewers == 1 { sampleApps() }
    }

    func endDetail() { viewers = max(0, viewers - 1) }

    private func sampleApps() {
        samplerQueue.async {
            let apps = self.sampler.sample()
            DispatchQueue.main.async { self.apps = apps }
        }
    }

    private func tick() {
        if let t = Self.cpuTicks() {
            if let p = prevTicks, t.total > p.total {
                cpu = Double(t.busy - p.busy) / Double(t.total - p.total)
                cpuHistory.append(cpu)
                if cpuHistory.count > 150 { cpuHistory.removeFirst() }
                cpuAverage = cpuHistory.reduce(0, +) / Double(cpuHistory.count)
            }
            prevTicks = t
        }
        memUsed = Self.memoryUsed()
        pressure = Self.sysctlInt32("kern.memorystatus_vm_pressure_level") ?? 1
        swapUsed = Self.swapUsed()
        if viewers > 0, tickCount % 2 == 0 { sampleApps() }
        if tickCount % 15 == 0 { battery = Battery.read() }

        // "Available for important usage" asks the cache-delete service, which is slow; every 10 s is plenty.
        let root = URL(fileURLWithPath: "/")
        if tickCount % 5 == 0, let v = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            diskFree = v.volumeAvailableCapacityForImportantUsage ?? 0
            diskTotal = Int64(v.volumeTotalCapacity ?? 0)
        }

        let n = Self.netBytes()
        let now = Date()
        if let p = prevNet {
            let dt = now.timeIntervalSince(p.at)
            if dt > 0 {
                netIn = n.rx >= p.rx ? Double(n.rx - p.rx) / dt : 0
                netOut = n.tx >= p.tx ? Double(n.tx - p.tx) / dt : 0
            }
        }
        prevNet = (n.rx, n.tx, now)
        tickCount += 1
    }

    /// Runs /usr/sbin/purge, which needs an admin password. It only drops the file cache;
    /// quitting heavy apps frees far more.
    func purge() {
        purging = true
        purgeMessage = nil
        let before = memUsed
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Shell.admin(["/usr/sbin/purge"])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.tick()
                self.purging = false
                if r != .ok {
                    self.purgeMessage = r == .cancelled ? "Cancelled." : "Could not run."
                } else {
                    let freed = Int64(before) - Int64(self.memUsed)
                    self.purgeMessage = freed > 0
                        ? "\(Fmt.bytes(freed)) freed. macOS will use this space for cache again over time."
                        : "Cache cleared; no noticeable change in memory used."
                }
            }
        }
    }

    func quit(_ app: AppUsage) {
        guard app.canQuit else { return }
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleURL?.path == app.id && !($0.bundleIdentifier ?? "").lowercased().hasPrefix("com.apple.") }
            .forEach { $0.terminate() }
    }

    /// Network speed test. Contacts Apple's servers, so it only runs when the user clicks.
    func runSpeedTest() {
        speedTesting = true
        speedError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let r = SpeedTest.run()
            DispatchQueue.main.async {
                self.speedTesting = false
                if let r { self.speed = r } else { self.speedError = "The speed test did not finish." }
            }
        }
    }

    private static func sysctlInt32(_ name: String) -> Int32? {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &v, &size, nil, 0) == 0 ? v : nil
    }

    private static func swapUsed() -> UInt64 {
        var s = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        return sysctlbyname("vm.swapusage", &s, &size, nil, 0) == 0 ? s.xsu_used : 0
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), sys = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + sys + nice, user + sys + nice + idle)
    }

    /// Roughly Activity Monitor's "Memory Used": app memory + wired + compressed.
    private static func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return 0 }
        let page = UInt64(getpagesize())
        let app = UInt64(stats.internal_page_count) - UInt64(min(stats.purgeable_count, stats.internal_page_count))
        return (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    /// Bytes in/out on physical interfaces (en*). VPN tunnels are skipped to avoid double counting.
    private static func netBytes() -> (rx: UInt64, tx: UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        var p = ifaddr
        while let cur = p {
            let a = cur.pointee
            if let sa = a.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK), let data = a.ifa_data,
               String(cString: a.ifa_name).hasPrefix("en") {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                rx += UInt64(d.ifi_ibytes)
                tx += UInt64(d.ifi_obytes)
            }
            p = a.ifa_next
        }
        return (rx, tx)
    }
}
