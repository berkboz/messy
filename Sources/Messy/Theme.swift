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
                .animation(spinning ? nil : .easeInOut(duration: 0.5), value: progress)
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
    /// Coral when the tile counts mess, the default text colour otherwise.
    var accent: Color = .primary
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
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(accent)
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
        if let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            MascotLayer(image: cg, motion: motion, flipbook: motion == .none ? nil : Flipbook.load(for: pose))
                .frame(width: size, height: size)
        } else {
            GradientIcon(symbol: "sparkles", size: size * 0.4).frame(width: size, height: size)
        }
    }
}

/// The mascot as a Core Animation layer. Its looping motion runs in the system's render server,
/// so an idle screen costs Messy no CPU (SwiftUI's repeating animations redraw every frame).
private struct MascotLayer: NSViewRepresentable {
    let image: CGImage
    let motion: Mascot.Motion
    let flipbook: Flipbook?

    /// Frames that already sweep or hop need no extra rocking or bouncing from the layer.
    private var layerMotion: Mascot.Motion {
        guard flipbook != nil else { return motion }
        switch motion {
        case .sweep: return .bob
        case .bounce: return .none
        default: return motion
        }
    }

    func makeNSView(context: Context) -> SpriteView {
        let view = SpriteView()
        view.sprite.contents = image
        Self.animate(view.sprite, layerMotion)
        flipbook?.play(on: view.sprite)
        context.coordinator.motion = motion
        return view
    }

    func updateNSView(_ view: SpriteView, context: Context) {
        view.sprite.contents = image
        if context.coordinator.motion != motion {
            context.coordinator.motion = motion
            Self.animate(view.sprite, layerMotion)
            flipbook?.play(on: view.sprite)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var motion: Mascot.Motion?
    }

    /// Keeps the sprite layer sized to the view; SwiftUI sizes the view after creating it.
    final class SpriteView: NSView {
        let sprite = CALayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            sprite.contentsGravity = .resizeAspect
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0)      // rock from the bristles, like sweeping
            layer?.addSublayer(sprite)
        }

        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sprite.bounds = bounds
            sprite.position = CGPoint(x: bounds.midX, y: 0)
            sprite.contentsScale = window?.backingScaleFactor ?? 2
            CATransaction.commit()
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            needsLayout = true
        }
    }

    private static func animate(_ layer: CALayer, _ motion: Mascot.Motion) {
        layer.removeAllAnimations()
        func loop(_ key: String, from: Double, to: Double, duration: Double) {
            let a = CABasicAnimation(keyPath: key)
            a.fromValue = from
            a.toValue = to
            a.duration = duration
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(a, forKey: key)
        }
        let degrees = Double.pi / 180
        switch motion {
        case .bob:
            loop("transform.translation.y", from: -4, to: 4, duration: 1.8)
            loop("transform.rotation.z", from: -2 * degrees, to: 2 * degrees, duration: 2.3)
        case .sweep:
            loop("transform.rotation.z", from: -14 * degrees, to: 14 * degrees, duration: 0.45)
        case .bounce:
            loop("transform.translation.y", from: 0, to: 10, duration: 0.35)
        case .none:
            break
        }
    }
}

/// Frames cut from a one-row sprite sheet (sprite-<name>.png), played as a keyframe animation of
/// the layer's contents, which also runs in the render server.
struct Flipbook {
    let frames: [CGImage]
    let keyTimes: [NSNumber]
    let values: [CGImage]
    let duration: Double

    private static var cache: [String: [CGImage]] = [:]

    static func load(for pose: Mascot.Pose) -> Flipbook? {
        switch pose {
        case .idle:
            // Mostly open eyes, with a quick blink every four seconds.
            guard let f = frames("blink", count: 4) else { return nil }
            return Flipbook(frames: f, keyTimes: [0, 0.90, 0.93, 0.96, 1].map { NSNumber(value: $0) },
                            values: [f[0], f[1], f[2], f[1], f[0]], duration: 4)
        case .sweep:
            guard let f = frames("sweep", count: 6) else { return nil }
            return evenly(f + f.dropFirst().dropLast().reversed(), duration: 0.9)
        case .happy:
            guard let f = frames("hop", count: 5) else { return nil }
            return evenly(f, duration: 0.7)
        case .worried:
            return nil
        }
    }

    private static func evenly(_ f: [CGImage], duration: Double) -> Flipbook {
        let times = (0...f.count).map { NSNumber(value: Double($0) / Double(f.count)) }
        return Flipbook(frames: f, keyTimes: times, values: f + [f[0]], duration: duration)
    }

    private static func frames(_ name: String, count: Int) -> [CGImage]? {
        if let hit = cache[name] { return hit }
        guard let url = Bundle.main.url(forResource: "sprite-\(name)", withExtension: "png"),
              let sheet = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let w = sheet.width / count
        let f = (0..<count).compactMap { sheet.cropping(to: CGRect(x: $0 * w, y: 0, width: w, height: sheet.height)) }
        guard f.count == count else { return nil }
        cache[name] = f
        return f
    }

    func play(on layer: CALayer) {
        let a = CAKeyframeAnimation(keyPath: "contents")
        a.values = values
        a.keyTimes = keyTimes
        a.calculationMode = .discrete
        a.duration = duration
        a.repeatCount = .infinity
        layer.add(a, forKey: "flipbook")
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

/// The icon's broom as a one-colour template, for the menu bar when no readings are shown.
enum BroomGlyph {
    static let menuBar: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Drawn upright, then leaned like the broom in the icon.
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: -.pi / 6)
            ctx.scaleBy(x: 0.92, y: 0.92)
            ctx.translateBy(x: -9, y: -9)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 8.1, y: 10.6, width: 1.8, height: 7.4), xRadius: 0.9, yRadius: 0.9).fill()
            NSBezierPath(roundedRect: NSRect(x: 5.9, y: 8.4, width: 6.2, height: 1.7), xRadius: 0.5, yRadius: 0.5).fill()
            let head = NSBezierPath()
            head.move(to: NSPoint(x: 6.2, y: 7.9))
            head.curve(to: NSPoint(x: 3.4, y: 0.8), controlPoint1: NSPoint(x: 4.6, y: 6.2), controlPoint2: NSPoint(x: 3.4, y: 3.2))
            head.curve(to: NSPoint(x: 14.6, y: 0.8), controlPoint1: NSPoint(x: 7.0, y: 0.0), controlPoint2: NSPoint(x: 11.0, y: 0.0))
            head.curve(to: NSPoint(x: 11.8, y: 7.9), controlPoint1: NSPoint(x: 14.6, y: 3.2), controlPoint2: NSPoint(x: 13.4, y: 6.2))
            head.close()
            head.fill()
            // Two cuts between the bristles.
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(0.9)
            ctx.setLineCap(.round)
            for (top, bottom) in [(NSPoint(x: 7.6, y: 5.6), NSPoint(x: 6.6, y: 1.4)), (NSPoint(x: 10.4, y: 5.6), NSPoint(x: 11.4, y: 1.4))] {
                ctx.move(to: top)
                ctx.addLine(to: bottom)
            }
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
