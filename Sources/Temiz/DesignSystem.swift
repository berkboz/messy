import SwiftUI

// Temiz draws its own controls so nothing looks like stock macOS. Styles are applied once at the
// root (`.temizStyle()`), so every Toggle, Button, ProgressView and TextField below picks them up.

extension Brand {
    static let mint = Color(red: 0.33, green: 0.84, blue: 0.76)
    static let sky = Color(red: 0.62, green: 0.93, blue: 0.88)
    static let ink = Color(red: 0.04, green: 0.20, blue: 0.22)
}

extension View {
    func temizStyle() -> some View {
        self
            .fontDesign(.rounded)
            .tint(Brand.teal)
            .toggleStyle(CheckStyle())
            .buttonStyle(SoftButtonStyle())
            .progressViewStyle(BarStyle())
            .textFieldStyle(PillFieldStyle())
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
    }
}

// MARK: - Background

/// The icon's mint sky: a soft gradient with two cloud glows.
struct BrandBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(colors: scheme == .dark
                           ? [Color(red: 0.05, green: 0.13, blue: 0.15), Color(red: 0.03, green: 0.09, blue: 0.11)]
                           : [Color(red: 0.90, green: 0.98, blue: 0.96), Color(red: 0.97, green: 0.99, blue: 0.99)],
                           startPoint: .top, endPoint: .bottom)
            // Static on purpose: animating full-window blurs costs real CPU on an idle screen.
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                Circle()
                    .fill(Brand.mint.opacity(scheme == .dark ? 0.16 : 0.30))
                    .frame(width: w * 0.55)
                    .blur(radius: 80)
                    .position(x: w * 0.82, y: h * 0.10)
                Circle()
                    .fill(Brand.sky.opacity(scheme == .dark ? 0.10 : 0.35))
                    .frame(width: w * 0.45)
                    .blur(radius: 90)
                    .position(x: w * 0.15, y: h * 0.92)
            }
            .drawingGroup()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Toggles

/// Default for every Toggle: a rounded check with a springy tick.
struct CheckStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(configuration.isOn ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.background.opacity(0.6)))
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(configuration.isOn ? Color.clear : Brand.teal.opacity(0.45), lineWidth: 1.5)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white)
                        .scaleEffect(configuration.isOn ? 1 : 0.2)
                        .opacity(configuration.isOn ? 1 : 0)
                }
                .frame(width: 18, height: 18)
                .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isOn)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// For on/off settings: a capsule switch with a bouncing knob.
struct PillSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label
                Spacer(minLength: 8)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.quaternary))
                        .frame(width: 38, height: 22)
                    Circle().fill(.white).shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .frame(width: 18, height: 18).padding(2)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Buttons

/// Default for every Button: a soft rounded chip that lifts on hover.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Chip(configuration: configuration) }

    private struct Chip: View {
        let configuration: ButtonStyleConfiguration
        @StateObject private var hover = HoverState()
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.callout.weight(.medium))
                .foregroundStyle(enabled ? Brand.teal : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Brand.teal.opacity(hover.on && enabled ? 0.20 : 0.11)))
                .overlay(Capsule().strokeBorder(Brand.teal.opacity(0.25), lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(enabled ? 1 : 0.5)
                .animation(.easeOut(duration: 0.15), value: hover.on)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
                .onHover { hover.on = $0 }
        }
    }
}

/// Text-only actions inside cards and rows.
struct LinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(Brand.teal)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == LinkStyle {
    static var brandLink: LinkStyle { LinkStyle() }
}

extension ButtonStyle where Self == BrandButtonStyle {
    static var brand: BrandButtonStyle { BrandButtonStyle() }
    static var brandLarge: BrandButtonStyle { BrandButtonStyle(large: true) }
}

// MARK: - Progress

/// Bars are brand-gradient capsules; indeterminate progress is a small spinning ring.
struct BarStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        if let f = configuration.fractionCompleted {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Brand.teal.opacity(0.12))
                    Capsule().fill(Brand.gradient)
                        .frame(width: max(6, geo.size.width * min(max(f, 0), 1)))
                        .animation(.easeInOut(duration: 0.5), value: f)
                }
            }
            .frame(height: 7)
        } else {
            VStack(spacing: 8) {
                ScanRing(progress: 0.25, spinning: true, size: 22, lineWidth: 3)
                configuration.label.foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Text fields

struct PillFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Brand.teal.opacity(0.8))
            configuration.textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(.background.opacity(0.7)))
        .overlay(Capsule().strokeBorder(Brand.teal.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Segmented control and stepper

/// A segmented control with a sliding gradient pill.
struct Segmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = value }
                } label: {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(selection == value ? Color.white : Brand.teal)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background {
                            if selection == value {
                                Capsule().fill(Brand.gradient).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Brand.teal.opacity(0.10)))
        .overlay(Capsule().strokeBorder(Brand.teal.opacity(0.2), lineWidth: 1))
        .fixedSize()
    }
}

struct PillStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                button("minus") { value = max(range.lowerBound, value - step) }
                Text("\(value)").font(.callout.weight(.semibold)).monospacedDigit()
                    .frame(minWidth: 36).contentTransition(.numericText())
                button("plus") { value = min(range.upperBound, value + step) }
            }
            .background(Capsule().fill(Brand.teal.opacity(0.10)))
            .overlay(Capsule().strokeBorder(Brand.teal.opacity(0.2), lineWidth: 1))
        }
    }

    private func button(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Image(systemName: icon).font(.caption.bold()).foregroundStyle(Brand.teal)
                .frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A pop-up menu that looks like the rest: label in a chip, choices in a menu.
struct ChipMenu<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        Menu {
            ForEach(options, id: \.0) { value, title in
                Button(title) { selection = value }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.first { $0.0 == selection }?.1 ?? "")
                Image(systemName: "chevron.down").font(.caption2.bold())
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(Brand.teal)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Brand.teal.opacity(0.11)))
            .overlay(Capsule().strokeBorder(Brand.teal.opacity(0.25), lineWidth: 1))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Lists

extension View {
    /// Hides the stock list chrome so rows sit on the brand background as cards.
    func cleanList() -> some View {
        self.listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 34)
    }

    /// A list row drawn as a soft card.
    func rowCard() -> some View {
        self.listRowBackground(
            RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.55)).padding(.vertical, 2)
        )
        .listRowSeparator(.hidden)
    }
}
