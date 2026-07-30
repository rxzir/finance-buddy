//
//  Theme.swift
//  Finance buddy
//
//  Single source of truth for the palette, typography, shared formatting
//  and interaction styles. Views reference these — no hex literals or
//  ad-hoc animations scattered around.
//
//  Design language: monochrome (black / grey / white), minimalist, glassy.
//  One functional exception to the mono palette: the warning tone for
//  overspending, kept muted so it whispers rather than shouts.
//

import SwiftUI

// MARK: - Palette (monochrome dark)

extension Color {
    /// App background — near-black in dark, warm off-white in light.
    static let fbBackground = Color(light: 0xF4F4F2, dark: 0x0A0A0A)
    /// Card surface (the `Card` container lifts it with a material).
    static let fbCard = Color(light: 0xFFFFFF, dark: 0x161616)
    /// Primary text / hero numbers.
    static let fbInk = Color(light: 0x1A1A1A, dark: 0xF2F2F2)
    /// Secondary / supporting text.
    static let fbSoftText = Color(light: 0x707070, dark: 0x8E8E8E)
    /// Hairline dividers & borders.
    static let fbHairline = Color(light: 0xE2E2E0, dark: 0x262626)
    /// Accent — flips with the scheme so filled buttons stay high contrast.
    static let fbPositive = Color(light: 0x1A1A1A, dark: 0xEDEDED)
    /// Warning / overspend — the one non-mono tone, muted terracotta.
    static let fbWarning = Color(light: 0xB25F41, dark: 0xC77B5D)
    /// Commitments in the "eaten" bar and user chat bubble — mid grey.
    static let fbCommitment = Color(light: 0x9A9A9A, dark: 0x6F6F6F)
    /// Text/icons placed on filled accent surfaces.
    static let fbOnAccent = Color(light: 0xF7F7F5, dark: 0x0A0A0A)
    /// Sky-blue accent — used sparingly for interactive highlights.
    static let fbAccent = Color(hex: 0x7ACDF7)

    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    /// A colour that resolves per colour scheme, so the mono palette
    /// inverts cleanly between dark and light mode.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { trait in
            UIColor(Color(hex: trait.userInterfaceStyle == .dark ? dark : light))
        })
        #else
        self.init(hex: dark)
        #endif
    }
}

/// The user's appearance choice, stored in AppStorage("fbAppearance").
enum FBAppearance: String, CaseIterable {
    case system, light, dark

    /// nil follows the device setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var label: String { rawValue.capitalized }
}

// MARK: - Backdrop

/// The app background: near-black with a barely-there top glow so screens
/// don't read as a dead flat void.
struct FBBackground: View {
    var body: some View {
        ZStack {
            Color.fbBackground
            LinearGradient(colors: [Color.fbInk.opacity(0.045), .clear],
                           startPoint: .top,
                           endPoint: UnitPoint(x: 0.5, y: 0.35))
        }
        .ignoresSafeArea()
    }
}

/// Two or three big, heavily blurred monochrome blobs drifting on slow
/// sine paths — a barely-there pulse so the app doesn't feel static.
/// Mounted once at the root (behind every page) so it never cuts off
/// while swiping between tabs.
struct FBBlobBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.addFilter(.blur(radius: 70))
                blob(&context, size: size, t: t, speed: 0.10, phase: 0.0,
                     radius: 0.42, opacity: 0.09)
                blob(&context, size: size, t: t, speed: 0.06, phase: 2.1,
                     radius: 0.50, opacity: 0.06)
                blob(&context, size: size, t: t, speed: 0.045, phase: 4.4,
                     radius: 0.34, opacity: 0.075)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func blob(_ context: inout GraphicsContext, size: CGSize,
                      t: Double, speed: Double, phase: Double,
                      radius: Double, opacity: Double) {
        let x = size.width * (0.5 + 0.38 * sin(t * speed + phase))
        let y = size.height * (0.45 + 0.34 * cos(t * speed * 0.8 + phase * 1.3))
        let r = size.width * radius
        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
        context.fill(Ellipse().path(in: rect),
                     with: .color(Color.fbInk.opacity(opacity)))
    }
}

// MARK: - Typography

extension Font {
    /// Geometric sans headers: bold, slightly tight tracking is applied
    /// separately via `.tracking()` on the Text.
    static func fbHeader(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    /// Monospaced numerals for anything financial (SF Mono stand-in).
    static func fbNumber(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Body / supporting text.
    static func fbBody(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Currency formatting

enum Money {
    /// Locale currency symbol shown throughout the UI. The spec uses £,
    /// so we default to GBP but keep it in one place.
    nonisolated static let currencyCode = "GBP"

    nonisolated static func string(_ value: Double, showsSign: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = value.rounded() == value ? 0 : 2
        if showsSign { formatter.positivePrefix = "+" + (formatter.currencySymbol ?? "") }
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Interaction (micro-animations)

/// Shared press feedback: a soft spring scale + fade. Applied to every
/// tappable control so the whole app answers touch the same way.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.65),
                       value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

extension Animation {
    /// The one spring used for modal presentation, z-stacking and layout
    /// moves, so every surface answers with the same motion.
    static let fbModal = Animation.spring(response: 0.38, dampingFraction: 0.85)
}

extension AnyTransition {
    /// A card arriving "from above" on the z-axis — scales down into place
    /// while the card beneath recedes. Used for every stacked modal.
    static let fbModalPush = AnyTransition
        .scale(scale: 0.94, anchor: .bottom)
        .combined(with: .offset(y: 26))
        .combined(with: .opacity)
}

// MARK: - Shared controls

/// The app's segmented toggle (Recurring/One-off, Expense/Income, …).
/// One implementation so every switch looks and moves the same.
struct FBSegmentedControl: View {
    let options: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selection = index
                    }
                } label: {
                    Text(options[index])
                        .font(.fbBody(14, weight: .semibold))
                        .foregroundStyle(selection == index ? Color.fbInk : Color.fbSoftText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(selection == index ? Color.fbBackground : .clear)
                        )
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.fbBackground.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.fbHairline, lineWidth: 1)
        )
    }
}

/// Full-width filled action button — the primary in every vertical stack.
struct FBPrimaryButton: View {
    let label: String
    var enabled = true
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.fbBody(16, weight: .semibold))
                .foregroundStyle(Color.fbOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(destructive ? Color.fbWarning : Color.fbPositive)
                )
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        // Disabled reads as the same button, just dimmed.
        .opacity(enabled ? 1 : 0.35)
        .animation(.easeInOut(duration: 0.15), value: enabled)
    }
}

/// The app's own switch: a mono capsule with a gliding knob — the native
/// toggle's tinting sits oddly in this palette.
struct FBSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    configuration.isOn.toggle()
                }
            } label: {
                Capsule()
                    .fill(configuration.isOn ? Color.fbAccent : Color.fbInk.opacity(0.12))
                    .overlay(Capsule().strokeBorder(Color.fbHairline, lineWidth: 1))
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(configuration.isOn ? Color.white : Color.fbSoftText)
                            .padding(3)
                    }
                    .frame(width: 46, height: 28)
            }
            .buttonStyle(.pressable)
        }
    }
}

/// A labelled switch row — plain, no container; sits at the end of forms.
struct FBToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label)
                .font(.fbBody(15, weight: .medium))
                .foregroundStyle(Color.fbInk)
        }
        .toggleStyle(FBSwitchStyle())
    }
}

/// Full-width quiet action button — always sits below the primary.
struct FBSecondaryButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.fbBody(15, weight: .semibold))
                .foregroundStyle(Color.fbInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(Color.fbInk.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.fbInk.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Toasts

/// App-wide bottom toasts ("Rent added", "Gym deleted" + Undo). One at a
/// time; showing a new one replaces the current. Deletions pass an undo
/// closure and get a little longer on screen.
@MainActor
@Observable
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let undo: (() -> Void)?

        static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
    }

    private(set) var current: Toast?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    func show(_ message: String, undo: (() -> Void)? = nil) {
        dismissTask?.cancel()
        let toast = Toast(message: message, undo: undo)
        current = toast
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(undo == nil ? 2.5 : 4))
            guard !Task.isCancelled else { return }
            if self?.current?.id == toast.id { self?.current = nil }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}

/// The toast itself: a small floating card rising from the bottom, above
/// everything — including open modals.
struct FBToastView: View {
    var center: ToastCenter

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if let toast = center.current {
                HStack(spacing: 14) {
                    Text(toast.message)
                        .font(.fbBody(14, weight: .medium))
                        .foregroundStyle(Color.fbInk)
                        .lineLimit(1)
                    if let undo = toast.undo {
                        Button {
                            undo()
                            center.dismiss()
                        } label: {
                            Text("Undo")
                                .font(.fbBody(14, weight: .bold))
                                .foregroundStyle(Color.fbPositive)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.fbCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Color.fbHairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 14, y: 4)
                .onTapGesture { center.dismiss() }
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
            }
        }
        .animation(.fbModal, value: center.current)
    }
}

// MARK: - Cross-platform helpers

/// Drops the current first responder — closes the keyboard from anywhere,
/// without needing access to the view's FocusState.
@MainActor
func fbDismissKeyboard() {
    #if canImport(UIKit)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                    to: nil, from: nil, for: nil)
    #endif
}

extension View {
    /// Applies the decimal keypad on iOS; a no-op elsewhere (e.g. when the
    /// preview/scheme resolves to macOS).
    @ViewBuilder
    func decimalKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}

// MARK: - Card container

/// The rounded glass card used everywhere. A subtle top-lit gradient over
/// a translucent material, edged with a light-catching stroke — quiet
/// depth without visual noise.
struct Card<Content: View>: View {
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 18
    /// Solid surface instead of glass — modals use it so content behind
    /// can't bleed through and muddy the card's controls.
    var opaque = false
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if opaque {
                    shape.fill(Color.fbCard)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
                shape.fill(
                    LinearGradient(colors: [Color.fbInk.opacity(0.045),
                                            Color.fbInk.opacity(0.01)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
            }
            .overlay(
                // Light catches the top edge, falls away at the bottom.
                shape.strokeBorder(
                    LinearGradient(colors: [Color.fbInk.opacity(0.14),
                                            Color.fbInk.opacity(0.03)],
                                   startPoint: .top,
                                   endPoint: .bottom),
                    lineWidth: 1
                )
            )
    }
}
