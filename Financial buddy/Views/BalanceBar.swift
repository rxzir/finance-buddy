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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geo in
                let width = geo.size.width
                HStack(spacing: gap) {
                    ForEach(Array(obligations.enumerated()), id: \.element.id) { index, ob in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(shade(for: index))
                            .frame(width: max(2, segmentWidth(ob.amount, in: width)))
                    }

                    if !isOverspent {
                        // Safe-to-spend reads as "open space": diagonal
                        // hatching instead of a solid block.
                        StripedFill(color: Color.fbPositive)
                            .background(Color.fbPositive.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .frame(width: max(2, segmentWidth(safeToSpend, in: width)))
                    }
                }
            }
            .frame(height: barHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if showsLegend {
                legend
            }
        }
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
