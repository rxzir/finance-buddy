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
    static let currencyCode = "GBP"

    static func string(_ value: Double, showsSign: Bool = false) -> String {
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
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
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

/// A labelled switch styled like the app's form fields — used for the
/// recurring/one-off choice everywhere.
struct FBToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label)
                .font(.fbBody(15, weight: .medium))
                .foregroundStyle(Color.fbInk)
        }
        .tint(Color.fbPositive)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.fbBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.fbHairline, lineWidth: 1)
        )
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
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.fbInk.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.fbInk.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.pressable)
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
