//
//  BalanceBar.swift
//  Finance buddy
//
//  The signature visual: a horizontal bar the full width of which is the
//  current balance. Each upcoming commitment "eats" a chunk proportional
//  to its amount; whatever is left over is what's safe to spend.
//

import SwiftUI

struct BalanceBar: View {
    let balance: Double
    let obligations: [Obligation]
    let safeToSpend: Double

    private let barHeight: CGFloat = 34
    private let gap: CGFloat = 2

    /// The bar always fills its width. If commitments exceed the balance we
    /// scale against the commitments so the overspend is still visible.
    private var denominator: Double {
        max(balance, obligations.reduce(0) { $0 + $1.amount }, 0.01)
    }

    private var isOverspent: Bool { safeToSpend < 0 }

    /// Distinct-but-related shades of the commitment blue so adjacent
    /// segments read as separate without turning into a rainbow.
    private func shade(for index: Int) -> Color {
        let steps = max(obligations.count - 1, 1)
        let t = Double(index) / Double(steps)          // 0...1
        return Color.fbCommitment.opacity(1.0 - t * 0.45)
    }

    /// Set false to render just the bar (e.g. when an itemized list lives
    /// elsewhere on the same screen and the legend would duplicate it).
    var showsLegend: Bool = true

    /// Tapped segment — shows a name / amount / percentage readout.
    private enum Selection: Equatable {
        case obligation(UUID)
        case safe
    }
    @State private var selection: Selection?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geo in
                let width = geo.size.width
                HStack(spacing: gap) {
                    ForEach(Array(obligations.enumerated()), id: \.element.id) { index, ob in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(shade(for: index))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Color.fbInk.opacity(
                                        selection == .obligation(ob.id) ? 0.9 : 0), lineWidth: 1.5)
                            )
                            .frame(width: max(2, segmentWidth(ob.amount, in: width)))
                            .contentShape(Rectangle())
                            .onTapGesture { toggle(.obligation(ob.id)) }
                    }

                    if !isOverspent {
                        // Safe-to-spend reads as "open space": diagonal
                        // hatching instead of a solid block.
                        StripedFill(color: Color.fbPositive)
                            .background(Color.fbPositive.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Color.fbInk.opacity(
                                        selection == .safe ? 0.9 : 0), lineWidth: 1.5)
                            )
                            .frame(width: max(2, segmentWidth(safeToSpend, in: width)))
                            .contentShape(Rectangle())
                            .onTapGesture { toggle(.safe) }
                    }
                }
            }
            .frame(height: barHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if let selection {
                detailChip(for: selection)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if showsLegend {
                legend
            }
        }
    }

    private func toggle(_ new: Selection) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selection = (selection == new) ? nil : new
        }
    }

    // MARK: Tap readout

    /// Name, amount and share of the balance for the tapped segment.
    private func detailChip(for selection: Selection) -> some View {
        let name: String
        let amount: Double
        let isSafe: Bool

        switch selection {
        case .safe:
            name = "Safe to spend"
            amount = safeToSpend
            isSafe = true
        case .obligation(let id):
            let ob = obligations.first { $0.id == id }
            name = ob?.name ?? ""
            amount = ob?.amount ?? 0
            isSafe = false
        }

        let percent = denominator > 0 ? Int((amount / denominator * 100).rounded()) : 0

        return HStack(spacing: 8) {
            Group {
                if isSafe {
                    StripedFill(color: Color.fbPositive, lineWidth: 1.5, spacing: 4)
                        .background(Color.fbPositive.opacity(0.12))
                } else {
                    Color.fbCommitment
                }
            }
            .frame(width: 12, height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

            Text(name)
                .font(.fbBody(13, weight: .semibold))
                .foregroundStyle(Color.fbInk)
                .lineLimit(1)
            Text(Money.string(amount))
                .font(.fbNumber(13, weight: .semibold))
                .foregroundStyle(Color.fbInk)
            Text("· \(percent)%")
                .font(.fbBody(13))
                .foregroundStyle(Color.fbSoftText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.fbHairline, lineWidth: 1))
    }

    private func segmentWidth(_ amount: Double, in totalWidth: CGFloat) -> CGFloat {
        let available = totalWidth - CGFloat(max(obligations.count, 1)) * gap
        return CGFloat(amount / denominator) * available
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(obligations.enumerated()), id: \.element.id) { index, ob in
                legendRow(swatch: shade(for: index), name: ob.name, amount: ob.amount)
            }
            Divider().overlay(Color.fbHairline)
            legendRow(swatch: isOverspent ? .fbWarning : .fbPositive,
                      name: isOverspent ? "Overspent" : "Safe to spend",
                      amount: safeToSpend,
                      emphasised: true)
        }
    }

    private func legendRow(swatch: Color, name: String, amount: Double, emphasised: Bool = false) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(swatch)
                .frame(width: 12, height: 12)
            Text(name)
                .font(.fbBody(15, weight: emphasised ? .semibold : .regular))
                .foregroundStyle(Color.fbInk)
            Spacer()
            Text(Money.string(amount))
                .font(.fbNumber(15, weight: emphasised ? .semibold : .regular))
                .foregroundStyle(emphasised ? (amount < 0 ? Color.fbWarning : Color.fbPositive) : Color.fbSoftText)
        }
    }
}

// MARK: - Striped fill

/// Diagonal 45° hatching — used for the safe-to-spend segment so "money
/// that's yours" reads differently from the solid committed blocks.
struct StripedFill: View {
    var color: Color
    var lineWidth: CGFloat = 2.5
    var spacing: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            var path = Path()
            // Cover the whole rect with 45° lines, starting off-canvas so
            // the corner is striped too.
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
    }
}

#Preview {
    let f = Finances.sample
    return VStack {
        Card {
            BalanceBar(balance: f.balance,
                        obligations: f.upcomingObligations(),
                        safeToSpend: f.safeToSpendToday())
        }
        .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.fbBackground)
    .preferredColorScheme(.dark)
}
