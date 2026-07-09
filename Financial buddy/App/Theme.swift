//
//  Theme.swift
//  Finance buddy
//
//  Single source of truth for the palette, typography and shared
//  formatting. Views reference these — no hex literals scattered around.
//

import SwiftUI

// MARK: - Palette

// Dark theme. Same semantic roles as the original light palette, tuned
// for dark surfaces (greens brightened, ink inverted to near-white).
extension Color {
    /// App background — deep green-black. #121714
    static let fbBackground = Color(hex: 0x121714)
    /// Card surface — a step lighter than the background. #1C2420
    static let fbCard = Color(hex: 0x1C2420)
    /// Primary text / hero numbers. #E9EFEA
    static let fbInk = Color(hex: 0xE9EFEA)
    /// Secondary / supporting text. #9AA79E
    static let fbSoftText = Color(hex: 0x9AA79E)
    /// Hairline dividers & borders. #2C362F
    static let fbHairline = Color(hex: 0x2C362F)
    /// Positive / headroom — brightened for dark surfaces. #4FAE7F
    static let fbPositive = Color(hex: 0x4FAE7F)
    /// Warning / overspend — brightened for dark surfaces. #D97D52
    static let fbWarning = Color(hex: 0xD97D52)
    /// Commitments in the "eaten" bar — lifted so segments read on dark. #8CA0D9
    static let fbCommitment = Color(hex: 0x8CA0D9)
    /// Text/icons placed on filled accent surfaces (buttons, user bubble).
    static let fbOnAccent = Color(hex: 0x0F1512)

    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
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

/// The rounded white card used everywhere. Keeps radius / padding / border
/// consistent so screens stay quiet.
struct Card<Content: View>: View {
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.fbCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.fbHairline, lineWidth: 1)
            )
    }
}
