import SwiftUI

@main
struct MessyApp: App {
    @StateObject private var stats = SystemStats()
    @StateObject private var store = Store()
    @AppStorage(Prefs.showMenuBar) private var showMenuBar = true

    init() { AlertPrefs.registerDefaults() }

    var body: some Scene {
        WindowGroup("Messy", id: "main") {
            ContentView(store: store, nav: store.nav, stats: stats)
                .environmentObject(stats)
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 660)
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            Dashboard(compact: true)
                .environmentObject(stats)
                .environmentObject(store)
                .frame(width: 340)
                .background(BrandBackground())
                .messyStyle()
        } label: {
            Text("\(Image(systemName: "cpu")) \(stats.cpuPercent)%  \(Image(systemName: "memorychip")) \(stats.memPercent)%")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Every module's model, created once so the Check up, the menu bar and the panes share results.
final class Store: ObservableObject {
    let nav = NavState()
    let clean = CleanModel()
    let uninstall = UninstallModel()
    let disk = DiskModel()
    let security = SecurityModel()
    let clutter = ClutterModel()
    let speed = SpeedModel()
    let updates = UpdatesModel()
    lazy var checkup = CheckupModel(store: self)
}

final class NavState: ObservableObject {
    @Published var pane: Pane = .checkup
}

enum Pane: String, CaseIterable, Identifiable {
    case checkup = "Check up"
    case clean = "Clean"
    case protect = "Protect"
    case speed = "Speed"
    case apps = "Apps"
    case clutter = "Clutter"
    case space = "Space"
    case monitor = "Monitor"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .checkup: "checkmark.seal"
        case .clean: "sparkles"
        case .protect: "lock.shield"
        case .speed: "bolt"
        case .apps: "square.grid.2x2"
        case .clutter: "doc.on.doc"
        case .space: "chart.pie"
        case .monitor: "gauge.with.dots.needle.50percent"
        }
    }
}

struct ContentView: View {
    let store: Store
    @ObservedObject var nav: NavState
    let stats: SystemStats
    @AppStorage(Prefs.onboarded) private var onboarded = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        main
            .onAppear {
                AlertCenter.shared.show = { [nav] pane in
                    nav.pane = pane
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                AlertCenter.shared.start(stats: stats, store: store)
            }
            .sheet(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
                OnboardingView { startWithScan in
                    onboarded = true
                    if startWithScan {
                        nav.pane = .protect
                        store.security.scan()
                    }
                }
                .interactiveDismissDisabled()
            }
    }

    @Namespace private var selection

    private var main: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 9) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                    Text("Messy").font(.system(size: 20, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 8)
                .padding(.top, 34)
                .padding(.bottom, 16)
                ForEach(Pane.allCases) { p in
                    SidebarButton(pane: p, selected: nav.pane == p, namespace: selection) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { nav.pane = p }
                    }
                    if p == .checkup { Divider().padding(.vertical, 6).padding(.horizontal, 8) }
                }
                Spacer()
            }
            .padding(10)
            .frame(width: 190)
            .background(.ultraThinMaterial)
            detail
                .id(nav.pane)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 22)
        }
        .background(BrandBackground())
        .ignoresSafeArea(.container, edges: .top)
        .messyStyle()
    }

    @ViewBuilder private var detail: some View {
        switch nav.pane {
        case .checkup: CheckupView(model: store.checkup, nav: nav, store: store)
        case .clean: CleanView(model: store.clean)
        case .protect: SecurityView(model: store.security)
        case .speed: SpeedView(model: store.speed)
        case .apps: AppsView(uninstall: store.uninstall, updates: store.updates)
        case .clutter: ClutterView(model: store.clutter)
        case .space: DiskView(model: store.disk)
        case .monitor:
            VStack(alignment: .leading, spacing: 0) {
                PaneHeader(title: "Monitor", subtitle: "Live system status. Also in the menu bar.") {}
                Divider()
                ScrollView {
                    Dashboard(compact: false).padding(16)
                }
            }
        }
    }
}

/// Stand-in while a pane is being built.
private struct ComingSoon: View {
    let pane: Pane

    var body: some View {
        VStack(spacing: 12) {
            GradientIcon(symbol: pane.icon, size: 40)
            Text(pane.rawValue).font(.title2.bold())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SidebarButton: View {
    let pane: Pane
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: pane.icon)
                    .frame(width: 20)
                    .foregroundStyle(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.secondary))
                    .scaleEffect(hover.on && !selected ? 1.12 : 1)
                Text(pane.rawValue).fontWeight(selected ? .semibold : .regular)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Brand.teal.opacity(0.2))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Brand.teal.opacity(0.35), lineWidth: 1))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hover.on {
                    RoundedRectangle(cornerRadius: 9).fill(.quaternary.opacity(0.5))
                }
            }
            .animation(.easeOut(duration: 0.15), value: hover.on)
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
    }
}
