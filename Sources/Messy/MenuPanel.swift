import SwiftUI

enum Widget: String, CaseIterable, Identifiable {
    case protection, storage, memory, cpu, battery, network, devices
    var id: String { rawValue }
}

/// The menu bar panel (compact: tap a widget to open it) and the Monitor pane (everything open).
struct Dashboard: View {
    let compact: Bool
    @EnvironmentObject private var stats: SystemStats
    @EnvironmentObject private var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        DashboardContent(compact: compact, stats: stats, network: stats.network,
                         security: store.security, clean: store.clean, nav: store.nav,
                         openMain: { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) })
            .onAppear { stats.beginDetail(); store.clean.refreshTrash() }
            .onDisappear { stats.endDetail() }
    }
}

private struct DashboardContent: View {
    let compact: Bool
    @ObservedObject var stats: SystemStats
    @ObservedObject var network: NetworkStatus
    @ObservedObject var security: SecurityModel
    @ObservedObject var clean: CleanModel
    let nav: NavState
    let openMain: () -> Void
    @AppStorage("menuExpanded") private var expanded = ""

    private var health: Health {
        Health.compute(stats: stats,
                       threats: security.scanned ? security.threats.filter { $0.trust == .danger && $0.strong }.count : nil,
                       weakThreats: security.threats.filter { $0.trust == .danger && !$0.strong }.count,
                       junk: clean.groups.isEmpty ? nil : clean.selectedSize)
    }

    private var widgets: [Widget] {
        Widget.allCases.filter {
            switch $0 {
            case .battery: stats.battery != nil
            case .devices: !compact || !stats.volumes.isEmpty
            default: true
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            healthHeader
            LazyVGrid(columns: compact ? [GridItem(.flexible()), GridItem(.flexible())]
                                       : [GridItem(.adaptive(minimum: 300), alignment: .top)],
                      alignment: .leading, spacing: 10) {
                ForEach(widgets) { w in
                    if compact { summary(w) } else { full(w) }
                }
            }
            if compact, let open = Widget(rawValue: expanded), widgets.contains(open) {
                detail(open).card(padding: 12)
            }
            if compact {
                Divider()
                HStack {
                    Button("Open Messy", action: openMain)
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }
                }
            }
        }
        .padding(compact ? 14 : 0)
    }

    // MARK: Header

    private var healthHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                ScanRing(progress: Double(health.score) / 100, size: compact ? 58 : 96, lineWidth: compact ? 7 : 10)
                Text("\(health.score)")
                    .font(.system(size: compact ? 18 : 28, weight: .semibold))
                    .contentTransition(.numericText())
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Mac health: \(health.label)").font(compact ? .headline : .title3.bold())
                if health.reasons.isEmpty {
                    Text("Nothing needs attention.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(health.reasons.prefix(compact ? 2 : 6), id: \.self) { r in
                    Text("• " + r).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if !security.scanned {
                    Text("Run a check in Protect to include threats.").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Widgets

    private func summary(_ w: Widget) -> some View {
        let (icon, title, value, caption) = headline(w)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded = expanded == w.rawValue ? "" : w.rawValue }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    GradientIcon(symbol: icon, size: 13)
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: expanded == w.rawValue ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                    .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.7)
                Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .card(padding: 10)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(expanded == w.rawValue ? Brand.teal : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func full(_ w: Widget) -> some View {
        let (icon, title, value, caption) = headline(w)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                GradientIcon(symbol: icon, size: 16)
                Text(title).font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
            detail(w)
        }
        .card()
    }

    private func headline(_ w: Widget) -> (String, String, String, String) {
        switch w {
        case .protection:
            let n = security.riskyCount
            return ("lock.shield", "Protection",
                    security.scanned ? (n == 0 ? "No issues" : plural(n, "issue")) : "Not checked",
                    security.scanned ? "Last check this session" : "Open Protect to check")
        case .storage:
            return ("internaldrive", "Storage", Fmt.bytes(stats.diskFree), "free of \(Fmt.bytes(stats.diskTotal))")
        case .memory:
            return ("memorychip", "Memory", "\(stats.memPercent)%", "Pressure: \(pressureText)")
        case .cpu:
            return ("cpu", "CPU", "\(stats.cpuPercent)%", SystemInfo.loadAverage.map { String(format: "Load %.2f", $0) } ?? "")
        case .battery:
            let b = stats.battery
            return ("battery.100percent", "Battery", "\(b?.percent ?? 0)%", batteryCaption)
        case .network:
            return ("network", "Network", Fmt.rate(stats.netIn), network.connected ? network.kind : "Offline")
        case .devices:
            return ("externaldrive", "Devices", "\(stats.volumes.count)",
                    stats.volumes.isEmpty ? "No external disks" : plural(stats.volumes.count, "external disk"))
        }
    }

    @ViewBuilder private func detail(_ w: Widget) -> some View {
        switch w {
        case .protection: protectionDetail
        case .storage: storageDetail
        case .memory: memoryDetail
        case .cpu: cpuDetail
        case .battery: batteryDetail
        case .network: networkDetail
        case .devices: devicesDetail
        }
    }

    // MARK: Details

    private var protectionDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if security.scanned {
                InfoRow(label: "Risky items", value: "\(security.riskyCount)")
                InfoRow(label: "Items to review", value: "\(security.reviewCount)")
            } else {
                Text("Messy checks background services, app signatures and system protections when you ask.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button(security.scanned ? "Open Protect" : "Check now") {
                nav.pane = .protect
                if !security.scanned { security.scan() }
                openMain()
            }
        }
    }

    private var storageDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: stats.diskTotal > 0 ? 1 - Double(stats.diskFree) / Double(stats.diskTotal) : 0)
                .tint(Brand.teal)
            InfoRow(label: "Free", value: Fmt.bytes(stats.diskFree))
            InfoRow(label: "Total", value: Fmt.bytes(stats.diskTotal))
            InfoRow(label: "Trash", value: clean.trash.map { "\(plural($0.count, "item")), \(Fmt.bytes($0.size))" }
                    ?? "Needs Full Disk Access")
            HStack {
                Button("Empty Trash…") { nav.pane = .clean; openMain(); clean.confirmEmpty = true }
                    .disabled(clean.trash?.count == 0)
                Button("What takes space") { nav.pane = .space; openMain() }
            }
        }
    }

    private var memoryDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            InfoRow(label: "Used", value: "\(Fmt.bytes(Int64(stats.memUsed))) of \(Fmt.bytes(Int64(stats.memTotal)))")
            HStack {
                Circle().fill(pressureColor).frame(width: 8, height: 8)
                Text("Memory pressure: \(pressureText)")
                Spacer()
                Text("Swap: \(Fmt.bytes(Int64(stats.swapUsed)))").foregroundStyle(.secondary)
            }
            .font(.callout)
            Text("Using the most memory").font(.caption.bold()).foregroundStyle(.secondary)
            appList(stats.topMemory.prefix(compact ? 5 : 8)) { Fmt.bytes(Int64($0.bytes)) }
            HStack {
                Button { stats.purge() } label: {
                    if stats.purging { ProgressView().controlSize(.small) } else { Text("Free up RAM") }
                }
                .disabled(stats.purging)
                Spacer()
            }
            if let m = stats.purgeMessage {
                Text(m).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(stats.pressure == 1
                 ? "With memory pressure normal there is no need to free RAM; macOS uses free RAM as cache. Quitting an app above makes the real difference."
                 : "Memory is tight. Quitting an app you are not using helps most.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cpuDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: min(stats.cpu, 1)).tint(Brand.teal)
            if let up = SystemInfo.uptime { InfoRow(label: "Up for", value: SystemInfo.duration(up)) }
            InfoRow(label: "Thermal state", value: SystemInfo.thermal)
            Text("Using the most CPU").font(.caption.bold()).foregroundStyle(.secondary)
            if stats.topCPU.isEmpty {
                Text("Measuring…").font(.caption).foregroundStyle(.tertiary)
            }
            appList(stats.topCPU.prefix(compact ? 5 : 6)) { String(format: "%.0f%%", $0.cpu) }
            Text("Chip temperatures and fan speeds are not available to apps without private macOS interfaces.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var batteryDetail: some View {
        if let b = stats.battery {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: Double(b.percent) / 100).tint(b.percent <= 20 ? .orange : Brand.emerald)
                if let h = b.health { InfoRow(label: "Health", value: "\(h)% of original capacity") }
                if let c = b.condition { InfoRow(label: "Condition", value: c.displaySafe) }
                if let c = b.cycles { InfoRow(label: "Charge cycles", value: "\(c)") }
                if let t = b.temperature { InfoRow(label: "Temperature", value: String(format: "%.1f °C", t)) }
            }
        }
    }

    private var networkDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            InfoRow(label: "Connection", value: network.connected ? network.kind : "Offline")
            InfoRow(label: "Download", value: Fmt.rate(stats.netIn))
            InfoRow(label: "Upload", value: Fmt.rate(stats.netOut))
            if let s = stats.speed {
                Divider()
                InfoRow(label: "Speed test down", value: SpeedTest.mbps(s.down))
                InfoRow(label: "Speed test up", value: SpeedTest.mbps(s.up))
                if let r = s.responsiveness { InfoRow(label: "Responsiveness", value: "\(r) RPM") }
            }
            if let e = stats.speedError { Text(e).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button { stats.runSpeedTest() } label: {
                    if stats.speedTesting { ProgressView().controlSize(.small) } else { Text("Test speed") }
                }
                .disabled(stats.speedTesting || !network.connected)
                Spacer()
            }
            Text("The speed test uses Apple's networkQuality tool and Apple's servers. It only runs when you click.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var devicesDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            if stats.volumes.isEmpty {
                Text("No external disks connected.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(stats.volumes) { v in
                HStack {
                    FileIcon(url: v.url, size: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(v.name.displaySafe).lineLimit(1)
                        Text("\(Fmt.bytes(v.free)) free of \(Fmt.bytes(v.total))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { _ = Volumes.eject(v) } label: { Image(systemName: "eject") }
                        .buttonStyle(.plain).foregroundStyle(Brand.teal).help("Eject \(v.name.displaySafe)")
                }
            }
        }
    }

    // MARK: Helpers

    private func appList(_ apps: ArraySlice<AppUsage>, value: @escaping (AppUsage) -> String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(apps)) { app in
                HStack(spacing: 8) {
                    FileIcon(url: app.url, size: 15)
                    Text(app.name.displaySafe).lineLimit(1)
                    if app.processes > 1 {
                        Text(plural(app.processes, "process", "processes")).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(value(app)).monospacedDigit().foregroundStyle(.secondary)
                    Button { stats.quit(app) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Quit \(app.name.displaySafe)")
                        .opacity(app.canQuit ? 1 : 0).disabled(!app.canQuit)
                }
                .font(.callout)
            }
        }
    }

    private var pressureText: String {
        switch stats.pressure {
        case 4: "Critical"
        case 2: "High"
        default: "Normal"
        }
    }

    private var pressureColor: Color {
        switch stats.pressure {
        case 4: .red
        case 2: .orange
        default: Brand.emerald
        }
    }

    private var batteryCaption: String {
        guard let b = stats.battery else { return "" }
        if b.charging { return b.minutesLeft.map { "Charging, full in \(SystemInfo.duration(Double($0 * 60)))" } ?? "Charging" }
        if b.onPower { return "On power" }
        return b.minutesLeft.map { "\(SystemInfo.duration(Double($0 * 60))) left" } ?? "On battery"
    }
}
