//
//  Theme.swift
//  Finance buddy
//
//  Single source of truth for the palette, typography and shared
//  formatting. Views reference these — no hex literals scattered around.
//

import SwiftUI

// MARK: - Palette

extension Color {
    /// App background — muted sage. #EEF1EC
    static let hrBackground = Color(hex: 0xEEF1EC)
    /// Card surface. #FFFFFF
    static let hrCard = Color(hex: 0xFFFFFF)
    /// Primary text / hero numbers. #1B2521
    static let hrInk = Color(hex: 0x1B2521)
    /// Secondary / supporting text. #5C6960
    static let hrSoftText = Color(hex: 0x5C6960)
    /// Hairline dividers & borders. #D3DBD1
    static let hrHairline = Color(hex: 0xD3DBD1)
    /// Positive / headroom. #2F6F4E
    static let hrPositive = Color(hex: 0x2F6F4E)
    /// Warning / overspend. #A84B2A
    static let hrWarning = Color(hex: 0xA84B2A)
    /// Commitments in the "eaten" bar. #2B3A67
    static let hrCommitment = Color(hex: 0x2B3A67)

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
    static func hrHeader(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    /// Monospaced numerals for anything financial (SF Mono stand-in).
    static func hrNumber(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Body / supporting text.
    static func hrBody(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
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
                    .fill(Color.hrCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.hrHairline, lineWidth: 1)
            )
    }
}
