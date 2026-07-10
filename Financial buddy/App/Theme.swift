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
    /// App background — near-black. #0A0A0A
    static let fbBackground = Color(hex: 0x0A0A0A)
    /// Card surface — dark grey, lifted by a gradient in `Card`. #161616
    static let fbCard = Color(hex: 0x161616)
    /// Primary text / hero numbers. #F2F2F2
    static let fbInk = Color(hex: 0xF2F2F2)
    /// Secondary / supporting text. #8E8E8E
    static let fbSoftText = Color(hex: 0x8E8E8E)
    /// Hairline dividers & borders. #262626
    static let fbHairline = Color(hex: 0x262626)
    /// Accent — white in the mono scheme (buttons, highlights, "safe").
    static let fbPositive = Color(hex: 0xEDEDED)
    /// Warning / overspend — the one non-mono tone, muted terracotta.
    static let fbWarning = Color(hex: 0xC77B5D)
    /// Commitments in the "eaten" bar and user chat bubble — mid grey.
    static let fbCommitment = Color(hex: 0x6F6F6F)
    /// Text/icons placed on filled accent surfaces (white buttons).
    static let fbOnAccent = Color(hex: 0x0A0A0A)

    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Backdrop

/// The app background: near-black with a barely-there top glow so screens
/// don't read as a dead flat void.
struct FBBackground: View {
    var body: some View {
        ZStack {
            Color.fbBackground
            LinearGradient(colors: [Color.white.opacity(0.045), .clear],
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

// MARK: - Cross-platform helpers

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
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(.ultraThinMaterial)
                shape.fill(
                    LinearGradient(colors: [Color.white.opacity(0.055),
                                            Color.white.opacity(0.015)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
            }
            .overlay(
                // Light catches the top edge, falls away at the bottom.
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.14),
                                            Color.white.opacity(0.03)],
                                   startPoint: .top,
                                   endPoint: .bottom),
                    lineWidth: 1
                )
            )
    }
}
