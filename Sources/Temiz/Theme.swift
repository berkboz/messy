import SwiftUI

/// Colours taken from the app icon.
enum Brand {
    static let teal = Color(red: 0.055, green: 0.624, blue: 0.604)
    static let emerald = Color(red: 0.122, green: 0.749, blue: 0.451)
    static let gradient = LinearGradient(colors: [teal, emerald], startPoint: .topLeading, endPoint: .bottomTrailing)
}

private struct CardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Brand.teal.opacity(0.18), lineWidth: 1))
            .shadow(color: Brand.ink.opacity(0.08), radius: 10, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View { modifier(CardModifier(padding: padding)) }
}

struct GradientIcon: View {
    let symbol: String
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Brand.gradient)
    }
}

/// Progress ring for scans. While `spinning`, a highlight runs around the track.
struct ScanRing: View {
    let progress: Double
    var spinning = false
    var size: CGFloat = 180
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(AngularGradient(colors: [Brand.teal, Brand.emerald, Brand.teal], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
            if spinning {
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                    Circle()
                        .trim(from: 0, to: 0.07)
                        .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(t * 360 - 90))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// A result tile: icon, big value, caption, optional tick in the corner and a Review link.
struct Tile: View {
    let icon: String
    let title: String
    let value: String
    let caption: String
    var selected: Binding<Bool>? = nil
    var busy = false
    var review: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                GradientIcon(symbol: icon, size: 22)
                    .symbolEffect(.pulse, isActive: busy)
                Spacer()
                if let selected {
                    Toggle("", isOn: selected).labelsHidden()
                }
            }
            Text(title).font(.headline)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let review {
                Button("Review", action: review).buttonStyle(.brandLink).font(.callout)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .card()
        .opacity(selected?.wrappedValue == false ? 0.6 : 1)
    }
}

/// Small label/value row used in cards.
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}

// MARK: - Brand components

/// The main call-to-action: a brand-gradient capsule that grows on hover and dips when pressed.
struct BrandButtonStyle: ButtonStyle {
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        BrandButton(configuration: configuration, large: large)
    }

    private struct BrandButton: View {
        let configuration: ButtonStyleConfiguration
        let large: Bool
        @StateObject private var hover = HoverState()
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(large ? .title3.bold() : .callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, large ? 40 : 16)
                .padding(.vertical, large ? 12 : 6)
                .background(Capsule().fill(Brand.gradient))
                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .shadow(color: Brand.teal.opacity(hover.on && enabled ? 0.55 : 0.25), radius: hover.on ? 14 : 6, y: 3)
                .scaleEffect(configuration.isPressed ? 0.96 : hover.on && enabled ? 1.03 : 1)
                .opacity(enabled ? 1 : 0.45)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hover.on)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
                .onHover { hover.on = $0 }
        }
    }
}

/// Hover state without the @State macro, which this toolchain does not ship.
final class HoverState: ObservableObject {
    @Published var on = false
}

/// Lifts a card a little under the pointer.
private struct HoverLift: ViewModifier {
    @StateObject private var hover = HoverState()

    func body(content: Content) -> some View {
        content
            .scaleEffect(hover.on ? 1.015 : 1)
            .shadow(color: .black.opacity(hover.on ? 0.25 : 0), radius: 12, y: 6)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: hover.on)
            .onHover { hover.on = $0 }
    }
}

extension View {
    func hoverLift() -> some View { modifier(HoverLift()) }
}

/// The broom mascot. Poses are PNGs in the app's Resources folder.
struct Mascot: View {
    enum Pose: String { case idle, sweep, happy, worried }
    enum Motion { case none, bob, sweep, bounce }

    let pose: Pose
    var size: CGFloat = 120
    var motion: Motion = .bob

    private static let cache = NSCache<NSString, NSImage>()

    private var image: NSImage? {
        let key = pose.rawValue as NSString
        if let hit = Self.cache.object(forKey: key) { return hit }
        guard let url = Bundle.main.url(forResource: "mascot-\(pose.rawValue)", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        Self.cache.setObject(img, forKey: key)
        return img
    }

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .modifier(MascotMotion(motion: motion))
        } else {
            GradientIcon(symbol: "sparkles", size: size * 0.4).frame(width: size, height: size)
        }
    }
}

/// Looping motion done with repeating implicit animations, which Core Animation runs in the
/// render server instead of redrawing the view every frame.
private struct MascotMotion: ViewModifier {
    let motion: Mascot.Motion
    @StateObject private var phase = HoverState()

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation), anchor: .bottom)
            .offset(y: offset)
            .animation(animation, value: phase.on)
            .onAppear { if motion != .none { phase.on = true } }
    }

    private var rotation: Double {
        switch motion {
        case .sweep: phase.on ? 14 : -14
        case .bob: phase.on ? 2 : -2
        default: 0
        }
    }

    private var offset: Double {
        switch motion {
        case .bob: phase.on ? -4 : 4
        case .bounce: phase.on ? -10 : 0
        case .sweep: phase.on ? -1.5 : 1.5
        case .none: 0
        }
    }

    private var animation: Animation? {
        switch motion {
        case .bob: .easeInOut(duration: 1.8).repeatForever(autoreverses: true)
        case .sweep: .easeInOut(duration: 0.45).repeatForever(autoreverses: true)
        case .bounce: .easeOut(duration: 0.35).repeatForever(autoreverses: true)
        case .none: nil
        }
    }
}

/// A short burst of confetti in the brand colours, for finished tasks.
struct Confetti: View {
    let started = Date()
    @StateObject private var clock = OneShot(after: 2.5)

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: clock.fired)) { ctx in
            Canvas { gc, size in
                let t = ctx.date.timeIntervalSince(started)
                guard t < 2.4 else { return }
                let colors: [Color] = [Brand.teal, Brand.emerald, .white, .yellow]
                for i in 0..<70 {
                    let seed = Double(i) * 12.9898
                    let angle = (sin(seed) * 0.5 + 0.5) * .pi * 2
                    let speed = 120 + (cos(seed * 1.7) * 0.5 + 0.5) * 220
                    let x = size.width / 2 + cos(angle) * speed * t
                    let y = size.height / 2 + sin(angle) * speed * t + 260 * t * t
                    let r = CGRect(x: x, y: y, width: 6, height: 9)
                    gc.opacity = max(0, 1 - t / 2.4)
                    gc.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(colors[i % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Flips once after a delay; used to stop animations that should not run forever.
final class OneShot: ObservableObject {
    @Published var fired = false

    init(after seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.fired = true }
    }
}

/// Fades and lifts a view in shortly after it appears, for staggered entrances.
private struct AppearIn: ViewModifier {
    let delay: Double
    @StateObject private var shown = HoverState()

    func body(content: Content) -> some View {
        content
            .opacity(shown.on ? 1 : 0)
            .offset(y: shown.on ? 0 : 14)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { shown.on = true }
                }
            }
    }
}

extension View {
    func appearIn(delay: Double) -> some View { modifier(AppearIn(delay: delay)) }
}
